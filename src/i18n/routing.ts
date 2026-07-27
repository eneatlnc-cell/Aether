import { defineRouting } from "next-intl/routing";

export const locales = [
  "en",
  "zh-Hant",
  "ko",
  "ja",
  "de",
  "es",
  "fr",
] as const;

export type Locale = (typeof locales)[number];

export const routing = defineRouting({
  locales,
  defaultLocale: "en",
  localePrefix: "always",
  localeDetection: true,
});

export const localeLabels: Record<Locale, { flag: string; label: string }> = {
  en: { flag: "🇬🇧", label: "English" },
  "zh-Hant": { flag: "🇭🇰", label: "繁體中文" },
  ko: { flag: "🇰🇷", label: "한국어" },
  ja: { flag: "🇯🇵", label: "日本語" },
  de: { flag: "🇩🇪", label: "Deutsch" },
  es: { flag: "🇪🇸", label: "Español" },
  fr: { flag: "🇫🇷", label: "Français" },
};
