"use client";

import { useTranslations, useFormatter } from "next-intl";
import { Card } from "@/components/ui/Card";
import { Skeleton } from "@/components/ui/Skeleton";
import { useCountUp } from "@/hooks/useCountUp";
import type { AssetHolding, ProjectFund } from "@/lib/fundFlowData";

interface KpiCardsProps {
  totalDonated: AssetHolding[];
  projectFunds: ProjectFund[];
  treasuryBalanceUsd: number;
  loading: boolean;
}

export function KpiCards({
  totalDonated,
  projectFunds,
  treasuryBalanceUsd,
  loading,
}: KpiCardsProps) {
  const t = useTranslations("fundFlow");

  if (loading) {
    return (
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        {[0, 1, 2].map((i) => (
          <Card key={i}>
            <Skeleton width="60%" height={14} />
            <div className="mt-4">
              <Skeleton width="80%" height={32} />
            </div>
            <div className="mt-3 space-y-2">
              <Skeleton width="100%" height={12} />
              <Skeleton width="70%" height={12} />
            </div>
          </Card>
        ))}
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
      <TotalDonatedCard totalDonated={totalDonated} title={t("totalDonated")} />
      <ProjectFundsCard projectFunds={projectFunds} title={t("projectAllocated")} />
      <TreasuryBalanceCard
        usd={treasuryBalanceUsd}
        title={t("treasuryBalance")}
      />
    </div>
  );
}

/* ---------- 总受捐金额 ---------- */
function TotalDonatedCard({
  totalDonated,
  title,
}: {
  totalDonated: AssetHolding[];
  title: string;
}) {
  const format = useFormatter();
  const totalUsd = totalDonated.reduce((s, a) => s + a.usdValue, 0);
  const animated = useCountUp(totalUsd);

  return (
    <Card>
      <p className="text-xs text-muted uppercase tracking-wide">{title}</p>
      <p className="mt-3 text-3xl font-bold text-ink">
        {format.number(Math.round(animated), {
          style: "currency",
          currency: "USD",
          maximumFractionDigits: 0,
        })}
      </p>
      <div className="mt-4 pt-4 border-t border-border space-y-2">
        {totalDonated.map((a) => (
          <div
            key={a.asset}
            className="flex items-center justify-between text-sm"
          >
            <span className="text-muted">{a.asset}</span>
            <span className="text-ink font-medium tabular-nums">
              {format.number(a.amount, {
                maximumFractionDigits: a.asset === "ETH" ? 2 : 0,
              })}
            </span>
          </div>
        ))}
      </div>
    </Card>
  );
}

/* ---------- 各项目已拨付资金 ---------- */
function ProjectFundsCard({
  projectFunds,
  title,
}: {
  projectFunds: ProjectFund[];
  title: string;
}) {
  const format = useFormatter();
  const totalSpent = projectFunds.reduce((s, p) => s + p.spentUsd, 0);
  const totalBudget = projectFunds.reduce((s, p) => s + p.budgetUsd, 0);
  const animated = useCountUp(totalSpent);

  return (
    <Card>
      <p className="text-xs text-muted uppercase tracking-wide">{title}</p>
      <p className="mt-3 text-3xl font-bold text-ink">
        {format.number(Math.round(animated), {
          style: "currency",
          currency: "USD",
          maximumFractionDigits: 0,
        })}
        <span className="text-base text-muted font-normal">
          {" / "}
          {format.number(totalBudget, {
            style: "currency",
            currency: "USD",
            maximumFractionDigits: 0,
          })}
        </span>
      </p>
      <div className="mt-4 pt-4 border-t border-border space-y-3">
        {projectFunds.map((p) => {
          const pct = (p.spentUsd / p.budgetUsd) * 100;
          return (
            <div key={p.projectId}>
              <div className="flex items-center justify-between text-xs mb-1">
                <span className="text-muted">{projectIdLabel(p.projectId)}</span>
                <span className="text-ink tabular-nums">
                  {pct.toFixed(0)}%
                </span>
              </div>
              <div className="w-full bg-border rounded-full overflow-hidden h-1.5">
                <div
                  className="h-full bg-gradient-to-r from-border to-ink transition-all duration-700"
                  style={{ width: `${pct}%` }}
                />
              </div>
            </div>
          );
        })}
      </div>
    </Card>
  );
}

/* ---------- 当前金库余额 ---------- */
function TreasuryBalanceCard({
  usd,
  title,
}: {
  usd: number;
  title: string;
}) {
  const format = useFormatter();
  const animated = useCountUp(usd);

  return (
    <Card>
      <p className="text-xs text-muted uppercase tracking-wide">{title}</p>
      <p className="mt-3 text-3xl font-bold text-accent">
        {format.number(Math.round(animated), {
          style: "currency",
          currency: "USD",
          maximumFractionDigits: 0,
        })}
      </p>
      <p className="mt-4 pt-4 border-t border-border text-xs text-muted leading-relaxed">
        Real-time on-chain balance of the Foundation treasury multisig on
        Arbitrum.
      </p>
    </Card>
  );
}

function projectIdLabel(id: string): string {
  const map: Record<string, string> = {
    "ai-framework": "GOV",
    "video-protocol": "Video",
    "self-organizing-net": "Mesh",
  };
  return map[id] ?? id;
}
