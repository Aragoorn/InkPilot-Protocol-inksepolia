# InkPilot

**Chat-driven, non-custodial USDC yield with onchain capital protection on Ink Sepolia.**

InkPilot helps users put USDC to work through a simple conversation, then keeps positions safer with transparent, permissionless protection logic ("Safe Mode"), withdraw-anytime controls, and verifiable onchain activity. It is designed as a consumer-friendly DeFi primitive for the Ink ecosystem: easier onboarding, clearer risk communication, and safer leverage defaults.

> **Status:** Testnet / demo-ready on **Ink Sepolia (chain ID 763373)**. Not audited for mainnet, not financial advice, and not a "no-loss guarantee." Protection reduces certain liquidation risks; it does not remove smart-contract, market, oracle, bridge, or stablecoin risks.
---
website: https://inkpilot-ink-sepolia.netlify.app/
---

## Problem statement

Onchain yield products are powerful but difficult and risky for most users:
- **Complexity:** users must understand lending markets, collateral/debt health, approvals, and liquidation mechanics.
- **Risk opacity:** "high APY" flows often hide leverage and liquidation risk.
- **Operational burden:** staying safe requires constant monitoring and fast reactions during volatility.
- **Trust gap:** many products over-promise safety without verifiable, user-controlled safeguards.

## Solution

InkPilot turns lending into a guided, user-owned workflow:
- **Plain-language planning:** users describe intent (e.g. "invest 1,000 USDC safely" or "use 2x boost") and receive an explicit, signable plan.
- **Per-user smart accounts:** each user gets an isolated account clone they own; funds are not pooled across users.
- **Safe Mode protection:** permissionless `protect()` can reduce risk (reserve top-up, repay, or exit-to-earn) when health deteriorates.
- **Honest risk UX:** "protected", never "guaranteed"; clear market states ("Active", "Safe but locked"), warnings, and receipts.
- **Onchain transparency:** public stats, contract links, and activity/receipt views are derived from chain data/events.

## Why this matters for Ink / grant alignment

- **Ecosystem utility:** lowers the barrier to safe USDC participation on Ink by combining guided UX with enforceable onchain controls.
- **Technical novelty:** chat-to-transaction planning + isolated per-user protection accounts + permissionless keeper-compatible safety actions.
- **Composable foundation:** the account/protection pattern can extend to additional Ink-native markets/strategies after audits and market verification.
- **Responsible DeFi:** explicit guardrails, capped leverage (max 2x), no custodial key requirement for protection, and transparent testnet/demo labeling.

---

## Architecture & key features

### Frontend (React + wagmi/viem)
- **App shell:** `src/App.tsx`, `src/main.tsx`, `src/config.ts`
- **Planning & execution UX:** `src/components/ChatPlanner.tsx`, `src/components/Onboarding.tsx`, `src/components/Dashboard.tsx`, `src/components/AmountSheet.tsx`, `src/hooks/useStartPlan.ts`, `src/hooks/useTxFlow.ts`
- **Safety & observability UI:** `SecurityCard`, `ProtectionCard`, `LockedBanner`, `ActivityList`, `ReceiptCard`, `Rescues`, `PublicStats`
- **Chain/data layer:** `src/hooks/usePilot.ts`, `useActivity.ts`, `usePublicStats.ts`, `src/lib/*` (planner, logs chunking, formatting, explorer links, errors)
- **Share/preview support:** `src/lib/share.ts`, `src/preview/PreviewPage.tsx` (`/?preview=1` for chainless UI review)

### Smart contracts (Solidity 0.8.28, Foundry, OpenZeppelin)
- **`PilotFactory` (UUPS, timelock-owned):** deploys deterministic per-user account clones, stores defaults/risk params for new accounts, guardian-controlled breaker (time-bounded).
- **`PilotAccount` (immutable per-user clone):** holds user position state, deposit/withdraw/reserve/boost/deleverage/protect/harvest logic, owner-only controls, non-custodial rescue rules.
- **`PilotTimelock`:** 48h delayed governance for factory upgrades/parameter changes.
- **`RiskLib`:** shared risk parameter validation and bounds.
- **Test/demo utilities:** `TestUSDC` (public faucet token, testnet-only) and `DemoTydroPool` (open stress controls for demos, testnet-only).

### Automation / ops
- **Permissionless protection:** anyone can call `protect()`; users are not dependent on a single backend.
- **Keeper (optional):** `scripts/keeper.ts` monitors accounts and triggers protection + Telegram alerts (gas key only, no custody of user funds).
- **Deployment tooling:** `deploy.sh`, `governance.sh`, verification helpers, Ink Sepolia-specific checks.

### Key product behaviors
- **Earn mode (no borrowing):** no liquidation risk from leverage.
- **Boost mode (optional, capped at 2x):** higher risk/reward with reserve and Safe Mode protections.
- **Profit handling:** Save (to withdrawable reserve) or Auto-Compound.
- **Market-state awareness:** deposits/boost blocked when market is not active; clear "Safe but locked" messaging.
- **Verifiable receipts:** shareable proof generated from real onchain protection events.

---

## Repository layout

```text
contracts/              Solidity contracts, interfaces, scripts, tests
src/                    React app (components, hooks, libs, config, ABI bindings)
scripts/                Keeper and deployment/verification helpers
docs/                   Design, validation, security, roadmap, governance, network checks
deploy.sh               Ink Sepolia deploy/simulate/verify/postcheck helper
governance.sh           Timelock operation helper
.env.example            Environment template (safe defaults, no secrets)
```

---

## Prerequisites

- **Bun** (frontend/package scripts)
- **Node-compatible environment** for tooling where needed
- **Foundry** (`forge`, `cast`) for contract build/test/deploy flows
- **jq** and **bash** for `deploy.sh` / `governance.sh`
- Browser wallet (MetaMask/Rabby/etc.) connected to **Ink Sepolia**
- Test ETH for gas on Ink Sepolia

---

## Setup & installation

### 1) Install dependencies

```bash
bun install
```

### 2) Configure environment

```bash
cp .env.example .env
```

Fill required values in `.env`:

| Variable | Purpose | Notes |
|---|---|---|
| `PRIVATE_KEY` | Deployer key for `deploy.sh` / `governance.sh` | **Testnet-only throwaway key. Never commit.** |
| `INK_SEPOLIA_RPC_URL` | RPC for scripts/keeper | Public RPC recommended server-side |
| `ASSET`, `POOL` | Optional existing market/token addresses | Leave empty to deploy demo `TestUSDC` + `DemoTydroPool` |
| `TIMELOCK_PROPOSER`, `GUARDIAN` | Governance roles for deployment | Set to keys/multisig you control before real use |
| `VITE_PILOT_*` | Frontend contract config | Written by `deploy.sh` after deploy |
| `VITE_INK_SEPOLIA_RPC_URL` | Optional browser RPC override | **Public HTTPS only** (VITE vars ship to browser) |
| `KEEPER_*`, `TELEGRAM_*` | Optional keeper automation/alerts | Keeper key must be gas-only |

> Security note: never place private keys, mnemonics, or keyed RPC URLs in `VITE_*` variables. `.env` is git-ignored; `.env.example` is the committed template.

### 3) Run the app (local)

```bash
bun run dev
```

Open the local URL shown by Vite. If contracts are not configured yet, the app shows setup guidance and a design preview (`/?preview=1`).

---

## Contract build, test, and deployment (Ink Sepolia)

### Build and test contracts

```bash
bun run contracts:build
bun run contracts:test
```

> If Foundry is not installed in your environment, install it first (`https://getfoundry.sh`) before running contract commands.

### Deploy helper flow (testnet)

```bash
./deploy.sh check      # validates tools, RPC chain (763373), deployer balance
./deploy.sh simulate   # dry-run deployment (no broadcast)
./deploy.sh deploy     # broadcast + verify + write VITE_PILOT_* to .env + postcheck
```

Useful follow-ups:

```bash
./deploy.sh verify     # retry Blockscout verification
./deploy.sh env        # rewrite VITE_PILOT_* from last broadcast
./deploy.sh postcheck  # compare deployed state vs expected config
```

After deployment, restart `bun run dev` so the frontend picks up updated `VITE_*` values.

### Governance operations (timelock-owned factory)

```bash
./governance.sh roles <address>
./governance.sh calldata <target> "<signature>" [args...]
./governance.sh schedule <target> "<signature>" [args...]
./governance.sh status   <target> "<signature>" [args...]
./governance.sh execute  <target> "<signature>" [args...]
./governance.sh cancel   <target> "<signature>" [args...]
```

See `docs/07-governance.md` for role model, redeploy-to-take-control guidance, and production requirements.

---

## Usage / demo walkthrough

### A. UI preview without chain interaction
1. Run `bun run dev`
2. Open `/?preview=1`
3. Review dashboard states (Earn, Protected, Watching, Needs protection, Safe but locked), receipts, and activity presentation

### B. Full testnet demo (deployed demo pool/token)
1. Deploy with empty `ASSET`/`POOL` (deploys `TestUSDC` + `DemoTydroPool`)
2. Connect wallet on Ink Sepolia and claim test USDC (faucet button, cooldown applies)
3. Use chat planner to create a plan (safe earn or 2x boost) and approve each wallet step
4. Observe balance/security/profit mode/activity updates from chain state/events
5. (Demo only) Use **Testnet lab** controls to freeze/unfreeze or spike borrow cost and watch Safe Mode/status behavior
6. Trigger/observe protection and share a **Rescue Receipt** (real event data only)

### C. Optional keeper automation

```bash
KEEPER_PRIVATE_KEY=0x... bun run keeper
```

- Uses chunked log scans compatible with Ink Sepolia RPC limits
- Calls permissionless `protect()` when eligible
- Can emit Telegram alerts when configured
- Never custodies user funds

---

## Security model (high level)

- **Non-custodial, per-user isolation:** each user owns their account clone; no shared vault.
- **Bounded risk:** same-asset strategy assumptions and max 2x leverage cap in v1 design.
- **Fail-safe controls:** breaker is designed to stop discretionary actions (not protection/withdrawal paths), and market status is surfaced before risky actions.
- **Upgradeable governance boundary:** factory is upgradeable behind a timelock; user account clones are not upgraded by factory upgrades.
- **Transparency:** event-derived stats/history and explorer-linked contracts/txs.

See `docs/03-security-spec.md`, `contracts/InkPilot-design.md`, and `docs/01-validation-report.md` for deeper analysis and known limitations.

### Known limitations (important)
- **Testnet/demo scope:** current deployment and demo pool/token flows are not mainnet-ready.
- **Governance must be verified:** a safe deployment requires proposer/guardian keys (ideally multisig) under operator control; do not assume this from a cloned repo alone.
- **No formal audit attestation in-repo:** external audits, bounty program, and production controls remain launch tasks.
- **Frontend indexing is RPC-based:** in-memory incremental log scans are suitable for testnet scale; production scale should use an indexer/subgraph.
- **Not all roadmap features implemented:** passkey/email onboarding, USDC-gas/paymaster UX, Nado integration, and production reward programs are future work.

---

## Roadmap & ecosystem impact

### Near-term (grant execution / pilot hardening)
- Verify and/or redeploy governed stack with operator-controlled timelock proposer/guardian (multisig for production)
- Expand automated tests (frontend integration/e2e + keeper/unit coverage where practical)
- Improve observability dashboards and alerting (ops health, protection outcomes, RPC/indexing reliability)
- Add indexed data backend for scalable public analytics and history

### Mid-term (production readiness)
- External security audits and remediation cycle
- Integrate/verify real Ink market deployment parameters (Tydro or equivalent) with strict runtime checks
- Harden UX for mobile/mini-app distribution and guided recovery/support flows
- Introduce feature flags/config validation for multi-environment deployments

### Longer-term (ecosystem expansion)
- Additional Ink-native strategies/products built on isolated protected-account primitives
- Optional automation marketplace/keeper incentives (permissionless, transparent)
- Safer leverage education and progressive risk controls

**Ecosystem impact:** InkPilot can serve as a reusable safety-first UX and smart-account pattern for Ink DeFi—helping onboard users to onchain yield with clearer risks, better defaults, and verifiable protection behavior.

---

## Documentation

- `docs/01-validation-report.md` – validation findings and pivots
- `docs/02-tech-spec.md` – technical specification
- `docs/03-security-spec.md` – security model and controls
- `docs/04-roadmap.md` – roadmap
- `docs/05-spark-pitch.md` – grant/pitch framing
- `docs/06-ink-sepolia-checks.md` – Ink Sepolia measurements/checks
- `docs/07-governance.md` – governance and timelock operations
- `contracts/InkPilot-design.md` – contract/design rationale

---

## Pre-launch & grant submission checklist

### Product & demo readiness
- [ ] Confirm deployed contract addresses in `.env` match the intended Ink Sepolia deployment
- [ ] Run `./deploy.sh postcheck` and capture results/screenshots
- [ ] Validate UI states: connect, faucet (if enabled), create account, deposit, withdraw, save/compound toggle, boost/deleverage (demo), protection receipt, public stats
- [ ] Record a deterministic demo script (or `/?preview=1` walkthrough + live testnet flow)
- [ ] Verify all user-facing copy says **"protected"** (not guaranteed) and clearly labels testnet/demo behavior

### Security & governance
- [ ] Verify factory owner is timelock and timelock roles/guardian are controlled by intended operators
- [ ] If current deployment uses placeholder/shared governance, redeploy with controlled `TIMELOCK_PROPOSER`/`GUARDIAN`
- [ ] Review breaker permissions, timelock delay, and emergency procedures
- [ ] Run/retain `forge test` results and document coverage scope
- [ ] Commission external audit(s) before mainnet or real-funds launch; track remediation

### Reliability & operations
- [ ] Validate RPC reliability and log-scan behavior on Ink Sepolia (including backfill)
- [ ] Test keeper in dry/alert mode and with a funded gas-only key
- [ ] Confirm Telegram alerts (if enabled) and operational logging/rotation practices
- [ ] Define monitoring for failed txs, stale data, and protection opportunities

### Compliance / submission packaging
- [ ] Prepare architecture diagram and threat-model summary for reviewers
- [ ] Include verifiable contract links, tx hashes, and demo evidence
- [ ] Document limitations, assumptions, and roadmap with milestones/deliverables
- [ ] Provide grant narrative mapping: user problem, Ink ecosystem value, technical differentiation, sustainability plan

---

## License / attribution

Built with Arc Studio foundations and extended for InkPilot. Review third-party licenses and generated/vendor files before redistribution or commercial launch.
