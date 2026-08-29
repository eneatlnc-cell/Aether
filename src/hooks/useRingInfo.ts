"use client";
// SPDX-License-Identifier: Apache-2.0

import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { useMemo } from "react";
import { AetherRingABI, ringAddress, RingTier } from "@/lib/contracts";

// 与合约 RingInfo struct 对齐（v3：14 tier + 新字段）
export interface RingInfo {
  tier: RingTier;
  mintedAt: number;
  termEndAt: number;
  consecutiveTerms: number;
  isActive: boolean;
  isEmeritus: boolean;
  isExpired: boolean;
  covenantHash: string;
  // ── v3 新增字段 ──
  lastActivityAt: number; // 最后一次治理活动时间（休眠判断用，仅公民）
  isDormant: boolean; // 是否休眠（仅公民）
  isRetiredElder: boolean; // 退休元老（无治理权）
  isAppointedElder: boolean; // 任命元老（有治理权：否决/弹劾）
}

/**
 * useRingInfo — 读取当前连接钱包的道环信息（v3）
 *
 * 用法：
 *   const { ringInfo, isBearer, tier, isAppointedElder, isRetiredElder, isLoading } = useRingInfo();
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

  // 2. 拿到 ringId 后批量读取详情（v3 含 isElderActive / isRetiredElder / isAppointedElder）
  const detailsQuery = useReadContracts({
    contracts: [
      { address: ring!, abi: AetherRingABI, functionName: "getRingInfo", args: [ringId] },
      { address: ring!, abi: AetherRingABI, functionName: "isBearer", args: [address ?? "0x0"] },
      { address: ring!, abi: AetherRingABI, functionName: "getTier", args: [address ?? "0x0"] },
      { address: ring!, abi: AetherRingABI, functionName: "isEmeritus", args: [address ?? "0x0"] },
      { address: ring!, abi: AetherRingABI, functionName: "isExpired", args: [ringId] },
      { address: ring!, abi: AetherRingABI, functionName: "isRetiredElder", args: [address ?? "0x0"] },
      { address: ring!, abi: AetherRingABI, functionName: "isElderActive", args: [address ?? "0x0"] },
    ],
    query: { enabled: hasRing },
  });

  const info = useMemo<RingInfo | null>(() => {
    if (!hasRing || !detailsQuery.data) return null;
    const [infoRes] = detailsQuery.data;
    if (infoRes.status !== "success" || !infoRes.result) return null;
    // RingInfo tuple（v3 12 字段）：
    //   tier, mintedAt, termEndAt, consecutiveTerms, isActive, isEmeritus, isExpired,
    //   covenantHash, lastActivityAt, isDormant, isRetiredElder, isAppointedElder
    // wagmi 对 struct 返回值推断为命名对象，需经 unknown 二次转换
    const raw = infoRes.result as unknown as readonly unknown[];
    return {
      tier: (raw[0] as number) as RingTier,
      mintedAt: Number(raw[1] as bigint),
      termEndAt: Number(raw[2] as bigint),
      consecutiveTerms: Number(raw[3] as bigint),
      isActive: raw[4] as boolean,
      isEmeritus: raw[5] as boolean,
      isExpired: raw[6] as boolean,
      covenantHash: raw[7] as string,
      lastActivityAt: Number(raw[8] as bigint),
      isDormant: raw[9] as boolean,
      isRetiredElder: raw[10] as boolean,
      isAppointedElder: raw[11] as boolean,
    };
  }, [hasRing, detailsQuery.data]);

  const isBearer = useMemo(() => {
    if (!hasRing || !detailsQuery.data) return false;
    return detailsQuery.data[1].status === "success" && detailsQuery.data[1].result === true;
  }, [hasRing, detailsQuery.data]);

  const tier = useMemo<RingTier>(() => {
    if (!hasRing || !detailsQuery.data) return RingTier.NONE;
    const r = detailsQuery.data[2];
    return r.status === "success" ? ((r.result as number) as RingTier) : RingTier.NONE;
  }, [hasRing, detailsQuery.data]);

  const isEmeritus = useMemo(() => {
    if (!hasRing || !detailsQuery.data) return false;
    return detailsQuery.data[3].status === "success" && detailsQuery.data[3].result === true;
  }, [hasRing, detailsQuery.data]);

  const isExpired = useMemo(() => {
    if (!hasRing || !detailsQuery.data) return false;
    return detailsQuery.data[4].status === "success" && detailsQuery.data[4].result === true;
  }, [hasRing, detailsQuery.data]);

  // v3 新增：退休元老（无治理权）
  const isRetiredElder = useMemo(() => {
    if (!hasRing || !detailsQuery.data) return false;
    return detailsQuery.data[5].status === "success" && detailsQuery.data[5].result === true;
  }, [hasRing, detailsQuery.data]);

  // v3 新增：任命元老（有治理权：可否决/发起弹劾）
  const isAppointedElder = useMemo(() => {
    if (!hasRing || !detailsQuery.data) return false;
    return detailsQuery.data[6].status === "success" && detailsQuery.data[6].result === true;
  }, [hasRing, detailsQuery.data]);

  // termRemaining 已移除：渲染期调用 Date.now() 违反纯函数约束
  // （react-hooks/purity），且当前无任何消费方。需要倒计时的组件请用
  // ringInfo.termEndAt 自行在 effect/定时器中计算。

  return {
    ringId: ringId,
    ringInfo: info,
    isBearer,
    tier,
    isEmeritus,
    isExpired,
    isRetiredElder,
    isAppointedElder,
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

/**
 * useActiveCitizens — 查询活跃公民数（v3：排除休眠公民，用于 quorum 分母展示）
 */
export function useActiveCitizens() {
  const { chainId } = useAccount();
  const ring = ringAddress(chainId ?? 0);
  const query = useReadContract({
    address: ring ?? undefined,
    abi: AetherRingABI,
    functionName: "getActiveCitizens",
    query: { enabled: !!ring },
  });
  return {
    activeCitizens: (query.data as bigint | undefined) ?? 0n,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/**
 * useCanReacquireCitizenship — 查询某地址是否可重新获取公民身份（30 天冷却期）
 */
export function useCanReacquireCitizenship(user: `0x${string}` | null) {
  const { chainId } = useAccount();
  const ring = ringAddress(chainId ?? 0);
  const query = useReadContract({
    address: ring ?? undefined,
    abi: AetherRingABI,
    functionName: "canReacquireCitizenship",
    args: [user ?? "0x0"],
    query: { enabled: !!ring && !!user },
  });
  return {
    canReacquire: (query.data as boolean | undefined) ?? false,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}
