import type { Metadata } from "next";
import { NextIntlClientProvider, hasLocale } from "next-intl";
import { getMessages, setRequestLocale } from "next-intl/server";
import { notFound } from "next/navigation";
import { routing } from "@/i18n/routing";
import { WagmiProvider } from "@/components/providers/WagmiProvider";
import { ToastProvider } from "@/components/ui/Toast";
import "../globals.css";

export const metadata: Metadata = {
  title: "Aether Foundation",
  description:
    "A non-profit foundation advancing decentralized infrastructure and artificial intelligence research.",
};

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export default async function LocaleLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  if (!hasLocale(routing.locales, locale)) {
    notFound();
  }
  setRequestLocale(locale);

  const messages = await getMessages();

  return (
    <html lang={locale} className="h-full antialiased">
      <body className="min-h-full flex flex-col bg-bg text-ink">
        <NextIntlClientProvider locale={locale} messages={messages}>
          <WagmiProvider>
            <ToastProvider>{children}</ToastProvider>
          </WagmiProvider>
        </NextIntlClientProvider>
      </body>
    </html>
  );
}
