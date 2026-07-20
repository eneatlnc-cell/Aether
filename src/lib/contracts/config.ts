// Aether DAO 合约配置
// 部署后填入实际地址，前端会从这里读

import { arbitrum, arbitrumSepolia } from "wagmi/chains";

// ──────────── 合约地址 ────────────
// 部署到 Arbitrum Sepolia 后，把这里替换成实际地址
// 通过 `forge script script/Deploy.s.sol:Deploy --rpc-url ... --broadcast` 部署

export const CONTRACTS = {
  // 测试网（Arbitrum Sepolia, chainId 421614）
  [arbitrumSepolia.id]: {
    AetherRing: "0x0000000000000000000000000000000000000000" as `0x${string}`,
    AetherGovernance: "0x0000000000000000000000000000000000000000" as `0x${string}`,
    AetherElection: "0x0000000000000000000000000000000000000000" as `0x${string}`,
  },
  // 主网（Arbitrum One, chainId 42161）— 暂未部署
  [arbitrum.id]: {
    AetherRing: "0x0000000000000000000000000000000000000000" as `0x${string}`,
    AetherGovernance: "0x0000000000000000000000000000000000000000" as `0x${string}`,
    AetherElection: "0x0000000000000000000000000000000000000000" as `0x${string}`,
  },
  // 本地开发链（Anvil, chainId 31337）
  31337: {
    AetherRing: "0x0000000000000000000000000000000000000000" as `0x${string}`,
    AetherGovernance: "0x0000000000000000000000000000000000000000" as `0x${string}`,
    AetherElection: "0x0000000000000000000000000000000000000000" as `0x${string}`,
  },
} as const;

export type ChainId = keyof typeof CONTRACTS;

export function getContracts(chainId: number) {
  return CONTRACTS[chainId as ChainId] ?? null;
}

export function isDeployed(chainId: number): boolean {
  const c = getContracts(chainId);
  if (!c) return false;
  return c.AetherRing !== "0x0000000000000000000000000000000000000000";
}
