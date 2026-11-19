# Six-week roadmap to MVP on Ink

Already done before week 1: contracts, 155 tests, review rounds, testnet deployment, web app, keeper, public stats.

| Week | Goal | Deliverables | Exit check |
| --- | --- | --- | --- |
| 1 | Verify the real market | Tydro Pool, reserve flags, grace-period setting and `repayWithATokens` confirmed on Ink. Ink fork test harness | Fork tests of deposit, boost, protect, frozen and paused all pass against the real pool |
| 2 | Contract hardening | Fix anything the fork shows. Automatic breaker design (Boost, harvest, deposits only). Timelock and multisig scripts | Full suite green, gas report, freeze release candidate |
| 3 | Safe Mode in production shape | Keeper with retries, monitoring, per-user Telegram and email alerts (opt-in with a signed message) | A staged price-free stress run triggers every tier on the fork, alerts delivered |
| 4 | Nado research track | Read-only Nado position viewer using the official SDK. Decide the v2 signer model (linked signer or EIP-1271) | Written go or no-go for a user-signed Nado strategy. Nothing custodial |
| 5 | Product | Passkey email sign-in (needs a Circle client key), gas sponsorship on Ink, Telegram mini app via a registered bot, invite rewards design with abuse limits | A new user reaches first deposit in under a minute, measured, not assumed |
| 6 | Security and grant | Audit one starts. Bounty drafted. Spark application with live testnet numbers | Application submitted, audit scope signed |

Mainnet needs: both audits finished, multisig live, bounty live, TVL cap on. Do not skip these.
