"use client";
// SPDX-License-Identifier: Apache-2.0

import { useTranslations } from "next-intl";
import { TriangleAlert } from "lucide-react";

/**
 * 演示数据横幅 —— 合约未部署期间，明示提案/资金流数据为界面演示
 *
 * variant:
 *  - governance：治理合约（提案与票数）尚未部署
 *  - treasury：金库（资金流与余额）尚未部署
 */
export function DemoBanner({
  variant,
  compact = false,
}: {
  variant: "governance" | "treasury";
  compact?: boolean;
}) {
  const t = useTranslations("common.demoData");

  return (
    <div
      role="note"
      aria-label={t("title")}
      className={`flex items-start gap-3 rounded-xl border border-amber-500/30 bg-amber-500/10 ${
        compact ? "px-4 py-3" : "px-4 py-3.5"
      }`}
    >
      <TriangleAlert
        size={compact ? 15 : 17}
        className="mt-0.5 shrink-0 text-amber-500"
        aria-hidden
      />
      <div className="min-w-0">
        <p className="text-sm font-semibold text-amber-500">{t("title")}</p>
        <p className="mt-0.5 text-xs leading-relaxed text-muted">
          {t(variant === "governance" ? "governanceBody" : "treasuryBody")}
        </p>
      </div>
    </div>
  );
}
