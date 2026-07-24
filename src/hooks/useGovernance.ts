"use client";

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
  ProposalType,
  ProposalStatus,
  TreasuryUrgency,
  VoteOption,
  ChamberStance,
} from "@/lib/contracts";

// ═══════════════════════════════════════════════════════════
//  类型定义（与合约 getProposal 返回值对齐，v3 19 字段）
// ═══════════════════════════════════════════════════════════

export interface ProposalDetail {
  id: bigint;
  proposer: `0x${string}`;
  pType: ProposalType;
  title: string;
  ipfsHash: string;
  status: ProposalStatus;
  target: `0x${string}`;
  executeAfter: bigint;
  isExecuted: boolean;
  isConstitutional: boolean;
  urgency: TreasuryUrgency;
  impeachedTarget: `0x${string}`;
  currentImpeachSignatures: bigint;
  requiredImpeachSignatures: bigint;
  currentVetoSignatures: bigint;
  requiredVetoSignatures: bigint;
  currentReturnSignatures: bigint;
  requiredReturnSignatures: bigint;
  emergencyApprovals: bigint;
}

export interface ProposalTimelines {
  createdAt: bigint;
  firstVoteStartAt: bigint;
  firstVoteEndAt: bigint;
  complianceVoteEndAt: bigint;
  publicVoteStartAt: bigint;
  publicVoteEndAt: bigint;
  vetoWindowEndAt: bigint;
  queuedAt: bigint;
  executeAfter: bigint;
}

export interface ProposalVoteCounts {
  parliamentFor: bigint;
  parliamentAgainst: bigint;
  federationFor: bigint;
  federationAgainst: bigint;
  tribunalFor: bigint;
  tribunalAgainst: bigint;
  citizenFor: bigint;
  citizenAgainst: bigint;
  citizenAbstain: bigint;
  citizenTotalSnapshot: bigint;
  complianceFor: bigint;
  complianceAgainst: bigint;
  parliamentStance: ChamberStance;
  federationStance: ChamberStance;
  tribunalStance: ChamberStance;
  citizenQuorumMet: boolean;
  passed: boolean;
}

export interface ConfidenceVoteInfo {
  chair: `0x${string}`;
  startedAt: bigint;
  forVotes: bigint;
  againstVotes: bigint;
  resolved: boolean;
}

// ═══════════════════════════════════════════════════════════
//  useGovernance — 提案全生命周期写入 hook
// ═══════════════════════════════════════════════════════════

/**
 * useGovernance — v3 七阶段提案流程写入入口
 *
 * 阶段流转（12 状态）：
 *   Drafting → PendingFirstVote → FirstVoteActive → PendingFormal
 *            → PendingCompliance → PublicVoteActive → PendingVeto
 *            → Queued → Executed
 *   （失败 → Defeated / Canceled / ReturnedToDraft）
 *
 * 用法：
 *   const { createProposal, advanceProposal, castFirstVote, ... } = useGovernance();
 */
export function useGovernance() {
  const { chainId } = useAccount();
  const gov = governanceAddress(chainId ?? 0);
  const { writeContractAsync, isPending: writing } = useWriteContract();
  const [lastTxHash, setLastTxHash] = useState<`0x${string}` | null>(null);
  const receiptQuery = useWaitForTransactionReceipt({ hash: lastTxHash ?? undefined });

  const ensure = () => {
    if (!gov) throw new Error("Governance 合约未部署");
    return gov;
  };

  // ── 1. 创建提案（仅 PROPOSER_ROLE + 三院成员 tier 1-9） ──
  const createProposal = async (params: {
    pType: ProposalType;
    title: string;
    ipfsHash: string;
    target: `0x${string}`;
    calldataPayload: `0x${string}`;
    isConstitutional: boolean;
    urgency: TreasuryUrgency;
  }): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "createProposal",
      args: [
        params.pType,
        params.title,
        params.ipfsHash,
        params.target,
        params.calldataPayload,
        params.isConstitutional,
        params.urgency,
      ],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 2. 理事长推进草案至待一审 ──
  const advanceProposal = async (proposalId: bigint): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "advanceProposal",
      args: [proposalId],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 3. ≥2 理事联署退回草案 ──
  const returnProposal = async (proposalId: bigint): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "returnProposal",
      args: [proposalId],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 4. 退回后原提议人修改重新推进 ──
  const resubmitFromReturn = async (
    proposalId: bigint,
    newTitle: string,
    newIpfs: string,
  ): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "resubmitFromReturn",
      args: [proposalId, newTitle, newIpfs],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 5. 议会一审：开启投票 ──
  const startFirstVote = async (proposalId: bigint): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "startFirstVote",
      args: [proposalId],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 6. 议会一审：投票（仅 tier 1/2/3） ──
  const castFirstVote = async (
    proposalId: bigint,
    option: VoteOption,
  ): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "castFirstVote",
      args: [proposalId, option],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 7. 议会一审：结算 ──
  const finalizeFirstVote = async (proposalId: bigint): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "finalizeFirstVote",
      args: [proposalId],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 8. 一审通过后正式提交（proposer 或理事长） ──
  const submitFormalProposal = async (proposalId: bigint): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "submitFormalProposal",
      args: [proposalId],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 9. 法庭合规审查投票（仅 tier 7/8/9） ──
  const castComplianceVote = async (
    proposalId: bigint,
    option: VoteOption,
  ): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "castComplianceVote",
      args: [proposalId, option],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 10. 法庭合规结算（合规 → 进入公投；不合规 → ReturnedToDraft） ──
  const finalizeCompliance = async (proposalId: bigint): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "finalizeCompliance",
      args: [proposalId],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 11. 公投投票（三院 + 公民；理事会/元老不可投） ──
  const castPublicVote = async (
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

  // ── 12. 公投结算（计算三院立场 + 公民 quorum + 加权通过率） ──
  const finalizeProposal = async (proposalId: bigint): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "finalizeProposal",
      args: [proposalId],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 13. 元老否决（仅任命元老，3 联署；IMPEACHMENT 不可否决） ──
  const vetoProposal = async (proposalId: bigint): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "vetoProposal",
      args: [proposalId],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 14. 否决窗口超时 → 进入 Timelock ──
  const finalizeVetoWindow = async (proposalId: bigint): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "finalizeVetoWindow",
      args: [proposalId],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 15. 执行提案（Timelock 到期后） ──
  const executeProposal = async (proposalId: bigint): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "executeProposal",
      args: [proposalId],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 16. 紧急拨款：任命元老快速批准（3 联署） ──
  const approveEmergencyTreasury = async (proposalId: bigint): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "approveEmergencyTreasury",
      args: [proposalId],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 17. 取消提案（仅 ADMIN_ROLE） ──
  const cancelProposal = async (proposalId: bigint): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "cancelProposal",
      args: [proposalId],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 18. 理事长信任投票：8 理事联署触发 ──
  const signConfidenceTrigger = async (chair: `0x${string}`): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "signConfidenceTrigger",
      args: [chair],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 19. 触发理事长信任投票（联署满 8 后由任意理事触发） ──
  const triggerConfidenceVote = async (
    chair: `0x${string}`,
    reasonIpfs: string,
  ): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "triggerConfidenceVote",
      args: [chair, reasonIpfs],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 20. 理事投票（仅 tier 10/11） ──
  const voteConfidence = async (voteId: bigint, support: boolean): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "voteConfidence",
      args: [voteId, support],
    });
    setLastTxHash(tx);
    return tx;
  };

  // ── 21. 信任投票结算（不通过 → 理事长 30 天内辞职） ──
  const finalizeConfidence = async (voteId: bigint): Promise<`0x${string}`> => {
    const addr = ensure();
    const tx = await writeContractAsync({
      address: addr,
      abi: AetherGovernanceABI,
      functionName: "finalizeConfidence",
      args: [voteId],
    });
    setLastTxHash(tx);
    return tx;
  };

  return {
    // 写入方法
    createProposal,
    advanceProposal,
    returnProposal,
    resubmitFromReturn,
    startFirstVote,
    castFirstVote,
    finalizeFirstVote,
    submitFormalProposal,
    castComplianceVote,
    finalizeCompliance,
    castPublicVote,
    finalizeProposal,
    vetoProposal,
    finalizeVetoWindow,
    executeProposal,
    approveEmergencyTreasury,
    cancelProposal,
    signConfidenceTrigger,
    triggerConfidenceVote,
    voteConfidence,
    finalizeConfidence,
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
 * useProposalDetail — 读取提案详情（getProposal 返回 19 字段）
 *
 * 字段索引（按 ABI 输出顺序）：
 *   0:id 1:proposer 2:pType 3:title 4:ipfsHash 5:status
 *   6:target 7:executeAfter 8:isExecuted 9:isConstitutional 10:urgency
 *   11:impeachedTarget 12:currentImpeachSignatures 13:requiredImpeachSignatures
 *   14:currentVetoSignatures 15:requiredVetoSignatures
 *   16:currentReturnSignatures 17:requiredReturnSignatures 18:emergencyApprovals
 */
export function useProposalDetail(proposalId: bigint | null) {
  const { chainId } = useAccount();
  const gov = governanceAddress(chainId ?? 0);
  const enabled = !!gov && proposalId !== null;

  const query = useReadContract({
    address: gov ?? undefined,
    abi: AetherGovernanceABI,
    functionName: "getProposal",
    args: [proposalId ?? 0n],
    query: { enabled },
  });

  const detail = useMemo<ProposalDetail | null>(() => {
    if (!query.data || query.status !== "success") return null;
    const raw = query.data as readonly unknown[];
    return {
      id: raw[0] as bigint,
      proposer: raw[1] as `0x${string}`,
      pType: raw[2] as ProposalType,
      title: raw[3] as string,
      ipfsHash: raw[4] as string,
      status: raw[5] as ProposalStatus,
      target: raw[6] as `0x${string}`,
      executeAfter: raw[7] as bigint,
      isExecuted: raw[8] as boolean,
      isConstitutional: raw[9] as boolean,
      urgency: raw[10] as TreasuryUrgency,
      impeachedTarget: raw[11] as `0x${string}`,
      currentImpeachSignatures: raw[12] as bigint,
      requiredImpeachSignatures: raw[13] as bigint,
      currentVetoSignatures: raw[14] as bigint,
      requiredVetoSignatures: raw[15] as bigint,
      currentReturnSignatures: raw[16] as bigint,
      requiredReturnSignatures: raw[17] as bigint,
      emergencyApprovals: raw[18] as bigint,
    };
  }, [query.data, query.status]);

  return {
    detail,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/**
 * useProposalTimelines — 读取提案时间窗口
 */
export function useProposalTimelines(proposalId: bigint | null) {
  const { chainId } = useAccount();
  const gov = governanceAddress(chainId ?? 0);
  const enabled = !!gov && proposalId !== null;

  const query = useReadContract({
    address: gov ?? undefined,
    abi: AetherGovernanceABI,
    functionName: "getProposalTimelines",
    args: [proposalId ?? 0n],
    query: { enabled },
  });

  const timelines = useMemo<ProposalTimelines | null>(() => {
    if (!query.data || query.status !== "success") return null;
    const raw = query.data as readonly unknown[];
    return {
      createdAt: raw[0] as bigint,
      firstVoteStartAt: raw[1] as bigint,
      firstVoteEndAt: raw[2] as bigint,
      complianceVoteEndAt: raw[3] as bigint,
      publicVoteStartAt: raw[4] as bigint,
      publicVoteEndAt: raw[5] as bigint,
      vetoWindowEndAt: raw[6] as bigint,
      queuedAt: raw[7] as bigint,
      executeAfter: raw[8] as bigint,
    };
  }, [query.data, query.status]);

  return {
    timelines,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/**
 * useProposalVoteCounts — 读取提案计票详情（三院 + 公民 + 立场 + 结果）
 */
export function useProposalVoteCounts(proposalId: bigint | null) {
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

  const counts = useMemo<ProposalVoteCounts | null>(() => {
    if (!query.data || query.status !== "success") return null;
    const raw = query.data as readonly unknown[];
    return {
      parliamentFor: raw[0] as bigint,
      parliamentAgainst: raw[1] as bigint,
      federationFor: raw[2] as bigint,
      federationAgainst: raw[3] as bigint,
      tribunalFor: raw[4] as bigint,
      tribunalAgainst: raw[5] as bigint,
      citizenFor: raw[6] as bigint,
      citizenAgainst: raw[7] as bigint,
      citizenAbstain: raw[8] as bigint,
      citizenTotalSnapshot: raw[9] as bigint,
      complianceFor: raw[10] as bigint,
      complianceAgainst: raw[11] as bigint,
      parliamentStance: raw[12] as ChamberStance,
      federationStance: raw[13] as ChamberStance,
      tribunalStance: raw[14] as ChamberStance,
      citizenQuorumMet: raw[15] as boolean,
      passed: raw[16] as boolean,
    };
  }, [query.data, query.status]);

  return {
    counts,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/**
 * useProposalVoterFlags — 批量查询当前用户在某提案各阶段的投票状态
 *
 * 返回：{ hasFirstVoted, hasComplianceVoted, hasPublicVoted, hasVetoed, hasSignedReturn, hasEmergencyApproved }
 */
export function useProposalVoterFlags(proposalId: bigint | null) {
  const { chainId, address } = useAccount();
  const gov = governanceAddress(chainId ?? 0);
  const enabled = !!gov && proposalId !== null && !!address;

  const query = useReadContracts({
    contracts: [
      {
        address: gov!,
        abi: AetherGovernanceABI,
        functionName: "hasFirstVoted",
        args: [proposalId ?? 0n, address ?? "0x0"],
      },
      {
        address: gov!,
        abi: AetherGovernanceABI,
        functionName: "hasComplianceVoted",
        args: [proposalId ?? 0n, address ?? "0x0"],
      },
      {
        address: gov!,
        abi: AetherGovernanceABI,
        functionName: "hasPublicVoted",
        args: [proposalId ?? 0n, address ?? "0x0"],
      },
      {
        address: gov!,
        abi: AetherGovernanceABI,
        functionName: "hasVetoed",
        args: [proposalId ?? 0n, address ?? "0x0"],
      },
      {
        address: gov!,
        abi: AetherGovernanceABI,
        functionName: "hasSignedReturn",
        args: [proposalId ?? 0n, address ?? "0x0"],
      },
      {
        address: gov!,
        abi: AetherGovernanceABI,
        functionName: "hasEmergencyApproved",
        args: [proposalId ?? 0n, address ?? "0x0"],
      },
    ],
    query: { enabled },
  });

  const flags = useMemo(() => {
    if (!query.data) {
      return {
        hasFirstVoted: false,
        hasComplianceVoted: false,
        hasPublicVoted: false,
        hasVetoed: false,
        hasSignedReturn: false,
        hasEmergencyApproved: false,
      };
    }
    const get = (i: number) => query.data![i].status === "success" && query.data![i].result === true;
    return {
      hasFirstVoted: get(0),
      hasComplianceVoted: get(1),
      hasPublicVoted: get(2),
      hasVetoed: get(3),
      hasSignedReturn: get(4),
      hasEmergencyApproved: get(5),
    };
  }, [query.data]);

  return {
    flags,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/**
 * useProposalCount — 读取提案总数（用于列表分页）
 */
export function useProposalCount() {
  const { chainId } = useAccount();
  const gov = governanceAddress(chainId ?? 0);
  const query = useReadContract({
    address: gov ?? undefined,
    abi: AetherGovernanceABI,
    functionName: "proposalCount",
    query: { enabled: !!gov },
  });
  return {
    count: (query.data as bigint | undefined) ?? 0n,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/**
 * useConfidenceVote — 读取理事长信任投票详情
 */
export function useConfidenceVote(voteId: bigint | null) {
  const { chainId } = useAccount();
  const gov = governanceAddress(chainId ?? 0);
  const enabled = !!gov && voteId !== null;

  const query = useReadContract({
    address: gov ?? undefined,
    abi: AetherGovernanceABI,
    functionName: "getConfidenceVote",
    args: [voteId ?? 0n],
    query: { enabled },
  });

  const info = useMemo<ConfidenceVoteInfo | null>(() => {
    if (!query.data || query.status !== "success") return null;
    const raw = query.data as readonly unknown[];
    return {
      chair: raw[0] as `0x${string}`,
      startedAt: raw[1] as bigint,
      forVotes: raw[2] as bigint,
      againstVotes: raw[3] as bigint,
      resolved: raw[4] as boolean,
    };
  }, [query.data, query.status]);

  return {
    info,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/**
 * useConfidenceVoteCount — 读取信任投票总数
 */
export function useConfidenceVoteCount() {
  const { chainId } = useAccount();
  const gov = governanceAddress(chainId ?? 0);
  const query = useReadContract({
    address: gov ?? undefined,
    abi: AetherGovernanceABI,
    functionName: "confidenceVoteCount",
    query: { enabled: !!gov },
  });
  return {
    count: (query.data as bigint | undefined) ?? 0n,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/**
 * useCouncilTriggerSignatures — 读取某理事长已收到的联署数（触发信任投票需 8 票）
 */
export function useCouncilTriggerSignatures(chair: `0x${string}` | null) {
  const { chainId } = useAccount();
  const gov = governanceAddress(chainId ?? 0);
  const query = useReadContract({
    address: gov ?? undefined,
    abi: AetherGovernanceABI,
    functionName: "councilTriggerSignatures",
    args: [chair ?? "0x0"],
    query: { enabled: !!gov && !!chair },
  });
  return {
    signatures: (query.data as bigint | undefined) ?? 0n,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}
