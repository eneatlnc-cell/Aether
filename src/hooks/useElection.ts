"use client";

import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useState } from "react";
import {
  AetherElectionABI,
  electionAddress,
  type ElectionType,
  type ElectionStatus,
} from "@/lib/contracts";

/**
 * useElection — 选举合约 hook
 *
 * 覆盖：
 *   - createElection（仅 ADMIN_ROLE，前端通常由 Safe 多签触发）
 *   - castVote / castReelectionAgainst
 *   - finalizeElection
 *   - cancelElection（仅 ADMIN_ROLE）
 *   - 读取选举详情 / 候选人票数 / 获胜者 / 连任结果
 */
export function useElection() {
  const { chainId } = useAccount();
  const election = electionAddress(chainId ?? 0);
  const { writeContractAsync, isPending: writing } = useWriteContract();
  const [lastTxHash, setLastTxHash] = useState<`0x${string}` | null>(null);
  const receiptQuery = useWaitForTransactionReceipt({ hash: lastTxHash ?? undefined });

  /**
   * 创建选举（仅 ADMIN_ROLE = Safe 多签）
   */
  const create = async (params: {
    eType: ElectionType;
    targetChamber: number; // 1=议会 2=联部 3=元老院；REELECTION 时忽略
    seatCount: number;
    candidates: `0x${string}`[];
    reelectionTarget: `0x${string}`; // REELECTION 时填目标地址，其他类型填 0x0
  }): Promise<`0x${string}`> => {
    if (!election) throw new Error("Election 合约未部署");
    const tx = await writeContractAsync({
      address: election,
      abi: AetherElectionABI,
      functionName: "createElection",
      args: [
        params.eType,
        params.targetChamber,
        BigInt(params.seatCount),
        params.candidates,
        params.reelectionTarget,
      ],
    });
    setLastTxHash(tx);
    return tx;
  };

  /**
   * 投票（普选/院选）
   */
  const castVote = async (electionId: bigint, candidate: `0x${string}`): Promise<`0x${string}`> => {
    if (!election) throw new Error("Election 合约未部署");
    const tx = await writeContractAsync({
      address: election,
      abi: AetherElectionABI,
      functionName: "castVote",
      args: [electionId, candidate],
    });
    setLastTxHash(tx);
    return tx;
  };

  /**
   * 连任选举：投反对票
   */
  const castReelectionAgainst = async (electionId: bigint): Promise<`0x${string}`> => {
    if (!election) throw new Error("Election 合约未部署");
    const tx = await writeContractAsync({
      address: election,
      abi: AetherElectionABI,
      functionName: "castReelectionAgainst",
      args: [electionId],
    });
    setLastTxHash(tx);
    return tx;
  };

  /**
   * 结算选举（任何人可调，投票期结束后）
   */
  const finalize = async (electionId: bigint): Promise<`0x${string}`> => {
    if (!election) throw new Error("Election 合约未部署");
    const tx = await writeContractAsync({
      address: election,
      abi: AetherElectionABI,
      functionName: "finalizeElection",
      args: [electionId],
    });
    setLastTxHash(tx);
    return tx;
  };

  /**
   * 取消选举（仅 ADMIN_ROLE = Safe 多签）
   */
  const cancel = async (electionId: bigint): Promise<`0x${string}`> => {
    if (!election) throw new Error("Election 合约未部署");
    const tx = await writeContractAsync({
      address: election,
      abi: AetherElectionABI,
      functionName: "cancelElection",
      args: [electionId],
    });
    setLastTxHash(tx);
    return tx;
  };

  return {
    create,
    castVote,
    castReelectionAgainst,
    finalize,
    cancel,
    writing,
    lastTxHash,
    receipt: receiptQuery.data,
    isConfirming: receiptQuery.isLoading,
    isConfirmed: !!receiptQuery.data,
  };
}

/**
 * useElectionState — 读取某选举的元信息
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

  const data = query.data as
    | readonly [ElectionType, ElectionStatus, bigint, bigint, bigint, bigint, bigint]
    | undefined;

  return {
    eType: data?.[0] ?? null,
    status: data?.[1] ?? null,
    candidateCount: data ? Number(data[2]) : 0,
    totalVotes: data ? Number(data[3]) : 0,
    votingStartAt: data ? Number(data[4]) : 0,
    votingEndAt: data ? Number(data[5]) : 0,
    seatCount: data ? Number(data[6]) : 0,
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
 * useCandidateVotes — 读取某候选人的票数
 */
export function useCandidateVotes(electionId: bigint | null, candidate: `0x${string}` | null) {
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
 * useReelectionResult — 读取连任选举结果（仅 REELECTION 类型）
 */
export function useReelectionResult(electionId: bigint | null) {
  const { chainId } = useAccount();
  const election = electionAddress(chainId ?? 0);
  const query = useReadContract({
    address: election ?? undefined,
    abi: AetherElectionABI,
    functionName: "getReelectionResult",
    args: [electionId ?? 0n],
    query: { enabled: !!election && electionId !== null },
  });
  const data = query.data as readonly [bigint, bigint, boolean] | undefined;
  return {
    forVotes: data ? Number(data[0]) : 0,
    againstVotes: data ? Number(data[1]) : 0,
    passed: data?.[2] ?? false,
    isLoading: query.isLoading,
  };
}
