# Ink Sepolia final check: Safe Mode and Profit Handling

Scope: Ink Sepolia (chain 763373) only. Mainnet is not configured anywhere in this project.

## What was measured, not assumed

| Fact | Result | How |
| --- | --- | --- |
| Chain ID | 763373 | `eth_chainId` on the public RPC |
| Block time | 1.0 s | 1,000 blocks spanned 1,000 s |
| Cancun opcodes (needed by clones) | Supported | An init-code probe using `MCOPY` ran without error |
| Gas | Tiny: base fee was 252 wei at the time | Latest block |
| Block gas limit | 30,000,000 | Latest block |
| Multicall3 | Present | `eth_getCode` |
| Blockscout API | Reachable | HTTP 200 on the stats endpoint |
| Full deploy cost (simulated) | About 0.0000165 ETH | forge estimate on a local fork of Ink Sepolia |

## Rehearsal on a fork of Ink Sepolia

`./deploy.sh deploy` was run against a local fork of live Ink Sepolia state, then a user flow was driven with `cast`. This is a rehearsal on a fork, not a transaction on the live chain.

1. Claim test USDC, create account, deposit 800, reserve 200, Boost to 2x: health 1.60.
2. Two borrowing-cost spikes: health 1.21.
3. `protect()`: reserve used, health back to 1.45, reserve now empty.
4. Freeze the market: status reads Frozen.
5. Unfreeze, withdraw everything: wallet received the remaining balance.

All eight post-deploy checks passed (owner is the timelock, pool, asset, account implementation, guardian, delay at least 48h, 6 decimals, factory logic cannot be initialized directly). 155 unit, fuzz and invariant tests pass.

## Sequencer and block-time behaviour

| Situation | What happens | Verdict |
| --- | --- | --- |
| Sequencer halted | No transaction runs, including `protect()` and liquidations. Nothing can be done by anyone until it resumes | Unavoidable. Position size (same asset, 2x cap) and the reserve inside the account limit the exposure |
| Sequencer resumes | Interest has accrued for the whole outage in one step. For a 24 hour outage at a 10 percent yearly borrow-minus-supply spread that is about 0.03 percent of the position, a negligible health change | Safe. `protect()` works in the first block |
| Liquidation grace period | Depends on the market having a price oracle sentinel. `tydro:verify` reads it and warns if there is none. The demo pool has none | Check before offering Boost on a real market |
| Force inclusion | OP Stack chains let a user submit a transaction through the L1 portal when the sequencer is down or censoring. viem's chain definition lists the Ink Sepolia portal. Not tested here | Treat as a fallback to verify, not a promise |
| Reorg of unsafe blocks | A `protect()` seen on an unconfirmed block could vanish. The next keeper cycle simply calls it again | Safe, idempotent by design (health gate, cooldown) |
| 1 second blocks | Cooldown of 60 s is about 60 blocks. The keeper cycle of 30 s is about 30 blocks. Nothing in the contracts counts blocks | Safe |
| Timestamps | Cooldown and breaker expiry use `block.timestamp`, which the sequencer sets. It can shift these by seconds only | Safe |
| Fee model | Fees are ETH and tiny today. The USDC `fixedCost` and tip are constants, not tied to ETH price | Fine on testnet. Recalibrate before any real network |

## Profit Handling

- **Auto-Compound** needs no transaction: the lending balance grows with the pool's index over time. Switching mode is one transaction and takes effect at once.
- **Save Profits** moves profit into the reserve when someone calls `harvest()` (anyone can). It withdraws from the pool, so it can fail when the pool has no free liquidity. `repayWithATokens`, used for protection exits, does not need free liquidity.
- Principal is never counted as profit (tested across fund, withdraw, protect and harvest).
- The breaker never blocks withdrawals, protection or the mode switch.

## Not verified (you must check)

1. Whether a Tydro market exists on Ink Sepolia and what its Pool and asset addresses are. Tydro's docs say a Sepolia test market exists in the Tydro app (testnet mode), without naming the chain or listing addresses. The Pool address on the docs' Contract Addresses page appears to be for Ink mainnet, so it was not used.
2. The real reserve flags, sentinel and liquidity of that market: run `bun run tydro:verify`.
3. Force inclusion through the L1 portal, and behaviour in a real sequencer outage.
4. Everything in the "Not done yet" list of the security spec (audits, bounty, 3-of-5 multisig). The testnet placeholders are the shared platform wallet for proposer and guardian, as agreed.
