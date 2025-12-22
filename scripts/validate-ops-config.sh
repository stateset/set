#!/bin/bash
# =============================================================================
# validate-ops-config.sh
# Validate Set Chain operational config for testnet/production readiness
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CHAIN_CONFIG="$ROOT_DIR/config/chain-config.toml"
ENV_FILE=""
MODE="devnet"
REQUIRE_FAULT_PROOFS=false
REQUIRE_ADMIN_POLICY=false

usage() {
    echo "Usage: $0 [--env-file <path>] [--mode <devnet|testnet|production>]"
    echo "          [--require-fault-proofs] [--require-admin-policy]"
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
        --require-fault-proofs)
            REQUIRE_FAULT_PROOFS=true
            ;;
        --require-admin-policy)
            REQUIRE_ADMIN_POLICY=true
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

errors=0
warnings=0

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

require_value() {
    local key="$1"
    local label="$2"
    local value

    value="$(get_env_value "$key")"
    if is_placeholder "$value"; then
        if [ "$MODE" = "production" ] || [ "$MODE" = "testnet" ]; then
            log_error "$label ($key) missing or placeholder in $ENV_FILE"
            errors=$((errors + 1))
        else
            log_warn "$label ($key) missing or placeholder in $ENV_FILE"
            warnings=$((warnings + 1))
        fi
        return
    fi

    log_ok "$label ($key) set"
}

read_toml_value() {
    local section="$1"
    local key="$2"

    if [ ! -f "$CHAIN_CONFIG" ]; then
        echo ""
        return
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
    ' "$CHAIN_CONFIG"
}

log_ok "Validating config: $ENV_FILE"
log_ok "Mode: $MODE"

require_value "L1_RPC_URL" "L1 RPC URL"
require_value "L1_BEACON_URL" "L1 beacon URL"
require_value "L2_RPC_URL" "L2 RPC URL"
require_value "ADMIN_ADDRESS" "Admin address"
require_value "DEPLOYER_ADDRESS" "Deployer address"
require_value "SEQUENCER_ADDRESS" "Sequencer address"
require_value "BATCHER_ADDRESS" "Batcher address"
require_value "PROPOSER_ADDRESS" "Proposer address"
require_value "JWT_SECRET" "JWT secret"

if [ "$MODE" = "production" ] || [ "$MODE" = "testnet" ]; then
    require_value "DEPLOYER_PRIVATE_KEY" "Deployer private key"
    require_value "BATCHER_PRIVATE_KEY" "Batcher private key"
    require_value "PROPOSER_PRIVATE_KEY" "Proposer private key"
    require_value "SEQUENCER_PRIVATE_KEY" "Sequencer private key"
    require_value "CHALLENGER_PRIVATE_KEY" "Challenger private key"
fi

if [ "$REQUIRE_FAULT_PROOFS" = true ]; then
    require_value "DISPUTE_GAME_FACTORY_ADDRESS" "Dispute game factory"
    require_value "CHALLENGER_ADDRESS" "Challenger address"
    require_value "CHALLENGER_PRIVATE_KEY" "Challenger private key"
fi

if [ "$REQUIRE_ADMIN_POLICY" = true ]; then
    require_value "UPGRADE_MULTISIG_ADDRESS" "Upgrade multisig"
    require_value "UPGRADE_TIMELOCK_ADDRESS" "Upgrade timelock"
    require_value "UPGRADE_TIMELOCK_DELAY_SECS" "Timelock delay"
    require_value "PAUSE_GUARDIAN_ADDRESS" "Pause guardian"

    admin_addr="$(get_env_value "ADMIN_ADDRESS")"
    timelock_addr="$(get_env_value "UPGRADE_TIMELOCK_ADDRESS")"
    if ! is_placeholder "$admin_addr" && ! is_placeholder "$timelock_addr"; then
        if [ "${admin_addr,,}" != "${timelock_addr,,}" ]; then
            log_warn "ADMIN_ADDRESS should point at the timelock for production"
            warnings=$((warnings + 1))
        fi
    fi
fi

p2p_enabled="$(read_toml_value sequencer p2p_enabled)"
l1_confs="$(read_toml_value sequencer l1_confs)"

if [ -n "$p2p_enabled" ]; then
    if [ "$MODE" = "production" ] && [ "$p2p_enabled" != "true" ]; then
        log_error "config/chain-config.toml: sequencer.p2p_enabled should be true for production"
        errors=$((errors + 1))
    fi
    if [ "$MODE" = "testnet" ] && [ "$p2p_enabled" != "true" ]; then
        log_warn "config/chain-config.toml: sequencer.p2p_enabled is false"
        warnings=$((warnings + 1))
    fi
else
    log_warn "config/chain-config.toml missing sequencer.p2p_enabled"
    warnings=$((warnings + 1))
fi

if [ -n "$l1_confs" ]; then
    if [ "$MODE" = "production" ] && [ "$l1_confs" -lt 1 ]; then
        log_error "config/chain-config.toml: sequencer.l1_confs should be >= 1 for production"
        errors=$((errors + 1))
    fi
    if [ "$MODE" = "testnet" ] && [ "$l1_confs" -lt 1 ]; then
        log_warn "config/chain-config.toml: sequencer.l1_confs is < 1"
        warnings=$((warnings + 1))
    fi
else
    log_warn "config/chain-config.toml missing sequencer.l1_confs"
    warnings=$((warnings + 1))
fi

echo ""
if [ "$errors" -gt 0 ]; then
    log_error "Validation failed with $errors error(s) and $warnings warning(s)"
    exit 1
fi

log_ok "Validation complete with $warnings warning(s)"
