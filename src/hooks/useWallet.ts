"use client";

import { useAccount, useConnect, useDisconnect, useChains } from "wagmi";
import { useToast } from "@/components/ui/Toast";
import { useTranslations } from "next-intl";

export function useWallet() {
  const t = useTranslations("nav");
  const tToast = useTranslations("toast");
  const { push } = useToast();
  const account = useAccount();
  const { connectAsync, connectors, isPending: connecting } = useConnect();
  const { disconnectAsync } = useDisconnect();
  const chains = useChains();

  const connect = async () => {
    if (connectors.length === 0) return;
    // 智能选择 connector：
    // - 浏览器装了 EIP-1193 钱包扩展（MetaMask 等）→ 用 injected 直连
    // - 否则（移动端浏览器 / PC 无扩展）→ 用 walletConnect 弹 QR
    const hasInjected =
      typeof window !== "undefined" &&
      typeof (window as unknown as { ethereum?: unknown }).ethereum !== "undefined";
    const connector =
      (hasInjected
        ? connectors.find((c) => c.id === "injected")
        : connectors.find((c) => c.id === "walletConnect")) ?? connectors[0];
    try {
      await connectAsync({ connector, chainId: chains[0]?.id });
      push(tToast("walletConnected"), "success");
    } catch (err) {
      // 用户拒绝等场景静默处理
      if ((err as Error)?.name !== "UserRejectedRequestError") {
        push(tToast("error"), "info");
      }
    }
  };

  const disconnect = async () => {
    try {
      await disconnectAsync();
      push(tToast("walletDisconnected"), "success");
    } catch {
      /* noop */
    }
  };

  return {
    address: account.address,
    isConnected: account.isConnected,
    chainId: account.chainId,
    connecting,
    connect,
    disconnect,
    /** 暴露给后续 useVote / useDonation */
    _t: t,
  };
}
