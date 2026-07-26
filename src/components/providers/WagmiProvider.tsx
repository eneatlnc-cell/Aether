"use client";

import { createConfig, http, WagmiProvider as WagmiProviderBase } from "wagmi";
import { arbitrum, arbitrumSepolia, mainnet } from "wagmi/chains";
import { walletConnect, injected, coinbaseWallet } from "@wagmi/connectors";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ReactNode, useState } from "react";

const WALLETCONNECT_PROJECT_ID = "f7e4e9de252752ac3fd539c42747e7a1";

const config = createConfig({
  chains: [arbitrum, arbitrumSepolia, mainnet],
  transports: {
    [arbitrum.id]: http(),
    [arbitrumSepolia.id]: http(),
    [mainnet.id]: http(),
  },
  connectors: [
    injected({ shimDisconnect: true }),
    walletConnect({ projectId: WALLETCONNECT_PROJECT_ID, showQrModal: true }),
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
