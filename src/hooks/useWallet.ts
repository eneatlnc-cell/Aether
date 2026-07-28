"use client";
// SPDX-License-Identifier: Apache-2.0

import {
  useAccount,
  useConnect,
  useDisconnect,
  useChains,
  useConnectors,
  useReconnect,
} from "wagmi";
import { useToast } from "@/components/ui/Toast";
import { useTranslations } from "next-intl";
import { useEffect, useState } from "react";

export function useWallet() {
  const t = useTranslations("nav");
  const tToast = useTranslations("toast");
  const { push } = useToast();
  const account = useAccount();
  const { connectAsync, isPending: connecting } = useConnect();
  const { disconnectAsync } = useDisconnect();
  const chains = useChains();
  // v3 推荐：useConnectors() 返回已就绪的 connectors 列表
  // 比 useConnect().connectors 更可靠，后者在 SSR/hydration 前可能返回空
  const connectors = useConnectors();
  const { reconnectAsync } = useReconnect();

  // mounted 守卫：SSR 期间不渲染任何依赖 connectors 的逻辑
  const [mounted, setMounted] = useState(false);
  useEffect(() => {
    setMounted(true);
  }, []);

  // 页面加载时尝试重连（处理刷新后丢失连接的场景）
  useEffect(() => {
    if (!mounted) return;
    reconnectAsync().catch(() => {
      /* 静默：重连失败不报错，用户可手动连接 */
    });
  }, [mounted, reconnectAsync]);

  // SSR-safe 检测 window.ethereum：必须在 hydration 之后才能读
  const [hasInjected, setHasInjected] = useState(false);
  useEffect(() => {
    setHasInjected(
      typeof window !== "undefined" &&
        typeof (window as unknown as { ethereum?: unknown }).ethereum !== "undefined"
    );
  }, []);

  const connect = async () => {
    // connectors 在 hydration 前可能为空，必须等 mounted
    if (!mounted || connectors.length === 0) {
      push(tToast("error"), "info");
      return;
    }
    // 智能选择 connector：
    // - 浏览器装了 EIP-1193 钱包扩展（MetaMask 等）→ 用 injected 直连
    // - 否则（移动端浏览器 / PC 无扩展）→ 用 walletConnect 弹 QR
    const connector =
      (hasInjected
        ? connectors.find((c) => c.id === "injected")
        : connectors.find((c) => c.id === "walletConnect")) ?? connectors[0];

    try {
      await connectAsync({
        connector,
        // 链 ID 可选：不强制传，让 connector 自己协商默认链
        ...(chains[0]?.id ? { chainId: chains[0].id } : {}),
      });
      push(tToast("walletConnected"), "success");
    } catch (err) {
      // 用户拒绝、链切换被拒等场景静默处理
      const name = (err as Error)?.name ?? "";
      const msg = (err as Error)?.message ?? "";
      if (
        name === "UserRejectedRequestError" ||
        /user rejected/i.test(msg) ||
        /rejected the request/i.test(msg)
      ) {
        return;
      }
      // 其余错误：把原始信息打到 console 便于诊断，同时给用户一个温和 toast
      console.error("[useWallet] connect failed:", err);
      push(tToast("error"), "info");
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
    /** SSR 期间为 false，客户端 mount 后为 true；组件可据此避免 hydration mismatch */
    mounted,
    /** 暴露给后续 useVote / useDonation */
    _t: t,
  };
}
