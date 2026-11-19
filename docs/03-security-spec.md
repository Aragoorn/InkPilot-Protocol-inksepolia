# InkPilot Security Spec

## Mechanisms in place

| Mechanism | What it does | Where |
| --- | --- | --- |
| Isolated accounts | One account per user, so one user's risk never reaches another | PilotFactory, PilotAccount |
| Owner-only funds | Only the owner deposits and withdraws. Protection can only move the account's own money to the pool, or pay a capped tip | PilotAccount |
| Timelock | Upgrades and parameter changes wait 48 hours | PilotTimelock |
| Upgrade isolation | A factory upgrade cannot change existing accounts. Each account holds its own validated settings | RiskLib, PilotAccount |
| Circuit breaker | Guardian can stop Boost and harvest. It auto-expires after 7 days. It never stops protection or withdrawals | PilotFactory |
| Status checks | Frozen, paused, LTV-zero and inactive are read before acting | PilotAccount |
| Economic gate | Acts only when expected loss beats cost, always acts at the emergency tier | PilotAccount |
| Progress rule | A protection call must improve health or it reverts, so tips cannot be farmed | PilotAccount |
| No flash loans, no swaps, no oracle math | Same-asset positions, so no price manipulation path | PilotAccount |
| Reentrancy guards, exact approvals, balance-delta checks | Standard hardening | PilotAccount |

## Testing done

- 155 Foundry tests pass: 151 for the system (unit, fuzz at 256 runs, 4 invariants), 3 for the demo pool and timelock, 1 for the test token.
- Invariants that hold: owner can always withdraw their reserve, nobody except pool, owner and capped tip receives USDC, tips stay bounded, the account holds no native coin.
- Three rounds of AI-assisted review with a rule corpus and a behavioural review, plus Slither. Real findings were fixed (see the validation report). Slither's remaining High and Medium items were checked and are false positives (owner-gated transfers, guarded functions, zero checks).
- The third round hit its round limit with items open. They were fixed and covered by tests, but a fourth independent review pass was not run.

## Not done yet (be clear about these before real funds)

1. **Two independent audits** from reputable firms. Not started.
2. **Bug bounty** (Immunefi, 50,000 USDC minimum). Not started.
3. **3-of-5 multisig** with public signers for the timelock proposer and canceller, and a separate guardian key.
4. **Fork tests against the real Tydro pool** on Ink.
5. **Automatic abnormal-withdrawal detection.** Today the breaker is set by the guardian. An automatic version needs accounts to report withdrawals to a factory counter, and must only ever pause Boost, harvest and new deposits, never withdrawals.
6. **Formal check of the Tydro assumptions**: reserve flags layout, liquidation grace-period contract, behaviour of `repayWithATokens`.
7. **Monitoring**: alert on `Protected`, `ProtectionSkipped`, breaker changes, and timelock `CallScheduled`.

## Trust model

| Key | Can | Worst case if stolen |
| --- | --- | --- |
| User wallet | Own account only | That user's funds |
| Timelock proposer | Queue upgrades and parameter changes | Nothing for 48 hours. Cancel and users exit. Existing accounts keep their own settings |
| Guardian | Breaker on or off | Boost and harvest stop for up to 7 days. No fund access |
| Keeper key | Pays gas for `protect()` | Nothing. It holds no funds and has no special rights |

## Audit plan

1. Freeze code. Tag a release. Publish the design doc and tests to auditors.
2. Audit one: contracts focus (accounting, tiers, rounding, reentrancy). Audit two: integration with Tydro on an Ink fork plus governance.
3. Fix, re-test, publish both reports.
4. Launch the bounty on testnet-to-mainnet transition, cap TVL at first, raise it in steps.
