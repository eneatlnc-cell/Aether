"use client";

import { useEffect, useState } from "react";
import { useTranslations, useLocale } from "next-intl";
import { useAccount } from "wagmi";
import { Loader2, ShieldCheck, ArrowRight } from "lucide-react";

/** /api/citizens/[address] 响应类型（精简版，只取横幅需要的字段） */
interface CitizenBannerData {
  citizen: {
    address: string;
    ringId: string;
    ringTier: number;
    ringTierLabel: string;
    totalDonatedUsdc: number;
    donationCount: number;
  };
}

type LoadState =
  | { status: "loading" }
  | { status: "not-citizen" }
  | { status: "ok"; data: CitizenBannerData };

/** 格式化 USDC 金额 */
function formatUsdc(n: number): string {
  return n.toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

/**
 * Citizen ID 横幅卡片 —— 显示在 /impact 治理页最顶部。
 *
 * 逻辑：
 *   - 未连接钱包 → 不渲染（返回 null）
 *   - 已连接钱包 → 拉取 /api/citizens/[address]
 *     - 不是公民（404）→ 显示"还不是公民"引导卡片
 *     - 是公民 → 显示道环可视化 + 公民信息预览 + 查看完整身份 CTA
 *
 * 点击卡片跳转 /${locale}/citizen/[address]
 */
export function CitizenBanner() {
  const t = useTranslations("citizenBanner");
  const locale = useLocale();
  const { address, isConnected } = useAccount();
  const [state, setState] = useState<LoadState>({ status: "loading" });

  useEffect(() => {
    if (!isConnected || !address) return;

    let cancelled = false;
    setState({ status: "loading" });

    fetch(`/api/citizens/${address.toLowerCase()}`)
      .then(async (res) => {
        if (cancelled) return;
        if (res.status === 404) {
          setState({ status: "not-citizen" });
          return;
        }
        if (!res.ok) {
          // 服务端错误时静默降级为"还不是公民"，避免阻塞治理页
          setState({ status: "not-citizen" });
          return;
        }
        const data = (await res.json()) as CitizenBannerData;
        setState({ status: "ok", data });
      })
      .catch(() => {
        if (!cancelled) setState({ status: "not-citizen" });
      });

    return () => {
      cancelled = true;
    };
  }, [isConnected, address]);

  // 未连接钱包 → 不渲染（游客视图）
  if (!isConnected || !address) return null;

  const citizenHref = `/${locale}/citizen/${address.toLowerCase()}`;

  // 加载中
  if (state.status === "loading") {
    return (
      <div className="mb-12 sm:mb-16">
        <div className="flex items-center gap-3 p-5 bg-card border border-border rounded-[12px]">
          <Loader2 size={20} className="animate-spin text-accent" />
          <span className="text-sm text-muted">{t("loading")}</span>
        </div>
      </div>
    );
  }

  // 已连接但还不是公民
  if (state.status === "not-citizen") {
    return (
      <div className="mb-12 sm:mb-16">
        <a
          href={`/${locale}`}
          className="block p-5 bg-card border border-dashed border-border rounded-[12px] hover:border-accent/50 transition-colors"
        >
          <div className="flex items-center gap-4">
            <div className="w-12 h-12 rounded-full bg-bg border border-border flex items-center justify-center flex-shrink-0">
              <ShieldCheck size={20} className="text-muted" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-semibold text-ink">
                {t("notCitizenTitle")}
              </p>
              <p className="text-xs text-muted mt-0.5">
                {t("notCitizenDesc")}
              </p>
            </div>
            <ArrowRight size={16} className="text-muted flex-shrink-0" />
          </div>
        </a>
      </div>
    );
  }

  // 已是公民 → 完整横幅卡片
  const { citizen } = state.data;
  const hue = parseInt(citizen.ringId.slice(-2), 16) % 360;

  return (
    <div className="mb-12 sm:mb-16">
      <a
        href={citizenHref}
        className="block p-5 sm:p-6 bg-gradient-to-br from-card to-bg border border-accent/20 rounded-[16px] hover:border-accent/40 transition-colors group"
      >
        <div className="flex items-center gap-4 sm:gap-6">
          {/* 小号道环可视化 */}
          <div
            className="relative w-16 h-16 sm:w-20 sm:h-20 rounded-full flex items-center justify-center flex-shrink-0 shadow-md"
            style={{
              background: `conic-gradient(from 0deg, hsl(${hue}, 70%, 60%), hsl(${(hue + 120) % 360}, 70%, 55%), hsl(${(hue + 240) % 360}, 70%, 60%), hsl(${hue}, 70%, 60%))`,
            }}
          >
            <div className="absolute inset-1.5 sm:inset-2 rounded-full bg-card flex items-center justify-center">
              <ShieldCheck size={20} className="text-accent" />
            </div>
          </div>

          {/* 公民信息预览 */}
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 mb-1">
              <span className="text-xs text-muted uppercase tracking-wide">
                {t("citizenIdLabel")}
              </span>
              <span className="text-[10px] text-accent bg-accent/10 px-1.5 py-0.5 rounded">
                {t("ringSimulated")}
              </span>
            </div>
            <h2 className="text-lg sm:text-xl font-bold text-ink">
              {citizen.ringTierLabel}
            </h2>
            <p className="text-xs sm:text-sm text-muted mt-1">
              {t("totalDonated", { amount: formatUsdc(citizen.totalDonatedUsdc) })}
              <span className="mx-1.5">·</span>
              {t("donationCount", { count: citizen.donationCount })}
            </p>
          </div>

          {/* CTA */}
          <div className="flex items-center gap-1.5 text-accent text-sm font-medium flex-shrink-0 group-hover:gap-2 transition-all">
            <span className="hidden sm:inline">{t("viewFullIdentity")}</span>
            <ArrowRight size={16} />
          </div>
        </div>
      </a>
    </div>
  );
}
