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
    const connector = connectors[0];
    if (!connector) return;
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
