"use client";
// SPDX-License-Identifier: Apache-2.0

import { useTranslations, useFormatter } from "next-intl";
import { Card } from "@/components/ui/Card";
import { Navbar } from "@/components/home/Navbar";
import { Footer } from "@/components/home/Footer";
import { CitizenBanner } from "@/components/citizen/CitizenBanner";
import { useToast } from "@/components/ui/Toast";
import {
  fundAllocations,
  annualBudget,
  councilCompensation,
  auditArrangement,
} from "@/lib/impactData";
import { Pie, PieChart, Cell, ResponsiveContainer } from "recharts";
import { Download } from "lucide-react";

const ALLOCATION_COLORS: Record<string, string> = {
  "ai-framework": "#1A1A1A",
  "self-organizing-net": "#64748B",
  unrestricted: "#C9A96E",
};

export function ImpactView() {
  const t = useTranslations("impact");
  const { push } = useToast();

  return (
    <>
      <Navbar />
      <main className="flex-1 py-16 sm:py-20 px-6 lg:px-8">
        <div className="max-w-[1280px] mx-auto">
          {/* Citizen ID 横幅卡片（已连接钱包才显示，未连接返回 null） */}
          <CitizenBanner />

          {/* 页面标题 */}
          <header className="mb-12 sm:mb-16">
            <h1 className="text-4xl sm:text-5xl font-extrabold text-ink tracking-tight">
              {t("title")}
            </h1>
            <p className="mt-4 text-lg text-muted max-w-2xl leading-relaxed">
              {t("subtitle")}
            </p>
          </header>

          {/* 1. 资金分配原则 + 环图 */}
          <section className="mb-20">
            <h2 className="text-2xl font-bold text-ink mb-3">
              {t("allocationPrinciple")}
            </h2>
            <p className="text-muted leading-relaxed mb-8 max-w-3xl">
              {t("allocationDescription")}
            </p>
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 items-center">
              <Card className="!p-8">
                <div className="h-[280px]">
                  <ResponsiveContainer width="100%" height="100%">
                    <PieChart>
                      <Pie
                        data={fundAllocations}
                        dataKey="percentage"
                        nameKey="projectId"
                        innerRadius={60}
                        outerRadius={110}
                        paddingAngle={2}
                        stroke="#FFFFFF"
                        strokeWidth={2}
                      >
                        {fundAllocations.map((a) => (
                          <Cell
                            key={a.projectId}
                            fill={ALLOCATION_COLORS[a.projectId]}
                          />
                        ))}
                      </Pie>
                    </PieChart>
                  </ResponsiveContainer>
                </div>
              </Card>
              <div className="space-y-4">
                {fundAllocations.map((a) => (
                  <div
                    key={a.projectId}
                    className="flex items-start gap-4 p-4 bg-card border border-border rounded-[12px]"
                  >
                    <span
                      className="w-3 h-3 rounded-sm mt-1.5 flex-shrink-0"
                      style={{ background: ALLOCATION_COLORS[a.projectId] }}
                    />
                    <div className="flex-1">
                      <div className="flex items-baseline justify-between">
                        <span className="text-sm font-semibold text-ink">
                          {t(`allocations.${a.projectId}.label` as never)}
                        </span>
                        <span className="text-sm font-bold text-accent tabular-nums">
                          {a.percentage}%
                        </span>
                      </div>
                      <p className="text-xs text-muted mt-1 leading-relaxed">
                        {t(`allocations.${a.projectId}.desc` as never)}
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </section>

          {/* 2. 年度预算 */}
          <section className="mb-20">
            <h2 className="text-2xl font-bold text-ink mb-3">
              {t("annualBudget")}
            </h2>
            <p className="text-muted leading-relaxed mb-8 max-w-3xl">
              {t("annualBudgetDescription")}
            </p>
            <BudgetTable />
          </section>

          {/* 3. 理事薪酬政策 */}
          <section className="mb-20">
            <h2 className="text-2xl font-bold text-ink mb-3">
              {t("councilCompensation")}
            </h2>
            <Card>
              <p className="text-sm text-ink leading-relaxed">
                {t("compensation.description")}
              </p>
              <div className="mt-5 pt-5 border-t border-border grid grid-cols-1 sm:grid-cols-2 gap-4 text-sm">
                <div>
                  <p className="text-xs text-muted uppercase tracking-wide mb-1">
                    {t("compensation.honorariumLabel")}
                  </p>
                  <p className="text-ink font-medium">
                    {councilCompensation.hasCompensation
                      ? t("compensation.hasCompensation")
                      : t("compensation.noCompensation")}
                  </p>
                </div>
                <div>
                  <p className="text-xs text-muted uppercase tracking-wide mb-1">
                    {t("compensation.reviewCycleLabel")}
                  </p>
                  <p className="text-ink font-medium">
                    {t("compensation.reviewCycle")}
                  </p>
                </div>
              </div>
            </Card>
          </section>

          {/* 4. 审计安排 */}
          <section className="mb-12">
            <h2 className="text-2xl font-bold text-ink mb-3">
              {t("auditArrangement")}
            </h2>
            <Card>
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-6 text-sm">
                <div>
                  <p className="text-xs text-muted uppercase tracking-wide mb-1">
                    {t("audit.cadenceLabel")}
                  </p>
                  <p className="text-ink font-medium">{t("audit.cadence")}</p>
                </div>
                <div>
                  <p className="text-xs text-muted uppercase tracking-wide mb-1">
                    {t("audit.providerLabel")}
                  </p>
                  <p className="text-ink font-medium">{t("audit.provider")}</p>
                </div>
                <div>
                  <p className="text-xs text-muted uppercase tracking-wide mb-1">
                    {t("audit.lastReportLabel")}
                  </p>
                  <p className="text-ink font-medium">
                    {auditArrangement.lastReportDate
                      ? new Date(auditArrangement.lastReportDate).toLocaleDateString()
                      : t("audit.notPublished")}
                  </p>
                </div>
              </div>
              {/* 报告未发布前不提供下载入口（没有报告就不渲染下载按钮） */}
              {auditArrangement.reportPublic && auditArrangement.lastReportDate && (
                <button
                  onClick={() => push(t("downloadReport"), "info")}
                  className="mt-6 inline-flex items-center gap-2 text-sm text-accent hover:text-accent/80 transition-colors"
                >
                  <Download size={14} />
                  {t("downloadReport")}
                </button>
              )}
            </Card>
          </section>
        </div>
      </main>
      <Footer />
    </>
  );
}

function BudgetTable() {
  const t = useTranslations("impact");
  const format = useFormatter();
  const total = annualBudget.totalUsd;

  return (
    <Card className="!p-0 overflow-hidden">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-border">
            <th className="text-left text-xs text-muted uppercase tracking-wide font-medium py-3 px-6">
              {t("budget.categoryColumn")}
            </th>
            <th className="text-right text-xs text-muted uppercase tracking-wide font-medium py-3 px-6">
              {t("budget.amountColumn")}
            </th>
            <th className="text-right text-xs text-muted uppercase tracking-wide font-medium py-3 px-6 hidden sm:table-cell">
              {t("budget.shareColumn")}
            </th>
            <th className="text-left text-xs text-muted uppercase tracking-wide font-medium py-3 px-6 hidden md:table-cell">
              {t("budget.noteColumn")}
            </th>
          </tr>
        </thead>
        <tbody>
          {annualBudget.lineItems.map((item) => {
            const share = (item.amountUsd / total) * 100;
            return (
              <tr
                key={item.category}
                className="border-b border-border last:border-b-0"
              >
                <td className="py-4 px-6 text-ink font-medium">{item.category}</td>
                <td className="py-4 px-6 text-right text-ink tabular-nums">
                  {format.number(item.amountUsd, {
                    style: "currency",
                    currency: "USD",
                    maximumFractionDigits: 0,
                  })}
                </td>
                <td className="py-4 px-6 text-right text-muted tabular-nums hidden sm:table-cell">
                  {share.toFixed(0)}%
                </td>
                <td className="py-4 px-6 text-muted hidden md:table-cell">
                  {t(item.noteKey as never)}
                </td>
              </tr>
            );
          })}
        </tbody>
        <tfoot>
          <tr className="bg-bg">
            <td className="py-4 px-6 text-ink font-bold">
              {t("budget.totalLabel")}
            </td>
            <td className="py-4 px-6 text-right text-accent font-bold tabular-nums">
              {format.number(total, {
                style: "currency",
                currency: "USD",
                maximumFractionDigits: 0,
              })}
            </td>
            <td className="py-4 px-6 text-right text-muted tabular-nums hidden sm:table-cell">
              100%
            </td>
            <td className="py-4 px-6 text-muted hidden md:table-cell">
              {annualBudget.fiscalYear}
            </td>
          </tr>
        </tfoot>
      </table>
    </Card>
  );
}
