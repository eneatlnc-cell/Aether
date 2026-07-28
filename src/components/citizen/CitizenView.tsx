"use client";
// SPDX-License-Identifier: Apache-2.0

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { AddressCopy } from "@/components/ui/AddressCopy";
import { Card } from "@/components/ui/Card";
import {
  Loader2,
  ShieldCheck,
  Coins,
  Calendar,
  ExternalLink,
  Award,
  AlertCircle,
} from "lucide-react";

/** /api/citizens/[address] 响应类型 */
interface CitizenApiResponse {
  citizen: {
    address: string;
    ringId: string;
    ringTier: number;
    ringTierLabel: string;
    isActive: boolean;
    firstDonationAt: string;
    totalDonatedUsdc: number;
    donationCount: number;
    nickname: string | null;
    bio: string | null;
  };
  donations: Array<{
    txHash: string;
    amountUsdc: number;
    timestamp: string;
    purpose: string;
  }>;
}

type LoadState =
  | { status: "loading" }
  | { status: "not-found" }
  | { status: "error"; message: string }
  | { status: "ok"; data: CitizenApiResponse };

const ARBISCAN_TX = "https://arbiscan.io/tx/";

/** 格式化 USDC 金额 */
function formatUsdc(n: number): string {
  return n.toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

/** 格式化日期 */
function formatDate(iso: string): string {
  try {
    return new Date(iso).toLocaleString("en-US", {
      year: "numeric",
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  } catch {
    return iso;
  }
}

export function CitizenView({ address }: { address: string }) {
  const t = useTranslations("citizen");
  const [state, setState] = useState<LoadState>({ status: "loading" });

  useEffect(() => {
    let cancelled = false;
    setState({ status: "loading" });

    fetch(`/api/citizens/${address}`)
      .then(async (res) => {
        if (cancelled) return;
        if (res.status === 404) {
          setState({ status: "not-found" });
          return;
        }
        if (!res.ok) {
          const body = await res.json().catch(() => ({}));
          setState({
            status: "error",
            message: body.error ?? `HTTP ${res.status}`,
          });
          return;
        }
        const data = (await res.json()) as CitizenApiResponse;
        setState({ status: "ok", data });
      })
      .catch(() => {
        if (!cancelled) {
          setState({ status: "error", message: "Network error" });
        }
      });

    return () => {
      cancelled = true;
    };
  }, [address]);

  if (state.status === "loading") {
    return (
      <div className="flex items-center justify-center py-24">
        <Loader2 size={24} className="animate-spin text-accent" />
      </div>
    );
  }

  if (state.status === "not-found") {
    return (
      <div className="max-w-2xl mx-auto px-4 py-16 text-center">
        <AlertCircle size={40} className="mx-auto text-muted mb-4" />
        <h2 className="text-lg font-semibold text-ink mb-2">
          {t("notCitizenTitle")}
        </h2>
        <p className="text-sm text-muted mb-6">{t("notCitizenDesc")}</p>
        <a
          href="/"
          className="inline-flex items-center gap-2 px-4 py-2 bg-accent text-white rounded-[8px] text-sm hover:bg-accent/90 transition-colors"
        >
          {t("donateToJoin")}
        </a>
      </div>
    );
  }

  if (state.status === "error") {
    return (
      <div className="max-w-2xl mx-auto px-4 py-16 text-center">
        <AlertCircle size={40} className="mx-auto text-muted mb-4" />
        <h2 className="text-lg font-semibold text-ink mb-2">
          {t("errorTitle")}
        </h2>
        <p className="text-sm text-muted font-mono">{state.message}</p>
      </div>
    );
  }

  const { citizen, donations } = state.data;

  return (
    <div className="max-w-3xl mx-auto px-4 sm:px-6 py-8 sm:py-12">
      {/* ── 模拟道环可视化 ── */}
      <div className="flex flex-col items-center mb-8">
        <RingVisual ringId={citizen.ringId} tier={citizen.ringTier} />
        <h1 className="text-xl font-bold text-ink mt-4">
          {t("citizenTitle")}
        </h1>
        <p className="text-xs text-muted mt-1">{t("ringSimulated")}</p>
      </div>

      {/* ── 公民信息卡 ── */}
      <Card className="p-5 mb-6">
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <InfoRow
            icon={<ShieldCheck size={16} className="text-accent" />}
            label={t("address")}
          >
            <AddressCopy address={citizen.address} label={t("copied")} />
          </InfoRow>
          <InfoRow
            icon={<Award size={16} className="text-accent" />}
            label={t("ringTier")}
          >
            <span className="text-sm font-medium text-ink">
              {citizen.ringTierLabel}
            </span>
          </InfoRow>
          <InfoRow
            icon={<Coins size={16} className="text-accent" />}
            label={t("totalDonated")}
          >
            <span className="text-sm font-semibold text-ink">
              {formatUsdc(citizen.totalDonatedUsdc)} USDC
            </span>
          </InfoRow>
          <InfoRow
            icon={<Calendar size={16} className="text-accent" />}
            label={t("firstDonation")}
          >
            <span className="text-sm text-ink">
              {formatDate(citizen.firstDonationAt)}
            </span>
          </InfoRow>
        </div>

        {/* 道环 ID（完整 hash） */}
        <div className="mt-4 pt-4 border-t border-border">
          <p className="text-xs text-muted uppercase tracking-wide mb-1.5">
            {t("ringId")}
          </p>
          <p className="text-xs text-ink font-mono break-all bg-bg px-3 py-2 rounded-[6px] border border-border">
            {citizen.ringId}
          </p>
        </div>
      </Card>

      {/* ── 捐款记录 ── */}
      <div className="mb-3 flex items-center justify-between">
        <h2 className="text-base font-semibold text-ink">
          {t("donationHistory")}
        </h2>
        <span className="text-xs text-muted">
          {t("donationCount", { count: citizen.donationCount })}
        </span>
      </div>

      {donations.length === 0 ? (
        <Card className="p-6 text-center">
          <p className="text-sm text-muted">{t("noDonations")}</p>
        </Card>
      ) : (
        <div className="space-y-2">
          {donations.map((d) => (
            <Card key={d.txHash} className="p-4 hover:bg-bg/50 transition-colors">
              <div className="flex items-center justify-between gap-3">
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2 mb-1">
                    <span className="text-sm font-semibold text-ink">
                      {formatUsdc(d.amountUsdc)} USDC
                    </span>
                    <span className="text-xs text-muted">·</span>
                    <span className="text-xs text-muted">
                      {formatDate(d.timestamp)}
                    </span>
                  </div>
                  <a
                    href={`${ARBISCAN_TX}${d.txHash}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1 text-xs text-accent hover:underline font-mono"
                  >
                    {d.txHash.slice(0, 18)}…{d.txHash.slice(-8)}
                    <ExternalLink size={11} />
                  </a>
                </div>
                <span className="text-xs text-muted capitalize flex-shrink-0">
                  {d.purpose}
                </span>
              </div>
            </Card>
          ))}
        </div>
      )}

      {/* ── 预启动阶段说明 ── */}
      <p className="text-xs text-muted text-center mt-8 leading-relaxed">
        {t("preLaunchNote")}
      </p>
    </div>
  );
}

/* ---------- 模拟道环可视化（纯 CSS，无 NFT） ---------- */
function RingVisual({
  ringId,
  tier,
}: {
  ringId: string;
  tier: number;
}) {
  // 用 ringId 末尾字节决定渐变色相，让每个公民的环视觉上略有差异
  const hue = parseInt(ringId.slice(-2), 16) % 360;
  const ringStyle = {
    background: `conic-gradient(from 0deg, hsl(${hue}, 70%, 60%), hsl(${(hue + 120) % 360}, 70%, 55%), hsl(${(hue + 240) % 360}, 70%, 60%), hsl(${hue}, 70%, 60%))`,
  };

  return (
    <div
      className="relative w-28 h-28 rounded-full flex items-center justify-center shadow-lg"
      style={ringStyle}
    >
      <div className="absolute inset-2 rounded-full bg-card flex items-center justify-center">
        <div className="text-center">
          <ShieldCheck size={28} className="text-accent mx-auto" />
          <p className="text-[10px] text-muted mt-1">TIER {tier}</p>
        </div>
      </div>
    </div>
  );
}

/* ---------- 信息行 ---------- */
function InfoRow({
  icon,
  label,
  children,
}: {
  icon: React.ReactNode;
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div>
      <p className="text-xs text-muted uppercase tracking-wide mb-1.5 flex items-center gap-1.5">
        {icon}
        {label}
      </p>
      {children}
    </div>
  );
}
