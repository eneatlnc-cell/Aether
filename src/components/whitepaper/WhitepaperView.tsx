"use client";

import { useTranslations } from "next-intl";
import { Navbar } from "@/components/home/Navbar";
import { Footer } from "@/components/home/Footer";
import { Card } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { useToast } from "@/components/ui/Toast";
import { ArrowLeft, FileText, Download } from "lucide-react";
import { useRouter } from "next/navigation";
import type { ProjectId } from "@/lib/data";

interface WhitepaperViewProps {
  projectId: ProjectId;
}

export function WhitepaperView({ projectId }: WhitepaperViewProps) {
  const t = useTranslations("whitepaper");
  const tProject = useTranslations("projects");
  const router = useRouter();
  const { push } = useToast();

  const sections = [
    { id: "overview", title: t("sections.overview"), key: `${projectId}.overview` },
    { id: "architecture", title: t("sections.architecture"), key: `${projectId}.architecture` },
    { id: "roadmap", title: t("sections.roadmap"), key: `${projectId}.roadmap` },
    { id: "team", title: t("sections.team"), key: `${projectId}.team` },
  ];

  return (
    <>
      <Navbar />
      <main className="flex-1 py-12 sm:py-16 px-6 lg:px-8">
        <div className="max-w-[960px] mx-auto">
          <button
            onClick={() => router.back()}
            className="inline-flex items-center gap-2 text-sm text-muted hover:text-accent transition-colors mb-6"
          >
            <ArrowLeft size={14} />
            {t("back")}
          </button>

          {/* 标题 */}
          <header className="mb-10">
            <div className="flex items-center gap-3 mb-4">
              <FileText size={20} className="text-accent" />
              <span className="text-xs text-muted uppercase tracking-wide">
                {t("label")}
              </span>
            </div>
            <h1 className="text-3xl sm:text-4xl font-extrabold text-ink tracking-tight">
              {tProject(`${projectId}.name` as never)}
            </h1>
            <p className="mt-3 text-lg text-muted max-w-2xl leading-relaxed">
              {tProject(`${projectId}.tagline` as never)}
            </p>
          </header>

          {/* 章节目录 + 下载 */}
          <Card className="mb-8">
            <div className="flex items-center justify-between flex-wrap gap-4">
              <div>
                <p className="text-xs text-muted uppercase tracking-wide mb-1">
                  {t("tableOfContents")}
                </p>
                <ul className="text-sm text-ink space-y-1">
                  {sections.map((s) => (
                    <li key={s.id}>
                      <a
                        href={`#${s.id}`}
                        className="hover:text-accent transition-colors"
                      >
                        · {s.title}
                      </a>
                    </li>
                  ))}
                </ul>
              </div>
              <Button
                variant="outline"
                onClick={() => push(t("placeholderNote"), "info")}
              >
                <Download size={14} />
                {t("downloadPdf")}
              </Button>
            </div>
          </Card>

          {/* 章节内容 */}
          <div className="space-y-12">
            {sections.map((s) => {
              // 支持 \n\n 分段；以 "- " 开头的段落渲染为要点列表
              const raw = t(`${s.key}` as never) as string;
              const paragraphs = raw.split("\n\n");
              return (
                <section key={s.id} id={s.id}>
                  <h2 className="text-2xl font-bold text-ink mb-4">{s.title}</h2>
                  <Card>
                    <div className="space-y-3">
                      {paragraphs.map((p, idx) =>
                        p.startsWith("- ") ? (
                          <ul
                            key={idx}
                            className="list-disc pl-5 text-base text-ink leading-relaxed space-y-1.5 marker:text-accent"
                          >
                            {p.split("\n").map((item, j) => (
                              <li key={j}>{item.replace(/^- /, "")}</li>
                            ))}
                          </ul>
                        ) : (
                          <p
                            key={idx}
                            className="text-base text-ink leading-relaxed whitespace-pre-line"
                          >
                            {p}
                          </p>
                        )
                      )}
                    </div>
                  </Card>
                </section>
              );
            })}
          </div>

          {/* 数据来源声明 */}
          <p className="mt-12 text-xs text-muted text-center italic">
            {t("placeholderNote")}
          </p>
        </div>
      </main>
      <Footer />
    </>
  );
}
