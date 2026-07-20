"use client";

import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { useMemo } from "react";
import { AetherRingABI, ringAddress, RingTier } from "@/lib/contracts";

// 与合约 RingInfo struct 对齐
export interface RingInfo {
  tier: RingTier;
  mintedAt: number;
  termEndAt: number;
  consecutiveTerms: number;
  isActive: boolean;
  isEmeritus: boolean;
  isExpired: boolean;
  covenantHash: string;
}

const MAX_UINT64 = BigInt("18446744073709551615");

/**
 * useRingInfo — 读取当前连接钱包的道环信息
 *
 * 用法：
 *   const { ringInfo, isBearer, tier, isLoading } = useRingInfo();
 */
export function useRingInfo() {
  const { address, chainId } = useAccount();
  const ring = ringAddress(chainId ?? 0);

  const enabled = !!address && !!ring;

  // 1. 先取 ringId
  const ringIdQuery = useReadContract({
    address: ring ?? undefined,
    abi: AetherRingABI,
    functionName: "getRingId",
    args: [address ?? "0x0"],
    query: { enabled },
  });

  const ringId = (ringIdQuery.data as bigint | undefined) ?? 0n;
  const hasRing = enabled && ringId > 0n && !ringIdQuery.isLoading;

  // 2. 拿到 ringId 后批量读取详情
  const detailsQuery = useReadContracts({
    contracts: [
      { address: ring!, abi: AetherRingABI, functionName: "getRingInfo", args: [ringId] },
      { address: ring!, abi: AetherRingABI, functionName: "isBearer", args: [address ?? "0x0"] },
      { address: ring!, abi: AetherRingABI, functionName: "getTier", args: [address ?? "0x0"] },
      { address: ring!, abi: AetherRingABI, functionName: "isEmeritus", args: [address ?? "0x0"] },
      { address: ring!, abi: AetherRingABI, functionName: "isExpired", args: [ringId] },
    ],
    query: { enabled: hasRing },
  });

  const info = useMemo<RingInfo | null>(() => {
    if (!hasRing || !detailsQuery.data) return null;
    const [infoRes, , tierRes] = detailsQuery.data;
    if (infoRes.status !== "success" || !infoRes.result) return null;
    const raw = infoRes.result as unknown as {
      tier: number;
      mintedAt: bigint;
      termEndAt: bigint;
      consecutiveTerms: number;
      isActive: boolean;
      isEmeritus: boolean;
      isExpired: boolean;
      covenantHash: string;
    };
    return {
      tier: raw.tier as RingTier,
      mintedAt: Number(raw.mintedAt),
      termEndAt: Number(raw.termEndAt),
      consecutiveTerms: raw.consecutiveTerms,
      isActive: raw.isActive,
      isEmeritus: raw.isEmeritus,
      isExpired: raw.isExpired,
      covenantHash: raw.covenantHash,
    };
  }, [hasRing, detailsQuery.data]);

  const isBearer = useMemo(() => {
    if (!hasRing || !detailsQuery.data) return false;
    return detailsQuery.data[1].status === "success" && detailsQuery.data[1].result === true;
  }, [hasRing, detailsQuery.data]);

  const tier = useMemo<RingTier>(() => {
    if (!hasRing || !detailsQuery.data) return RingTier.NONE;
    const r = detailsQuery.data[2];
    return r.status === "success" ? (r.result as number) : RingTier.NONE;
  }, [hasRing, detailsQuery.data]);

  const isEmeritus = useMemo(() => {
    if (!hasRing || !detailsQuery.data) return false;
    return detailsQuery.data[3].status === "success" && detailsQuery.data[3].result === true;
  }, [hasRing, detailsQuery.data]);

  const isExpired = useMemo(() => {
    if (!hasRing || !detailsQuery.data) return false;
    return detailsQuery.data[4].status === "success" && detailsQuery.data[4].result === true;
  }, [hasRing, detailsQuery.data]);

  const termRemaining = useMemo(() => {
    if (!info) return 0;
    if (BigInt(info.termEndAt) === MAX_UINT64) return Infinity;
    const diff = info.termEndAt - Math.floor(Date.now() / 1000);
    return diff > 0 ? diff : 0;
  }, [info]);

  return {
    ringId: ringId,
    ringInfo: info,
    isBearer,
    tier,
    isEmeritus,
    isExpired,
    termRemaining, // 秒；Infinity 表示终生
    isLoading: ringIdQuery.isLoading || (hasRing && detailsQuery.isLoading),
    isError: ringIdQuery.isError || (hasRing && detailsQuery.isError),
  };
}

/**
 * useRingCount — 查询某 tier 的当前持环数（用于席位展示）
 */
export function useRingCount(tier: RingTier) {
  const { chainId } = useAccount();
  const ring = ringAddress(chainId ?? 0);
  const query = useReadContract({
    address: ring ?? undefined,
    abi: AetherRingABI,
    functionName: "getTierCount",
    args: [tier],
    query: { enabled: !!ring },
  });
  return {
    count: (query.data as bigint | undefined) ?? 0n,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}
