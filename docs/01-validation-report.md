# InkPilot Validation Report (Phase 1 results and Phase 2 solutions)

Verdict: **the idea survives, with two pivots.** Nothing found was unsolvable for the core product. One part of the original brief (the Nado leg) could not be made safe and non-custodial in v1, so it moves to v2.

## Pivots

| Original idea | Problem found | Pivot |
| --- | --- | --- |
| "No-loss guarantee" | No contract can promise zero loss. Protocol bugs, a stablecoin depeg, a market pause or bad debt are outside any automation layer. | Sold and built as **capital protection**. The app says "Protected", never "Guaranteed". The contract header says the same. |
| Automatic Nado fallback to Tydro | Per Nado's docs: collateral is USDT0 (not USDC), and withdrawals are executed against an off-chain engine with a signed nonce from the subaccount owner. A contract cannot trigger that on its own without a signer, which would mean holding a key (custody). | Nado is **not in v1**. v2 is an opt-in, user-signed strategy (linked signer or EIP-1271 to be verified), with a read-only monitor first. |

## Bugs and risks found in Phase 1, and what fixed them

| # | Finding | Severity | Fix |
| --- | --- | --- | --- |
| 1 | Sequencer halt: no transaction can run, including protection and liquidations | Design | Same-asset positions (no price risk), capped 2x, reserve already inside the account, permissionless `protect()`, check of the liquidation grace period, L1 force-inclusion path (verify for Ink) |
| 2 | Shared vault would let one user's leverage hurt others | Design | One isolated account per user (EIP-1167 clone) |
| 3 | A compromised factory upgrade could change existing accounts' rules and drain tips | Critical (review) | Each account copies and validates its own risk settings at creation. It never reads them from the factory again |
| 4 | Principal counted as profit after reserve moves, so permissionless harvest could pull principal out of collateral | High (review) | `invested` redefined and tested across fund, withdraw, protect and harvest |
| 5 | A 1-unit USDC "dust" donation could stall protection | High (review) | Minimum reserve step plus try/catch, falls back to self-deleverage |
| 6 | Withdrawal could push leverage above the 2x cap | High (review) | Withdraw auto-deleverages first, and never blocks withdrawals |
| 7 | Predicted account address depended on a mutable implementation, so prefunding could strand funds | Medium (review) | Prediction removed, warning added |
| 8 | Tip farming with dust actions | Medium (review) | `NoProgress` check: health must strictly improve |
| 9 | Test pool could be paused then ownership renounced | High (review) | Renounce disabled |
| 10 | Frozen or paused market would revert user transactions | Aave-fork class | Status read before every action. Frozen: supply and borrow blocked upfront, repay and withdraw still work. Paused: clean error, nothing sent. UI shows "Safe but locked" |
| 11 | Safe Mode could cost more than it saves | Economic | Onchain gate: act only if expected loss is above tip plus fixed cost, always act at the emergency tier |
| 12 | Circuit breaker could block protection | Design | Breaker only stops Boost and harvest. Protection and withdrawals never depend on it |

## Brief versus delivered (Phase 2 to 5)

| Requirement | Status | Note |
| --- | --- | --- |
| UUPS, `onlyOwner` upgrade auth, `_disableInitializers`, `upgradeToAndCall`, `proxiableUUID` | Done | Factory is UUPS on OpenZeppelin 5.6.1. Existing accounts are immutable clones, so an upgrade cannot touch them |
| 48 hour timelock | Done (testnet) | Factory owner is a 48 hour timelock. Its proposer on testnet is the shared platform deployer wallet, a placeholder |
| 3-of-5 multisig, known signers | Not done | Needs real signers. Production blocker |
| Tydro status detection | Done | Active, Frozen, Paused, LtvZero, Inactive |
| Aave v3.0.2 fork | Not applicable | We integrate with the existing market. Tydro's version and flags must be verified on Ink |
| Safe Mode "every block" | Done differently | A contract cannot wake itself. `protect()` is public, and `scripts/keeper.ts` calls it. Anyone can run their own |
| Alerts by site, email, Telegram | Partly | Site and Telegram (via the keeper, one chat). Email not built |
| Save and Auto-Compound, switch any time | Done | Save moves profit to a withdrawable reserve. Compound leaves it earning |
| Nado integration, fallback | Moved to v2 | See pivots |
| Max 2x leverage, higher only after a test | 2x cap done | Higher leverage is blocked in code. The education gate is not built |
| Wallet login | Done (browser wallets) | Email and Apple need Circle passkey setup, not enabled |
| Gas paid in USDC | Not done | Ink Sepolia fees are paid in test ETH. USDC-only fees need a paymaster, not built |
| 60 seconds to first win | Not measured | The flow is three approvals: create, allow, deposit |
| Invariant: "no user liquidated without warning", "no principal loss" | Not possible as written | Neither can be a contract invariant. We test what is provable: protection never improves nothing, never pays a third party, owner can always withdraw reserve |
| Two audits, Immunefi 50,000 USDC bounty | Not done | Process items, see the security spec |
| Rescue Receipt, share to X and Telegram | Done | Real data only. The "14% profit, zero risk" example is not used because it would be an unverifiable claim |
| Telegram mini app | Prepared | The app is mobile first. It needs a bot registered with BotFather |
| 5 USDC invite reward | Not live | Needs a funded pool and anti-abuse rules. The referrer is recorded onchain meanwhile |
| Public Spark dashboard | Done | Read from chain events. Testnet numbers are demo activity |
