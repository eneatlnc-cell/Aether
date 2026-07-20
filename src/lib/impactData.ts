export interface FundAllocation {
  projectId: "ai-framework" | "video-protocol" | "self-organizing-net" | "unrestricted";
  percentage: number;
  descriptionKey: string;
}

export interface AnnualBudget {
  fiscalYear: number;
  totalUsd: number;
  lineItems: {
    category: string;
    amountUsd: number;
    noteKey: string;
  }[];
}

export interface CouncilCompensationPolicy {
  hasCompensation: boolean;
  descriptionKey: string;
  monthlyHonorariumUsd?: number;
  reviewCycleKey: string;
}

export interface AuditArrangement {
  cadenceKey: string;
  providerKey: string;
  reportPublic: boolean;
  lastReportDate: string;
}

export const fundAllocations: FundAllocation[] = [
  {
    projectId: "ai-framework",
    percentage: 30,
    descriptionKey: "impact.allocations.ai-framework.desc",
  },
  {
    projectId: "video-protocol",
    percentage: 30,
    descriptionKey: "impact.allocations.video-protocol.desc",
  },
  {
    projectId: "self-organizing-net",
    percentage: 30,
    descriptionKey: "impact.allocations.self-organizing-net.desc",
  },
  {
    projectId: "unrestricted",
    percentage: 10,
    descriptionKey: "impact.allocations.unrestricted.desc",
  },
];

export const annualBudget: AnnualBudget = {
  fiscalYear: 2026,
  totalUsd: 900_000,
  lineItems: [
    {
      category: "R&D Grants",
      amountUsd: 540_000,
      // 注意：调用方 useTranslations("impact")，key 已剥离 "impact." 前缀
      noteKey: "budget.items.rd",
    },
    {
      category: "Infrastructure",
      amountUsd: 180_000,
      noteKey: "budget.items.infra",
    },
    {
      category: "Operations",
      amountUsd: 120_000,
      noteKey: "budget.items.ops",
    },
    {
      category: "Audit & Compliance",
      amountUsd: 60_000,
      noteKey: "budget.items.audit",
    },
  ],
};

export const councilCompensation: CouncilCompensationPolicy = {
  hasCompensation: true,
  descriptionKey: "impact.compensation.description",
  monthlyHonorariumUsd: 2500,
  reviewCycleKey: "impact.compensation.reviewCycle",
};

export const auditArrangement: AuditArrangement = {
  cadenceKey: "impact.audit.cadence",
  providerKey: "impact.audit.provider",
  reportPublic: true,
  lastReportDate: "2026-04-30",
};
