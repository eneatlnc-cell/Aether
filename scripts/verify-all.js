// verify-all.js — 使用 solc-js 0.8.26 编译所有 .sol 文件（src + test + script）
//   验证 0 编译错误 + 合约体积 < 24KB
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
        if (entry.isDirectory()) findSolFiles(full, out);
        else if (entry.name.endsWith(".sol")) out.push(full);
    }
    return out;
}

function resolveImport(importPath) {
    if (importPath.startsWith("@openzeppelin/")) {
        const rel = importPath.slice("@openzeppelin/contracts/".length);
        const full = path.join(OZ_PATH, rel);
        if (fs.existsSync(full)) return { contents: fs.readFileSync(full, "utf8") };
    }
    if (importPath.startsWith("forge-std/")) {
        const rel = importPath.slice("forge-std/".length);
        const full = path.join(FORGE_STD_MOCK, rel);
        if (fs.existsSync(full)) return { contents: fs.readFileSync(full, "utf8") };
    }
    if (importPath.startsWith("/")) {
        if (fs.existsSync(importPath)) return { contents: fs.readFileSync(importPath, "utf8") };
    }
    const base = path.basename(importPath);
    const allFiles = [...findSolFiles(WORKSPACE), ...findSolFiles(FORGE_STD_MOCK)];
    for (const f of allFiles) {
        if (path.basename(f) === base) return { contents: fs.readFileSync(f, "utf8") };
    }
    function walkOZ(dir) {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
            const full = path.join(dir, entry.name);
            if (entry.isDirectory()) { const r = walkOZ(full); if (r) return r; }
            else if (entry.name === base) return full;
        }
        return null;
    }
    const ozMatch = walkOZ(OZ_PATH);
    if (ozMatch) return { contents: fs.readFileSync(ozMatch, "utf8") };
    throw new Error("Cannot resolve import: " + importPath);
}

// ── 收集所有源文件 ──
const sources = {};

// 1. 所有 src 源文件
for (const f of findSolFiles(WORKSPACE)) {
    if (f.includes("/test/") || f.includes("/script/")) continue;
    const rel = path.relative(WORKSPACE, f);
    sources[rel] = { content: fs.readFileSync(f, "utf8") };
}

// 2. forge-std mock 文件
for (const f of findSolFiles(FORGE_STD_MOCK)) {
    const rel = "forge-std/" + path.relative(FORGE_STD_MOCK, f);
    sources[rel] = { content: fs.readFileSync(f, "utf8") };
}

// 3. 测试文件
const testFiles = findSolFiles(path.join(WORKSPACE, "test"));
for (const f of testFiles) {
    const rel = path.relative(WORKSPACE, f);
    sources[rel] = { content: fs.readFileSync(f, "utf8") };
}

// 4. 脚本文件
const scriptFiles = findSolFiles(path.join(WORKSPACE, "script"));
for (const f of scriptFiles) {
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
            "*": { "*": ["abi", "evm.bytecode.object", "evm.deployedBytecode.object"] },
        },
    },
};

console.log("Compiling", Object.keys(sources).length, "files (src + test + script + mock)...");
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

console.log(`\n✅ Full compilation succeeded — 0 errors, ${warnCount} warning(s)`);

// ── 合约体积检查（仅检查 src/ 下的生产合约） ──
console.log("\nContract sizes (runtime bytecode bytes):");
const LIMIT = 24576; // 24KB
let allUnderLimit = true;
for (const [file, contracts] of Object.entries(output.contracts || {})) {
    for (const [name, data] of Object.entries(contracts)) {
        const bytecode = data.evm?.deployedBytecode?.object || "";
        const size = bytecode.length / 2;
        if (size === 0) continue; // skip interfaces/libraries without bytecode
        const isProduction = file.startsWith("src/");
        const pct = ((size / LIMIT) * 100).toFixed(1);
        let flag = "";
        if (isProduction && size > LIMIT) {
            flag = " ❌ OVER LIMIT";
            allUnderLimit = false;
        } else if (!isProduction && size > LIMIT) {
            flag = " (test/script, no limit)";
        }
        console.log(`  ${name.padEnd(24)} ${String(size).padStart(6)} bytes  (${pct}% of 24KB limit)${flag}`);
    }
}

if (!allUnderLimit) {
    console.log("\n❌ Some contracts exceed 24KB limit!");
    process.exit(1);
}

console.log("\n✅ All contracts under 24KB limit");
