"use client";
// SPDX-License-Identifier: Apache-2.0

import {
  useAccount,
  useReadContract,
  useReadContracts,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { useMemo, useState } from "react";
import {
  AetherElectionABI,
  electionAddress,
  type ElectionType,
  type ElectionStatus,
  type CouncilTargetTier,
} from "@/lib/contracts";

// ═══════════════════════════════════════════════════════════
//  类型定义（v3）
// ═══════════════════════════════════════════════════════════

// getElection 返回 8 字段（v3 新增 unfilledSeats）
export interface ElectionInfo {
  eType: ElectionType;
  status: ElectionStatus;
  candidateCount: number;
  totalVotes: number;
  votingStartAt: number;
  votingEndAt: number;
  seatCount: number;
  unfilledSeats: number; // v3 新增：空缺席位（PartiallyFilled 时 > 0）
}

// getElectionTimelines 返回 6 字段（v3 新增 councilReviewEndAt / parliamentApprovalEndAt）
export interface ElectionTimelines {
  registrationStartAt: number;
  registrationEndAt: number;
  councilReviewEndAt: number;
  parliamentApprovalEndAt: number;
  votingStartAt: number;
  votingEndAt: number;
}

// getCandidateInfo 返回 6 字段（v3）
export interface CandidateInfo {
  isNominated: boolean; // 已注册为候选人
  isRegistered: boolean; // 通过理事会审批，进入投票池
  isRejected: boolean; // 被理事会拒绝
  voteCount: bigint;
  won: boolean; // 当选
  registeredAt: number;
}

// ═══════════════════════════════════════════════════════════
//  useElection — 选举全流程写入 hook（v3）
// ═══════════════════════════════════════════════════════════

/**
 * useElection — v3 选举合约 hook
 *
 * 4 阶段状态机：
 *   Pending（候选人注册）→ CouncilReview（理事会整理）→
 *   ParliamentApproval（议会审批）→ Active（投票）→ Finalized
 *   失败/空缺路径 → PartiallyFilled（理事长可 appointToVacancy 填补）
 *
 * 3 种选举类型：
 *   - MEMBER_TO_GRASSROOTS：公民 → 三院基层（普选）
 *   - GRASSROOTS_TO_MID：三院基层 → 中层（院选）
 *   - CITIZEN_TO_COUNCIL：公民 → 理事/常务理事（v3 新增）
 *
 * 与 v2 区别：
 *   - 删除 REELECTION（不可连任）
 *   - 删除 castReelectionAgainst / getReelectionResult
 *   - createElection 参数变化：新增 councilTarget，删除 candidates/reelectionTarget
 *   - 新增 registerCandidate / advanceToCouncilReview / approveCandidate / rejectCandidate
 *   - 新增 advanceToParliamentApproval / parliamentApproveCandidateList / forceAdvanceToVoting
 *   - 新增 appointToVacancy（空缺处理）
 */
export function useElection() {
  const { chainId } = useAccount();
  const election = electionAddress(chainId ?? 0);
  const { writeContractAsync, isPending: writing } = useWriteContract();
  const [lastTxHash, setLastTxHash] = useState<`0x${string}` | null>(null);
  const receiptQuery = useWaitForTransactionReceipt({ hash: lastTxHash ?? undefined });

  const ensure = () => {
    if (!election) throw new Error("Election 合约未部署");
    return election;
  };

  // ── 阶段 0：创建选举（仅 ADMIN_ROLE = Safe 多签） ──
  const create = async (params: {
    eType: ElectionType;
    chamber: number; // 1=议会 2=联邦 3=法庭 4=理事 5=常务理事
    councilTarget: CouncilTargetTier; // 仅 CITIZEN_TO_COUNCIL 用
    seatCount: number;
  }): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherElectionABI,
      functionName: "createElection",
      args: [
        params.eType,
        params.chamber,
        params.councilTarget,
        BigInt(params.seatCount),
      ],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 阶段 1：候选人注册（自荐） ──
  const registerCandidate = async (electionId: bigint): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherElectionABI,
      functionName: "registerCandidate",
      args: [electionId],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 阶段 1：无人参选时延长注册期 7 天 ──
  const extendRegistrationIfNoCandidates = async (
    electionId: bigint,
  ): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherElectionABI,
      functionName: "extendRegistrationIfNoCandidates",
      args: [electionId],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 阶段 1→2：推进至理事会整理 ──
  const advanceToCouncilReview = async (electionId: bigint): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherElectionABI,
      functionName: "advanceToCouncilReview",
      args: [electionId],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 阶段 2：理事长批准候选人（仅 COUNCIL_CHAIR_ROLE） ──
  const approveCandidate = async (
    electionId: bigint,
    candidate: `0x${string}`,
  ): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherElectionABI,
      functionName: "approveCandidate",
      args: [electionId, candidate],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 阶段 2：理事长拒绝候选人（仅 COUNCIL_CHAIR_ROLE） ──
  const rejectCandidate = async (
    electionId: bigint,
    candidate: `0x${string}`,
  ): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherElectionABI,
      functionName: "rejectCandidate",
      args: [electionId, candidate],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 阶段 2→3：推进至议会审批 ──
  const advanceToParliamentApproval = async (
    electionId: bigint,
  ): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherElectionABI,
      functionName: "advanceToParliamentApproval",
      args: [electionId],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 阶段 3：议会成员投批准票（仅 tier 1/2/3） ──
  const parliamentApproveCandidateList = async (
    electionId: bigint,
  ): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherElectionABI,
      functionName: "parliamentApproveCandidateList",
      args: [electionId],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 阶段 3→4：议会审批期超时强制推进至投票 ──
  const forceAdvanceToVoting = async (electionId: bigint): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherElectionABI,
      functionName: "forceAdvanceToVoting",
      args: [electionId],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 阶段 4：投票 ──
  const castVote = async (
    electionId: bigint,
    candidate: `0x${string}`,
  ): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherElectionABI,
      functionName: "castVote",
      args: [electionId, candidate],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 阶段 5：计票 finalize（任何人可调，投票期结束后） ──
  const finalize = async (electionId: bigint): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherElectionABI,
      functionName: "finalizeElection",
      args: [electionId],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 空缺填补：理事长任命（仅 COUNCIL_CHAIR_ROLE，PartiallyFilled 状态） ──
  const appointToVacancy = async (
    electionId: bigint,
    candidate: `0x${string}`,
  ): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherElectionABI,
      functionName: "appointToVacancy",
      args: [electionId, candidate],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 取消选举（仅 ADMIN_ROLE） ──
  const cancel = async (electionId: bigint): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherElectionABI,
      functionName: "cancelElection",
      args: [electionId],
    });
    setLastTxHash(tx);
    return tx;
  };

  return {
    // 写入方法
    create,
    registerCandidate,
    extendRegistrationIfNoCandidates,
    advanceToCouncilReview,
    approveCandidate,
    rejectCandidate,
    advanceToParliamentApproval,
    parliamentApproveCandidateList,
    forceAdvanceToVoting,
    castVote,
    finalize,
    appointToVacancy,
    cancel,
    // 交易状态
    writing,
    lastTxHash,
    receipt: receiptQuery.data,
    isConfirming: receiptQuery.isLoading,
    isConfirmed: !!receiptQuery.data,
  };
}

// ═══════════════════════════════════════════════════════════
//  读取 hooks
// ═══════════════════════════════════════════════════════════

/**
 * useElectionState — 读取选举元信息（v3，8 字段含 unfilledSeats）
 */
export function useElectionState(electionId: bigint | null) {
  const { chainId } = useAccount();
  const election = electionAddress(chainId ?? 0);
  const enabled = !!election && electionId !== null;

  const query = useReadContract({
    address: election ?? undefined,
    abi: AetherElectionABI,
    functionName: "getElection",
    args: [electionId ?? 0n],
    query: { enabled },
  });

  const info = useMemo<ElectionInfo | null>(() => {
    if (!query.data || query.status !== "success") return null;
    const raw = query.data as readonly unknown[];
    return {
      eType: raw[0] as ElectionType,
      status: raw[1] as ElectionStatus,
      candidateCount: Number(raw[2] as bigint),
      totalVotes: Number(raw[3] as bigint),
      votingStartAt: Number(raw[4] as bigint),
      votingEndAt: Number(raw[5] as bigint),
      seatCount: Number(raw[6] as bigint),
      unfilledSeats: Number(raw[7] as bigint),
    };
  }, [query.data, query.status]);

  return {
    info,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/**
 * useElectionTimelines — 读取选举各阶段时间窗口（v3，6 字段）
 */
export function useElectionTimelines(electionId: bigint | null) {
  const { chainId } = useAccount();
  const election = electionAddress(chainId ?? 0);
  const enabled = !!election && electionId !== null;

  const query = useReadContract({
    address: election ?? undefined,
    abi: AetherElectionABI,
    functionName: "getElectionTimelines",
    args: [electionId ?? 0n],
    query: { enabled },
  });

  const timelines = useMemo<ElectionTimelines | null>(() => {
    if (!query.data || query.status !== "success") return null;
    const raw = query.data as readonly unknown[];
    return {
      registrationStartAt: Number(raw[0] as bigint),
      registrationEndAt: Number(raw[1] as bigint),
      councilReviewEndAt: Number(raw[2] as bigint),
      parliamentApprovalEndAt: Number(raw[3] as bigint),
      votingStartAt: Number(raw[4] as bigint),
      votingEndAt: Number(raw[5] as bigint),
    };
  }, [query.data, query.status]);

  return {
    timelines,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/**
 * useElectionWinners — 读取获胜者列表（finalize 后）
 */
export function useElectionWinners(electionId: bigint | null) {
  const { chainId } = useAccount();
  const election = electionAddress(chainId ?? 0);
  const query = useReadContract({
    address: election ?? undefined,
    abi: AetherElectionABI,
    functionName: "getWinners",
    args: [electionId ?? 0n],
    query: { enabled: !!election && electionId !== null },
  });
  return {
    winners: (query.data as `0x${string}`[] | undefined) ?? [],
    isLoading: query.isLoading,
  };
}

/**
 * useElectionCandidates — 读取候选人地址列表
 */
export function useElectionCandidates(electionId: bigint | null) {
  const { chainId } = useAccount();
  const election = electionAddress(chainId ?? 0);
  const query = useReadContract({
    address: election ?? undefined,
    abi: AetherElectionABI,
    functionName: "getCandidates",
    args: [electionId ?? 0n],
    query: { enabled: !!election && electionId !== null },
  });
  return {
    candidates: (query.data as `0x${string}`[] | undefined) ?? [],
    isLoading: query.isLoading,
  };
}

/**
 * useCandidateInfo — 读取某候选人的详细信息（v3）
 */
export function useCandidateInfo(
  electionId: bigint | null,
  candidate: `0x${string}` | null,
) {
  const { chainId } = useAccount();
  const election = electionAddress(chainId ?? 0);
  const enabled = !!election && electionId !== null && !!candidate;

  const query = useReadContract({
    address: election ?? undefined,
    abi: AetherElectionABI,
    functionName: "getCandidateInfo",
    args: [electionId ?? 0n, candidate ?? "0x0"],
    query: { enabled },
  });

  const info = useMemo<CandidateInfo | null>(() => {
    if (!query.data || query.status !== "success") return null;
    const raw = query.data as readonly unknown[];
    return {
      isNominated: raw[0] as boolean,
      isRegistered: raw[1] as boolean,
      isRejected: raw[2] as boolean,
      voteCount: raw[3] as bigint,
      won: raw[4] as boolean,
      registeredAt: Number(raw[5] as bigint),
    };
  }, [query.data, query.status]);

  return {
    info,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/**
 * useCandidateVotes — 读取某候选人的票数
 */
export function useCandidateVotes(
  electionId: bigint | null,
  candidate: `0x${string}` | null,
) {
  const { chainId } = useAccount();
  const election = electionAddress(chainId ?? 0);
  const query = useReadContract({
    address: election ?? undefined,
    abi: AetherElectionABI,
    functionName: "getCandidateVoteCount",
    args: [electionId ?? 0n, candidate ?? "0x0"],
    query: { enabled: !!election && electionId !== null && !!candidate },
  });
  return {
    voteCount: (query.data as bigint | undefined) ?? 0n,
    isLoading: query.isLoading,
  };
}

/**
 * useElectionVoterFlags — 批量查询当前用户的参与状态
 *   - hasVoted：投票阶段是否已投票
 *   - hasParliamentApproved：议会审批阶段是否已批准
 */
export function useElectionVoterFlags(electionId: bigint | null) {
  const { chainId, address } = useAccount();
  const election = electionAddress(chainId ?? 0);
  const enabled = !!election && electionId !== null && !!address;

  const query = useReadContracts({
    contracts: [
      {
        address: election!,
        abi: AetherElectionABI,
        functionName: "hasVoted",
        args: [electionId ?? 0n, address ?? "0x0"],
      },
      {
        address: election!,
        abi: AetherElectionABI,
        functionName: "hasParliamentApproved",
        args: [electionId ?? 0n, address ?? "0x0"],
      },
    ],
    query: { enabled },
  });

  const flags = useMemo(() => {
    if (!query.data) {
      return { hasVoted: false, hasParliamentApproved: false };
    }
    const get = (i: number) =>
      query.data![i].status === "success" && query.data![i].result === true;
    return {
      hasVoted: get(0),
      hasParliamentApproved: get(1),
    };
  }, [query.data]);

  return {
    flags,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/**
 * useElectionCount — 读取选举总数（用于列表分页）
 */
export function useElectionCount() {
  const { chainId } = useAccount();
  const election = electionAddress(chainId ?? 0);
  const query = useReadContract({
    address: election ?? undefined,
    abi: AetherElectionABI,
    functionName: "electionCount",
    query: { enabled: !!election },
  });
  return {
    count: (query.data as bigint | undefined) ?? 0n,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}
