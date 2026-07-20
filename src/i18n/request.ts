import { getRequestConfig } from "next-intl/server";
import { routing, type Locale } from "./routing";

import en from "@/messages/en.json";
import zhHant from "@/messages/zh-Hant.json";
import ko from "@/messages/ko.json";
import ja from "@/messages/ja.json";
import de from "@/messages/de.json";
import es from "@/messages/es.json";
import fr from "@/messages/fr.json";

const messages = {
  en,
  "zh-Hant": zhHant,
  ko,
  ja,
  de,
  es,
  fr,
} as const;

export default getRequestConfig(async ({ requestLocale }) => {
  let locale = await requestLocale;

  if (!locale || !routing.locales.includes(locale as Locale)) {
    locale = routing.defaultLocale;
  }

  return {
    locale,
    messages: messages[locale as Locale],
  };
});
