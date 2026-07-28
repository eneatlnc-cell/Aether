# Aether Foundation

> Tokenless on-chain governance for public-good infrastructure.

Aether is a tokenless on-chain governance kernel deployed on Arbitrum. It provides three-chamber councils (Council, Parliament, Elders), weighted voting, a 14-rank soulbound-token (SBT) identity system, and a Safe multisig treasury — without issuing any token. The governance kernel is co-developed with the [Havix](https://github.com/eneatlnc-cell/Havix) network layer, which provides the off-chain P2P coordination plane.

## Getting Started

First, run the development server:

```bash
npm run dev
# or
yarn dev
# or
pnpm dev
# or
bun dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

You can start editing the page by modifying `src/app/[locale]/page.tsx`. The page auto-updates as you edit the file.

This project uses [`next/font`](https://nextjs.org/docs/app/building-your-application/optimizing/fonts) to automatically optimize and load [Geist](https://vercel.com/font), a new font family for Vercel.

## Project Structure

- `src/` — Next.js App Router frontend (TypeScript, React, wagmi, viem)
- `contracts/` — Solidity governance kernel (AetherRing, AetherGovernance, AetherElection, AetherDonation)
- `src/messages/` — Internationalization files (en, zh-Hant, ko, ja, de, es, fr)
- `contracts/lib/openzeppelin-contracts/` — OpenZeppelin (git submodule, MIT-licensed third-party)

## Learn More

To learn more about the project:

- [Aether Technical Whitepaper](https://aether.foundation) — governance kernel design
- [Havix Network Layer](https://github.com/eneatlnc-cell/Havix) — off-chain P2P coordination

To learn more about Next.js:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.

## Deploy on Vercel

The easiest way to deploy your Next.js app is to use the [Vercel Platform](https://vercel.com/new?utm_medium=default-template&filter=next.js&utm_source=create-next-app&utm_campaign=create-next-app-readme) from the creators of Next.js.

Check out our [Next.js deployment documentation](https://nextjs.org/docs/app/building-your-application/deploying) for more details.

---

## License

Aether is licensed under the **Apache License, Version 2.0** (Apache-2.0).

- Full license text: see [LICENSE](./LICENSE)
- Third-party notices: see [NOTICE](./NOTICE)
- Copyright: © 2024-2026 Aether Foundation

Every source file (TypeScript and Solidity) carries an SPDX identifier:

```
// SPDX-License-Identifier: Apache-2.0
```

### What this means

- ✅ You may use, copy, modify, merge, publish, and distribute this software, including for commercial purposes.
- ✅ You must retain the LICENSE and NOTICE files in derivative distributions.
- ✅ You must clearly indicate any modifications you make to the original files.
- ✅ Patent grant: contributors grant you a perpetual, worldwide, non-exclusive, royalty-free patent license.

For the complete terms, see the [Apache License 2.0 summary](https://choosealicense.com/licenses/apache-2.0/) or the full [LICENSE](./LICENSE) file.

### Third-party components

The `contracts/lib/openzeppelin-contracts` submodule is **not** covered by the Apache-2.0 license of this repository — it is included as a third-party dependency under its own MIT License. See the [NOTICE](./NOTICE) file for the full list of third-party components and their licenses.

### Related project

The Aether governance kernel is co-developed with the [Havix](https://github.com/eneatlnc-cell/Havix) network layer. Aether provides the on-chain governance kernel on Arbitrum; Havix provides the off-chain P2P coordination plane. Both are released under Apache-2.0.
