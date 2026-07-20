"use client";

import { useTranslations } from "next-intl";
import { KpiCards } from "./KpiCards";
import { MonthlyTrendChart } from "./MonthlyTrendChart";
import { RecentTransactions } from "./RecentTransactions";
import { useFundFlow } from "@/hooks/useFundFlow";
import { useTreasuryTransactions } from "@/hooks/useTreasuryTransactions";

export function FundFlowDashboard() {
  const t = useTranslations("fundFlow");
  const { totalDonated, projectFunds, treasuryBalanceUsd, monthlyFlow, loading } =
    useFundFlow();
  const { data: txs, loading: txsLoading } = useTreasuryTransactions(5);

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

        <KpiCards
          totalDonated={totalDonated}
          projectFunds={projectFunds}
          treasuryBalanceUsd={treasuryBalanceUsd}
          loading={loading}
        />

        <div className="mt-6 grid grid-cols-1 lg:grid-cols-5 gap-6">
          <div className="lg:col-span-3">
            <MonthlyTrendChart data={monthlyFlow} loading={loading} />
          </div>
          <div className="lg:col-span-2">
            <RecentTransactions data={txs} loading={txsLoading} />
          </div>
        </div>
      </div>
    </section>
  );
}
