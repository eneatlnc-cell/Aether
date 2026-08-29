"use client";
// SPDX-License-Identifier: Apache-2.0

import { useTranslations } from "next-intl";
import { Link } from "@/i18n/navigation";
import { Card } from "@/components/ui/Card";
import { StatusDot } from "@/components/ui/StatusDot";
import { ProgressBar } from "@/components/ui/ProgressBar";
import { useProposals } from "@/hooks/useProposals";
import { GOVERNANCE_DEPLOYED } from "@/lib/deployment";
import { DemoBanner } from "@/components/ui/DemoBanner";
import { ArrowRight } from "lucide-react";
import { useEffect, useState } from "react";

export function ProposalFeed() {
  const t = useTranslations("proposals");
  const proposals = useProposals();

  return (
    <section id="governance" className="md:col-span-2">
      <header className="mb-6">
        <h2 className="text-2xl font-bold text-ink">{t("sectionTitle")}</h2>
        <p className="mt-2 text-sm text-muted leading-relaxed">
          {t("sectionSubtitle")}
        </p>
      </header>
      {!GOVERNANCE_DEPLOYED && (
        <div className="mb-5">
          <DemoBanner variant="governance" />
        </div>
      )}
      <div className="flex flex-col gap-4">
        {proposals.map((p) => (
          <Card key={p.id} hover>
            <div className="flex items-start justify-between gap-4">
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 mb-2">
                  <StatusDot
                    status={p.status === "active" ? "active" : p.status === "passed" ? "passed" : "rejected"}
                    label={
                      p.status === "active"
                        ? t("statusActive")
                        : p.status === "passed"
                        ? t("statusPassed")
                        : t("statusRejected")
                    }
                  />
                </div>
                <h3 className="text-base font-semibold text-ink leading-snug">
                  {p.title}
                </h3>
                <p className="mt-2 text-sm text-muted leading-relaxed">
                  {p.summary}
                </p>
              </div>
            </div>

            <div className="mt-5 grid grid-cols-3 gap-3 text-xs">
              <VoteStat label={t("forVotes")} value={p.forVotes} tone="accent" />
              <VoteStat label={t("againstVotes")} value={p.againstVotes} tone="muted" />
              <VoteStat label={t("abstainVotes")} value={p.abstainVotes} tone="muted" />
            </div>

            <div className="mt-5">
              <ProgressBar value={p.progress} variant="neutral" />
            </div>

            <div className="mt-4 pt-4 border-t border-border flex items-center justify-between">
              <Countdown deadline={p.deadline} label={t("deadline")} />
              <Link
                href={`/proposals/${p.id}`}
                className="inline-flex items-center gap-1 text-sm text-ink hover:text-accent transition-colors"
              >
                {t("viewDetail")}
                <ArrowRight size={14} />
              </Link>
            </div>
          </Card>
        ))}
      </div>
    </section>
  );
}

function VoteStat({
  label,
  value,
  tone,
}: {
  label: string;
  value: number;
  tone: "accent" | "muted";
}) {
  return (
    <div className="flex flex-col">
      <span className="text-muted">{label}</span>
      <span
        className={`text-lg font-semibold ${
          tone === "accent" ? "text-accent" : "text-ink"
        }`}
      >
        {value}
      </span>
    </div>
  );
}

function Countdown({ deadline, label }: { deadline: number; label: string }) {
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000 * 60);
    return () => clearInterval(id);
  }, []);

  const remaining = Math.max(0, deadline - now);
  const days = Math.floor(remaining / (1000 * 60 * 60 * 24));
  const hours = Math.floor((remaining % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));

  return (
    <span className="text-xs text-muted">
      {label}:{" "}
      <span className="text-ink font-medium">
        {days}d {hours}h
      </span>
    </span>
  );
}
