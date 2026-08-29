"use client";
// SPDX-License-Identifier: Apache-2.0

import { useTranslations } from "next-intl";
import { Link } from "@/i18n/navigation";
import { Landmark, Share2, Heart, Code } from "lucide-react";

const PROGRAM_ICONS = {
  "ai-framework": Landmark,
  "self-organizing-net": Share2,
} as const;

export function Footer() {
  const t = useTranslations("footer");
  const tNav = useTranslations("nav");
  const tProject = useTranslations("projects");

  const year = new Date().getFullYear();

  return (
    <footer className="relative border-t border-border bg-card mt-16 overflow-hidden">
      {/* 装饰：顶部细线渐变 */}
      <div className="h-px bg-gradient-to-r from-transparent via-accent/40 to-transparent" />

      {/* 装饰：右上角光晕 */}
      <div
        aria-hidden
        className="pointer-events-none absolute -top-32 -right-32 w-96 h-96 rounded-full bg-accent/5 blur-3xl"
      />
      <div
        aria-hidden
        className="pointer-events-none absolute -bottom-32 -left-32 w-96 h-96 rounded-full bg-accent/3 blur-3xl"
      />

      <div className="relative max-w-[1280px] mx-auto px-6 lg:px-8 py-14">
        {/* 上半部：4 列 */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-8 md:gap-10">
          {/* 品牌 */}
          <div className="col-span-2 md:col-span-1">
            <p className="font-bold text-[18px] text-ink mb-3 tracking-tight">
              {tNav("logo")}
            </p>
            <p className="text-sm text-muted leading-relaxed">
              {t("tagline")}
            </p>
            <div className="mt-4 inline-flex items-center gap-2 text-xs text-muted">
              <Heart size={12} className="text-accent/70" />
              <span>{t("tokenless")}</span>
            </div>
          </div>

          {/* Programs */}
          <div>
            <p className="text-xs text-muted uppercase tracking-wider mb-4 font-semibold">
              {t("programs")}
            </p>
            <ul className="space-y-2.5 text-sm">
              {(["ai-framework", "self-organizing-net"] as const).map(
                (id) => {
                  const Icon = PROGRAM_ICONS[id];
                  return (
                    <li key={id}>
                      <Link
                        href={`/whitepaper/${id}`}
                        className="group inline-flex items-center gap-2 text-ink/80 hover:text-accent transition-colors"
                      >
                        <Icon
                          size={12}
                          className="text-ink/30 group-hover:text-accent transition-colors"
                          strokeWidth={1.5}
                        />
                        <span className="truncate">
                          {tProject(`${id}.name` as never)}
                        </span>
                      </Link>
                    </li>
                  );
                }
              )}
            </ul>
          </div>

          {/* Governance */}
          <div>
            <p className="text-xs text-muted uppercase tracking-wider mb-4 font-semibold">
              {t("governance")}
            </p>
            <ul className="space-y-2.5 text-sm">
              <li>
                <Link
                  href="/impact"
                  className="text-ink/80 hover:text-accent transition-colors"
                >
                  {t("transparency")}
                </Link>
              </li>
              <li>
                <Link
                  href="/impact#proposals"
                  className="text-ink/80 hover:text-accent transition-colors"
                >
                  {t("proposals")}
                </Link>
              </li>
              <li>
                <Link
                  href="/impact#council"
                  className="text-ink/80 hover:text-accent transition-colors"
                >
                  {t("council")}
                </Link>
              </li>
            </ul>
          </div>

          {/* Foundation */}
          <div>
            <p className="text-xs text-muted uppercase tracking-wider mb-4 font-semibold">
              {t("foundation")}
            </p>
            <ul className="space-y-2.5 text-sm">
              <li>
                <a
                  href="https://github.com/eneatlnc-cell"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-2 text-ink/80 hover:text-accent transition-colors"
                >
                  <Code size={12} className="text-ink/30" strokeWidth={1.5} />
                  GitHub
                </a>
              </li>
              <li>
                <Link
                  href="/impact#audit"
                  className="text-ink/80 hover:text-accent transition-colors"
                >
                  {t("audit")}
                </Link>
              </li>
              <li>
                <a
                  href="https://bscscan.com"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-ink/80 hover:text-accent transition-colors"
                >
                  BscScan
                </a>
              </li>
            </ul>
          </div>
        </div>

        {/* 中间：使命引述装饰条 */}
        <div className="relative my-12">
          <div
            aria-hidden="true"
            className="absolute inset-0 flex items-center"
          >
            <div className="w-full h-px bg-gradient-to-r from-transparent via-border to-transparent" />
          </div>
          <div className="relative flex justify-center">
            <p className="bg-card px-6 text-center text-sm text-muted italic max-w-2xl leading-relaxed">
              &ldquo;{t("mission")}&rdquo;
            </p>
          </div>
        </div>

        {/* 底部：版权 + 关键事实徽章 */}
        <div className="flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
          <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted">
            <span>
              © {year} {t("org")}
            </span>
            <span aria-hidden className="text-border">·</span>
            <span>{t("chain")}</span>
            <span aria-hidden className="text-border">·</span>
            <span>{t("license")}</span>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-bg border border-border text-[11px] text-muted">
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-500/70" />
              {t("statusLive")}
            </span>
            <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-bg border border-border text-[11px] text-muted">
              <span className="w-1.5 h-1.5 rounded-full bg-amber-500/70" />
              {t("statusChain")}
            </span>
          </div>
        </div>
      </div>
    </footer>
  );
}
