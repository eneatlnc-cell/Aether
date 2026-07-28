"use client";
// SPDX-License-Identifier: Apache-2.0

import { useState, useRef, useEffect } from "react";
import { useLocale } from "next-intl";
import { usePathname, useRouter } from "@/i18n/navigation";
import { localeLabels, type Locale } from "@/i18n/routing";

export function LanguageSwitcher() {
  const locale = useLocale() as Locale;
  const router = useRouter();
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener("mousedown", onClick);
    return () => document.removeEventListener("mousedown", onClick);
  }, []);

  const switchTo = (next: Locale) => {
    if (next === locale) {
      setOpen(false);
      return;
    }
    // next-intl 的 router.replace 会自动处理 locale 前缀切换
    router.replace(pathname, { locale: next });
    setOpen(false);
  };

  const current = localeLabels[locale];

  return (
    <div ref={ref} className="relative">
      <button
        onClick={() => setOpen(!open)}
        className="w-7 h-7 flex items-center justify-center rounded-full hover:scale-110 transition-transform duration-300 focus:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-2 focus-visible:ring-offset-bg"
        aria-label={`Switch language, current: ${current.label}`}
        aria-expanded={open}
      >
        <span className="text-[18px] leading-none" aria-hidden="true">
          {current.flag}
        </span>
      </button>
      {open && (
        <div className="absolute right-0 mt-2 bg-card border border-border rounded-[8px] shadow-[0_4px_12px_rgba(0,0,0,0.04)] p-1 z-50 min-w-[44px]">
          {Object.entries(localeLabels).map(([l, info]) => (
            <button
              key={l}
              onClick={() => switchTo(l as Locale)}
              className={`flex items-center justify-center w-9 h-9 rounded-md hover:bg-bg transition-colors ${
                l === locale ? "bg-bg" : ""
              }`}
              title={info.label}
              aria-label={info.label}
            >
              <span className="text-[18px] leading-none" aria-hidden="true">
                {info.flag}
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
