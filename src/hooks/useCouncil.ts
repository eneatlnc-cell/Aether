"use client";
// SPDX-License-Identifier: Apache-2.0

import { councilMembers } from "@/lib/data";
import { useTranslations } from "next-intl";

export function useCouncil() {
  const t = useTranslations();
  return councilMembers.map((m) => ({
    ...m,
    focus: t(m.focusKey as never),
  }));
}
