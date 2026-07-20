"use client";

import { useState } from "react";
import { useTranslations, useLocale } from "next-intl";
import { useWallet } from "@/hooks/useWallet";
import { LanguageSwitcher } from "@/components/LanguageSwitcher";
import { DonationModal } from "@/components/home/donation/DonationModal";
import { useDonationReceipt } from "@/lib/generateDonationReceipt";
import type { DonationResult } from "@/hooks/useDonation";
import { Wallet, LogOut } from "lucide-react";

export function Navbar() {
  const t = useTranslations("nav");
  const locale = useLocale();
  const { isConnected, address, connect, disconnect, connecting } = useWallet();
  const [donationOpen, setDonationOpen] = useState(false);
  const generateReceipt = useDonationReceipt();

  const handleDownloadReceipt = (result: DonationResult) => {
    generateReceipt(result);
  };

  return (
    <>
      <header className="sticky top-0 z-40 bg-bg/80 backdrop-blur border-b border-border">
        <div className="max-w-[1280px] mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between gap-2">
          <a
            href={`/${locale}`}
            className="font-bold text-[18px] sm:text-[20px] text-ink tracking-tight flex-shrink-0"
          >
            {t("logo")}
          </a>

          <nav
            className="flex items-center gap-2 sm:gap-4 lg:gap-5 flex-shrink-0"
            aria-label="Main navigation"
          >
            <a
              href={`/${locale}/impact`}
              className="text-sm text-ink hover:text-accent transition-colors hidden md:inline"
            >
              {t("governance")}
            </a>
            <button
              onClick={() => setDonationOpen(true)}
              aria-label={t("donate")}
              className="px-3 sm:px-4 py-2 bg-accent text-white rounded-[8px] text-sm hover:bg-accent/90 transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-2 focus-visible:ring-offset-bg"
            >
              {t("donate")}
            </button>
            {isConnected ? (
              <button
                onClick={disconnect}
                aria-label={t("disconnect")}
                className="inline-flex items-center gap-1.5 sm:gap-2 px-3 sm:px-4 py-2 border border-accent text-accent rounded-[8px] text-sm hover:bg-accent/5 transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-2 focus-visible:ring-offset-bg"
              >
                <span className="font-mono text-xs hidden sm:inline">
                  {address?.slice(0, 6)}…{address?.slice(-4)}
                </span>
                <span className="font-mono text-xs sm:hidden">●</span>
                <LogOut size={14} />
              </button>
            ) : (
              <button
                onClick={connect}
                disabled={connecting}
                aria-label={t("connectWallet")}
                className="inline-flex items-center gap-1.5 sm:gap-2 px-3 sm:px-4 py-2 border border-accent text-accent rounded-[8px] text-sm hover:bg-accent/5 transition-colors disabled:opacity-60 focus:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-2 focus-visible:ring-offset-bg"
              >
                <Wallet size={14} />
                <span className="hidden sm:inline">{t("connectWallet")}</span>
              </button>
            )}
            <LanguageSwitcher />
          </nav>
        </div>
      </header>

      <DonationModal
        open={donationOpen}
        onClose={() => setDonationOpen(false)}
        onDownloadReceipt={handleDownloadReceipt}
      />
    </>
  );
}
