"use client";
// SPDX-License-Identifier: Apache-2.0

import { useTranslations, useFormatter } from "next-intl";
import { Card } from "@/components/ui/Card";
import { Skeleton } from "@/components/ui/Skeleton";
import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import type { MonthlyFlowPoint } from "@/lib/fundFlowData";

interface MonthlyTrendChartProps {
  data: MonthlyFlowPoint[];
  loading: boolean;
}

export function MonthlyTrendChart({ data, loading }: MonthlyTrendChartProps) {
  const t = useTranslations("fundFlow");

  if (loading) {
    return (
      <Card>
        <Skeleton width="40%" height={14} />
        <div className="mt-6">
          <Skeleton width="100%" height={240} />
        </div>
      </Card>
    );
  }

  return (
    <Card>
      <div className="flex items-baseline justify-between flex-wrap gap-2">
        <h3 className="text-base font-semibold text-ink">
          {t("monthlyTrend")}
        </h3>
        <div className="flex items-center gap-4 text-xs text-muted">
          <Legend color="bg-ink" label={t("income")} />
          <Legend color="bg-accent" label={t("expense")} />
        </div>
      </div>

      <div className="mt-6 w-full h-[240px]">
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart
            data={data}
            margin={{ top: 4, right: 4, left: -16, bottom: 0 }}
          >
            <defs>
              <linearGradient id="incomeFill" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="#1A1A1A" stopOpacity={0.18} />
                <stop offset="100%" stopColor="#1A1A1A" stopOpacity={0} />
              </linearGradient>
              <linearGradient id="expenseFill" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="#2B3A67" stopOpacity={0.18} />
                <stop offset="100%" stopColor="#2B3A67" stopOpacity={0} />
              </linearGradient>
            </defs>
            <CartesianGrid
              strokeDasharray="3 3"
              stroke="#E8ECF0"
              vertical={false}
            />
            <XAxis
              dataKey="month"
              tick={{ fill: "#64748B", fontSize: 11 }}
              axisLine={{ stroke: "#E8ECF0" }}
              tickLine={false}
            />
            <YAxis
              tick={{ fill: "#64748B", fontSize: 11 }}
              axisLine={false}
              tickLine={false}
              tickFormatter={(v) => `${(v / 1000).toFixed(0)}k`}
            />
            <Tooltip
              content={<TrendTooltip />}
              cursor={{ stroke: "#E8ECF0", strokeWidth: 1 }}
            />
            <Area
              type="monotone"
              dataKey="incomeUsd"
              stroke="#1A1A1A"
              strokeWidth={1.5}
              fill="url(#incomeFill)"
            />
            <Area
              type="monotone"
              dataKey="expenseUsd"
              stroke="#2B3A67"
              strokeWidth={1.5}
              fill="url(#expenseFill)"
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>
    </Card>
  );
}

function Legend({ color, label }: { color: string; label: string }) {
  return (
    <span className="inline-flex items-center gap-2">
      <span className={`inline-block w-2.5 h-2.5 rounded-sm ${color}`} />
      {label}
    </span>
  );
}

function TrendTooltip({ active, payload, label }: any) {
  const format = useFormatter();
  if (!active || !payload?.length) return null;
  return (
    <div className="bg-card border border-border rounded-[8px] shadow-[0_4px_12px_rgba(0,0,0,0.04)] px-3 py-2 text-xs">
      <p className="text-muted mb-2">{label}</p>
      {payload.map((p: any) => (
        <div key={p.dataKey} className="flex items-center gap-2">
          <span
            className="inline-block w-2 h-2 rounded-sm"
            style={{ background: p.color }}
          />
          <span className="text-muted">
            {p.dataKey === "incomeUsd" ? "Income" : "Expense"}:
          </span>
          <span className="text-ink font-medium tabular-nums">
            {format.number(p.value, {
              style: "currency",
              currency: "USD",
              maximumFractionDigits: 0,
            })}
          </span>
        </div>
      ))}
    </div>
  );
}
