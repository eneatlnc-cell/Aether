"use client";

import { useCallback, useMemo, useState } from "react";
import {
  useAccount,
  useReadContract,
  useReadContracts,
  useSendTransaction,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { parseUnits, type Address } from "viem";
import { useToast } from "@/components/ui/Toast";
import { useTranslations } from "next-intl";
import {
  TREASURY_ADDRESSES,
  PREFERRED_ASSET,
  type AssetCode,
  type DonationPurpose,
} from "@/lib/fundFlowData";
import {
  AetherDonationABI,
  donationAddress,
} from "@/lib/contracts";

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
//  类型定义（v3 合约 Donation 结构体，9 字段）
// ═══════════════════════════════════════════════════════════

/** 与 IAetherDonation.Donation 对齐的 9 字段结构体 */
export interface DonationInfo {
  donor: `0x${string}`;
  amount: bigint; // 捐款金额（USD 6 decimals）
  usdcAmount: bigint; // 实际注入国库的 USDC（settle 后 > 0）
  paypalTxId: string;
  paypalAccountHash: `0x${string}`;
  timestamp: number; // 铸造时间戳（秒）
  isSettled: boolean; // 是否已多签结算
  sponsorCount: number; // 当前担保人数
  fastTrackActivated: boolean; // 是否已激活快速通道
}

// ═══════════════════════════════════════════════════════════
//  旧版 ETH 转账流程（DonationModal UI 兼容，保持不变）
// ═══════════════════════════════════════════════════════════

export type DonationStep =
  | "idle"
  | "form"
  | "awaiting-signature"
  | "submitting"
  | "success"
  | "error";

export interface DonationResult {
  txHash: string;
  asset: AssetCode;
  amount: number;
  purpose: DonationPurpose;
  timestamp: number;
  donor: Address;
  treasury: Address;
}

interface SubmitArgs {
  asset: AssetCode;
  amount: number;
  purpose: DonationPurpose;
}

/**
 * 旧版捐赠流程 Hook（ETH 直接转账到国库多签地址）
 *
 * 保留原因：v3 合约 AetherDonation 不直接接收 ETH/USDC，
 * 实际资金通过 PayPal 链下流转 + 链上 SBT 铸造（mintDonation）。
 * 但前端 DonationModal 仍需要一个"链上 ETH 转账"入口用于：
 *  - 直接 ETH 捐赠（绕过 PayPal）
 *  - UI 流程演示
 *
 * v3 合约集成请使用下方的 useDonationInfo / useDonationWrite 等 hooks。
 */
export function useDonation() {
  const t = useTranslations("donation");
  const tToast = useTranslations("toast");
  const { push } = useToast();
  const { address, isConnected } = useAccount();
  const { sendTransactionAsync } = useSendTransaction();

  const [step, setStep] = useState<DonationStep>("idle");
  const [result, setResult] = useState<DonationResult | null>(null);

  const reset = useCallback(() => {
    setStep("idle");
    setResult(null);
  }, []);

  const submit = useCallback(
    async ({ asset, amount, purpose }: SubmitArgs) => {
      if (!isConnected || !address) {
        push(t("connectFirst"), "info");
        return;
      }

      if (amount <= 0) return;

      setStep("awaiting-signature");
      try {
        const treasury = TREASURY_ADDRESSES.arbitrum as Address;
        let txHash: string;

        if (asset === "ETH") {
          // 真实链上 ETH 转账
          const value = parseUnits(amount.toFixed(18), 18);
          const tx = await sendTransactionAsync({
            to: treasury,
            value,
            chainId: 42161,
          });
          txHash = tx;
        } else {
          // USDC / USDT 占位：缺少合约地址，模拟一笔成功交易
          // 真实接入后替换为 ERC20 transfer
          await new Promise((r) => setTimeout(r, 1200));
          txHash =
            "0x" +
            Array.from({ length: 64 }, () =>
              "0123456789abcdef"[Math.floor(Math.random() * 16)]
            ).join("");
        }

        setStep("submitting");
        // 等待确认（ETH 真实交易可监听 receipt，这里简化）
        await new Promise((r) => setTimeout(r, 800));

        const donationResult: DonationResult = {
          txHash,
          asset,
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
        const name = (err as Error)?.name;
        if (name === "UserRejectedRequestError") {
          // 用户取消，静默回到表单
          setStep("form");
        } else {
          setStep("error");
          push(tToast("error"), "info");
        }
      }
    },
    [address, isConnected, sendTransactionAsync, push, t, tToast]
  );

  return {
    step,
    result,
    isConnected,
    preferredAsset: PREFERRED_ASSET,
    treasuryAddress: TREASURY_ADDRESSES.arbitrum,
    submit,
    reset,
  };
}

// ═══════════════════════════════════════════════════════════
//  v3 读取 hooks（AetherDonation 合约查询）
// ═══════════════════════════════════════════════════════════

/**
 * useDonationInfo — 读取单笔捐款凭证详情（getDonation，9 字段）
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
    // wagmi 对 struct 返回值推断为命名对象，需经 unknown 二次转换
    const raw = query.data as unknown as readonly unknown[];
    return {
      donor: raw[0] as `0x${string}`,
      amount: raw[1] as bigint,
      usdcAmount: raw[2] as bigint,
      paypalTxId: raw[3] as string,
      paypalAccountHash: raw[4] as `0x${string}`,
      timestamp: Number(raw[5] as bigint),
      isSettled: raw[6] as boolean,
      sponsorCount: Number(raw[7] as bigint),
      fastTrackActivated: raw[8] as boolean,
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
 * useTotalDonations — 读取捐款凭证总数（已铸 NFT 数量）
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
 * useNextDonationTokenId — 读取下一个将铸的 tokenId（_nextTokenId）
 */
export function useNextDonationTokenId() {
  const { chainId } = useAccount();
  const donation = donationAddress(chainId ?? 0);
  const query = useReadContract({
    address: donation ?? undefined,
    abi: AetherDonationABI,
    functionName: "nextTokenId",
    query: { enabled: !!donation },
  });
  return {
    nextTokenId: (query.data as bigint | undefined) ?? 0n,
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
    /** 是否已达到 3 公民担保阈值 */
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
 *                          （30 天冷却期检查，由 AetherRing.canReacquireCitizenship 实现）
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
 * useDonationTreasury — 读取合约记录的国库多签地址
 *                       （仅记录用，实际 USDC 接收方）
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
 * useUnsettledDonations — 读取未结算的捐款 tokenId 列表（审计用，O(n)）
 */
export function useUnsettledDonations() {
  const { chainId } = useAccount();
  const donation = donationAddress(chainId ?? 0);
  const query = useReadContract({
    address: donation ?? undefined,
    abi: AetherDonationABI,
    functionName: "getUnsettledDonations",
    query: { enabled: !!donation },
  });
  return {
    unsettledTokenIds: (query.data as bigint[] | undefined) ?? [],
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/**
 * useUsedPaypalTxId — 读取某 PayPal 交易 ID 是否已用于防重放
 */
export function useUsedPaypalTxId(paypalTxId: string | null) {
  const { chainId } = useAccount();
  const donation = donationAddress(chainId ?? 0);
  const enabled = !!donation && !!paypalTxId;

  const query = useReadContract({
    address: donation ?? undefined,
    abi: AetherDonationABI,
    functionName: "usedPaypalTxIds",
    args: [paypalTxId ?? ""],
    query: { enabled },
  });
  return {
    used: (query.data as boolean | undefined) ?? false,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/**
 * usePaypalAccountWallet — 读取某 PayPal 账户哈希绑定的钱包地址（防女巫审计）
 *                          返回 0x0 表示尚未绑定
 */
export function usePaypalAccountWallet(
  paypalAccountHash: `0x${string}` | null,
) {
  const { chainId } = useAccount();
  const donation = donationAddress(chainId ?? 0);
  const enabled = !!donation && !!paypalAccountHash;

  const query = useReadContract({
    address: donation ?? undefined,
    abi: AetherDonationABI,
    functionName: "paypalAccountToWallet",
    args: [paypalAccountHash ?? "0x0"],
    query: { enabled },
  });
  return {
    linkedWallet: (query.data as `0x${string}` | undefined) ?? "0x0",
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/**
 * useDonorStatus — 批量查询当前用户的捐款参与状态
 *   - donationTokenIds：用户已铸的捐款凭证列表
 *   - totalDonations：合约总捐款数
 *   - nextTokenId：下一个将铸的 tokenId
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
      {
        address: donation!,
        abi: AetherDonationABI,
        functionName: "nextTokenId",
      },
    ],
    query: { enabled },
  });

  const status = useMemo(() => {
    if (!query.data) {
      return {
        donationTokenIds: [] as bigint[],
        totalDonations: 0n,
        nextTokenId: 0n,
      };
    }
    const safe = <T>(i: number, fallback: T): T =>
      query.data![i].status === "success"
        ? (query.data![i].result as T)
        : fallback;
    return {
      donationTokenIds: safe<bigint[]>(0, []),
      totalDonations: safe<bigint>(1, 0n),
      nextTokenId: safe<bigint>(2, 0n),
    };
  }, [query.data]);

  return {
    status,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

// ═══════════════════════════════════════════════════════════
//  v3 写入 hook（AetherDonation 合约交互）
// ═══════════════════════════════════════════════════════════

/**
 * useDonationWrite — AetherDonation 写入 hook
 *
 * 写入方法分三类权限：
 *   - MINTER_ROLE  (PayPal webhook 服务端)：mintDonation
 *   - ADMIN_ROLE   (Safe 多签)：settleDonation / setTreasury / setRingContract / grantMinterRole / revokeMinterRole
 *   - 任意活跃公民  (tier==14)：sponsorDonation
 *
 * 链下兑换 + 链上 settle 流程：
 *   1. 用户链下 PayPal 付款 → PayPal webhook 调 mintDonation 铸 SBT + 公民道环
 *   2. Safe 多签确认 USDC 到账后调 settleDonation 记录金额
 *   3. 其他公民可调 sponsorDonation 为其担保（凑齐 3 人激活快速通道）
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

  // ── MINTER_ROLE：铸造捐款凭证 NFT（PayPal webhook 服务端调用） ──
  const mintDonation = async (params: {
    donor: `0x${string}`;
    amount: bigint; // USD 6 decimals，≥ MIN_DONATION_USD
    paypalTxId: string;
    paypalAccountHash: `0x${string}`; // keccak256(payer_id)
  }): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherDonationABI,
      functionName: "mintDonation",
      args: [
        params.donor,
        params.amount,
        params.paypalTxId,
        params.paypalAccountHash,
      ],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── ADMIN_ROLE：多签结算（USDC 真实到账后记录） ──
  const settleDonation = async (
    tokenId: bigint,
    usdcAmount: bigint,
  ): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherDonationABI,
      functionName: "settleDonation",
      args: [tokenId, usdcAmount],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 任意活跃公民：担保捐款（凑齐 3 人激活快速通道） ──
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

  // ── ADMIN_ROLE：授予 / 撤销 MINTER_ROLE ──
  const grantMinterRole = async (
    account: `0x${string}`,
  ): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherDonationABI,
      functionName: "grantMinterRole",
      args: [account],
    });
    setLastTxHash(tx);
    return tx;
  };

  const revokeMinterRole = async (
    account: `0x${string}`,
  ): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherDonationABI,
      functionName: "revokeMinterRole",
      args: [account],
    });
    setLastTxHash(tx);
    return tx;
  };

  return {
    // 写入方法
    mintDonation,
    settleDonation,
    sponsorDonation,
    setTreasury,
    setRingContract,
    grantMinterRole,
    revokeMinterRole,
    // 交易状态
    writing,
    lastTxHash,
    receipt: receiptQuery.data,
    isConfirming: receiptQuery.isLoading,
    isConfirmed: !!receiptQuery.data,
  };
}
