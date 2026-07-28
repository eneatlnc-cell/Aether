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

// ERC20 最小 ABI（预启动阶段只需 transfer，直接转 USDC 到金库 EOA）
const ERC20_ABI = [
  {
    inputs: [
      { internalType: "address", name: "to", type: "address" },
      { internalType: "uint256", name: "amount", type: "uint256" },
    ],
    name: "transfer",
    outputs: [{ internalType: "bool", name: "", type: "bool" }],
    stateMutability: "nonpayable",
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
//  捐款流程（预启动阶段）：USDC.transfer + 后端记录
//  真实 USDC 转账到金库 EOA；公民身份与道环由后端模拟生成
// ═══════════════════════════════════════════════════════════

export type DonationStep =
  | "idle"
  | "form"
  | "transferring" // 等待用户签 USDC.transfer
  | "transfer-pending" // transfer tx 等待上链确认
  | "recording" // 调用后端 /api/donations/record 记录捐款 + 生成模拟道环
  | "success"
  | "error";

export interface DonationResult {
  /** USDC.transfer 的 tx hash（链上真实转账） */
  txHash: string;
  /** 捐款金额（USDC，原始 6 decimals） */
  amount: bigint;
  /** 捐款用途（仅前端展示用，后端记录但不入合约） */
  purpose: DonationPurpose;
  /** 时间戳（ms） */
  timestamp: number;
  /** 捐款人地址 */
  donor: Address;
  /** 金库地址（USDC 接收方，预启动阶段为 EOA） */
  treasury: Address;
  /** 后端生成的模拟道环 ID（keccak256，0x + 64 hex） */
  ringId?: string;
  /** 是否为该地址的首次捐款（首次时生成公民身份） */
  isFirstDonation?: boolean;
}

interface SubmitArgs {
  amount: bigint; // USDC 6 decimals
  purpose: DonationPurpose;
}

/**
 * 捐款 Hook（预启动阶段）—— USDC.transfer + 后端记录
 *
 * 流程：
 *   1. USDC.transfer(treasury EOA, amount) —— 真实链上转账，无合约调用
 *   2. 等待 tx 上链确认
 *   3. POST /api/donations/record —— 后端验证 tx + 入库 + 生成模拟道环 ID
 *
 * 用户感知：点捐款 → 钱包弹 transfer 签名 → 等待确认 → 生成公民身份 → 完成。
 * 公民身份与道环为前端模拟（后端 DB 持久化），正式启动后迁移至主网合约。
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

  // ── 解析地址（预启动阶段不需要 donation 合约地址） ──
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
      if (!usdc || !treasury) {
        push(t("errorConfig"), "info");
        return;
      }

      let transferTx: `0x${string}` | null = null;
      try {
        // ── 步骤 1：USDC.transfer 直接转给金库 EOA ──
        setStep("transferring");
        transferTx = await writeContractAsync({
          address: usdc,
          abi: ERC20_ABI,
          functionName: "transfer",
          args: [treasury, amount],
          chainId: chainId,
        });
        setLastTxHash(transferTx);
        setStep("transfer-pending");
        // 等待 transfer tx 上链确认
        await waitForTransactionReceipt(wagmiConfig, {
          hash: transferTx,
          confirmations: 1,
        });

        // ── 步骤 2：调用后端记录捐款 + 生成模拟道环 ──
        setStep("recording");
        const apiRes = await fetch("/api/donations/record", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            txHash: transferTx,
            donorAddress: address,
            purpose,
          }),
        });

        // 200 = 新记录；409 = 已记录（幂等，同样视为成功）
        if (apiRes.status !== 200 && apiRes.status !== 409) {
          const body = await apiRes.json().catch(() => ({}));
          throw new Error(body.error ?? `Record failed (${apiRes.status})`);
        }
        const data = (await apiRes.json()) as {
          ringId?: string;
          isFirstDonation?: boolean;
        };

        const donationResult: DonationResult = {
          txHash: transferTx,
          amount,
          purpose,
          timestamp: Date.now(),
          donor: address,
          treasury,
          ringId: data.ringId,
          isFirstDonation: data.isFirstDonation,
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
          // 用户在钱包签名阶段取消，回到表单
          setStep("form");
        } else {
          console.error("[useDonation] submit failed:", err);
          setStep("error");
          push(tToast("error"), "info");
        }
      }
    },
    [address, isConnected, chainId, usdc, treasury, writeContractAsync, wagmiConfig, push, t, tToast]
  );

  return {
    step,
    result,
    isConnected,
    preferredAsset: PREFERRED_ASSET,
    treasuryAddress: treasury ?? "",
    usdcAddress: usdc,
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
