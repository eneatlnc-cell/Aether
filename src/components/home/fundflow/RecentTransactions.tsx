"use client";
// SPDX-License-Identifier: Apache-2.0

import { useTranslations, useFormatter } from "next-intl";
import { Card } from "@/components/ui/Card";
import { Skeleton } from "@/components/ui/Skeleton";
import { ArrowDownLeft, ArrowUpRight, ExternalLink } from "lucide-react";
import { TREASURY_DEPLOYED } from "@/lib/deployment";
import type { TreasuryTransaction } from "@/lib/fundFlowData";

interface RecentTransactionsProps {
  data: TreasuryTransaction[];
  loading: boolean;
}

export function RecentTransactions({ data, loading }: RecentTransactionsProps) {
  const t = useTranslations("fundFlow");

  if (loading) {
    return (
      <Card>
        <Skeleton width="40%" height={14} />
        <div className="mt-6 space-y-4">
          {[0, 1, 2, 3, 4].map((i) => (
            <Skeleton key={i} width="100%" height={40} />
          ))}
        </div>
      </Card>
    );
  }

  return (
    <Card>
      <h3 className="text-base font-semibold text-ink">
        {t("recentTransactions")}
      </h3>
      <ul className="mt-5 divide-y divide-border">
        {data.map((tx) => (
          <TransactionRow key={tx.id} tx={tx} />
        ))}
      </ul>
    </Card>
  );
}

function TransactionRow({ tx }: { tx: TreasuryTransaction }) {
  const t = useTranslations("fundFlow");
  const format = useFormatter();
  const isIn = tx.direction === "in";

  const date = new Date(tx.timestamp);
  const dateLabel = format.dateTime(date, {
    year: "numeric",
    month: "short",
    day: "numeric",
  });

  const amountLabel = `${tx.amount.toLocaleString("en-US", {
    maximumFractionDigits: tx.asset === "BNB" ? 2 : 0,
  })} ${tx.asset}`;

  return (
    <li className="py-3 flex items-center gap-4">
      <span
        className={`w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0 ${
          isIn ? "bg-bg text-ink" : "bg-bg text-accent"
        }`}
      >
        {isIn ? <ArrowDownLeft size={14} /> : <ArrowUpRight size={14} />}
      </span>

      <div className="flex-1 min-w-0">
        <p className="text-sm text-ink leading-tight">
          {amountLabel}
          <span className="text-muted"> · {t(`purposeLabels.${tx.purpose}` as never)}</span>
        </p>
        <p className="text-xs text-muted mt-0.5">
          {dateLabel} · {tx.counterparty}
        </p>
      </div>

      <div className="text-right flex-shrink-0">
        <p
          className={`text-sm font-medium tabular-nums ${
            isIn ? "text-ink" : "text-accent"
          }`}
        >
          {isIn ? "+" : "−"}
          {format.number(tx.usdValue, {
            style: "currency",
            currency: "USD",
            maximumFractionDigits: 0,
          })}
        </p>
        {TREASURY_DEPLOYED ? (
          <a
            href={`https://bscscan.com/tx/${tx.txHash}`}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1 text-xs text-muted hover:text-accent transition-colors mt-0.5"
          >
            {t("viewOnExplorer")}
            <ExternalLink size={10} />
          </a>
        ) : (
          // 演示数据：txHash 为占位假值，不出示可点击的浏览器链接以免误导
          <span className="inline-flex items-center gap-1 text-xs text-muted/60 mt-0.5">
            {t("demoTxNote")}
          </span>
        )}
      </div>
    </li>
  );
}
