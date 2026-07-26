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

export const localeLabels: Record<Locale, { flag: string; countryCode: string; label: string }> = {
  en: { flag: "🇬🇧", countryCode: "gb", label: "English" },
  "zh-Hant": { flag: "🇭🇰", countryCode: "hk", label: "繁體中文" },
  ko: { flag: "🇰🇷", countryCode: "kr", label: "한국어" },
  ja: { flag: "🇯🇵", countryCode: "jp", label: "日本語" },
  de: { flag: "🇩🇪", countryCode: "de", label: "Deutsch" },
  es: { flag: "🇪🇸", countryCode: "es", label: "Español" },
  fr: { flag: "🇫🇷", countryCode: "fr", label: "Français" },
};
