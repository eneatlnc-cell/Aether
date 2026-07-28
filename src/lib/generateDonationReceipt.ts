"use client";
// SPDX-License-Identifier: Apache-2.0

import { jsPDF } from "jspdf";
import { useTranslations, useLocale, useFormatter } from "next-intl";
import type { DonationResult } from "@/hooks/useDonation";

const LOCALE_TO_PDF_FONT: Record<string, string> = {
  en: "helvetica",
  "zh-Hant": "helvetica", // PDF 标准字体不支持中文，统一用 helvetica + 罗马字兜底
  ko: "helvetica",
  ja: "helvetica",
  de: "helvetica",
  es: "helvetica",
  fr: "helvetica",
};

/**
 * 生成捐赠凭证 PDF 并触发浏览器下载
 *
 * 凭证内容跟随当前 locale（标题、字段标签、用途翻译）
 * 设计：极简白底 + 深蓝灰强调色 + 暗金分隔线，呼应基金会调性
 *
 * 使用方式：在客户端组件内调用 const generate = useDonationReceipt();
 *           然后 generate(donationResult) 即可触发下载
 */
export function useDonationReceipt() {
  const t = useTranslations("donation.receipt");
  const tPurpose = useTranslations("donation.purposes");
  const locale = useLocale();
  const format = useFormatter();

  return (result: DonationResult) => {
    const doc = new jsPDF({
      unit: "pt",
      format: "a4",
      orientation: "portrait",
    });

    const font = LOCALE_TO_PDF_FONT[locale] ?? "helvetica";
    doc.setFont(font);

    const pageWidth = doc.internal.pageSize.getWidth();
    const marginX = 56;
    const contentWidth = pageWidth - marginX * 2;

    let y = 64;

    /* ---------- 顶部标识 ---------- */
    doc.setFontSize(10);
    doc.setTextColor(100, 116, 139); // #64748B
    doc.setFont(font, "normal");
    doc.text("AETHER FOUNDATION", marginX, y);
    doc.text(`Arbitrum · ${locale.toUpperCase()}`, pageWidth - marginX, y, {
      align: "right",
    });

    y += 36;

    /* ---------- 标题 ---------- */
    doc.setFontSize(22);
    doc.setTextColor(26, 26, 26); // #1A1A1A
    doc.setFont(font, "bold");
    doc.text(t("title"), marginX, y);

    y += 16;
    doc.setFontSize(10);
    doc.setTextColor(100, 116, 139);
    doc.setFont(font, "normal");
    doc.text(t("issuer"), marginX, y);

    y += 28;

    /* ---------- 暗金分隔线 ---------- */
    doc.setDrawColor(201, 169, 110); // #C9A96E
    doc.setLineWidth(1);
    doc.line(marginX, y, pageWidth - marginX, y);

    y += 32;

    /* ---------- 字段表 ---------- */
    const purposeLabel = tPurpose(result.purpose as never);
    // 预启动阶段只支持 USDC（6 decimals），amount 是原始 bigint
    const usdcAmount = Number(result.amount) / 10 ** 6;
    const amountStr = `${usdcAmount.toLocaleString("en-US", {
      maximumFractionDigits: 2,
    })} USDC`;

    const date = new Date(result.timestamp);
    const dateStr = format.dateTime(date, {
      year: "numeric",
      month: "long",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
      timeZone: "UTC",
      timeZoneName: "short",
    });

    const rows: Array<[string, string]> = [
      [t("txHash"), result.txHash],
      [t("amount"), amountStr],
      [t("timestamp"), dateStr],
      [t("purpose"), purposeLabel],
      [t("donor"), result.donor],
      [t("treasury"), result.treasury],
      [t("network"), "Arbitrum One"],
    ];

    const labelWidth = 110;
    const valueX = marginX + labelWidth + 8;

    doc.setFontSize(10);

    rows.forEach(([label, value]) => {
      // 标签
      doc.setFont(font, "normal");
      doc.setTextColor(100, 116, 139);
      doc.text(label.toUpperCase(), marginX, y);

      // 值（长哈希需要换行）
      doc.setFont(font, "bold");
      doc.setTextColor(26, 26, 26);
      const valueLines = doc.splitTextToSize(value, contentWidth - labelWidth - 8);
      doc.text(valueLines, valueX, y);

      y += Math.max(20, valueLines.length * 13 + 8);
    });

    y += 16;

    /* ---------- 声明 ---------- */
    doc.setDrawColor(232, 236, 240); // #E8ECF0
    doc.setLineWidth(0.5);
    doc.line(marginX, y, pageWidth - marginX, y);

    y += 24;
    doc.setFont(font, "normal");
    doc.setFontSize(9);
    doc.setTextColor(100, 116, 139);
    const declarationLines = doc.splitTextToSize(t("declaration"), contentWidth);
    doc.text(declarationLines, marginX, y);
    y += declarationLines.length * 12 + 24;

    /* ---------- 页脚 ---------- */
    doc.setDrawColor(201, 169, 110);
    doc.setLineWidth(0.5);
    doc.line(marginX, y, pageWidth - marginX, y);

    y += 16;
    doc.setFontSize(9);
    doc.setTextColor(100, 116, 139);
    doc.text(t("footer"), marginX, y);

    /* ---------- 保存 ---------- */
    const fileName = `aether-receipt-${result.txHash.slice(0, 10)}.pdf`;
    doc.save(fileName);
  };
}
