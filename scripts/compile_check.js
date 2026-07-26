// 用 solc-js 编译 Aether DAO 所有合约，验证编译通过（语法/类型/链接）
// 不跑测试，仅做编译检查（相当于 forge build 的前置验证）
const fs = require("fs");
const path = require("path");
const solc = require("/workspace/node_modules/solc");

const CONTRACTS_DIR = "/workspace/contracts/src";
const TEST_DIR = "/workspace/contracts/test";
const SCRIPT_DIR = "/workspace/contracts/script";
// OZ npm 包：@openzeppelin/contracts 是包名，其内部 import 路径就是
// @openzeppelin/contracts/access/AccessControl.sol → node_modules/@openzeppelin/contracts/access/AccessControl.sol
// 所以 remapping 应该把 "@openzeppelin/contracts/" 直接映射到包目录
const REMAPPINGS = {
  "@openzeppelin/contracts/": "/workspace/node_modules/@openzeppelin/contracts/",
};

// 递归收集 .sol 文件
function collectSols(dir, acc = {}) {
  if (!fs.existsSync(dir)) return acc;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      collectSols(full, acc);
    } else if (entry.name.endsWith(".sol")) {
      acc[full] = { content: fs.readFileSync(full, "utf8") };
    }
  }
  return acc;
}

// forge-std 的 Test/Script 基类是 solidity 文件，solc-js 无法解析 import "forge-std/..."
// 解决：用 stub 文件提供空的 Test/Script/console2/vm 符号
const STUBS = {
  "forge-std/Test.sol": `// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;
interface Vm {
  function envUint(string calldata) external view returns (uint256);
  function envAddress(string calldata) external view returns (address);
  function envString(string calldata) external view returns (string memory);
  function envBool(string calldata) external view returns (bool);
  function envOr(string calldata, uint256) external view returns (uint256);
  function envOr(string calldata, address) external view returns (address);
  function addr(uint256) external pure returns (address);
  function startBroadcast(uint256) external;
  function stopBroadcast() external;
  function startBroadcast(address) external;
  function prank(address) external;
  function startPrank(address) external;
  function stopPrank() external;
  function warp(uint256) external;
  function skip(uint256) external;
  function roll(uint256) external;
  function expectRevert() external;
  function expectRevert(bytes4) external;
  function expectRevert(bytes memory) external;
  function expectEmit(bool,bool,bool,bool) external;
  function expectEmit(bool,bool,bool,bool,address) external;
  function deal(address, uint256) external;
  function store(address, bytes32, bytes32) external;
  function load(address, bytes32) external view returns (bytes32);
  function label(address, string calldata) external;
  function deriveKey(string calldata, uint32) external pure returns (uint256);
  function rememberKey(uint256) external returns (address);
  function broadcast() external;
  function broadcast(uint256) external;
  function broadcast(address) external;
}
contract Test {
  Vm internal constant vm = Vm(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D));
  function assertTrue(bool) public {}
  function assertTrue(bool, string memory) public {}
  function assertFalse(bool) public {}
  function assertFalse(bool, string memory) public {}
  function assertEq(uint256,uint256) public {}
  function assertEq(address,address) public {}
  function assertEq(bytes32,bytes32) public {}
  function assertEq(uint8,uint8) public {}
  function assertEq(string memory,string memory) public {}
  function assertEq(uint256,uint256,string memory) public {}
  function assertEq(address,address,string memory) public {}
  function assertEq(uint8,uint8,string memory) public {}
  function assertEq(bool,bool) public {}
  function assertNotEq(uint256,uint256) public {}
  function assertGt(uint256,uint256) public {}
  function assertGt(uint256,uint256,string memory) public {}
  function assertLt(uint256,uint256) public {}
  function assertApproxEqAbs(uint256,uint256,uint256) public {}
  function assertApproxEqAbs(uint256,uint256,uint256,string memory) public {}
  function skip(uint256) public {}
  function rewind(uint256) public {}
}
contract Script { Vm internal constant vm = Vm(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D)); }
library console2 { function log(string memory) internal pure {} function log(string memory, address) internal pure {} function log(string memory, uint256) internal pure {} function log(string memory, string memory) internal pure {} function log(string memory, string memory, string memory) internal pure {} function log(string memory, address, address) internal pure {} function log(string memory, uint256, uint256) internal pure {} function log(string memory, string memory, uint256) internal pure {} function log(string memory, string memory, string memory, uint256) internal pure {} function log(string memory, address, string memory) internal pure {} function log(string memory, address, uint256) internal pure {} function log(string memory, uint256, string memory) internal pure {} }
`,
  "forge-std/Script.sol": `// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;
interface Vm {
  function envUint(string calldata) external view returns (uint256);
  function envAddress(string calldata) external view returns (address);
  function envString(string calldata) external view returns (string memory);
  function envBool(string calldata) external view returns (bool);
  function envOr(string calldata, uint256) external view returns (uint256);
  function envOr(string calldata, address) external view returns (address);
  function addr(uint256) external pure returns (address);
  function startBroadcast(uint256) external;
  function stopBroadcast() external;
  function startBroadcast(address) external;
  function prank(address) external;
  function startPrank(address) external;
  function stopPrank() external;
  function warp(uint256) external;
  function skip(uint256) external;
  function roll(uint256) external;
  function expectRevert() external;
  function expectRevert(bytes4) external;
  function expectRevert(bytes memory) external;
  function expectEmit(bool,bool,bool,bool) external;
  function expectEmit(bool,bool,bool,bool,address) external;
  function deal(address, uint256) external;
  function store(address, bytes32, bytes32) external;
  function load(address, bytes32) external view returns (bytes32);
  function label(address, string calldata) external;
  function deriveKey(string calldata, uint32) external pure returns (uint256);
  function rememberKey(uint256) external returns (address);
  function broadcast() external;
  function broadcast(uint256) external;
  function broadcast(address) external;
}
contract Script { Vm internal constant vm = Vm(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D)); }
library console2 { function log(string memory) internal pure {} function log(string memory, address) internal pure {} function log(string memory, uint256) internal pure {} function log(string memory, string memory) internal pure {} function log(string memory, string memory, string memory) internal pure {} function log(string memory, address, address) internal pure {} function log(string memory, uint256, uint256) internal pure {} function log(string memory, string memory, uint256) internal pure {} function log(string memory, string memory, string memory, uint256) internal pure {} function log(string memory, address, string memory) internal pure {} function log(string memory, address, uint256) internal pure {} function log(string memory, uint256, string memory) internal pure {} }
`,
  "forge-std/console2.sol": `// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;
library console2 { function log(string memory) internal pure {} function log(string memory, address) internal pure {} function log(string memory, uint256) internal pure {} function log(string memory, string memory) internal pure {} }
`,
  "forge-std/console.sol": `// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;
library console { function log(string memory) internal pure {} function log(string memory, address) internal pure {} function log(string memory, uint256) internal pure {} }
`,
};

// solc-js 的 remapping 通过 importCallback 解析
function findFile(importPath) {
  for (const [prefix, target] of Object.entries(REMAPPINGS)) {
    if (importPath.startsWith(prefix)) {
      const realPath = importPath.replace(prefix, target);
      if (fs.existsSync(realPath)) {
        return realPath;
      }
    }
  }
  if (STUBS[importPath]) return null;
  return null;
}

const readCallback = {
  import: (importPath) => {
    const realPath = findFile(importPath);
    if (realPath && fs.existsSync(realPath)) {
      return { contents: fs.readFileSync(realPath, "utf8") };
    }
    return { error: `File not found: ${importPath}` };
  },
};

const sources = {};
Object.assign(sources, collectSols(CONTRACTS_DIR));
const testSols = collectSols(TEST_DIR);
const scriptSols = collectSols(SCRIPT_DIR);

// 先单独编译 src/ 合约（核心，必须 0 错误）
console.log("=== Phase 1: Compiling src/ contracts (core) ===");
const srcOnlyInput = {
  language: "Solidity",
  sources: { ...sources },
  settings: {
    optimizer: { enabled: true, runs: 200 },
    viaIR: true,
    outputSelection: { "*": { "*": ["abi"] } },
  },
};
const srcOnlyOutput = JSON.parse(solc.compile(JSON.stringify(srcOnlyInput), readCallback));
const srcErrors = (srcOnlyOutput.errors || []).filter((e) => e.severity === "error");
console.log(`src/ errors: ${srcErrors.length}`);
if (srcErrors.length > 0) {
  for (const e of srcErrors) {
    const file = e.sourceLocation?.file || "(unknown)";
    console.log(`  ${path.basename(file)}: ${e.message}`);
  }
  console.log("\n❌ Core contracts have errors — aborting");
  process.exit(1);
}
console.log("✅ Core contracts (src/) compile clean\n");

// Phase 2: 加上测试和脚本（stub 可能有重载歧义，标记为已知局限）
console.log("=== Phase 2: Compiling tests + scripts (stub-based) ===");
Object.assign(sources, testSols);
Object.assign(sources, scriptSols);

// 添加 stubs
for (const [stubPath, content] of Object.entries(STUBS)) {
  sources[stubPath] = { content };
}

const input = {
  language: "Solidity",
  sources,
  settings: {
    optimizer: { enabled: true, runs: 200 },
    viaIR: true,
    outputSelection: {
      "*": {
        "*": ["abi"],
      },
    },
  },
};

console.log(`Compiling ${Object.keys(sources).length} sources...`);
const startTime = Date.now();

const output = JSON.parse(solc.compile(JSON.stringify(input), readCallback));
const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);

const errors = (output.errors || []).filter((e) => e.severity === "error");
const warnings = (output.errors || []).filter((e) => e.severity === "warning");

console.log(`\n=== Compilation finished in ${elapsed}s ===`);
console.log(`Errors:   ${errors.length}`);
console.log(`Warnings: ${warnings.length}`);

if (errors.length > 0) {
  console.log("\n=== ERRORS ===");
  const byFile = {};
  for (const e of errors) {
    const file = e.sourceLocation?.file || "(unknown)";
    if (!byFile[file]) byFile[file] = [];
    byFile[file].push(e);
  }
  for (const [file, errs] of Object.entries(byFile)) {
    console.log(`\n--- ${file} (${errs.length} errors) ---`);
    for (const e of errs.slice(0, 10)) {
      const line = e.sourceLocation?.start || 0;
      const formattedMessage = e.formattedMessage || e.message;
      console.log(`  L${line}: ${formattedMessage}`);
    }
    if (errs.length > 10) console.log(`  ... and ${errs.length - 10} more`);
  }
  process.exit(1);
} else {
  console.log("\n✅ All contracts compiled successfully");

  const compiled = [];
  for (const [file, data] of Object.entries(output.contracts || {})) {
    for (const name of Object.keys(data)) {
      compiled.push(`${name} (${path.basename(file)})`);
    }
  }
  console.log(`\nCompiled ${compiled.length} contracts:`);
  for (const c of compiled.sort()) console.log(`  - ${c}`);
}

if (warnings.length > 0) {
  console.log(`\n=== Warnings (${warnings.length}) ===`);
  for (const w of warnings.slice(0, 20)) {
    const file = w.sourceLocation?.file || "(unknown)";
    const line = w.sourceLocation?.start || 0;
    console.log(`  ${path.basename(file)}:L${line}: ${w.message}`);
  }
  if (warnings.length > 20) console.log(`  ... and ${warnings.length - 20} more`);
}
