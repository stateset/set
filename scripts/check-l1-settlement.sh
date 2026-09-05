#!/bin/bash
# =============================================================================
# check-l1-settlement.sh
# Verify L1 settlement contracts exist and RPC is reachable
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE=""
MODE="devnet"
REQUIRE_ADDRESSES=false

usage() {
    echo "Usage: $0 [--env-file <path>] [--mode <devnet|testnet|production>] [--require-addresses]"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --env-file)
            ENV_FILE="$2"
            shift
            ;;
        --mode)
            MODE="$2"
            shift
            ;;
        --require-addresses)
            REQUIRE_ADDRESSES=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
    shift
 done

if [ -z "$ENV_FILE" ]; then
    if [ -f "$ROOT_DIR/config/sepolia.env" ]; then
        ENV_FILE="$ROOT_DIR/config/sepolia.env"
    else
        ENV_FILE="$ROOT_DIR/config/sepolia.env.example"
    fi
fi

if [ ! -f "$ENV_FILE" ]; then
    echo "Missing env file: $ENV_FILE"
    exit 1
fi

case "$MODE" in
    devnet|testnet|production)
        ;;
    *)
        echo "Invalid mode: $MODE"
        usage
        exit 1
        ;;
esac

log_ok() { echo "[OK] $1"; }
log_warn() { echo "[WARN] $1"; }
log_error() { echo "[ERROR] $1"; }

get_env_value() {
    local key="$1"
    local line
    line=$(grep -E "^${key}=" "$ENV_FILE" | tail -n 1 || true)
    if [ -z "$line" ]; then
        echo ""
        return
    fi
    echo "${line#*=}"
}

is_placeholder() {
    local value="$1"

    if [ -z "$value" ]; then
        return 0
    fi

    if [[ "$value" == 0x0000000000000000000000000000000000000000 ]]; then
        return 0
    fi

    if [[ "$value" == 0x0000000000000000000000000000000000000000000000000000000000000000 ]]; then
        return 0
    fi

    if [[ "$value" =~ ^0x0{39}[0-9a-fA-F]$ ]]; then
        return 0
    fi

    if [[ "$value" == *"YOUR_INFURA_KEY"* ]] || [[ "$value" == *"YOUR_ALCHEMY_KEY"* ]]; then
        return 0
    fi

    return 1
}

rpc_call() {
    local method="$1"
    local params="${2:-[]}";

    local response
    response=$(curl --connect-timeout 5 --max-time 20 -sf "$L1_RPC_URL" -X POST -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}") || return 1
    jq -er 'select(.jsonrpc == "2.0" and .id == 1 and (has("error") | not)) | .result | select(type == "string")' <<< "$response"
}

L1_RPC_URL="$(get_env_value "L1_RPC_URL")"
if is_placeholder "$L1_RPC_URL"; then
    log_error "L1_RPC_URL missing or placeholder in $ENV_FILE"
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    log_error "Missing dependency: curl"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    log_error "Missing dependency: jq"
    exit 1
fi

log_ok "Using env file: $ENV_FILE"
log_ok "Checking configured L1 RPC"

if ! chain_resp="$(rpc_call eth_chainId)"; then
    log_error "L1 RPC not reachable"
    exit 1
fi

chain_id_hex="$chain_resp"
expected_chain_id="$(get_env_value L1_CHAIN_ID)"
if [[ ! "$chain_id_hex" =~ ^0x[0-9a-fA-F]{1,13}$ ]] ||
   [[ ! "$expected_chain_id" =~ ^[1-9][0-9]{0,14}$ ]]; then
    log_error "Expected decimal L1_CHAIN_ID and valid RPC chain ID are required"
    exit 1
fi
if [ "$((chain_id_hex))" -ne "$expected_chain_id" ]; then
    log_error "L1 chain ID does not match L1_CHAIN_ID"
    exit 1
fi
log_ok "L1 chain ID: $chain_id_hex"

check_contract() {
    local key="$1"
    local label="$2"
    local address

    address="$(get_env_value "$key")"
    if is_placeholder "$address"; then
        if [ "$REQUIRE_ADDRESSES" = true ] || [ "$MODE" != "devnet" ]; then
            log_error "$label ($key) missing or placeholder"
            return 1
        fi
        log_warn "$label ($key) missing or placeholder"
        return
    fi

    if [[ ! "$address" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
        log_error "$label has an invalid address"
        return 1
    fi
    local code
    if ! code="$(rpc_call eth_getCode "[\"$address\", \"latest\"]")"; then
        log_error "$label bytecode RPC failed"
        return 1
    fi
    if [[ ! "$code" =~ ^0x([0-9a-fA-F]{2})+$ ]]; then
        log_error "$label bytecode is missing or malformed"
        return 1
    fi

    log_ok "$label deployed at $address"
}

errors=0
check_contract "OPTIMISM_PORTAL_ADDRESS" "OptimismPortal" || errors=$((errors + 1))
check_contract "L2_OUTPUT_ORACLE_ADDRESS" "L2OutputOracle" || errors=$((errors + 1))
check_contract "SYSTEM_CONFIG_ADDRESS" "SystemConfig" || errors=$((errors + 1))
check_contract "DISPUTE_GAME_FACTORY_ADDRESS" "DisputeGameFactory" || errors=$((errors + 1))

if [ "$errors" -gt 0 ]; then
    log_error "Settlement check failed with $errors error(s)"
    exit 1
fi

log_ok "Settlement chain ID and contract bytecode presence verified; identity, wiring and withdrawals require integration verification"
