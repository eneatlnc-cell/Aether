"use client";
// SPDX-License-Identifier: Apache-2.0

import { jsPDF } from "jspdf";
import { useTranslations, useLocale, useFormatter } from "next-intl";
import { formatUnits } from "viem";
import type { DonationResult } from "@/hooks/useDonation";
import { getNetworkLabel } from "@/lib/contracts";

/** CJK 字体族名（jsPDF addFont 注册名） */
const CJK_FONT_FAMILY = "NotoSansCJK";
/** CJK 子集字体路径（构建脚本产出，覆盖 zh-Hant/ko/ja 凭证全部文案字符） */
const CJK_FONT_URL = "/fonts/NotoSansCJK-Receipt.ttf";

const LOCALE_TO_PDF_FONT: Record<string, string> = {
  en: "helvetica",
  // v3.6：zh-Hant/ko/ja 嵌入 Noto Sans CJK 子集字体（315KB，按需懒加载），
  // 不再用 helvetica 罗马字兜底（此前 CJK 文案在 PDF 中显示为乱码）
  "zh-Hant": CJK_FONT_FAMILY,
  ko: CJK_FONT_FAMILY,
  ja: CJK_FONT_FAMILY,
  de: "helvetica",
  es: "helvetica",
  fr: "helvetica",
};

/** CJK 字体 base64 模块级缓存（每个会话只 fetch 一次） */
let cjkFontBase64: string | null = null;

/**
 * 懒加载 CJK 子集字体并注册到 jsPDF。
 * Noto Sans CJK 无真正的 bold 字重，将同一文件同时注册为
 * normal/bold 两个 style，保证 doc.setFont(family, "bold") 不抛错。
 */
async function ensureCjkFont(doc: jsPDF): Promise<void> {
  if (cjkFontBase64 === null) {
    const res = await fetch(CJK_FONT_URL);
    if (!res.ok) {
      throw new Error(`Failed to load CJK font (${res.status})`);
    }
    const buf = new Uint8Array(await res.arrayBuffer());
    // 分块转 base64，避免大数组触发 String.fromCharCode 栈溢出
    let binary = "";
    const CHUNK = 0x8000;
    for (let i = 0; i < buf.length; i += CHUNK) {
      binary += String.fromCharCode(...buf.subarray(i, i + CHUNK));
    }
    cjkFontBase64 = btoa(binary);
  }
  const fileName = "NotoSansCJK-Receipt.ttf";
  doc.addFileToVFS(fileName, cjkFontBase64);
  doc.addFont(fileName, CJK_FONT_FAMILY, "normal");
  doc.addFont(fileName, CJK_FONT_FAMILY, "bold");
}

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

  return async (result: DonationResult) => {
    const doc = new jsPDF({
      unit: "pt",
      format: "a4",
      orientation: "portrait",
    });

    let font = LOCALE_TO_PDF_FONT[locale] ?? "helvetica";
    if (font === CJK_FONT_FAMILY) {
      // CJK locale：懒加载子集字体并注册（失败则回退 helvetica，至少保住 ASCII 内容）
      try {
        await ensureCjkFont(doc);
      } catch {
        console.warn("[receipt] CJK font load failed, falling back to helvetica");
        font = "helvetica";
      }
    }
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
    // v3.5：网络标签按交易所在链动态显示（BSC 56 / 97）
    // v3.6：兜底链改为 56（BSC 主网）——唯一目标链
    const networkLabel = getNetworkLabel(result.chainId ?? 56);
    doc.text(`${networkLabel} · ${locale.toUpperCase()}`, pageWidth - marginX, y, {
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
    // 精度按交易所在链的稳定币 decimals（BSC 为 18），符号按链配置
    const decimals = result.assetDecimals ?? 6;
    const symbol = result.assetSymbol ?? "USDC";
    // viem formatUnits：字符串精确换算，避免 18 decimals 大数先过 Number 丢精度
    const usdcAmount = Number(formatUnits(result.amount, decimals));
    const amountStr = `${usdcAmount.toLocaleString("en-US", {
      maximumFractionDigits: 2,
    })} ${symbol}`;

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
      [t("network"), networkLabel],
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
