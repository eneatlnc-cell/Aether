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
  AetherGovernanceABI,
  governanceAddress,
  type ProposalStatus,
  type VoteOption,
} from "@/lib/contracts";

// ═══════════════════════════════════════════════════════════
//  类型定义
// ═══════════════════════════════════════════════════════════

export interface ImpeachmentState {
  status: ProposalStatus | null;
  requiredSignatures: number;
  currentSignatures: number;
  impeachedTarget: `0x${string}` | null;
  hasSigned: boolean;
}

// v3 弹劾计票快照（finalizeImpeachment 的判定依据）
export interface ImpeachmentVoteCounts {
  citizenFor: bigint; // 支持弹劾
  citizenAgainst: bigint; // 反对弹劾
  citizenAbstain: bigint;
  citizenTotalSnapshot: bigint; // 公投开始时活跃公民数
  // 计算字段（前端预览用，实际判定以链上 finalizeImpeachment 为准）
  participationBps: number; // 参与率 = (For+Against+Abstain) / snapshot
  // 注：合约当前实现使用 citizenAgainst 判定反对率（已知 bug，见 V3_REAL_ENV_TODO.md §5.2.1）
  // 建议语义：passRateMet = citizenFor / citizenVotes >= 60%（支持弹劾率 ≥60%）
  supportBps: number; // 支持率 = For / (For+Against+Abstain)
}

// ═══════════════════════════════════════════════════════════
//  useImpeachment — 弹劾提案写入 hook（v3）
// ═══════════════════════════════════════════════════════════

/**
 * useImpeachment — v3 弹劾全流程 hook
 *
 * 流程：
 *   1. createImpeachmentProposal(target, title, ipfsHash) → Drafting（联署中）
 *      - 仅任命元老（isAppointedElder）可发起
 *      - 目标 tier 1-13，不可弹劾公民（tier 14）
 *      - 发起人自动联署 1 票
 *   2. signImpeachment(proposalId) × 2 → 联署满 3 自动进入 PublicVoteActive
 *      - 仅任命元老可联署
 *   3. castPublicVote(proposalId, option) → 公民投票
 *      - FOR = 支持弹劾，AGAINST = 反对弹劾
 *   4. finalizeImpeachment(proposalId) → 通过则撤销道环
 *      - 通过条件：参与率 ≥40% + 支持率 ≥60%
 *      - 注：跳过法庭审查和元老否决（V5）
 *
 * 与 v2 区别：
 *   - 删除 approveImpeachmentByMultisig / rejectImpeachmentByMultisig（v3 无多签审查）
 *   - 发起方从"多签"改为"任命元老联署"
 *   - hasSigned 改为 hasImpeachSigned
 */
export function useImpeachment() {
  const { chainId } = useAccount();
  const gov = governanceAddress(chainId ?? 0);
  const { writeContractAsync, isPending: writing } = useWriteContract();
  const [lastTxHash, setLastTxHash] = useState<`0x${string}` | null>(null);

  const receiptQuery = useWaitForTransactionReceipt({ hash: lastTxHash ?? undefined });

  const ensure = () => {
    if (!gov) throw new Error("Governance 合约未部署");
    return gov;
  };

  /**
   * 创建弹劾提案（仅任命元老）
   * @param target  弹劾目标地址（tier 1-13，不可为公民 tier 14）
   * @param title   标题
   * @param ipfsHash IPFS 哈希
   * @returns txHash（前端可监听 ProposalCreated 事件拿 proposalId）
   */
  const create = async (params: {
    target: `0x${string}`;
    title: string;
    ipfsHash: string;
  }): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "createImpeachmentProposal",
      args: [params.target, params.title, params.ipfsHash],
    });
    setLastTxHash(tx);
    return tx;
  };

  /**
   * 联署弹劾提案（仅任命元老，联署满 3 自动进入公投）
   */
  const sign = async (proposalId: bigint): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "signImpeachment",
      args: [proposalId],
    });
    setLastTxHash(tx);
    return tx;
  };

  /**
   * 公民投票（弹劾公投阶段）
   * @param option FOR=支持弹劾，AGAINST=反对弹劾，ABSTAIN=弃权
   */
  const castVote = async (
    proposalId: bigint,
    option: VoteOption,
  ): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "castPublicVote",
      args: [proposalId, option],
    });
    setLastTxHash(tx);
    return tx;
  };

  /**
   * 结算弹劾（公投期结束后任何人可调）
   * - 通过：撤销目标道环，状态 → Executed
   * - 未通过：状态 → Defeated
   */
  const finalize = async (proposalId: bigint): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "finalizeImpeachment",
      args: [proposalId],
    });
    setLastTxHash(tx);
    return tx;
  };

  return {
    create,
    sign,
    castVote,
    finalize,
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
 * useImpeachmentState — 读取某弹劾提案的状态（v3）
 *
 * 字段索引（getProposal 返回 19 字段，详见 useGovernance.ts）：
 *   5:status 11:impeachedTarget 12:currentImpeachSignatures 13:requiredImpeachSignatures
 */
export function useImpeachmentState(proposalId: bigint | null) {
  const { chainId, address } = useAccount();
  const gov = governanceAddress(chainId ?? 0);
  const enabled = !!gov && proposalId !== null;

  const proposalQuery = useReadContract({
    address: gov ?? undefined,
    abi: AetherGovernanceABI,
    functionName: "getProposal",
    args: [proposalId ?? 0n],
    query: { enabled },
  });

  // v3: hasImpeachSigned（v2 为 hasSigned，已重命名）
  const signedQuery = useReadContract({
    address: gov ?? undefined,
    abi: AetherGovernanceABI,
    functionName: "hasImpeachSigned",
    args: [proposalId ?? 0n, address ?? "0x0"],
    query: { enabled },
  });

  const state = useMemo<ImpeachmentState>(() => {
    if (!proposalQuery.data || proposalQuery.status !== "success") {
      return {
        status: null,
        requiredSignatures: 0,
        currentSignatures: 0,
        impeachedTarget: null,
        hasSigned: false,
      };
    }
    // getProposal 返回 19 字段（v3），mapping 字段已跳过
    // 0:id 1:proposer 2:pType 3:title 4:ipfsHash 5:status
    // 6:target 7:executeAfter 8:isExecuted 9:isConstitutional 10:urgency
    // 11:impeachedTarget 12:currentImpeachSignatures 13:requiredImpeachSignatures
    // 14:currentVetoSignatures 15:requiredVetoSignatures
    // 16:currentReturnSignatures 17:requiredReturnSignatures 18:emergencyApprovals
    const raw = proposalQuery.data as readonly unknown[];
    return {
      status: (raw[5] as ProposalStatus) ?? null,
      requiredSignatures: Number(raw[13] as bigint ?? 0n),
      currentSignatures: Number(raw[12] as bigint ?? 0n),
      impeachedTarget: (raw[11] as `0x${string}`) ?? null,
      hasSigned: signedQuery.data === true,
    };
  }, [proposalQuery.data, proposalQuery.status, signedQuery.data]);

  return {
    state,
    isLoading: proposalQuery.isLoading || signedQuery.isLoading,
    isError: proposalQuery.isError || signedQuery.isError,
  };
}

/**
 * useImpeachmentVoteCounts — 读取弹劾公投计票详情（v3）
 *
 * 用于前端预览"如果现在 finalize 会不会通过"：
 *   - 参与率 = (For + Against + Abstain) / snapshot ≥ 40%
 *   - 支持率 = For / (For + Against + Abstain) ≥ 60%
 *
 * 注：合约 finalizeImpeachment 当前实现使用 citizenAgainst 判定（已知 bug），
 *     详见 V3_REAL_ENV_TODO.md §5.2.1，前端展示按"支持率"语义。
 */
export function useImpeachmentVoteCounts(proposalId: bigint | null) {
  const { chainId } = useAccount();
  const gov = governanceAddress(chainId ?? 0);
  const enabled = !!gov && proposalId !== null;

  const query = useReadContract({
    address: gov ?? undefined,
    abi: AetherGovernanceABI,
    functionName: "getVoteCounts",
    args: [proposalId ?? 0n],
    query: { enabled },
  });

  const counts = useMemo<ImpeachmentVoteCounts | null>(() => {
    if (!query.data || query.status !== "success") return null;
    // getVoteCounts 返回 17 字段（v3）
    // 0:parliamentFor 1:parliamentAgainst 2:federationFor 3:federationAgainst
    // 4:tribunalFor 5:tribunalAgainst
    // 6:citizenFor 7:citizenAgainst 8:citizenAbstain 9:citizenTotalSnapshot
    // 10:complianceFor 11:complianceAgainst
    // 12:parliamentStance 13:federationStance 14:tribunalStance
    // 15:citizenQuorumMet 16:passed
    const raw = query.data as readonly unknown[];
    const citizenFor = raw[6] as bigint;
    const citizenAgainst = raw[7] as bigint;
    const citizenAbstain = raw[8] as bigint;
    const snapshot = raw[9] as bigint;

    const totalVotes = citizenFor + citizenAgainst + citizenAbstain;
    const participationBps =
      snapshot > 0n ? Number((totalVotes * 10000n) / snapshot) : 0;
    const supportBps =
      totalVotes > 0n ? Number((citizenFor * 10000n) / totalVotes) : 0;

    return {
      citizenFor,
      citizenAgainst,
      citizenAbstain,
      citizenTotalSnapshot: snapshot,
      participationBps,
      supportBps,
    };
  }, [query.data, query.status]);

  return {
    counts,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/**
 * useImpeachmentVoterFlags — 批量查询当前用户在某弹劾提案的参与状态
 */
export function useImpeachmentVoterFlags(proposalId: bigint | null) {
  const { chainId, address } = useAccount();
  const gov = governanceAddress(chainId ?? 0);
  const enabled = !!gov && proposalId !== null && !!address;

  const query = useReadContracts({
    contracts: [
      {
        address: gov!,
        abi: AetherGovernanceABI,
        functionName: "hasImpeachSigned",
        args: [proposalId ?? 0n, address ?? "0x0"],
      },
      {
        address: gov!,
        abi: AetherGovernanceABI,
        functionName: "hasPublicVoted",
        args: [proposalId ?? 0n, address ?? "0x0"],
      },
    ],
    query: { enabled },
  });

  const flags = useMemo(() => {
    if (!query.data) {
      return { hasSigned: false, hasVoted: false };
    }
    const get = (i: number) =>
      query.data![i].status === "success" && query.data![i].result === true;
    return {
      hasSigned: get(0),
      hasVoted: get(1),
    };
  }, [query.data]);

  return {
    flags,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}
