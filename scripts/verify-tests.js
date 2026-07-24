// verify-tests.js — 使用 solc-js 0.8.26 编译 AetherRing.t.sol，验证 0 编译错误
//   使用 /workspace/.cache/forge-std/src/Test.sol 作为 forge-std mock（仅类型检查，不执行）
const fs = require("fs");
const path = require("path");
const solc = require("/tmp/solc-verify/node_modules/solc");

const WORKSPACE = "/workspace/contracts";
const FORGE_STD_MOCK = "/workspace/.cache/forge-std/src";
const OZ_PATH = "/tmp/solc-verify/node_modules/@openzeppelin/contracts";

function findSolFiles(dir, out = []) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        if (entry.name === "lib" || entry.name === "out" || entry.name === "cache") continue;
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) {
            findSolFiles(full, out);
        } else if (entry.name.endsWith(".sol")) {
            out.push(full);
        }
    }
    return out;
}

function resolveImport(importPath) {
    // 1. @openzeppelin/...
    if (importPath.startsWith("@openzeppelin/")) {
        const rel = importPath.slice("@openzeppelin/contracts/".length);
        const full = path.join(OZ_PATH, rel);
        if (fs.existsSync(full)) return { contents: fs.readFileSync(full, "utf8") };
    }
    // 2. forge-std/... → mock
    if (importPath.startsWith("forge-std/")) {
        const rel = importPath.slice("forge-std/".length);
        const full = path.join(FORGE_STD_MOCK, rel);
        if (fs.existsSync(full)) return { contents: fs.readFileSync(full, "utf8") };
    }
    // 3. absolute path
    if (importPath.startsWith("/")) {
        if (fs.existsSync(importPath)) return { contents: fs.readFileSync(importPath, "utf8") };
    }
    // 4. basename walking across workspace + mock dir
    const base = path.basename(importPath);
    const allFiles = [...findSolFiles(WORKSPACE), ...findSolFiles(FORGE_STD_MOCK)];
    for (const f of allFiles) {
        if (path.basename(f) === base) return { contents: fs.readFileSync(f, "utf8") };
    }
    // 5. OZ basename fallback
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

// ── 收集源文件 + 测试文件 ──
const sources = {};

// 加入所有 src 源文件（不含 test/script）
for (const f of findSolFiles(WORKSPACE)) {
    if (f.includes("/test/") || f.includes("/script/")) continue;
    const rel = path.relative(WORKSPACE, f);
    sources[rel] = { content: fs.readFileSync(f, "utf8") };
}

// 加入 forge-std mock
sources["forge-std/src/Test.sol"] = {
    content: fs.readFileSync(path.join(FORGE_STD_MOCK, "Test.sol"), "utf8"),
};

// 加入测试文件
const testFiles = findSolFiles(path.join(WORKSPACE, "test"));
for (const f of testFiles) {
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
                "*": ["abi", "evm.bytecode.object", "evm.deployedBytecode.object"],
            },
        },
    },
};

console.log("Compiling", Object.keys(sources).length, "files (src + test + mock)...");
console.log("Test files:", testFiles.map((f) => path.relative(WORKSPACE, f)).join(", "));

const output = JSON.parse(solc.compile(JSON.stringify(input), { import: resolveImport }));

let errorCount = 0;
let warnCount = 0;
if (output.errors) {
    for (const err of output.errors) {
        const tag = err.severity === "error" ? "ERROR" : "WARN";
        console.log(`[${tag}] ${err.formattedMessage || err.message}`);
        if (err.severity === "error") errorCount++;
        else warnCount++;
    }
}

if (errorCount > 0) {
    console.log(`\n❌ Compilation FAILED — ${errorCount} error(s), ${warnCount} warning(s)`);
    process.exit(1);
}

console.log(`\n✅ Test compilation succeeded — 0 errors, ${warnCount} warning(s)`);

// ── 列出测试合约 + 测试函数 ──
console.log("\nTest contracts found:");
let totalTests = 0;
for (const [file, contracts] of Object.entries(output.contracts || {})) {
    if (!file.includes("test/")) continue;
    for (const [name] of Object.entries(contracts)) {
        const abi = contracts[name].abi || [];
        const testFns = abi.filter(
            (e) => e.type === "function" && /^test[_A-Z]/.test(e.name || "")
        );
        totalTests += testFns.length;
        console.log(`  ${file} :: ${name}  (${testFns.length} test functions)`);
        for (const fn of testFns) {
            console.log(`    - ${fn.name}()`);
        }
    }
}
console.log(`\nTotal test functions: ${totalTests}`);
