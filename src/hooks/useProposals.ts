"use client";
// SPDX-License-Identifier: Apache-2.0

import { useTranslations } from "next-intl";
import { proposals as mockProposals } from "@/lib/data";

export function useProposals() {
  const t = useTranslations();
  // 当前为 Mock，待治理合约接入后替换为 wagmi useReadContract
  return mockProposals.map((p) => ({
    ...p,
    title: t(p.titleKey as never),
    summary: t(p.summaryKey as never),
  }));
}
