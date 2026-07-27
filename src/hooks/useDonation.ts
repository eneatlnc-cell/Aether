"use client";

import { useCallback, useMemo, useState } from "react";
import {
  useAccount,
  useConfig,
  useReadContract,
  useReadContracts,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { waitForTransactionReceipt } from "@wagmi/core";
import type { Address } from "viem";
import { useToast } from "@/components/ui/Toast";
import { useTranslations } from "next-intl";
import { PREFERRED_ASSET, type AssetCode, type DonationPurpose } from "@/lib/fundFlowData";
import {
  AetherDonationABI,
  AetherRingABI,
  donationAddress,
  ringAddress,
  getUsdcAddress,
  getTreasuryAddress,
} from "@/lib/contracts";

// ERC20 approve 用的最小 ABI（只用到 approve）
const ERC20_ABI = [
  {
    inputs: [
      { internalType: "address", name: "spender", type: "address" },
      { internalType: "uint256", name: "amount", type: "uint256" },
    ],
    name: "approve",
    outputs: [{ internalType: "bool", name: "", type: "bool" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { internalType: "address", name: "owner", type: "address" },
      { internalType: "address", name: "spender", type: "address" },
    ],
    name: "allowance",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

// ═══════════════════════════════════════════════════════════
//  常量（与合约 AetherDonation.sol 对齐）
// ═══════════════════════════════════════════════════════════

/** 最低捐款金额（$10，USDC 6 decimals） */
export const MIN_DONATION_USD = 10n * 10n ** 6n;
/** 快速通道所需担保人数 */
export const SPONSORS_REQUIRED = 3;
/** 快速通道等待期（24h） */
export const FAST_TRACK_DELAY = 24 * 60 * 60;
/** 普通通道等待期（7 天） */
export const NORMAL_TRACK_DELAY = 7 * 24 * 60 * 60;

// ═══════════════════════════════════════════════════════════
//  类型定义（与新合约 IAetherDonation.Donation 对齐，5 字段）
// ═══════════════════════════════════════════════════════════

/** 与 IAetherDonation.Donation 对齐的 5 字段结构体 */
export interface DonationInfo {
  donor: `0x${string}`;
  amount: bigint; // USDC 数量（6 decimals）
  timestamp: number; // 铸造时间戳（秒）
  sponsorCount: number; // 当前担保人数
  fastTrackActivated: boolean; // 是否已激活快速通道
}

// ═══════════════════════════════════════════════════════════
//  捐款流程：approve + donateAndMint 两步串行
// ═══════════════════════════════════════════════════════════

export type DonationStep =
  | "idle"
  | "form"
  | "approving" // 等待用户签 approve
  | "approve-pending" // approve tx 等待确认
  | "donating" // 等待用户签 donateAndMint
  | "donate-pending" // donateAndMint tx 等待确认
  | "success"
  | "error";

export interface DonationResult {
  /** donateAndMint 的 tx hash（铸环+转账+凭证 NFT 的最终交易） */
  txHash: string;
  /** 捐款金额（USDC，原始 6 decimals） */
  amount: bigint;
  /** 捐款用途（仅前端展示用，合约不记录） */
  purpose: DonationPurpose;
  /** 时间戳（ms） */
  timestamp: number;
  /** 捐款人地址 */
  donor: Address;
  /** 金库地址（USDC 接收方） */
  treasury: Address;
  /** 新铸的捐款凭证 NFT tokenId（如有） */
  donationTokenId?: bigint;
}

interface SubmitArgs {
  amount: bigint; // USDC 6 decimals
  purpose: DonationPurpose;
}

/**
 * 捐款 Hook —— approve + donateAndMint 两步串行
 *
 * 流程：
 *   1. 检查 USDC allowance，若不足则先 approve
 *   2. 调 AetherDonation.donateAndMint(amount)
 *      合约内部：transferFrom USDC 到 treasury + 铸捐款凭证 NFT + 铸公民道环（首次）
 *   3. 等待 tx 确认，返回结果
 *
 * 全部在 Arbitrum 主网执行。用户感知：点捐款 → 钱包弹 approve → 钱包弹 donateAndMint → 完成。
 */
export function useDonation() {
  const t = useTranslations("donation");
  const tToast = useTranslations("toast");
  const { push } = useToast();
  const { address, isConnected, chainId } = useAccount();
  const wagmiConfig = useConfig();
  const { writeContractAsync, isPending: writing } = useWriteContract();

  const [step, setStep] = useState<DonationStep>("idle");
  const [result, setResult] = useState<DonationResult | null>(null);
  const [lastTxHash, setLastTxHash] = useState<`0x${string}` | null>(null);

  const receiptQuery = useWaitForTransactionReceipt({
    hash: lastTxHash ?? undefined,
  });

  const reset = useCallback(() => {
    setStep("idle");
    setResult(null);
    setLastTxHash(null);
  }, []);

  // ── 解析地址 ──
  const donation = donationAddress(chainId ?? 0);
  const usdc = getUsdcAddress(chainId ?? 0);
  const treasury = getTreasuryAddress(chainId ?? 0);

  const submit = useCallback(
    async ({ amount, purpose }: SubmitArgs) => {
      if (!isConnected || !address) {
        push(t("connectFirst"), "info");
        return;
      }
      if (amount < MIN_DONATION_USD) {
        push(t("errorMinAmount"), "info");
        return;
      }
      if (!donation || !usdc || !treasury) {
        push(t("errorConfig"), "info");
        return;
      }

      try {
        // ── 步骤 1：approve USDC（精确金额，覆盖旧额度） ──
        setStep("approving");
        const approveTx = await writeContractAsync({
          address: usdc,
          abi: ERC20_ABI,
          functionName: "approve",
          args: [donation, amount],
          chainId: chainId,
        });
        setStep("approve-pending");
        // 正确等待 approve tx 上链确认（@wagmi/core action，非响应式 hook）
        await waitForTransactionReceipt(wagmiConfig, {
          hash: approveTx,
          confirmations: 1,
        });

        // ── 步骤 2：调 donateAndMint（合约内部 transferFrom + 铸 NFT + 铸道环） ──
        setStep("donating");
        const donateTx = await writeContractAsync({
          address: donation,
          abi: AetherDonationABI,
          functionName: "donateAndMint",
          args: [amount],
          chainId: chainId,
        });
        setLastTxHash(donateTx);
        setStep("donate-pending");
        // 等 donateAndMint tx 确认
        await waitForTransactionReceipt(wagmiConfig, {
          hash: donateTx,
          confirmations: 1,
        });

        const donationResult: DonationResult = {
          txHash: donateTx,
          amount,
          purpose,
          timestamp: Date.now(),
          donor: address,
          treasury,
        };
        setResult(donationResult);
        setStep("success");
        push(tToast("donationSuccess"), "success");
      } catch (err) {
        const name = (err as Error)?.name ?? "";
        const msg = (err as Error)?.message ?? "";
        if (
          name === "UserRejectedRequestError" ||
          /user rejected/i.test(msg) ||
          /rejected the request/i.test(msg)
        ) {
          // 用户取消，回到表单
          setStep("form");
        } else {
          console.error("[useDonation] submit failed:", err);
          setStep("error");
          push(tToast("error"), "info");
        }
      }
    },
    [address, isConnected, chainId, donation, usdc, treasury, writeContractAsync, wagmiConfig, push, t, tToast]
  );

  return {
    step,
    result,
    isConnected,
    preferredAsset: PREFERRED_ASSET,
    treasuryAddress: treasury ?? "",
    usdcAddress: usdc,
    donationAddress: donation,
    submit,
    reset,
    /** wagmi 写入状态 */
    writing,
    /** 最近一笔 tx 的 receipt */
    receipt: receiptQuery.data,
    isConfirming: receiptQuery.isLoading,
  };
}

// ═══════════════════════════════════════════════════════════
//  读取 hooks（AetherDonation 合约查询）
// ═══════════════════════════════════════════════════════════

/**
 * useDonationInfo — 读取单笔捐款凭证详情（getDonation，5 字段）
 */
export function useDonationInfo(tokenId: bigint | null) {
  const { chainId } = useAccount();
  const donation = donationAddress(chainId ?? 0);
  const enabled = !!donation && tokenId !== null;

  const query = useReadContract({
    address: donation ?? undefined,
    abi: AetherDonationABI,
    functionName: "getDonation",
    args: [tokenId ?? 0n],
    query: { enabled },
  });

  const info = useMemo<DonationInfo | null>(() => {
    if (!query.data || query.status !== "success") return null;
    const raw = query.data as unknown as readonly unknown[];
    return {
      donor: raw[0] as `0x${string}`,
      amount: raw[1] as bigint,
      timestamp: Number(raw[2] as bigint),
      sponsorCount: Number(raw[3] as bigint),
      fastTrackActivated: raw[4] as boolean,
    };
  }, [query.data, query.status]);

  return {
    info,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/**
 * useDonationsByDonor — 读取某地址的所有捐款 tokenId 列表
 */
export function useDonationsByDonor(donor: `0x${string}` | null) {
  const { chainId } = useAccount();
  const donation = donationAddress(chainId ?? 0);
  const enabled = !!donation && !!donor;

  const query = useReadContract({
    address: donation ?? undefined,
    abi: AetherDonationABI,
    functionName: "getDonationsByDonor",
    args: [donor ?? "0x0"],
    query: { enabled },
  });

  return {
    tokenIds: (query.data as bigint[] | undefined) ?? [],
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/**
 * useTotalDonations — 读取捐款凭证总数
 */
export function useTotalDonations() {
  const { chainId } = useAccount();
  const donation = donationAddress(chainId ?? 0);
  const query = useReadContract({
    address: donation ?? undefined,
    abi: AetherDonationABI,
    functionName: "getTotalDonations",
    query: { enabled: !!donation },
  });
  return {
    total: (query.data as bigint | undefined) ?? 0n,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/**
 * useSponsorCount — 读取某捐款凭证的当前担保人数
 */
export function useSponsorCount(tokenId: bigint | null) {
  const { chainId } = useAccount();
  const donation = donationAddress(chainId ?? 0);
  const query = useReadContract({
    address: donation ?? undefined,
    abi: AetherDonationABI,
    functionName: "getSponsorCount",
    args: [tokenId ?? 0n],
    query: { enabled: !!donation && tokenId !== null },
  });
  return {
    sponsorCount: Number((query.data as bigint | undefined) ?? 0n),
    isLoading: query.isLoading,
    isError: query.isError,
    thresholdMet:
      Number((query.data as bigint | undefined) ?? 0n) >= SPONSORS_REQUIRED,
  };
}

/**
 * useIsFastTrackActivated — 读取某捐款是否已激活快速通道
 */
export function useIsFastTrackActivated(tokenId: bigint | null) {
  const { chainId } = useAccount();
  const donation = donationAddress(chainId ?? 0);
  const query = useReadContract({
    address: donation ?? undefined,
    abi: AetherDonationABI,
    functionName: "isFastTrackActivated",
    args: [tokenId ?? 0n],
    query: { enabled: !!donation && tokenId !== null },
  });
  return {
    fastTrackActivated: (query.data as boolean | undefined) ?? false,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/**
 * useHasSponsored — 读取某地址是否已担保某笔捐款
 */
export function useHasSponsored(
  tokenId: bigint | null,
  sponsor: `0x${string}` | null,
) {
  const { chainId } = useAccount();
  const donation = donationAddress(chainId ?? 0);
  const enabled = !!donation && tokenId !== null && !!sponsor;

  const query = useReadContract({
    address: donation ?? undefined,
    abi: AetherDonationABI,
    functionName: "hasSponsoredDonation",
    args: [tokenId ?? 0n, sponsor ?? "0x0"],
    query: { enabled },
  });
  return {
    hasSponsored: (query.data as boolean | undefined) ?? false,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/**
 * useCanReacquireCitizenship — 代理查询：donor 是否可重新获取公民身份
 */
export function useCanReacquireCitizenship(user: `0x${string}` | null) {
  const { chainId } = useAccount();
  const donation = donationAddress(chainId ?? 0);
  const enabled = !!donation && !!user;

  const query = useReadContract({
    address: donation ?? undefined,
    abi: AetherDonationABI,
    functionName: "canReacquireCitizenship",
    args: [user ?? "0x0"],
    query: { enabled },
  });
  return {
    canReacquire: (query.data as boolean | undefined) ?? false,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/**
 * useDonationTreasury — 读取合约记录的国库地址
 */
export function useDonationTreasury() {
  const { chainId } = useAccount();
  const donation = donationAddress(chainId ?? 0);
  const query = useReadContract({
    address: donation ?? undefined,
    abi: AetherDonationABI,
    functionName: "treasury",
    query: { enabled: !!donation },
  });
  return {
    treasury: (query.data as `0x${string}` | undefined) ?? null,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/**
 * useDonorStatus — 批量查询当前用户的捐款参与状态
 */
export function useDonorStatus(donor: `0x${string}` | null) {
  const { chainId } = useAccount();
  const donation = donationAddress(chainId ?? 0);
  const enabled = !!donation && !!donor;

  const query = useReadContracts({
    contracts: [
      {
        address: donation!,
        abi: AetherDonationABI,
        functionName: "getDonationsByDonor",
        args: [donor ?? "0x0"],
      },
      {
        address: donation!,
        abi: AetherDonationABI,
        functionName: "getTotalDonations",
      },
    ],
    query: { enabled },
  });

  const status = useMemo(() => {
    if (!query.data) {
      return {
        donationTokenIds: [] as bigint[],
        totalDonations: 0n,
      };
    }
    const safe = <T>(i: number, fallback: T): T =>
      query.data![i].status === "success"
        ? (query.data![i].result as T)
        : fallback;
    return {
      donationTokenIds: safe<bigint[]>(0, []),
      totalDonations: safe<bigint>(1, 0n),
    };
  }, [query.data]);

  return {
    status,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

// ═══════════════════════════════════════════════════════════
//  道环查询 hooks（AetherRing 合约）
// ═══════════════════════════════════════════════════════════

/**
 * useRingInfo — 读取当前用户持有的道环信息
 * 返回 tokenId（0 表示无道环）和 tier（0-14）
 */
export function useRingInfo(holder: `0x${string}` | null) {
  const { chainId } = useAccount();
  const ring = ringAddress(chainId ?? 0);
  const enabled = !!ring && !!holder;

  const query = useReadContracts({
    contracts: [
      {
        address: ring!,
        abi: AetherRingABI,
        functionName: "getRingId",
        args: [holder ?? "0x0"],
      },
      {
        address: ring!,
        abi: AetherRingABI,
        functionName: "getTier",
        args: [holder ?? "0x0"],
      },
      {
        address: ring!,
        abi: AetherRingABI,
        functionName: "isBearer",
        args: [holder ?? "0x0"],
      },
    ],
    query: { enabled },
  });

  const info = useMemo(() => {
    if (!query.data) {
      return {
        ringId: 0n,
        tier: 0,
        isBearer: false,
      };
    }
    const safe = <T>(i: number, fallback: T): T =>
      query.data![i].status === "success"
        ? (query.data![i].result as T)
        : fallback;
    return {
      ringId: safe<bigint>(0, 0n),
      tier: Number(safe<bigint>(1, 0n)),
      isBearer: safe<boolean>(2, false),
    };
  }, [query.data]);

  return {
    ...info,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

// ═══════════════════════════════════════════════════════════
//  写入 hook（AetherDonation 合约交互）
// ═══════════════════════════════════════════════════════════

/**
 * useDonationWrite — AetherDonation 写入 hook
 *
 * 写入方法：
 *   - 任意地址：donateAndMint（核心捐款入口）
 *   - 任意活跃公民（tier==14）：sponsorDonation
 *   - ADMIN_ROLE：setTreasury / setRingContract / setUsdcToken
 */
export function useDonationWrite() {
  const { chainId } = useAccount();
  const donation = donationAddress(chainId ?? 0);
  const { writeContractAsync, isPending: writing } = useWriteContract();
  const [lastTxHash, setLastTxHash] = useState<`0x${string}` | null>(null);
  const receiptQuery = useWaitForTransactionReceipt({ hash: lastTxHash ?? undefined });

  const ensure = () => {
    if (!donation) throw new Error("AetherDonation 合约未部署");
    return donation;
  };

  // ── 任意地址：捐款 + 铸环 ──
  const donateAndMint = async (amount: bigint): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherDonationABI,
      functionName: "donateAndMint",
      args: [amount],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 任意活跃公民：担保捐款 ──
  const sponsorDonation = async (tokenId: bigint): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherDonationABI,
      functionName: "sponsorDonation",
      args: [tokenId],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── ADMIN_ROLE：更新国库地址 ──
  const setTreasury = async (
    newTreasury: `0x${string}`,
  ): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherDonationABI,
      functionName: "setTreasury",
      args: [newTreasury],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── ADMIN_ROLE：更换道环合约引用 ──
  const setRingContract = async (
    newRing: `0x${string}`,
  ): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherDonationABI,
      functionName: "setRingContract",
      args: [newRing],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── ADMIN_ROLE：更新 USDC 合约地址 ──
  const setUsdcToken = async (
    newUsdc: `0x${string}`,
  ): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherDonationABI,
      functionName: "setUsdcToken",
      args: [newUsdc],
    });
    setLastTxHash(tx);
    return tx;
  };

  return {
    donateAndMint,
    sponsorDonation,
    setTreasury,
    setRingContract,
    setUsdcToken,
    writing,
    lastTxHash,
    receipt: receiptQuery.data,
    isConfirming: receiptQuery.isLoading,
    isConfirmed: !!receiptQuery.data,
  };
}
