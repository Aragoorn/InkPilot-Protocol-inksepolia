#!/usr/bin/env bash
# InkPilot governance helper for Ink Sepolia (763373). TESTNET ONLY.
# The factory is owned by the timelock, so every owner action must be scheduled, wait the delay (48h), then executed
# by an address that holds the timelock's proposer / executor roles.
#
#   ./governance.sh calldata <target> "<signature>" [args...]   show the call and the operation id (read-only)
#   ./governance.sh schedule <target> "<signature>" [args...]   queue it (needs PROPOSER role)
#   ./governance.sh status   <target> "<signature>" [args...]   pending / ready / done, and when
#   ./governance.sh execute  <target> "<signature>" [args...]   run it after the delay (needs EXECUTOR role)
#   ./governance.sh cancel   <target> "<signature>" [args...]   cancel it (needs CANCELLER role)
#   ./governance.sh roles    <address>                          which timelock roles an address holds
#
# Examples (FACTORY and TIMELOCK come from .env):
#   ./governance.sh schedule "$VITE_PILOT_FACTORY" "setGuardian(address)" 0xNEWGUARDIAN
#   ./governance.sh schedule "$VITE_PILOT_FACTORY" "upgradeToAndCall(address,bytes)" 0xNEWIMPLEMENTATION 0x
#   ./governance.sh schedule "$VITE_PILOT_TIMELOCK" "grantRole(bytes32,address)" "$(cast keccak PROPOSER_ROLE)" 0xNEWPROPOSER
# Set SALT=0x... to queue the same call twice.
set -euo pipefail
cd "$(dirname "$0")"
if [ -f .env ]; then set -a; . ./.env; set +a; fi
RPC="${INK_SEPOLIA_RPC_URL:-https://rpc-gel-sepolia.inkonchain.com}"
T="${VITE_PILOT_TIMELOCK:-}"
ZERO=0x0000000000000000000000000000000000000000000000000000000000000000
SALT="${SALT:-$ZERO}"
die() { echo "error: $*" >&2; exit 1; }
command -v cast >/dev/null || die "cast (Foundry) is required"
[ -n "$T" ] || die "VITE_PILOT_TIMELOCK is not set in .env"
[ "$(cast chain-id --rpc-url "$RPC")" = "763373" ] || die "RPC is not Ink Sepolia (763373). Refusing."

cmd="${1:-}"; shift || true
send() { [ -n "${PRIVATE_KEY:-}" ] || die "PRIVATE_KEY is empty in .env"; cast send "$T" "$@" --rpc-url "$RPC" --private-key "$PRIVATE_KEY"; }

if [ "$cmd" = "roles" ]; then
  who="${1:?address}"
  for r in PROPOSER_ROLE CANCELLER_ROLE EXECUTOR_ROLE; do
    echo "$r: $(cast call "$T" 'hasRole(bytes32,address)(bool)' "$(cast keccak "$r")" "$who" --rpc-url "$RPC")"
  done
  exit 0
fi

target="${1:?target}"; sig="${2:?signature}"; shift 2 || true
data="$(cast calldata "$sig" "$@")"
id="$(cast call "$T" 'hashOperation(address,uint256,bytes,bytes32,bytes32)(bytes32)' "$target" 0 "$data" "$ZERO" "$SALT" --rpc-url "$RPC")"
delay="$(cast call "$T" 'getMinDelay()(uint256)' --rpc-url "$RPC" | awk '{print $1}')"

case "$cmd" in
  calldata) echo "target   : $target"; echo "data     : $data"; echo "salt     : $SALT"; echo "id       : $id"; echo "delay    : ${delay}s" ;;
  schedule) send 'schedule(address,uint256,bytes,bytes32,bytes32,uint256)' "$target" 0 "$data" "$ZERO" "$SALT" "$delay"
            echo "Scheduled $id. It can be executed in $((delay / 3600)) hours." ;;
  status)   echo "id       : $id"
            echo "pending  : $(cast call "$T" 'isOperationPending(bytes32)(bool)' "$id" --rpc-url "$RPC")"
            echo "ready    : $(cast call "$T" 'isOperationReady(bytes32)(bool)' "$id" --rpc-url "$RPC")"
            echo "done     : $(cast call "$T" 'isOperationDone(bytes32)(bool)' "$id" --rpc-url "$RPC")"
            ts="$(cast call "$T" 'getTimestamp(bytes32)(uint256)' "$id" --rpc-url "$RPC" | awk '{print $1}')"
            [ "$ts" -gt 1 ] && echo "ready at : $(date -u -d "@$ts" 2>/dev/null || echo "unix $ts")" || true ;;
  execute)  send 'execute(address,uint256,bytes,bytes32,bytes32)' "$target" 0 "$data" "$ZERO" "$SALT" ;;
  cancel)   send 'cancel(bytes32)' "$id" ;;
  *) sed -n '2,24p' "$0"; exit 1 ;;
esac
