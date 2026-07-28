// SPDX-License-Identifier: Apache-2.0
import { setRequestLocale } from "next-intl/server";
import { CitizenView } from "@/components/citizen/CitizenView";

interface PageProps {
  params: Promise<{ locale: string; address: string }>;
}

const ADDRESS_RE = /^0x[a-fA-F0-9]{40}$/;

export default async function CitizenPage({ params }: PageProps) {
  const { locale, address } = await params;
  setRequestLocale(locale);

  // 地址格式不合法时直接显示空视图（CitizenView 会走 error 分支）
  const normalized = ADDRESS_RE.test(address)
    ? address.toLowerCase()
    : address;

  return <CitizenView address={normalized} />;
}
