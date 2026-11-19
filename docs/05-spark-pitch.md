# InkPilot: Spark grant pitch

## One line
InkPilot is the safety and automation layer for lending on Ink. You say what you want in plain words, it sets it up, watches it all day, and steps in before it gets dangerous.

## The gap
Lending on Tydro is powerful and unforgiving. Ordinary users do not watch health factors, and when a market freezes they are stuck with failing transactions. Spark's own focus is lending tools, risk management and automation for Tydro and Nado. Nothing we know of on Ink combines all three for ordinary users, and we are not claiming to have surveyed every project.

## What exists today (Ink Sepolia testnet, verifiable once deployed)
- Per-user accounts, Boost capped at 2x, four-step protection, Save or Auto-Compound profit handling.
- Upgradeable factory behind a 48-hour timelock, accounts that upgrades cannot touch.
- 155 passing tests, three rounds of review with fixes, and a public contract status page.
- A live app: chat plan builder, dashboard with a green, yellow, red security light, "Safe but locked" market states, shareable Rescue Receipts, public stats read from chain events.

## What makes it different
1. Protection is permissionless. Anyone can trigger it, so it has no central point of failure.
2. Same-asset positions, so there is no price-oracle attack path.
3. Honest by design: no loss guarantee is claimed, and every risk that remains is listed.

## Traction we will report, and how
Numbers come only from the public stats page: accounts, supplied amount, total invested and times Safe Mode acted. On testnet they are demo activity. Ink numbers start after mainnet launch.

## Ask
A grant in the 500 to 20,000 USDC range, spent in this order: Ink fork tests and verification of Tydro assumptions, audit scoping and a first audit deposit, keeper hosting and alerts, and the bug bounty seed.

## Milestones
1. Week 1 to 2: real-market verification and fork tests.
2. Week 3 to 4: production keeper, alerts, Nado read-only research.
3. Week 5 to 6: passkey sign-in, Telegram mini app, audit start, grant report.

## Risks we name up front
Tydro or USDC risk is not removed. Nado trading is not in v1, because Nado settles through an off-chain engine and uses a different collateral asset, so a safe non-custodial design needs more research. Mainnet waits for two audits.
