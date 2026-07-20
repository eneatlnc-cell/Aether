"use client";

import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useState, useMemo } from "react";
import { AetherGovernanceABI, governanceAddress, type ProposalStatus } from "@/lib/contracts";

export interface ImpeachmentState {
  status: ProposalStatus | null;
  requiredSignatures: number;
  currentSignatures: number;
  impeachedTarget: string | null;
  hasSigned: boolean;
}

/**
 * useImpeachment — 弹劾提案全流程 hook
 *
 * 流程：
 *   1. createImpeachmentProposal(target, title, ipfsHash) → Drafting
 *   2. signImpeachment(proposalId) × 100 → PendingMultisig
 *   3. [Safe 多签] approveImpeachmentByMultisig(proposalId) → Active
 *   4. 普通投票期（24h）
 *   5. finalize(proposalId)
 *   6. execute(proposalId) → 自动 revokeRing
 *
 * 用法：
 *   const { create, sign, state } = useImpeachment();
 *   await create({ target, title, ipfsHash });
 *   await sign(proposalId);
 */
export function useImpeachment() {
  const { chainId } = useAccount();
  const gov = governanceAddress(chainId ?? 0);
  const { writeContractAsync, isPending: writing } = useWriteContract();
  const [lastTxHash, setLastTxHash] = useState<`0x${string}` | null>(null);

  const receiptQuery = useWaitForTransactionReceipt({ hash: lastTxHash ?? undefined });

  /**
   * 创建弹劾提案
   * @param target 弹劾目标地址（必须是高层 tier 3/6/9）
   * @param title  标题
   * @param ipfsHash IPFS 哈希
   * @returns proposalId（从事件解析；这里返回 tx hash，前端可监听 ProposalCreated 事件拿 ID）
   */
  const create = async (params: {
    target: `0x${string}`;
    title: string;
    ipfsHash: string;
  }): Promise<`0x${string}`> => {
    if (!gov) throw new Error("Governance 合约未部署");
    const tx = await writeContractAsync({
      address: gov,
      abi: AetherGovernanceABI,
      functionName: "createImpeachmentProposal",
      args: [params.target, params.title, params.ipfsHash],
    });
    setLastTxHash(tx);
    return tx;
  };

  /**
   * 联署弹劾提案（仅 tier==10 会员）
   */
  const sign = async (proposalId: bigint): Promise<`0x${string}`> => {
    if (!gov) throw new Error("Governance 合约未部署");
    const tx = await writeContractAsync({
      address: gov,
      abi: AetherGovernanceABI,
      functionName: "signImpeachment",
      args: [proposalId],
    });
    setLastTxHash(tx);
    return tx;
  };

  /**
   * 多签审查通过（msg.sender 必须是 Safe 钱包）
   * 前端通常不直接调，而是通过 Safe SDK 走 execTransaction
   */
  const approveByMultisig = async (proposalId: bigint): Promise<`0x${string}`> => {
    if (!gov) throw new Error("Governance 合约未部署");
    const tx = await writeContractAsync({
      address: gov,
      abi: AetherGovernanceABI,
      functionName: "approveImpeachmentByMultisig",
      args: [proposalId],
    });
    setLastTxHash(tx);
    return tx;
  };

  /**
   * 多签审查拒绝（msg.sender 必须是 Safe 钱包）
   */
  const rejectByMultisig = async (proposalId: bigint): Promise<`0x${string}`> => {
    if (!gov) throw new Error("Governance 合约未部署");
    const tx = await writeContractAsync({
      address: gov,
      abi: AetherGovernanceABI,
      functionName: "rejectImpeachmentByMultisig",
      args: [proposalId],
    });
    setLastTxHash(tx);
    return tx;
  };

  /**
   * 模拟弹劾结果（不写链，返回如果现在 finalize 会不会通过）
   */
  const simulate = async (proposalId: bigint): Promise<{
    wouldPass: boolean;
    participationBps: number;
    againstBps: number;
  }> => {
    if (!gov) throw new Error("Governance 合约未部署");
    // 直接走 cast call 等价；这里用 useReadContract 已在外部
    throw new Error("Use useSimulateImpeachment hook instead");
  };

  return {
    create,
    sign,
    approveByMultisig,
    rejectByMultisig,
    writing,
    lastTxHash,
    receipt: receiptQuery.data,
    isConfirming: receiptQuery.isLoading,
    isConfirmed: !!receiptQuery.data,
  };
}

/**
 * useImpeachmentState — 读取某弹劾提案的状态
 */
export function useImpeachmentState(proposalId: bigint | null) {
  const { chainId, address } = useAccount();
  const gov = governanceAddress(chainId ?? 0);
  const enabled = !!gov && proposalId !== null;

  const proposalQuery = useReadContract({
    address: gov ?? undefined,
    abi: AetherGovernanceABI,
    functionName: "proposals",
    args: [proposalId ?? 0n],
    query: { enabled },
  });

  const signedQuery = useReadContract({
    address: gov ?? undefined,
    abi: AetherGovernanceABI,
    functionName: "hasSigned",
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
    // Proposal struct 字段索引（mapping(address=>bool) hasSigned 在 tuple 中被跳过）
    // 参考 AetherGovernance.sol 的 Proposal struct 定义：
    //   0:id 1:proposer 2:pType 3:title 4:ipfsHash 5:createdAt
    //   6:votingStartAt 7:votingEndAt
    //   8:parliamentFor 9:parliamentAgainst 10:federationFor 11:federationAgainst
    //   12:senateFor 13:senateAgainst 14:memberFor 15:memberAgainst
    //   16:memberAbstain 17:memberTotalSnapshot
    //   18:totalForWeighted 19:totalAgainstWeighted
    //   20:chamberConsensus 21:memberQuorumMet 22:memberVetoTriggered
    //   23:status 24:target 25:calldataPayload 26:queuedAt 27:executeAfter 28:isFinalized
    //   29:impeachedTarget 30:requiredSignatures 31:currentSignatures
    const raw = proposalQuery.data as readonly unknown[];
    return {
      status: (raw[23] as ProposalStatus) ?? null,
      requiredSignatures: Number(raw[30] as bigint ?? 0n),
      currentSignatures: Number(raw[31] as bigint ?? 0n),
      impeachedTarget: (raw[29] as `0x${string}`) ?? null,
      hasSigned: signedQuery.data === true,
    };
  }, [proposalQuery.data, proposalQuery.status, signedQuery.data]);

  return {
    state,
    isLoading: proposalQuery.isLoading || signedQuery.isLoading,
    isError: proposalQuery.isError || signedQuery.isError,
  };
}
