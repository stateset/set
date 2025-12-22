#!/bin/bash
# =============================================================================
# validate-devnet.sh
# Validate local Anvil devnet against config/chain-config.toml
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$ROOT_DIR/config/chain-config.toml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

RPC_URL="${RPC_URL:-http://localhost:8545}"
REQUIRE_CONTRACTS=false
SKIP_CONTRACTS=false

usage() {
    echo "Usage: $0 [--require-contracts] [--skip-contracts] [--rpc-url <url>]"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --require-contracts)
            REQUIRE_CONTRACTS=true
            ;;
        --skip-contracts)
            SKIP_CONTRACTS=true
            ;;
        --rpc-url)
            RPC_URL="$2"
            shift
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

log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

for cmd in curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Missing dependency: $cmd"
        exit 1
    fi
done

read_toml_value() {
    local section="$1"
    local key="$2"

    if [ ! -f "$CONFIG_FILE" ]; then
        return 0
    fi

    awk -v section="$section" -v key="$key" '
        $0 ~ "^[[:space:]]*\\[" {
            in_section = ($0 ~ "^[[:space:]]*\\[" section "\\][[:space:]]*$")
        }
        in_section && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            split($0, parts, "=")
            val = parts[2]
            sub(/#.*/, "", val)
            gsub(/[[:space:]]+/, "", val)
            gsub(/\"/, "", val)
            print val
            exit
        }
    ' "$CONFIG_FILE"
}

rpc_call() {
    local method="$1"
    local params="${2:-[]}"

    curl -sf "$RPC_URL" -X POST -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}"
}

CHAIN_ID_DEFAULT=84532001
BLOCK_TIME_DEFAULT=2
GAS_LIMIT_DEFAULT=30000000

EXPECTED_CHAIN_ID="$(read_toml_value chain chain_id)"
EXPECTED_BLOCK_TIME="$(read_toml_value block block_time)"
EXPECTED_GAS_LIMIT="$(read_toml_value block gas_limit)"

failures=0
warnings=0

if [ -z "$EXPECTED_CHAIN_ID" ]; then
    EXPECTED_CHAIN_ID="$CHAIN_ID_DEFAULT"
    log_warn "Missing chain.chain_id in $CONFIG_FILE; using default $EXPECTED_CHAIN_ID"
    warnings=$((warnings + 1))
fi

if [ -z "$EXPECTED_BLOCK_TIME" ]; then
    EXPECTED_BLOCK_TIME="$BLOCK_TIME_DEFAULT"
    log_warn "Missing block.block_time in $CONFIG_FILE; using default $EXPECTED_BLOCK_TIME"
    warnings=$((warnings + 1))
fi

if [ -z "$EXPECTED_GAS_LIMIT" ]; then
    EXPECTED_GAS_LIMIT="$GAS_LIMIT_DEFAULT"
    log_warn "Missing block.gas_limit in $CONFIG_FILE; using default $EXPECTED_GAS_LIMIT"
    warnings=$((warnings + 1))
fi

if ! chain_id_resp="$(rpc_call eth_chainId)"; then
    log_error "RPC not reachable at $RPC_URL"
    exit 1
fi

CHAIN_ID_HEX="$(echo "$chain_id_resp" | jq -r '.result')"
if [[ ! "$CHAIN_ID_HEX" =~ ^0x[0-9a-fA-F]+$ ]]; then
    log_error "Invalid chainId response: $CHAIN_ID_HEX"
    exit 1
fi
CHAIN_ID=$((CHAIN_ID_HEX))

if [ "$CHAIN_ID" -eq "$EXPECTED_CHAIN_ID" ]; then
    log_ok "Chain ID matches: $CHAIN_ID"
else
    log_error "Chain ID mismatch: expected $EXPECTED_CHAIN_ID, got $CHAIN_ID"
    failures=$((failures + 1))
fi

BLOCK_HEX="$(rpc_call eth_blockNumber | jq -r '.result')"
if [[ ! "$BLOCK_HEX" =~ ^0x[0-9a-fA-F]+$ ]]; then
    log_error "Invalid blockNumber response: $BLOCK_HEX"
    failures=$((failures + 1))
else
    BLOCK_NUMBER=$((BLOCK_HEX))
    BLOCK_JSON="$(rpc_call eth_getBlockByNumber "[\"$BLOCK_HEX\", false]")"
    GAS_LIMIT_HEX="$(echo "$BLOCK_JSON" | jq -r '.result.gasLimit')"

    if [[ "$GAS_LIMIT_HEX" =~ ^0x[0-9a-fA-F]+$ ]]; then
        GAS_LIMIT=$((GAS_LIMIT_HEX))
        if [ "$GAS_LIMIT" -eq "$EXPECTED_GAS_LIMIT" ]; then
            log_ok "Gas limit matches: $GAS_LIMIT"
        else
            log_error "Gas limit mismatch: expected $EXPECTED_GAS_LIMIT, got $GAS_LIMIT"
            failures=$((failures + 1))
        fi
    else
        log_error "Invalid gasLimit response: $GAS_LIMIT_HEX"
        failures=$((failures + 1))
    fi

    if [ "$BLOCK_NUMBER" -gt 0 ]; then
        PREV_BLOCK_HEX="$(printf "0x%x" $((BLOCK_NUMBER - 1)))"
        PREV_BLOCK_JSON="$(rpc_call eth_getBlockByNumber "[\"$PREV_BLOCK_HEX\", false]")"
        PREV_TS_HEX="$(echo "$PREV_BLOCK_JSON" | jq -r '.result.timestamp')"
        CURR_TS_HEX="$(echo "$BLOCK_JSON" | jq -r '.result.timestamp')"

        if [[ "$PREV_TS_HEX" =~ ^0x[0-9a-fA-F]+$ && "$CURR_TS_HEX" =~ ^0x[0-9a-fA-F]+$ ]]; then
            PREV_TS=$((PREV_TS_HEX))
            CURR_TS=$((CURR_TS_HEX))
            DELTA=$((CURR_TS - PREV_TS))
            LOWER=$((EXPECTED_BLOCK_TIME - 1))
            UPPER=$((EXPECTED_BLOCK_TIME + 1))

            if [ "$DELTA" -ge "$LOWER" ] && [ "$DELTA" -le "$UPPER" ]; then
                log_ok "Block time looks consistent: ${DELTA}s (expected ${EXPECTED_BLOCK_TIME}s)"
            else
                log_warn "Block time drift: ${DELTA}s (expected ~${EXPECTED_BLOCK_TIME}s)"
                warnings=$((warnings + 1))
            fi
        else
            log_warn "Could not read block timestamps for block time check"
            warnings=$((warnings + 1))
        fi
    else
        log_warn "Block number is 0; skipping block time check"
        warnings=$((warnings + 1))
    fi
fi

if [ "$SKIP_CONTRACTS" = true ]; then
    log_warn "Skipping contract checks"
else
    BROADCAST_FILE="$ROOT_DIR/contracts/broadcast/Deploy.s.sol/$CHAIN_ID/run-latest.json"

    if [ ! -f "$BROADCAST_FILE" ]; then
        log_warn "Deploy broadcast not found: $BROADCAST_FILE"
        warnings=$((warnings + 1))
    else
        PROXY_ADDRESSES="$(jq -r '.transactions[] | select(.contractName=="ERC1967Proxy") | .contractAddress' \
            "$BROADCAST_FILE")"
        REGISTRY_PROXY="$(echo "$PROXY_ADDRESSES" | sed -n '1p')"
        PAYMASTER_PROXY="$(echo "$PROXY_ADDRESSES" | sed -n '2p')"

        check_code() {
            local name="$1"
            local address="$2"
            local code

            if [ -z "$address" ]; then
                log_warn "$name proxy not found in $BROADCAST_FILE"
                warnings=$((warnings + 1))
                return
            fi

            code="$(rpc_call eth_getCode "[\"$address\", \"latest\"]" | jq -r '.result')"
            if [ "$code" = "0x" ]; then
                if [ "$REQUIRE_CONTRACTS" = true ]; then
                    log_error "$name not deployed at $address"
                    failures=$((failures + 1))
                else
                    log_warn "$name not deployed at $address"
                    warnings=$((warnings + 1))
                fi
            else
                log_ok "$name deployed at $address"
            fi
        }

        check_code "SetRegistry proxy" "$REGISTRY_PROXY"
        check_code "SetPaymaster proxy" "$PAYMASTER_PROXY"
    fi
fi

echo ""
if [ "$failures" -gt 0 ]; then
    log_error "Validation failed with $failures error(s) and $warnings warning(s)"
    exit 1
fi

log_ok "Validation complete with $warnings warning(s)"
