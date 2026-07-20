"use client";

import { useTranslations } from "next-intl";
import { Link } from "@/i18n/navigation";
import { Card } from "@/components/ui/Card";
import { projects, type ProjectMeta } from "@/lib/data";
import { ArrowRight, Hexagon, Waves, Share2 } from "lucide-react";

const iconMap = {
  hex: Hexagon,
  wave: Waves,
  mesh: Share2,
} as const;

const statusKeyMap: Record<ProjectMeta["status"], string> = {
  research: "In Research",
  testnet: "Testnet Live",
};

export function FlagshipProjects() {
  const t = useTranslations("projects");
  const tProject = useTranslations("projects");

  return (
    <section className="py-16 sm:py-20 px-6 lg:px-8">
      <div className="max-w-[1280px] mx-auto">
        <header className="mb-10 sm:mb-12">
          <h2 className="text-3xl sm:text-4xl font-bold text-ink">
            {t("sectionTitle")}
          </h2>
          <p className="mt-3 text-muted max-w-2xl leading-relaxed">
            {t("sectionSubtitle")}
          </p>
        </header>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 lg:gap-8">
          {projects.map((p) => {
            const Icon = iconMap[p.icon];
            return (
              <Card key={p.id} hover className="flex flex-col h-full">
                <div className="mb-6">
                  <Icon size={32} className="text-ink/40" strokeWidth={1.5} />
                </div>
                <h3 className="text-xl font-bold text-ink leading-snug">
                  {tProject(`${p.id}.name` as never)}
                </h3>
                <p className="mt-3 text-sm text-muted leading-relaxed flex-1">
                  {tProject(`${p.id}.tagline` as never)}
                </p>
                <div className="mt-8 pt-5 border-t border-border flex items-center justify-between">
                  <span className="inline-flex items-center gap-2 text-xs text-muted">
                    <span className="w-2 h-2 rounded-full bg-ink/50" />
                    {statusKeyMap[p.status]}
                  </span>
                  <Link
                    href={`/whitepaper/${p.id}`}
                    className="inline-flex items-center gap-1 text-sm text-ink hover:text-accent transition-colors"
                  >
                    {tProject(`${p.id}.viewWhitepaper` as never)}
                    <ArrowRight size={14} />
                  </Link>
                </div>
              </Card>
            );
          })}
        </div>
      </div>
    </section>
  );
}
