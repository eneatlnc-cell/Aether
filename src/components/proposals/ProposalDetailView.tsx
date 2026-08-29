"use client";
// SPDX-License-Identifier: Apache-2.0

import { useTranslations } from "next-intl";
import { Navbar } from "@/components/home/Navbar";
import { Footer } from "@/components/home/Footer";
import { Card } from "@/components/ui/Card";
import { StatusDot } from "@/components/ui/StatusDot";
import { ProgressBar } from "@/components/ui/ProgressBar";
import { Button } from "@/components/ui/Button";
import { useWallet } from "@/hooks/useWallet";
import { proposals } from "@/lib/data";
import { GOVERNANCE_DEPLOYED } from "@/lib/deployment";
import { DemoBanner } from "@/components/ui/DemoBanner";
import { ArrowLeft, Check, X, Minus, Clock } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState, useEffect } from "react";

interface ProposalDetailViewProps {
  proposalId: string;
}

export function ProposalDetailView({ proposalId }: ProposalDetailViewProps) {
  const t = useTranslations("proposals");
  const tDetail = useTranslations("proposalDetail");
  const proposal = proposals.find((p) => p.id === proposalId);

  if (!proposal) {
    return (
      <>
        <Navbar />
        <main className="flex-1 flex items-center justify-center px-6 py-20">
          <p className="text-muted">{tDetail("notFound")}</p>
        </main>
      </>
    );
  }

  // Mock proposal.id 到 i18n key 的映射
  // 注意：t = useTranslations("proposals")，所以 key 不能再带 "proposals." 前缀
  const titleKey = getProposalI18nKey(proposal.id, "title");
  const summaryKey = getProposalI18nKey(proposal.id, "summary");
  const titleText = t(titleKey as never);
  const summaryText = t(summaryKey as never);

  return (
    <>
      <Navbar />
      <main className="flex-1 py-12 sm:py-16 px-6 lg:px-8">
        <div className="max-w-[960px] mx-auto">
          <BackLink />

          {!GOVERNANCE_DEPLOYED && (
            <div className="mt-6">
              <DemoBanner variant="governance" />
            </div>
          )}

          <article className="mt-6">
            {/* 标题区 */}
            <header className="mb-8">
              <div className="flex items-center gap-3 mb-4">
                <StatusDot
                  status={
                    proposal.status === "active"
                      ? "active"
                      : proposal.status === "passed"
                      ? "passed"
                      : "rejected"
                  }
                  label={
                    proposal.status === "active"
                      ? t("statusActive")
                      : proposal.status === "passed"
                      ? t("statusPassed")
                      : t("statusRejected")
                  }
                />
                <span className="text-xs text-muted font-mono">
                  {proposal.id}
                </span>
              </div>
              <h1 className="text-3xl sm:text-4xl font-extrabold text-ink tracking-tight leading-tight">
                {titleText}
              </h1>
            </header>

            {/* 简述 */}
            <Card className="mb-6">
              <p className="text-xs text-muted uppercase tracking-wide mb-2">
                {tDetail("summary")}
              </p>
              <p className="text-base text-ink leading-relaxed">{summaryText}</p>
            </Card>

            {/* 投票统计 */}
            <Card className="mb-6">
              <h2 className="text-base font-semibold text-ink mb-5">
                {tDetail("voteBreakdown")}
              </h2>
              <div className="grid grid-cols-3 gap-4 mb-6">
                <VoteStat
                  icon={<Check size={16} />}
                  label={t("forVotes")}
                  value={proposal.forVotes}
                  tone="accent"
                />
                <VoteStat
                  icon={<X size={16} />}
                  label={t("againstVotes")}
                  value={proposal.againstVotes}
                  tone="muted"
                />
                <VoteStat
                  icon={<Minus size={16} />}
                  label={t("abstainVotes")}
                  value={proposal.abstainVotes}
                  tone="muted"
                />
              </div>
              <ProgressBar value={proposal.progress} showLabel label={tDetail("councilProgress")} />
            </Card>

            {/* 投票区 */}
            <Card>
              <h2 className="text-base font-semibold text-ink mb-4">
                {tDetail("castVote")}
              </h2>
              {!GOVERNANCE_DEPLOYED ? (
                <VotingNotLive />
              ) : (
                <VoteControls
                  isActive={proposal.status === "active"}
                  deadline={proposal.deadline}
                />
              )}
            </Card>
          </article>
        </div>
      </main>
      <Footer />
    </>
  );
}

/**
 * 诚实占位：治理合约尚未部署，投票功能不存在。
 * 不渲染任何"看起来能投票"的按钮，避免用户误以为点击已生效。
 * 部署后由 GOVERNANCE_DEPLOYED 开关切换回真实 VoteControls。
 */
function VotingNotLive() {
  const t = useTranslations("proposalDetail");
  return (
    <div className="rounded-xl border border-border bg-bg px-5 py-5">
      <div className="flex items-center gap-2 mb-2">
        <Clock size={15} className="text-muted" aria-hidden />
        <p className="text-sm font-semibold text-ink">
          {t("votingNotLiveTitle")}
        </p>
      </div>
      <p className="text-sm text-muted leading-relaxed">
        {t("votingNotLiveBody")}
      </p>
    </div>
  );
}

function VoteStat({
  icon,
  label,
  value,
  tone,
}: {
  icon: React.ReactNode;
  label: string;
  value: number;
  tone: "accent" | "muted";
}) {
  return (
    <div className="text-center">
      <div
        className={`w-10 h-10 mx-auto rounded-full flex items-center justify-center mb-2 ${
          tone === "accent" ? "bg-accent/10 text-accent" : "bg-bg text-muted"
        }`}
      >
        {icon}
      </div>
      <p className="text-2xl font-bold text-ink tabular-nums">{value}</p>
      <p className="text-xs text-muted mt-1">{label}</p>
    </div>
  );
}

function VoteControls({
  isActive,
  deadline,
}: {
  isActive: boolean;
  deadline: number;
}) {
  const t = useTranslations("proposalDetail");
  const { isConnected, mounted } = useWallet();
  const [voting, setVoting] = useState(false);
  const [remaining, setRemaining] = useState(() => deadline - Date.now());

  useEffect(() => {
    const id = setInterval(() => setRemaining(deadline - Date.now()), 60_000);
    return () => clearInterval(id);
  }, [deadline]);

  const days = Math.max(0, Math.floor(remaining / (1000 * 60 * 60 * 24)));
  const hours = Math.max(
    0,
    Math.floor((remaining % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60))
  );

  const handleVote = async () => {
    if (!isConnected) return;
    setVoting(true);
    // 占位：实际通过 EIP-712 链下签名聚合（按选项 for/against/abstain 分流）
    await new Promise((r) => setTimeout(r, 800));
    setVoting(false);
    // toast 由 useVote Hook 触发，这里简化
  };

  if (!isActive) {
    return (
      <p className="text-sm text-muted">{t("voteClosed")}</p>
    );
  }

  if (!mounted || !isConnected) {
    return (
      <p className="text-sm text-muted">{t("connectToVote")}</p>
    );
  }

  return (
    <>
      <div className="mb-4 flex items-center justify-between text-sm">
        <span className="text-muted">{t("remaining")}</span>
        <span className="text-ink font-medium">
          {days}d {hours}h
        </span>
      </div>
      <div className="grid grid-cols-3 gap-3">
        <Button
          variant="accent"
          onClick={() => handleVote()}
          disabled={voting}
        >
          <Check size={14} />
          {t("for")}
        </Button>
        <Button
          variant="outline"
          onClick={() => handleVote()}
          disabled={voting}
        >
          <X size={14} />
          {t("against")}
        </Button>
        <Button
          variant="ghost"
          onClick={() => handleVote()}
          disabled={voting}
        >
          <Minus size={14} />
          {t("abstain")}
        </Button>
      </div>
    </>
  );
}

function BackLink() {
  const t = useTranslations("proposalDetail");
  const router = useRouter();
  return (
    <button
      onClick={() => router.back()}
      className="inline-flex items-center gap-2 text-sm text-muted hover:text-accent transition-colors"
    >
      <ArrowLeft size={14} />
      {t("back")}
    </button>
  );
}

/**
 * Mock proposal.id 到 i18n key 的映射
 * 真实接入后由治理合约返回 proposal metadata 时直接带 i18n key
 *
 * 返回的 key 已剥离 "proposals." 前缀，因为调用方已 useTranslations("proposals")
 */
function getProposalI18nKey(proposalId: string, field: "title" | "summary"): string {
  const map: Record<string, string> = {
    "Q4-2025-bandwidth": "q4Bandwidth",
    "ai-opensource-ecosystem": "aiEcosystem",
    "mesh-routing-2026": "meshRouting",
  };
  const shortKey = map[proposalId] ?? proposalId;
  return `items.${shortKey}.${field}`;
}
