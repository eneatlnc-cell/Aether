"use client";

import { useTranslations } from "next-intl";
import { Link } from "@/i18n/navigation";

export function Footer() {
  const t = useTranslations("footer");
  const tNav = useTranslations("nav");

  return (
    <footer className="border-t border-border bg-card mt-16">
      <div className="max-w-[1280px] mx-auto px-6 lg:px-8 py-12">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
          {/* 品牌 */}
          <div>
            <p className="font-bold text-[18px] text-ink mb-3">
              {tNav("logo")}
            </p>
            <p className="text-sm text-muted leading-relaxed max-w-xs">
              {t("tagline")}
            </p>
          </div>

          {/* 链接 */}
          <div>
            <p className="text-xs text-muted uppercase tracking-wide mb-3">
              {t("transparency")}
            </p>
            <ul className="space-y-2 text-sm">
              <li>
                <Link
                  href="/impact"
                  className="text-ink hover:text-accent transition-colors"
                >
                  {t("transparency")}
                </Link>
              </li>
            </ul>
          </div>

          {/* 信息 */}
          <div>
            <p className="text-xs text-muted uppercase tracking-wide mb-3">
              {t("governance")}
            </p>
            <p className="text-sm text-muted leading-relaxed">
              {t("languageNote")}
            </p>
          </div>
        </div>

        <div className="mt-10 pt-6 border-t border-border flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3">
          <p className="text-xs text-muted">
            © {new Date().getFullYear()} Aether Foundation · Arbitrum
          </p>
          <p className="text-xs text-muted">Non-profit · Tokenless governance</p>
        </div>
      </div>
    </footer>
  );
}
