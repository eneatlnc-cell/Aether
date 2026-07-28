// SPDX-License-Identifier: Apache-2.0
import { useTranslations } from "next-intl";

export function Hero() {
  const t = useTranslations("hero");
  const tags = [t("tag1"), t("tag2"), t("tag3")];

  return (
    <section className="py-20 sm:py-32 px-6 lg:px-8">
      <div className="max-w-[1280px] mx-auto text-center">
        <h1 className="text-[64px] sm:text-[80px] lg:text-[96px] font-extrabold tracking-tighter text-ink leading-none">
          {t("title")}
        </h1>
        <p className="mt-6 text-lg sm:text-xl text-muted max-w-2xl mx-auto leading-relaxed">
          {t("subtitle")}
        </p>
        <div className="mt-10 flex flex-wrap items-center justify-center gap-3 max-w-4xl mx-auto">
          {tags.map((tag) => (
            <span
              key={tag}
              className="inline-block px-4 py-2 border border-border bg-card rounded-full text-sm text-ink"
            >
              {tag}
            </span>
          ))}
        </div>
      </div>
    </section>
  );
}
