// SPDX-License-Identifier: Apache-2.0
// Aether DAO 合约地址索引
// 部署后自动更新此处（或用环境变量）

import { AetherRingABI } from "./AetherRing.abi";
import { AetherGovernanceABI } from "./AetherGovernance.abi";
import { AetherElectionABI } from "./AetherElection.abi";
import { AetherDonationABI } from "./AetherDonation.abi";
import { getContracts, getSafeWalletAddress, getIpfsGateway, getUsdcAddress, getTreasuryAddress } from "./config";

export { getSafeWalletAddress, getIpfsGateway, getUsdcAddress, getTreasuryAddress };

// ──────────── 道环权级枚举（与合约 RingTier 对齐，v3 14 级） ────────────
export enum RingTier {
  NONE = 0,
  PARLIAMENT_MEMBER = 1, // 议员（议会基层）
  PARLIAMENT_SENIOR = 2, // 参议员（议会中层）
  PARLIAMENT_SPEAKER = 3, // 议长（议会高层）
  FEDERATION_MEMBER = 4, // 委员（联邦基层）
  FEDERATION_SENIOR = 5, // 委员长（联邦中层）
  FEDERATION_MINISTER = 6, // 执政（联邦高层）
  TRIBUNAL_JUDGE = 7, // 法官（法庭基层）
  TRIBUNAL_SENIOR = 8, // 大法官（法庭中层）
  TRIBUNAL_CHIEF = 9, // 首席（法庭高层）
  COUNCIL_MEMBER = 10, // 理事（理事会基层）
  COUNCIL_SENIOR = 11, // 常务理事（理事会中层）
  COUNCIL_CHAIR = 12, // 理事长（理事会高层）
  ELDER = 13, // 元老（独立机构）
  CITIZEN = 14, // 公民
}

export type Chamber = "parliament" | "federation" | "tribunal" | "council" | "elder" | "citizen";

export const TIER_LABELS: Record<RingTier, { zh: string; en: string; chamber: Chamber | "" }> = {
  [RingTier.NONE]: { zh: "无", en: "None", chamber: "" },
  [RingTier.PARLIAMENT_MEMBER]: { zh: "议员", en: "Parliament Member", chamber: "parliament" },
  [RingTier.PARLIAMENT_SENIOR]: { zh: "参议员", en: "Parliament Senior", chamber: "parliament" },
  [RingTier.PARLIAMENT_SPEAKER]: { zh: "议长", en: "Parliament Speaker", chamber: "parliament" },
  [RingTier.FEDERATION_MEMBER]: { zh: "委员", en: "Federation Member", chamber: "federation" },
  [RingTier.FEDERATION_SENIOR]: { zh: "委员长", en: "Federation Senior", chamber: "federation" },
  [RingTier.FEDERATION_MINISTER]: { zh: "执政", en: "Federation Minister", chamber: "federation" },
  [RingTier.TRIBUNAL_JUDGE]: { zh: "法官", en: "Tribunal Judge", chamber: "tribunal" },
  [RingTier.TRIBUNAL_SENIOR]: { zh: "大法官", en: "Tribunal Senior", chamber: "tribunal" },
  [RingTier.TRIBUNAL_CHIEF]: { zh: "首席", en: "Tribunal Chief", chamber: "tribunal" },
  [RingTier.COUNCIL_MEMBER]: { zh: "理事", en: "Council Member", chamber: "council" },
  [RingTier.COUNCIL_SENIOR]: { zh: "常务理事", en: "Council Senior", chamber: "council" },
  [RingTier.COUNCIL_CHAIR]: { zh: "理事长", en: "Council Chair", chamber: "council" },
  [RingTier.ELDER]: { zh: "元老", en: "Elder", chamber: "elder" },
  [RingTier.CITIZEN]: { zh: "公民", en: "Citizen", chamber: "citizen" },
};

export function chamberOf(tier: RingTier): Chamber | null {
  if (tier >= 1 && tier <= 3) return "parliament";
  if (tier >= 4 && tier <= 6) return "federation";
  if (tier >= 7 && tier <= 9) return "tribunal";
  if (tier >= 10 && tier <= 12) return "council";
  if (tier === 13) return "elder";
  if (tier === 14) return "citizen";
  return null;
}

// ──────────── 治理枚举（与合约对齐，v3） ────────────
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

// v3: 4 种提案类型（IMPEACHMENT 走专用 createImpeachmentProposal 入口）
export enum ProposalType {
  SIGNAL = 0,
  PARAM = 1,
  TREASURY = 2,
  IMPEACHMENT = 3,
}

// v3: 12 状态七阶段流程
// Drafting → PendingFirstVote → FirstVoteActive → PendingFormal
//          → PendingCompliance → PublicVoteActive → PendingVeto
//          → Queued → Executed
// 失败路径 → Defeated / Canceled / ReturnedToDraft
export enum ProposalStatus {
  Drafting = 0, // 草案（理事会推进/退回，弹劾联署中）
  PendingFirstVote = 1, // 待开始一审
  FirstVoteActive = 2, // 议会一审中
  PendingFormal = 3, // 一审通过，待正式提交
  PendingCompliance = 4, // 法庭合规审查中
  PublicVoteActive = 5, // 公投中
  PendingVeto = 6, // 待元老否决（72h 窗口）
  Queued = 7, // Timelock 排队
  Executed = 8, // 已执行
  Defeated = 9, // 未通过
  Canceled = 10, // 被否决/取消
  ReturnedToDraft = 11, // 退回草案
}

// v3: 紧急拨款标识
export enum TreasuryUrgency {
  Normal = 0,
  Emergency = 1,
}

// ──────────── 选举枚举（与 IAetherElection 对齐，v3） ────────────
// v3: 删除 REELECTION（不可连任）；新增 CITIZEN_TO_COUNCIL
export enum ElectionType {
  MEMBER_TO_GRASSROOTS = 0, // 公民 → 三院基层（普选）
  GRASSROOTS_TO_MID = 1, // 三院基层 → 中层（院选）
  CITIZEN_TO_COUNCIL = 2, // 公民 → 理事/常务理事（普选，v3 新增）
}

// v3: 4 阶段状态机（Pending→CouncilReview→ParliamentApproval→Active→Finalized）
//     失败/部分路径 → PartiallyFilled / Canceled
export enum ElectionStatus {
  Pending = 0, // 候选人注册阶段
  CouncilReview = 1, // 理事会整理阶段
  ParliamentApproval = 2, // 议会审批阶段
  Active = 3, // 投票中
  Finalized = 4, // 已计票（席位已满）
  PartiallyFilled = 5, // 已计票但有空缺（v3 新增）
  Canceled = 6, // 取消
}

// v3 新增：CITIZEN_TO_COUNCIL 目标层级
export enum CouncilTargetTier {
  CouncilMember = 0, // → tier 10 理事
  CouncilSenior = 1, // → tier 11 常务理事
}

// ──────────── ABI 导出 ────────────
export { AetherRingABI } from "./AetherRing.abi";
export { AetherGovernanceABI } from "./AetherGovernance.abi";
export { AetherElectionABI } from "./AetherElection.abi";
export { AetherDonationABI } from "./AetherDonation.abi";

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

export function donationAddress(chainId: number): `0x${string}` | null {
  const c = getContracts(chainId);
  if (!c) return null;
  if (c.AetherDonation === "0x0000000000000000000000000000000000000000") return null;
  return c.AetherDonation;
}

export function safeWalletAddress(chainId: number): `0x${string}` | null {
  return getSafeWalletAddress(chainId);
}
