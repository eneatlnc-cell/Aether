"use client";
// SPDX-License-Identifier: Apache-2.0

import { createConfig, http, WagmiProvider as WagmiProviderBase } from "wagmi";
import { bsc, bscTestnet } from "wagmi/chains";
import { walletConnect, injected, coinbaseWallet } from "@wagmi/connectors";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ReactNode, useState } from "react";

// WalletConnect ProjectId：仅从环境变量读取（v3.6：移除代码内置默认值的硬编码——
// 模板自带的公共 ID 属于他人配额且不可审计，仓库内不应出现）。
// 在 https://cloud.reown.com（原 cloud.walletconnect.com）申请，
// 写入环境变量 NEXT_PUBLIC_WC_PROJECT_ID（参考 .env.example）。
const WALLETCONNECT_PROJECT_ID = process.env.NEXT_PUBLIC_WC_PROJECT_ID;

// 生产环境缺配置直接 fail-fast（构建期/运行期都会暴露，与金库地址同款策略）；
// 开发环境仅告警并禁用 WalletConnect 连接器（桌面注入钱包不受影响）。
if (!WALLETCONNECT_PROJECT_ID && process.env.NODE_ENV === "production") {
  throw new Error(
    "NEXT_PUBLIC_WC_PROJECT_ID is not set; WalletConnect (mobile wallets) cannot start. " +
      "Get a Project ID at https://cloud.reown.com and set it in your environment."
  );
}
if (!WALLETCONNECT_PROJECT_ID) {
  console.warn(
    "[WagmiProvider] NEXT_PUBLIC_WC_PROJECT_ID 未设置：WalletConnect（移动端扫码）已禁用，" +
      "桌面注入钱包不受影响。申请地址：https://cloud.reown.com"
  );
}

// v3.6（单链 BSC）：唯一目标链为 BNB Smart Chain（56），排首位作为默认链。
// Arbitrum 已移除（早期仅作测试链使用，从未部署主网）。
const config = createConfig({
  chains: [bsc, bscTestnet],
  transports: {
    [bsc.id]: http(),
    [bscTestnet.id]: http(),
  },
  // injected 在前：PC 端装了 MetaMask 等扩展时优先直连，避免无谓弹 QR
  // walletConnect 兜底：移动端 / 无扩展时弹出 QR 让用户手机扫（需配置 ProjectId）
  connectors: [
    injected({ shimDisconnect: true }),
    ...(WALLETCONNECT_PROJECT_ID
      ? [
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
        ]
      : []),
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
