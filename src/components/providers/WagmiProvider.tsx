"use client";
// SPDX-License-Identifier: Apache-2.0

import { createConfig, http, WagmiProvider as WagmiProviderBase } from "wagmi";
import { bsc, bscTestnet } from "wagmi/chains";
import { walletConnect, injected, coinbaseWallet } from "@wagmi/connectors";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ReactNode, useState } from "react";

// WalletConnect ProjectId：优先用环境变量，没有才回退到内置默认值
// 在 https://cloud.walletconnect.com 申请，写入 .env.local 的 NEXT_PUBLIC_WC_PROJECT_ID
const WALLETCONNECT_PROJECT_ID =
  process.env.NEXT_PUBLIC_WC_PROJECT_ID || "f7e4e9de252752ac3fd539c42747e7a1";

// v3.6（单链 BSC）：唯一目标链为 BNB Smart Chain（56），排首位作为默认链。
// Arbitrum 已移除（早期仅作测试链使用，从未部署主网）。
const config = createConfig({
  chains: [bsc, bscTestnet],
  transports: {
    [bsc.id]: http(),
    [bscTestnet.id]: http(),
  },
  // injected 在前：PC 端装了 MetaMask 等扩展时优先直连，避免无谓弹 QR
  // walletConnect 兜底：移动端 / 无扩展时弹出 QR 让用户手机扫
  connectors: [
    injected({ shimDisconnect: true }),
    walletConnect({
      projectId: WALLETCONNECT_PROJECT_ID,
      showQrModal: true,
      metadata: {
        name: "Aether Foundation",
        description: "Tokenless on-chain governance for public-good infrastructure",
        // 用常量避免 SSR/客户端不一致导致 hydration warning
        url: "https://aether.foundation",
        icons: ["https://aether.foundation/logo.png"],
      },
    }),
    coinbaseWallet({ appName: "Aether DAO" }),
  ],
  ssr: true,
});

export function WagmiProvider({ children }: { children: ReactNode }) {
  const [client] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: { staleTime: 60_000, refetchOnWindowFocus: false },
        },
      })
  );

  return (
    <WagmiProviderBase config={config}>
      <QueryClientProvider client={client}>{children}</QueryClientProvider>
    </WagmiProviderBase>
  );
}
