// Aether DAO 合约地址索引
// 部署后自动更新此处（或用环境变量）

import { AetherRingABI } from "./AetherRing.abi";
import { AetherGovernanceABI } from "./AetherGovernance.abi";
import { AetherElectionABI } from "./AetherElection.abi";
import { getContracts } from "./config";

// ──────────── 道环权级枚举（与合约 RingTier 对齐） ────────────
export enum RingTier {
  NONE = 0,
  PARLIAMENT_MEMBER = 1, // 议员
  PARLIAMENT_SENIOR = 2, // 参议员
  PARLIAMENT_SPEAKER = 3, // 议长
  FEDERATION_MEMBER = 4, // 委员
  FEDERATION_SENIOR = 5, // 委员长
  FEDERATION_MINISTER = 6, // 部长
  SENATE_ADVISOR = 7, // 顾问
  SENATE_FELLOW = 8, // 研究员
  SENATE_ELDER = 9, // 元老
  GENERAL_MEMBER = 10, // 普通会员
}

export const TIER_LABELS: Record<RingTier, { zh: string; en: string; chamber: string }> = {
  [RingTier.NONE]: { zh: "无", en: "None", chamber: "" },
  [RingTier.PARLIAMENT_MEMBER]: { zh: "议员", en: "Parliament Member", chamber: "parliament" },
  [RingTier.PARLIAMENT_SENIOR]: { zh: "参议员", en: "Parliament Senior", chamber: "parliament" },
  [RingTier.PARLIAMENT_SPEAKER]: { zh: "议长", en: "Parliament Speaker", chamber: "parliament" },
  [RingTier.FEDERATION_MEMBER]: { zh: "委员", en: "Federation Member", chamber: "federation" },
  [RingTier.FEDERATION_SENIOR]: { zh: "委员长", en: "Federation Senior", chamber: "federation" },
  [RingTier.FEDERATION_MINISTER]: { zh: "部长", en: "Federation Minister", chamber: "federation" },
  [RingTier.SENATE_ADVISOR]: { zh: "顾问", en: "Senate Advisor", chamber: "senate" },
  [RingTier.SENATE_FELLOW]: { zh: "研究员", en: "Senate Fellow", chamber: "senate" },
  [RingTier.SENATE_ELDER]: { zh: "元老", en: "Senate Elder", chamber: "senate" },
  [RingTier.GENERAL_MEMBER]: { zh: "普通会员", en: "General Member", chamber: "member" },
};

export function chamberOf(tier: RingTier): "parliament" | "federation" | "senate" | "member" | null {
  if (tier >= 1 && tier <= 3) return "parliament";
  if (tier >= 4 && tier <= 6) return "federation";
  if (tier >= 7 && tier <= 9) return "senate";
  if (tier === 10) return "member";
  return null;
}

// ──────────── 治理枚举（与合约对齐） ────────────
export enum VoteOption {
  NONE = 0,
  FOR = 1,
  AGAINST = 2,
  ABSTAIN = 3,
}

export enum ChamberStance {
  NEUTRAL = 0,
  FOR = 1,
  AGAINST = 2,
}

// v2: 新增 IMPEACHMENT 弹劾类型
export enum ProposalType {
  SIGNAL = 0,
  PARAM = 1,
  TREASURY = 2,
  IMPEACHMENT = 3,
}

// v2: 新增 Drafting（弹劾联署中）、PendingMultisig（弹劾等 Safe 审查）
export enum ProposalStatus {
  Active = 0,
  Defeated = 1,
  Queued = 2,
  Executed = 3,
  Canceled = 4,
  Drafting = 5,
  PendingMultisig = 6,
}

// ──────────── 选举枚举（与 IAetherElection 对齐） ────────────
export enum ElectionType {
  MEMBER_TO_GRASSROOTS = 0, // 普通会员 → 基层
  GRASSROOTS_TO_MID = 1, // 基层 → 中层
  REELECTION = 2, // 连任选举
}

export enum ElectionStatus {
  Active = 0, // 投票中
  Finalized = 1, // 已结算
  Canceled = 2, // 已取消
}

// ──────────── ABI 导出 ────────────
export { AetherRingABI } from "./AetherRing.abi";
export { AetherGovernanceABI } from "./AetherGovernance.abi";
export { AetherElectionABI } from "./AetherElection.abi";

// ──────────── 地址获取（按当前链） ────────────
export function ringAddress(chainId: number): `0x${string}` | null {
  const c = getContracts(chainId);
  if (!c) return null;
  if (c.AetherRing === "0x0000000000000000000000000000000000000000") return null;
  return c.AetherRing;
}

export function governanceAddress(chainId: number): `0x${string}` | null {
  const c = getContracts(chainId);
  if (!c) return null;
  if (c.AetherGovernance === "0x0000000000000000000000000000000000000000") return null;
  return c.AetherGovernance;
}

export function electionAddress(chainId: number): `0x${string}` | null {
  const c = getContracts(chainId);
  if (!c) return null;
  if (c.AetherElection === "0x0000000000000000000000000000000000000000") return null;
  return c.AetherElection;
}
