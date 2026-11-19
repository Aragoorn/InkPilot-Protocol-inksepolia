#!/usr/bin/env bash
# InkPilot deployment helper for Ink Sepolia (chain 763373). TESTNET ONLY.
#
#   ./deploy.sh check      read-only checks: tools, RPC chain id, deployer balance
#   ./deploy.sh simulate   dry run of the whole deployment against the live chain, nothing is sent
#   ./deploy.sh deploy     broadcast, verify on Blockscout, write addresses into .env, run post-deploy checks
#   ./deploy.sh verify     retry Blockscout verification for the last broadcast
#   ./deploy.sh env        (re)write the VITE_PILOT_* lines in .env from the last broadcast
#   ./deploy.sh postcheck  read the deployed contracts back and compare with what was intended
#
# Add -y to skip the typed confirmation on `deploy`.
set -euo pipefail
cd "$(dirname "$0")"

CHAIN_ID=763373
DEFAULT_RPC="https://rpc-gel-sepolia.inkonchain.com"
EXPLORER="https://explorer-sepolia.inkonchain.com"
EXPLORER_API="$EXPLORER/api/"
SCRIPT="contracts/script/DeployInk.s.sol:DeployInk"
BROADCAST="broadcast/DeployInk.s.sol/$CHAIN_ID/run-latest.json"
PLATFORM_WALLET="0x5B12Ce46C7194aD57d143bC22847224047b1Ef42"

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required (install Foundry from https://getfoundry.sh, and jq from your package manager)"; }

if [ -f .env ]; then set -a; . ./.env; set +a; fi
RPC="${INK_SEPOLIA_RPC_URL:-$DEFAULT_RPC}"

preflight() {
  need forge; need cast; need jq
  local chain
  chain="$(cast chain-id --rpc-url "$RPC")" || die "cannot reach $RPC"
  [ "$chain" = "$CHAIN_ID" ] || die "RPC reports chain $chain, expected $CHAIN_ID (Ink Sepolia). Refusing to continue."
  [ -n "${PRIVATE_KEY:-}" ] || die "PRIVATE_KEY is empty. Put a throwaway testnet key in .env (see .env.example)."
  [[ "$PRIVATE_KEY" =~ ^0x[0-9a-fA-F]{64}$ ]] || die "PRIVATE_KEY must be 0x followed by 64 hex characters"
  DEPLOYER="$(cast wallet address --private-key "$PRIVATE_KEY")"
  local bal
  bal="$(cast balance "$DEPLOYER" --rpc-url "$RPC" --ether)"
  echo "chain id   : $chain (Ink Sepolia)"
  echo "deployer   : $DEPLOYER"
  echo "balance    : $bal ETH"
  [ "$bal" != "0.000000000000000000" ] && [ "$bal" != "0" ] || die "deployer has no Ink Sepolia ETH. Faucets: https://docs.inkonchain.com/tools/faucets"
  echo "asset      : ${ASSET:-<deploy TestUSDC>}"
  echo "pool       : ${POOL:-<deploy DemoTydroPool>}"
  echo "proposer   : ${TIMELOCK_PROPOSER:-$PLATFORM_WALLET (shared platform wallet, testnet placeholder)}"
  echo "guardian   : ${GUARDIAN:-$PLATFORM_WALLET (shared platform wallet, testnet placeholder)}"
}

build() { forge build; }

simulate() {
  preflight; build
  forge script "$SCRIPT" --rpc-url "$RPC" --sender "$DEPLOYER" -vv
  echo "Simulation finished. Nothing was sent."
}

addr() { jq -r --arg n "$1" '[.transactions[] | select(.contractName == $n and .transactionType == "CREATE")][0].contractAddress // empty' "$BROADCAST"; }

set_env() { # KEY VALUE
  touch .env
  sed -i.bak "/^$1=/d" .env && rm -f .env.bak
  printf '%s=%s\n' "$1" "$2" >> .env
}

write_env() {
  [ -f "$BROADCAST" ] || die "no broadcast file at $BROADCAST. Run ./deploy.sh deploy first."
  local factory timelock accimpl facimpl asset pool block testusdc demopool
  factory="$(addr PilotProxy)"; timelock="$(addr PilotTimelock)"
  accimpl="$(addr PilotAccount)"; facimpl="$(addr PilotFactory)"
  testusdc="$(addr TestUSDC)"; demopool="$(addr DemoTydroPool)"
  asset="${ASSET:-$testusdc}"; pool="${POOL:-$demopool}"
  [ -n "$factory" ] && [ -n "$timelock" ] && [ -n "$accimpl" ] && [ -n "$facimpl" ] && [ -n "$asset" ] && [ -n "$pool" ] || die "broadcast file is missing a contract"
  block="$(printf '%d' "$(jq -r '.receipts[0].blockNumber' "$BROADCAST")")"
  set_env VITE_PILOT_FACTORY "$factory"
  set_env VITE_PILOT_POOL "$pool"
  set_env VITE_PILOT_ASSET "$asset"
  set_env VITE_PILOT_TIMELOCK "$timelock"
  set_env VITE_PILOT_ACCOUNT_IMPL "$accimpl"
  set_env VITE_PILOT_FACTORY_IMPL "$facimpl"
  set_env VITE_PILOT_DEPLOY_BLOCK "$((block > 5 ? block - 5 : 0))"
  # The faucet button and the testnet lab are on only when the asset really has a faucet and the pool really is the demo pool.
  # This also covers re-using a TestUSDC or DemoTydroPool from an earlier deployment (ASSET and POOL set in .env).
  local has_faucet=false has_lab=false
  cast call "$asset" 'FAUCET_AMOUNT()(uint256)' --rpc-url "$RPC" >/dev/null 2>&1 && has_faucet=true
  cast call "$pool" 'MAX_DEMO_ACCRUAL_BPS()(uint256)' --rpc-url "$RPC" >/dev/null 2>&1 && has_lab=true
  set_env VITE_PILOT_FAUCET "$has_faucet"
  set_env VITE_PILOT_DEMO_POOL "$has_lab"
  echo "Wrote VITE_PILOT_* to .env. Restart the dev server (bun run dev) so the app picks them up."
  echo "Factory (proxy): $EXPLORER/address/$factory"
}

postcheck() {
  need cast
  local f="${VITE_PILOT_FACTORY:-}"; [ -n "$f" ] || { . ./.env; f="$VITE_PILOT_FACTORY"; }
  local ok=1
  chk() { # label actual expected
    if [ "$(echo "$2" | tr 'A-Z' 'a-z')" = "$(echo "$3" | tr 'A-Z' 'a-z')" ]; then echo "ok    $1"; else echo "FAIL  $1: got $2, expected $3"; ok=0; fi
  }
  chk "owner is the timelock"          "$(cast call "$f" 'owner()(address)' --rpc-url "$RPC")"                 "$VITE_PILOT_TIMELOCK"
  chk "pool"                           "$(cast call "$f" 'pool()(address)' --rpc-url "$RPC")"                  "$VITE_PILOT_POOL"
  chk "asset"                          "$(cast call "$f" 'asset()(address)' --rpc-url "$RPC")"                 "$VITE_PILOT_ASSET"
  chk "account implementation"         "$(cast call "$f" 'accountImplementation()(address)' --rpc-url "$RPC")" "$VITE_PILOT_ACCOUNT_IMPL"
  chk "guardian"                       "$(cast call "$f" 'guardian()(address)' --rpc-url "$RPC")"              "${GUARDIAN:-$PLATFORM_WALLET}"
  chk "timelock delay >= 48h"          "$([ "$(cast call "$VITE_PILOT_TIMELOCK" 'getMinDelay()(uint256)' --rpc-url "$RPC" | awk '{print $1}')" -ge 172800 ] && echo yes || echo no)" "yes"
  chk "asset has 6 decimals"           "$(cast call "$VITE_PILOT_ASSET" 'decimals()(uint8)' --rpc-url "$RPC")" "6"
  chk "factory logic cannot be initialized directly" "$(cast call "$VITE_PILOT_FACTORY_IMPL" 'owner()(address)' --rpc-url "$RPC")" "0x0000000000000000000000000000000000000000"
  [ "$ok" = 1 ] && echo "All post-deploy checks passed." || die "post-deploy checks failed. Do not use this deployment."
}

verify() {
  preflight
  forge script "$SCRIPT" --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --resume --verify --verifier blockscout --verifier-url "$EXPLORER_API"
}

deploy() {
  preflight; build
  if [ "${1:-}" != "-y" ]; then
    echo; echo "This sends real transactions to Ink Sepolia (a testnet). Type DEPLOY to continue:"
    read -r answer; [ "$answer" = "DEPLOY" ] || die "cancelled"
  fi
  local verify_flags=(--verify --verifier blockscout --verifier-url "$EXPLORER_API")
  [ "${SKIP_VERIFY:-}" = "1" ] && verify_flags=()   # only for rehearsals on a local fork
  if ! forge script "$SCRIPT" --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast --slow \
      ${verify_flags[@]+"${verify_flags[@]}"} -vvv; then
    echo "forge reported an error. If the contracts were broadcast, run ./deploy.sh verify to retry verification." >&2
  fi
  write_env
  set -a; . ./.env; set +a
  postcheck
}

case "${1:-}" in
  check)     preflight ;;
  simulate)  simulate ;;
  deploy)    deploy "${2:-}" ;;
  verify)    verify ;;
  env)       write_env ;;
  postcheck) postcheck ;;
  *) sed -n '2,12p' "$0"; exit 1 ;;
esac
