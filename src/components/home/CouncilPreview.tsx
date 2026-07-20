"use client";

import { useTranslations } from "next-intl";
import { Card } from "@/components/ui/Card";
import { useCouncil } from "@/hooks/useCouncil";
import type { CouncilTier } from "@/lib/data";

export function CouncilPreview() {
  const t = useTranslations("council");
  const members = useCouncil();

  return (
    <section className="md:col-span-1">
      <header className="mb-6">
        <h2 className="text-2xl font-bold text-ink">{t("sectionTitle")}</h2>
        <p className="mt-2 text-sm text-muted leading-relaxed">
          {t("sectionSubtitle")}
        </p>
      </header>
      <div className="flex flex-col gap-3">
        {members.map((m) => (
          <Card key={m.id} className="!p-4">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-full bg-bg border border-border flex items-center justify-center text-sm font-semibold text-ink/70 flex-shrink-0">
                {m.initials}
              </div>
              <div className="min-w-0">
                <p className="text-sm font-semibold text-ink leading-tight">
                  {m.name}
                </p>
                <p className="text-xs text-muted mt-0.5">
                  {tierLabel(t, m.tier)} · {m.focus}
                </p>
              </div>
            </div>
          </Card>
        ))}
      </div>
    </section>
  );
}

function tierLabel(
  t: ReturnType<typeof useTranslations>,
  tier: CouncilTier
): string {
  return t(tier);
}
