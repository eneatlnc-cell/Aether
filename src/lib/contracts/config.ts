// SPDX-License-Identifier: Apache-2.0
// Aether DAO 合约配置
// 部署后通过 NEXT_PUBLIC_* 环境变量注入地址（Vercel / .env.local）
// 硬编码值作为 fallback，未设置环境变量时使用
//
// v3.6（单链 BSC）：目标主网为 BNB Smart Chain（56），Arbitrum 支持已移除
// （早期仅作测试链使用，从未部署主网）。
// 稳定币抽象 StablecoinConfig：地址 + decimals + symbol 按链配置，
// BSC 的 Binance-Peg USDC/USDT（18 decimals）金额换算不硬编码精度。

import { bsc, bscTestnet } from "wagmi/chains";

export type ContractSet = {
  AetherRing: `0x${string}`;
  AetherGovernance: `0x${string}`;
  AetherElection: `0x${string}`;
  AetherDonation: `0x${string}`;
};

const ZERO = "0x0000000000000000000000000000000000000000" as `0x${string}`;

// ──────────── 链 ID 常量 ────────────
export const CHAIN_IDS = {
  bsc: 56,
  bscTestnet: 97,
  anvil: 31337,
} as const;

// ──────────── 硬编码 fallback（保持兼容旧部署） ────────────
// 默认全部为零地址；真实地址通过 NEXT_PUBLIC_* 注入
const FALLBACK: ContractSet = {
  AetherRing: ZERO,
  AetherGovernance: ZERO,
  AetherElection: ZERO,
  AetherDonation: ZERO,
};

export const CONTRACTS = {
  [bsc.id]: { ...FALLBACK }, // BNB Smart Chain 主网（唯一目标部署链）
  [bscTestnet.id]: { ...FALLBACK }, // BSC 测试网
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

// ═══════════════════════════════════════════════════════════
//  稳定币抽象：地址 + decimals + symbol 按链配置
//  与合约 AetherDonation 的动态 decimals 逻辑对齐：
//  同一份前端在不同精度稳定币上语义一致
// ═══════════════════════════════════════════════════════════

export interface StablecoinConfig {
  address: `0x${string}`;
  decimals: number;
  symbol: string;
}

/** 各链默认稳定币（未配置环境变量时使用） */
const STABLECOIN_DEFAULTS: Record<number, StablecoinConfig> = {
  // BNB Smart Chain 主网：Binance-Peg USDC（BEP-20，18 decimals）
  [CHAIN_IDS.bsc]: {
    address: "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d",
    decimals: 18,
    symbol: "USDC",
  },
  // BSC 测试网 / Anvil：无权威默认值，必须用环境变量注入
};

/** 环境变量里读取 0x 地址的通用工具 */
function envAddr(names: string[]): `0x${string}` | null {
  if (typeof process === "undefined" || !process.env) return null;
  for (const n of names) {
    const v = process.env[n];
    if (v && /^0x[a-fA-F0-9]{40}$/.test(v)) return v as `0x${string}`;
  }
  return null;
}

/**
 * 获取某链的捐款稳定币配置。
 *
 * 环境变量优先（支持通用与链专属两套命名，稳定币新命名与 USDC 旧命名均兼容）：
 *   - NEXT_PUBLIC_STABLECOIN_ADDRESS / NEXT_PUBLIC_STABLECOIN_<CHAINID>_ADDRESS
 *   - NEXT_PUBLIC_USDC_ADDRESS / NEXT_PUBLIC_USDC_<CHAINID>_ADDRESS（旧）
 *   - NEXT_PUBLIC_STABLECOIN_DECIMALS / NEXT_PUBLIC_STABLECOIN_<CHAINID>_DECIMALS
 *     （仅当用环境变量覆盖地址时需要；默认值自带 decimals）
 *   - NEXT_PUBLIC_STABLECOIN_SYMBOL（可选，默认 "USDC"）
 *
 * 无默认值且未配置 → null（前端应显示"未配置"并禁用捐款）。
 */
export function getStablecoin(chainId: number): StablecoinConfig | null {
  const address = envAddr([
    `NEXT_PUBLIC_STABLECOIN_${chainId}_ADDRESS`,
    "NEXT_PUBLIC_STABLECOIN_ADDRESS",
    `NEXT_PUBLIC_USDC_${chainId}_ADDRESS`,
    "NEXT_PUBLIC_USDC_ADDRESS",
  ]);

  if (address) {
    // 环境变量覆盖地址：优先已知默认地址的 decimals，其次 DECIMALS 环境变量
    const known = STABLECOIN_DEFAULTS[chainId];
    const decimalsEnv =
      process.env?.[`NEXT_PUBLIC_STABLECOIN_${chainId}_DECIMALS`] ??
      process.env?.["NEXT_PUBLIC_STABLECOIN_DECIMALS"];
    const decimals =
      known && known.address.toLowerCase() === address.toLowerCase()
        ? known.decimals
        : decimalsEnv
          ? Number(decimalsEnv)
          : (known?.decimals ?? 18);
    const symbol =
      process.env?.[`NEXT_PUBLIC_STABLECOIN_${chainId}_SYMBOL`] ??
      process.env?.["NEXT_PUBLIC_STABLECOIN_SYMBOL"] ??
      known?.symbol ??
      "USDC";
    return { address, decimals, symbol };
  }

  return STABLECOIN_DEFAULTS[chainId] ?? null;
}

/**
 * 兼容旧接口：USDC（捐款稳定币）地址。
 */
export function getUsdcAddress(chainId: number): `0x${string}` | null {
  return getStablecoin(chainId)?.address ?? null;
}

/** 最低捐款额（整数美元部分，与合约 MIN_DONATION_WHOLE_USD 一致） */
export const MIN_DONATION_WHOLE_USD = 10n;

/**
 * 按链精度计算最低捐款额（最小单位），与合约 MIN_DONATION_USD 对齐。
 * 例：BSC（18 decimals）→ 10 * 10^18。
 * 未配置稳定币的链返回 null（前端应禁用捐款）。
 */
export function getMinDonation(chainId: number): bigint | null {
  const sc = getStablecoin(chainId);
  if (!sc) return null;
  return MIN_DONATION_WHOLE_USD * 10n ** BigInt(sc.decimals);
}

// ──────────── 网络标签（收据/展示用） ────────────
const NETWORK_LABELS: Record<number, string> = {
  [CHAIN_IDS.bsc]: "BNB Smart Chain",
  [CHAIN_IDS.bscTestnet]: "BSC Testnet",
  [CHAIN_IDS.anvil]: "Anvil (local)",
};

export function getNetworkLabel(chainId: number): string {
  return NETWORK_LABELS[chainId] ?? `Chain ${chainId}`;
}

// ──────────── 金库地址（前期 EOA，后期 Safe 多签） ────────────
// 预启动阶段：基金会临时 EOA 接收捐款；正式启动后切换为 Safe 多签
// 通过 NEXT_PUBLIC_TREASURY_ADDRESS 环境变量覆盖
// 注意：任何链都无硬编码默认金库，必须在环境变量中显式配置（fail-safe）
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
  return null;
}
