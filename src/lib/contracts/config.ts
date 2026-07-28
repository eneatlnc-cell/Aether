// SPDX-License-Identifier: Apache-2.0
// Aether DAO 合约配置
// 部署后通过 NEXT_PUBLIC_* 环境变量注入地址（Vercel / .env.local）
// 硬编码值作为 fallback，未设置环境变量时使用

import { arbitrum, arbitrumSepolia } from "wagmi/chains";

export type ContractSet = {
  AetherRing: `0x${string}`;
  AetherGovernance: `0x${string}`;
  AetherElection: `0x${string}`;
  AetherDonation: `0x${string}`;
};

const ZERO = "0x0000000000000000000000000000000000000000" as `0x${string}`;

// ──────────── 硬编码 fallback（保持兼容旧部署） ────────────
// 默认全部为零地址；真实地址通过 NEXT_PUBLIC_* 注入
const FALLBACK: ContractSet = {
  AetherRing: ZERO,
  AetherGovernance: ZERO,
  AetherElection: ZERO,
  AetherDonation: ZERO,
};

export const CONTRACTS = {
  [arbitrumSepolia.id]: { ...FALLBACK },
  [arbitrum.id]: { ...FALLBACK },
  31337: { ...FALLBACK }, // 本地 Anvil
} as const;

export type ChainId = keyof typeof CONTRACTS;

// ──────────── 环境变量读取 ────────────
// 优先级：NEXT_PUBLIC_<NAME>_ADDRESS > NEXT_PUBLIC_<NAME>_<CHAINID>_ADDRESS > fallback
// 这样可以单链部署用通用变量，多链部署用链专属变量
function readEnvAddr(baseName: string, chainId: number): `0x${string}` | null {
  if (typeof process === "undefined" || !process.env) return null;
  // 1. 链专属变量（多链场景）
  const chainSpecific = process.env[`NEXT_PUBLIC_${baseName}_${chainId}_ADDRESS`];
  if (chainSpecific && /^0x[a-fA-F0-9]{40}$/.test(chainSpecific)) {
    return chainSpecific as `0x${string}`;
  }
  // 2. 通用变量（单链场景）
  const general = process.env[`NEXT_PUBLIC_${baseName}_ADDRESS`];
  if (general && /^0x[a-fA-F0-9]{40}$/.test(general)) {
    return general as `0x${string}`;
  }
  return null;
}

function resolveChain(chainId: number): ContractSet {
  const fallback = CONTRACTS[chainId as ChainId] ?? FALLBACK;
  return {
    AetherRing: readEnvAddr("AETHER_RING", chainId) ?? fallback.AetherRing,
    AetherGovernance: readEnvAddr("AETHER_GOVERNANCE", chainId) ?? fallback.AetherGovernance,
    AetherElection: readEnvAddr("AETHER_ELECTION", chainId) ?? fallback.AetherElection,
    AetherDonation: readEnvAddr("AETHER_DONATION", chainId) ?? fallback.AetherDonation,
  };
}

export function getContracts(chainId: number): ContractSet | null {
  if (!(chainId in CONTRACTS) && !readEnvAddr("AETHER_RING", chainId)) {
    // 未知链且无环境变量 → null
    return null;
  }
  return resolveChain(chainId);
}

export function isDeployed(chainId: number): boolean {
  const c = getContracts(chainId);
  if (!c) return false;
  return c.AetherRing !== ZERO;
}

// ──────────── Safe 多签地址（治理合约与道环合约共用） ────────────
export function getSafeWalletAddress(chainId: number): `0x${string}` | null {
  if (typeof process !== "undefined" && process.env) {
    const chainSpecific = process.env[`NEXT_PUBLIC_SAFE_WALLET_${chainId}_ADDRESS`];
    if (chainSpecific && /^0x[a-fA-F0-9]{40}$/.test(chainSpecific)) {
      return chainSpecific as `0x${string}`;
    }
    const general = process.env["NEXT_PUBLIC_SAFE_WALLET_ADDRESS"];
    if (general && /^0x[a-fA-F0-9]{40}$/.test(general)) {
      return general as `0x${string}`;
    }
  }
  return null;
}

// ──────────── IPFS 网关 ────────────
export function getIpfsGateway(): string {
  if (typeof process !== "undefined" && process.env?.NEXT_PUBLIC_IPFS_GATEWAY) {
    return process.env.NEXT_PUBLIC_IPFS_GATEWAY;
  }
  return "https://gateway.pinata.cloud/ipfs/";
}

// ──────────── USDC 合约地址 ────────────
// Arbitrum One 主网原生 USDC（Circle 官方）: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831
// 通过 NEXT_PUBLIC_USDC_ADDRESS 覆盖（多链场景用 NEXT_PUBLIC_USDC_<CHAINID>_ADDRESS）
export function getUsdcAddress(chainId: number): `0x${string}` | null {
  if (typeof process !== "undefined" && process.env) {
    const chainSpecific = process.env[`NEXT_PUBLIC_USDC_${chainId}_ADDRESS`];
    if (chainSpecific && /^0x[a-fA-F0-9]{40}$/.test(chainSpecific)) {
      return chainSpecific as `0x${string}`;
    }
    const general = process.env["NEXT_PUBLIC_USDC_ADDRESS"];
    if (general && /^0x[a-fA-F0-9]{40}$/.test(general)) {
      return general as `0x${string}`;
    }
  }
  // 默认 Arbitrum One 主网原生 USDC
  if (chainId === 42161) {
    return "0xaf88d065e77c8cC2239327C5EDb3A432268e5831" as `0x${string}`;
  }
  return null;
}

// ──────────── 金库地址（前期 EOA，后期 Safe 多签） ────────────
// 预启动阶段：基金会临时 EOA 接收捐款；正式启动后切换为 Safe 多签
// 通过 NEXT_PUBLIC_TREASURY_ADDRESS 环境变量覆盖
// 未配置环境变量时，Arbitrum One 主网 (42161) 使用下方硬编码的临时金库 EOA
const TREASURY_EOA_ARBITRUM_MAINNET =
  "0x973B213023bdAfa8cD4a895e4dE748d2503E7137" as `0x${string}`;

export function getTreasuryAddress(chainId: number): `0x${string}` | null {
  if (typeof process !== "undefined" && process.env) {
    const chainSpecific = process.env[`NEXT_PUBLIC_TREASURY_${chainId}_ADDRESS`];
    if (chainSpecific && /^0x[a-fA-F0-9]{40}$/.test(chainSpecific)) {
      return chainSpecific as `0x${string}`;
    }
    const general = process.env["NEXT_PUBLIC_TREASURY_ADDRESS"];
    if (general && /^0x[a-fA-F0-9]{40}$/.test(general)) {
      return general as `0x${string}`;
    }
  }
  // 默认：Arbitrum One 主网临时金库 EOA（预启动阶段）
  if (chainId === 42161) {
    return TREASURY_EOA_ARBITRUM_MAINNET;
  }
  return null;
}
