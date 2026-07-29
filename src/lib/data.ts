// SPDX-License-Identifier: Apache-2.0
export type ProjectId =
  | "ai-framework"
  | "self-organizing-net";

export type ProposalStatus = "active" | "passed" | "rejected";

export type CouncilTier =
  | "coreDirector"
  | "seniorResearcher"
  | "ecosystemBuilder";

export interface ProjectMeta {
  id: ProjectId;
  icon: "hex" | "wave" | "mesh";
  status: "research" | "testnet";
}

export interface Proposal {
  id: string;
  titleKey: string;
  summaryKey: string;
  status: ProposalStatus;
  forVotes: number;
  againstVotes: number;
  abstainVotes: number;
  /** 截止时间戳（毫秒） */
  deadline: number;
  /** 进度 0-100 */
  progress: number;
}

export interface CouncilMember {
  id: string;
  name: string;
  tier: CouncilTier;
  /** 负责项目或研究领域（i18n key） */
  focusKey: string;
  initials: string;
}

export const projects: ProjectMeta[] = [
  { id: "ai-framework", icon: "hex", status: "research" },
  { id: "self-organizing-net", icon: "mesh", status: "research" },
];

export const proposals: Proposal[] = [
  {
    id: "ai-opensource-ecosystem",
    titleKey: "proposals.items.aiEcosystem.title",
    summaryKey: "proposals.items.aiEcosystem.summary",
    status: "active",
    forVotes: 9,
    againstVotes: 1,
    abstainVotes: 0,
    deadline: Date.now() + 1000 * 60 * 60 * 24 * 4,
    progress: 81,
  },
  {
    id: "mesh-routing-2026",
    titleKey: "proposals.items.meshRouting.title",
    summaryKey: "proposals.items.meshRouting.summary",
    status: "passed",
    forVotes: 10,
    againstVotes: 0,
    abstainVotes: 0,
    deadline: Date.now() - 1000 * 60 * 60 * 24 * 3,
    progress: 100,
  },
];

export const councilMembers: CouncilMember[] = [
  {
    id: "c-01",
    name: "Aria Vance",
    tier: "coreDirector",
    focusKey: "council.members.aria.focus",
    initials: "AV",
  },
  {
    id: "c-02",
    name: "Kenji Mori",
    tier: "coreDirector",
    focusKey: "council.members.kenji.focus",
    initials: "KM",
  },
  {
    id: "c-03",
    name: "Linnea Holm",
    tier: "seniorResearcher",
    focusKey: "council.members.linnea.focus",
    initials: "LH",
  },
  {
    id: "c-04",
    name: "Diego Salas",
    tier: "seniorResearcher",
    focusKey: "council.members.diego.focus",
    initials: "DS",
  },
  {
    id: "c-05",
    name: "Priya Iyer",
    tier: "ecosystemBuilder",
    focusKey: "council.members.priya.focus",
    initials: "PI",
  },
];
