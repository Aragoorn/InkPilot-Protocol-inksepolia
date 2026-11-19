# InkPilot

> Built with Arc Studio - money-powered apps in minutes

This is the **project memory** - what Arc Studio remembers about building this app. It helps future agents (or humans) understand and extend the project.

---

## What This App Does

InkPilot: chat-driven USDC lending with per-user protected accounts (Earn, optional 2x Boost, Safe Mode, Save or Compound profit handling). Targets Ink Sepolia (testnet, 763373) only, with a Tydro test market or a demo stand-in pool. Mainnet is deliberately not configured. Honest rule: never say "guaranteed"; say "protected".

## Tech Stack

- Frontend: React 18, Vite, TypeScript, Tailwind CSS
- Web3: wagmi v2, viem v2, ConnectKit
- Contracts: Solidity 0.8.28 + Foundry. Sources in `contracts/`, unit tests in `contracts/test/*.t.sol`. Build with `bun run contracts:build` (`forge build`), test with `bun run contracts:test` (`forge test`).
- Wallet: injected (MetaMask, etc.)
- Chain: Ink Sepolia (Chain ID: 763373, `inkSepolia` from `viem/chains`). Ink is not in Arc Studio's onchain-facts registry, so do not use `@/onchain-facts` for chain or token data.
- Token: 6-decimal asset from `VITE_PILOT_ASSET` (TestUSDC from deploy.sh, or your own)
- Toasts: Sonner

## Key Files

- `src/App.tsx` - Main application logic
- `src/components/` - UI components
- `src/config.ts` - wagmi config (chains, connectors, transports)

## Share links

- Starter apps already ship `getShareBase`, `buildShareLink` and `installShareSync` in `src/lib/share.ts`; import them instead of rewriting them.
- Keep shareable state in the URL path or query, not in the `#fragment`.
- Never put a secret (private key, claim secret, seed phrase, session token, API key) in the URL path or query, encoded or not: every in-app path and query is mirrored to the visitor's studio.arc.io address bar and browser history and reaches servers. A bearer claim secret goes only in the `#fragment` appended to the share link (`` `${await buildShareLink('/claim')}#${secret}` ``) and is read from `location.hash` on load. A link to the app's own share URL shown inside the app must be copy-only or open in a new tab with `target="_blank" rel="noopener noreferrer"`.
- Build every link a user copies or sends with `buildShareLink()` from `src/lib/share.ts`.
- Keep the `installShareSync()` call in `src/main.tsx` when editing it; it keeps the Studio address bar in step with in-app navigation.
- Navigate inside the app with relative links.

## To Run

```bash
bun install
bun run dev
```


## Deployed on Ink Sepolia (763373), verified on Blockscout

- PilotFactory proxy: 0x98aF69fB0E3fCFa4B911624B4486CB579ADE500e (deploy block 65958390)
- PilotFactory logic: 0xA43bDCbBFD3267FEcEB754A8036Fd65646B592e9
- PilotAccount logic: 0x103558779c76b4D9C647152Dcdd6275a59aA10Ce
- PilotTimelock (48h, factory owner): 0xb5182f1cAB9aC5E1B0b63eD4b3177838886dD52A
- DemoTydroPool: 0x2FC02096D53A622Dcb95aEe1635e0dfA237A7114
- TestUSDC (public faucet): 0x416d7684b88aC73fA3E82Dc53f1A0140412A5A8c
- Governance of this deployment is the shared platform wallet (proposer, canceller, executor, guardian), which cannot be handed over. Plan: redeploy the governance layer with `TIMELOCK_PROPOSER` and `GUARDIAN` set to the owner's wallet (see docs/07-governance.md). Addresses live in `.env` as VITE_PILOT_*.
- The Ink Sepolia RPC rejects log ranges over 1,000 blocks. `src/lib/logs.ts` scans in 990-block chunks.

## Deployment

- Run `./deploy.sh deploy` (see README). It writes `VITE_PILOT_*` into `.env`. Never hardcode addresses.
- The earlier Arc Testnet prototype is retired and removed from the code and config.
- Timelock proposer and guardian default to the shared platform wallet (testnet placeholder). Replace before real use.

## Decisions

- Accounts are immutable clones with their own validated risk settings. Factory upgrades never reach them.
- Same-asset (USDC) positions only, so health needs no oracle.
- Breaker stops only Boost and harvest, never protection or withdrawals.
- Nado is deferred to v2 (USDT0 collateral, off-chain signed withdrawals).
- Do not edit `src/abi/pilot.ts` by hand. Regenerate from `contracts/out` after contract changes.
- Gas on Ink Sepolia is ETH. Faucet button exists only if TestUSDC was deployed (`VITE_PILOT_FAUCET`), lab switches only for the demo pool (`VITE_PILOT_DEMO_POOL`).
- `deploy.sh` and `DeployInk.s.sol` refuse any chain other than 763373.
