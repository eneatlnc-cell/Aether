// verify.js — 使用 solc-js 0.8.26 编译 Aether 合约，验证 0 错误
const fs = require("fs");
const path = require("path");
const solc = require("/tmp/solc-verify/node_modules/solc");

const WORKSPACE = "/workspace/contracts";
const OZ_PATH = "/tmp/solc-verify/node_modules/@openzeppelin/contracts";

// ──────────── 收集所有 .sol 源文件 ────────────
function findSolFiles(dir, base = dir) {
    const out = [];
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        // 跳过 lib/（forge install 的依赖）和 out/（编译产物）
        if (entry.name === "lib" || entry.name === "out" || entry.name === "cache") continue;
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) {
            out.push(...findSolFiles(full, base));
        } else if (entry.name.endsWith(".sol")) {
            out.push(full);
        }
    }
    return out;
}

// ──────────── basename-walking import 解析 ────────────
// OZ v5 内部用相对路径 ../utils/Context.sol，我们需要回溯到 node_modules 找
function resolveImport(importPath) {
    // 1. @openzeppelin/... → node_modules
    if (importPath.startsWith("@openzeppelin/")) {
        const rel = importPath.slice("@openzeppelin/contracts/".length);
        const full = path.join(OZ_PATH, rel);
        if (fs.existsSync(full)) return { contents: fs.readFileSync(full, "utf8") };
    }
    // 2. 绝对路径
    if (importPath.startsWith("/")) {
        if (fs.existsSync(importPath)) return { contents: fs.readFileSync(importPath, "utf8") };
    }
    // 3. basename walking：尝试在所有源文件目录中按 basename 匹配
    const base = path.basename(importPath);
    const allFiles = findSolFiles(WORKSPACE);
    for (const f of allFiles) {
        if (path.basename(f) === base) return { contents: fs.readFileSync(f, "utf8") };
    }
    // 4. 最后再尝试 OZ 里 basename
    function walkOZ(dir) {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
            const full = path.join(dir, entry.name);
            if (entry.isDirectory()) {
                const r = walkOZ(full);
                if (r) return r;
            } else if (entry.name === base) {
                return full;
            }
        }
        return null;
    }
    const ozMatch = walkOZ(OZ_PATH);
    if (ozMatch) return { contents: fs.readFileSync(ozMatch, "utf8") };

    throw new Error("Cannot resolve import: " + importPath);
}

// ──────────── 构造 solc 输入 ────────────
const sources = {};
for (const f of findSolFiles(WORKSPACE)) {
    // 跳过测试文件和 script（编译它们需要 forge-std，我们没有）
    if (f.includes("/test/") || f.includes("/script/")) continue;
    const rel = path.relative(WORKSPACE, f);
    sources[rel] = { content: fs.readFileSync(f, "utf8") };
}

const input = {
    language: "Solidity",
    sources,
    settings: {
        optimizer: { enabled: true, runs: 200 },
        viaIR: true,
        outputSelection: {
            "*": {
                "*": ["abi", "evm.bytecode.object", "evm.deployedBytecode.object"]
            }
        }
    }
};

console.log("Compiling", Object.keys(sources).length, "source files...");
console.log("Files:", Object.keys(sources).join(", "));

const output = JSON.parse(
    solc.compile(JSON.stringify(input), { import: resolveImport })
);

// ──────────── 报告错误 ────────────
let hasError = false;

if (output.errors) {
    for (const err of output.errors) {
        const tag = err.severity === "error" ? "ERROR" : "WARN";
        console.log(`[${tag}] ${err.formattedMessage || err.message}`);
        if (err.severity === "error") hasError = true;
    }
}

if (hasError) {
    console.log("\n❌ Compilation failed");
    process.exit(1);
}

// ──────────── 报告合约大小 ────────────
console.log("\n✅ Compilation succeeded\n");
console.log("Contract sizes (runtime bytecode bytes):");
for (const [file, contracts] of Object.entries(output.contracts || {})) {
    for (const [name, data] of Object.entries(contracts)) {
        const bc = data.evm?.deployedBytecode?.object || "";
        const size = bc.length / 2; // hex string → bytes
        const limit = 24576; // 24KB
        const pct = ((size / limit) * 100).toFixed(1);
        const flag = size > limit ? " ❌ EXCEEDS 24KB!" : "";
        console.log(`  ${name.padEnd(20)} ${String(size).padStart(6)} bytes  (${pct}% of 24KB limit)${flag}`);
    }
}

// ──────────── 输出 ABI（保存供后续生成前端用） ────────────
const abis = {};
for (const [file, contracts] of Object.entries(output.contracts || {})) {
    for (const [name, data] of Object.entries(contracts)) {
        abis[name] = data.abi;
    }
}
fs.writeFileSync("/workspace/.cache/contract-abis.json", JSON.stringify(abis, null, 2));
console.log("\nABIs saved to /workspace/.cache/contract-abis.json");
