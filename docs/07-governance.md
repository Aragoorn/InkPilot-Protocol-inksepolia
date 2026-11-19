# Governance on Ink Sepolia

## How control is arranged

```
you (EOA) --> PilotTimelock (48 hours) --> PilotFactory (UUPS proxy) --> new accounts
                     ^ proposer, canceller, executor           guardian = breaker only
```

- The **factory** is owned by the **timelock**. Upgrades and parameter changes must be queued, wait 48 hours, then be executed.
- The **timelock** has no admin account. It administers itself, so adding or removing proposers is also a queued, 48-hour change.
- The **guardian** is a separate key that can only switch the breaker (Boost and harvest) on or off. It is set at deploy time and changed by a queued call to `setGuardian`.
- Existing user accounts are not affected by any of this.

## Why the factory is not transferred to a plain wallet

`PilotFactory` uses a two-step ownership transfer. If it were handed to an ordinary wallet, that wallet could upgrade the factory instantly, and the 48-hour exit window would be gone. "Only my address can queue upgrades" is achieved by making your address the timelock's only proposer, canceller and executor, and keeping the timelock as the owner. That is what `TIMELOCK_PROPOSER` does at deploy time.

## State of the first Ink Sepolia deployment (read from the chain)

- Factory owner: the timelock `0xb5182f1cAB9aC5E1B0b63eD4b3177838886dD52A` (delay 172,800 s).
- Timelock proposer, canceller and executor: only the shared platform wallet. Guardian: the same wallet.
- Your wallet holds no role.

Every role change has to be queued by a current proposer, and the only proposer is the platform wallet, which nobody using this project can sign for. So this deployment's governance cannot be handed to you. It has no user accounts yet, so the clean fix is to deploy a fresh factory stack that is yours from the first block, re-using the verified test token and demo pool.

## Take control: redeploy the governance layer

In `.env` set (your own wallet as proposer and guardian, and the existing token and pool):

```
TIMELOCK_PROPOSER=0xA1C6808b8f08D091e2826C9640Be302a310655E1
GUARDIAN=0xA1C6808b8f08D091e2826C9640Be302a310655E1
ASSET=0x416d7684b88aC73fA3E82Dc53f1A0140412A5A8c
POOL=0x2FC02096D53A622Dcb95aEe1635e0dfA237A7114
```

Then:

```bash
./deploy.sh simulate
./deploy.sh deploy
```

This deploys a new account implementation, factory implementation, timelock and proxy. The post-deploy check confirms the owner is the new timelock and the guardian is your wallet. `.env` is updated, so restart `bun run dev`. Confirm with:

```bash
./governance.sh roles 0xA1C6808b8f08D091e2826C9640Be302a310655E1
```

## Day-to-day operations (after the redeploy)

All use `./governance.sh` and your key in `.env`.

| Goal | Command |
| --- | --- |
| Change the guardian | `./governance.sh schedule "$VITE_PILOT_FACTORY" "setGuardian(address)" 0xNEW` |
| Upgrade the factory | `./governance.sh schedule "$VITE_PILOT_FACTORY" "upgradeToAndCall(address,bytes)" 0xNEWIMPL 0x` |
| Hand over to a multisig | schedule `grantRole(bytes32,address)` on the timelock for each of PROPOSER_ROLE, CANCELLER_ROLE, EXECUTOR_ROLE, then `revokeRole` for your own address |
| See where a queued call is | `./governance.sh status <same target, signature, args>` |
| Run it after 48 hours | `./governance.sh execute <same target, signature, args>` |
| Cancel it | `./governance.sh cancel <same target, signature, args>` |

The guardian wallet flips the breaker directly with `cast send $VITE_PILOT_FACTORY "setBreaker(bool)" true --private-key ...`. It expires on its own after 7 days.

Before mainnet: the proposer, canceller and executor must be a 3-of-5 multisig with publicly known signers. A single wallet is a testnet convenience only.
