"use client";

import { createConfig, http, WagmiProvider as WagmiProviderBase } from "wagmi";
import { arbitrum } from "wagmi/chains";
import { mainnet } from "wagmi/chains";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ReactNode, useState } from "react";

const config = createConfig({
  chains: [arbitrum, mainnet],
  transports: {
    [arbitrum.id]: http(),
    [mainnet.id]: http(),
  },
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
