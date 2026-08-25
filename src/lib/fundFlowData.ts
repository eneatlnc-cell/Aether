// SPDX-License-Identifier: Apache-2.0
import { getTreasuryAddress as _getTreasuryAddress } from "@/lib/contracts/config";

export type AssetCode = "USDC" | "USDT" | "ETH";

export type DonationPurpose =
  | "ai-framework"
  | "self-organizing-net"
  | "unrestricted";

export interface AssetHolding {
  asset: AssetCode;
  amount: number;
  /** USD 估值 */
  usdValue: number;
}

export interface ProjectFund {
  projectId: "ai-framework" | "self-organizing-net";
  allocatedUsd: number;
  spentUsd: number;
  /** 预算上限 USD */
  budgetUsd: number;
}

export interface TreasuryTransaction {
  id: string;
  /** ISO 时间 */
  timestamp: string;
  direction: "in" | "out";
  asset: AssetCode;
  amount: number;
  usdValue: number;
  purpose: DonationPurpose;
  counterparty: string;
  txHash: string;
}

export interface MonthlyFlowPoint {
  /** 月份标签，如 "2025-08" */
  month: string;
  incomeUsd: number;
  expenseUsd: number;
}

export interface FundFlowSnapshot {
  totalDonated: AssetHolding[];
  projectFunds: ProjectFund[];
  treasuryBalanceUsd: number;
  monthlyFlow: MonthlyFlowPoint[];
}

/**
 * 基金会金库地址（前期 EOA，后期 Safe 多签）
 * 从环境变量 NEXT_PUBLIC_TREASURY_ADDRESS 读取
 * 未配置时返回 null，前端应显示"配置中"
 */
export function getTreasuryAddress(chainId: number): `0x${string}` | null {
  return _getTreasuryAddress(chainId);
}

// 保留旧常量名兼容（内部用），但改为 null 占位，强制走 getTreasuryAddress
export const TREASURY_ADDRESSES: Record<"bsc" | "ethereum", string> = {
  bsc: "",
  ethereum: "",
};

export const PREFERRED_ASSET: AssetCode = "USDC";

export const fundFlow: FundFlowSnapshot = {
  totalDonated: [
    { asset: "USDC", amount: 512_340, usdValue: 512_340 },
    { asset: "USDT", amount: 88_500, usdValue: 88_500 },
    { asset: "ETH", amount: 124.6, usdValue: 312_876 },
  ],
  projectFunds: [
    {
      projectId: "ai-framework",
      allocatedUsd: 280_000,
      spentUsd: 184_500,
      budgetUsd: 300_000,
    },
    {
      projectId: "self-organizing-net",
      allocatedUsd: 180_000,
      spentUsd: 91_200,
      budgetUsd: 300_000,
    },
  ],
  treasuryBalanceUsd: 412_540,
  monthlyFlow: buildMonthlyFlow(),
};

function buildMonthlyFlow(): MonthlyFlowPoint[] {
  const now = new Date("2026-07-01");
  const points: MonthlyFlowPoint[] = [];
  for (let i = 11; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
    const month = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
    // 用确定性伪随机，避免每次渲染抖动
    const seed = d.getFullYear() * 12 + d.getMonth();
    const income = 38_000 + ((seed * 7) % 26_000);
    const expense = 22_000 + ((seed * 13) % 18_000);
    points.push({ month, incomeUsd: income, expenseUsd: expense });
  }
  return points;
}

export const treasuryTransactions: TreasuryTransaction[] = [
  {
    id: "tx-001",
    timestamp: "2026-07-18T09:24:00Z",
    direction: "in",
    asset: "USDC",
    amount: 25_000,
    usdValue: 25_000,
    purpose: "ai-framework",
    counterparty: "0x7a3F…b29C",
    txHash: "0xab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56",
  },
  {
    id: "tx-003",
    timestamp: "2026-07-12T03:48:00Z",
    direction: "in",
    asset: "ETH",
    amount: 6.2,
    usdValue: 15_568,
    purpose: "unrestricted",
    counterparty: "0x9b1E…44d2",
    txHash: "0xef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34",
  },
  {
    id: "tx-004",
    timestamp: "2026-07-08T18:32:00Z",
    direction: "out",
    asset: "USDC",
    amount: 12_000,
    usdValue: 12_000,
    purpose: "self-organizing-net",
    counterparty: "0x2c8D…77ab",
    txHash: "0x56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef",
  },
  {
    id: "tx-005",
    timestamp: "2026-07-03T11:05:00Z",
    direction: "in",
    asset: "USDT",
    amount: 10_000,
    usdValue: 10_000,
    purpose: "ai-framework",
    counterparty: "0xa5F2…3b91",
    txHash: "0x12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab",
  },
];
