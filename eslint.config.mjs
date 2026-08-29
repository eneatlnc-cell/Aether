// SPDX-License-Identifier: Apache-2.0
// ESLint 扁平配置（Next 16 已移除 `next lint`，改为直接跑 eslint CLI）
// eslint-config-next 16 起原生导出扁平配置，无需 FlatCompat 兼容层。
// 用法：npm run lint

import coreWebVitals from "eslint-config-next/core-web-vitals";
import typescript from "eslint-config-next/typescript";

const eslintConfig = [
  {
    ignores: [
      "node_modules/**",
      ".next/**",
      "out/**",
      "public/**",
      // Foundry/Solidity 工具链（含 forge-std 子模块），由 forge test 覆盖
      "contracts/**",
      // Next 自动生成的类型声明
      "next-env.d.ts",
    ],
  },
  ...coreWebVitals,
  ...typescript,
  {
    files: ["scripts/**/*.{js,cjs}"],
    rules: {
      // scripts/ 目录是 CommonJS Node 工具脚本（package.json 无 "type": "module"），
      // require() 是其合法模块语法，不适用 ESM 规则
      "@typescript-eslint/no-require-imports": "off",
    },
  },
];

export default eslintConfig;
