#!/bin/bash
# =============================================================================
# anchor-devnet.sh
# Helper for running the anchor service against local Anvil devnet
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ANCHOR_DIR="$ROOT_DIR/anchor"
MOCK_SCRIPT="$SCRIPT_DIR/mock-sequencer.py"

DEFAULT_RPC_URL="http://localhost:8545"
DEFAULT_SEQUENCER_KEY="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
DEFAULT_SEQUENCER_ADDR="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"

load_env() {
    if [ -f "$ROOT_DIR/config/local.env" ]; then
        set -a
        # shellcheck disable=SC1090
        . "$ROOT_DIR/config/local.env"
        set +a
    fi
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing dependency: $1"
        exit 1
    fi
}

python_cmd() {
    if command -v python3 >/dev/null 2>&1; then
        echo "python3"
        return
    fi
    if command -v python >/dev/null 2>&1; then
        echo "python"
        return
    fi
    echo ""
}

get_chain_id() {
    curl -sf "$L2_RPC_URL" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
        | jq -r '.result' | xargs printf "%d"
}

get_registry_address() {
    if [ -n "${SET_REGISTRY_ADDRESS:-}" ]; then
        echo "$SET_REGISTRY_ADDRESS"
        return
    fi

    require_cmd jq
    require_cmd curl

    local chain_id
    chain_id="$(get_chain_id)"
    local broadcast_file="$ROOT_DIR/contracts/broadcast/Deploy.s.sol/$chain_id/run-latest.json"

    if [ ! -f "$broadcast_file" ]; then
        echo ""
        return
    fi

    jq -r '.transactions[] | select(.contractName=="ERC1967Proxy") | .contractAddress' \
        "$broadcast_file" | sed -n '1p'
}

anchor_command() {
    if [ -n "${ANCHOR_BIN:-}" ] && [ -x "$ANCHOR_BIN" ]; then
        echo "$ANCHOR_BIN"
        return
    fi

    if [ -x "$ANCHOR_DIR/target/release/set-anchor" ]; then
        echo "$ANCHOR_DIR/target/release/set-anchor"
        return
    fi

    if [ -x "$ANCHOR_DIR/target/debug/set-anchor" ]; then
        echo "$ANCHOR_DIR/target/debug/set-anchor"
        return
    fi

    echo "cargo run --manifest-path $ANCHOR_DIR/Cargo.toml --bin set-anchor"
}

start_mock_sequencer() {
    local port="$1"
    local py
    py="$(python_cmd)"
    if [ -z "$py" ]; then
        echo "Python not found (python3 or python required)."
        exit 1
    fi

    require_cmd curl

    if [ ! -f "$MOCK_SCRIPT" ]; then
        echo "Mock sequencer script not found: $MOCK_SCRIPT"
        exit 1
    fi

    "$py" "$MOCK_SCRIPT" --port "$port" >/tmp/mock-sequencer.log 2>&1 &
    MOCK_PID=$!

    for _ in $(seq 1 30); do
        if curl -sf "http://localhost:$port/health" >/dev/null 2>&1; then
            return
        fi
        sleep 1
    done

    echo "Mock sequencer failed to start on port $port."
    tail -n 200 /tmp/mock-sequencer.log || true
    exit 1
}

start_anchor_background() {
    local cmd
    cmd="$(anchor_command)"
    bash -c "$cmd" >/tmp/set-anchor.log 2>&1 &
    ANCHOR_PID=$!
}

run_anchor_foreground() {
    local cmd
    cmd="$(anchor_command)"
    bash -c "$cmd"
}

cleanup() {
    if [ -n "${ANCHOR_PID:-}" ]; then
        kill "$ANCHOR_PID" >/dev/null 2>&1 || true
    fi
    if [ -n "${MOCK_PID:-}" ]; then
        kill "$MOCK_PID" >/dev/null 2>&1 || true
    fi
}

cmd_start() {
    local use_mock=true
    local mock_port="${MOCK_SEQUENCER_PORT:-3001}"

    while [ $# -gt 0 ]; do
        case "$1" in
            --no-mock)
                use_mock=false
                ;;
            --mock-port)
                mock_port="$2"
                shift
                ;;
            *)
                echo "Unknown argument: $1"
                exit 1
                ;;
        esac
        shift
    done

    L2_RPC_URL="${L2_RPC_URL:-${RPC_URL:-$DEFAULT_RPC_URL}}"
    SEQUENCER_PRIVATE_KEY="${SEQUENCER_PRIVATE_KEY:-$DEFAULT_SEQUENCER_KEY}"
    SEQUENCER_ADDRESS="${SEQUENCER_ADDRESS:-$DEFAULT_SEQUENCER_ADDR}"
    ANCHOR_INTERVAL_SECS="${ANCHOR_INTERVAL_SECS:-5}"
    MIN_EVENTS_FOR_ANCHOR="${MIN_EVENTS_FOR_ANCHOR:-1}"
    HEALTH_PORT="${HEALTH_PORT:-9090}"

    SET_REGISTRY_ADDRESS="$(get_registry_address)"
    if [ -z "$SET_REGISTRY_ADDRESS" ]; then
        echo "SET_REGISTRY_ADDRESS not found. Run: ./scripts/dev.sh deploy"
        exit 1
    fi

    export L2_RPC_URL
    export SEQUENCER_PRIVATE_KEY
    export SEQUENCER_ADDRESS
    export SET_REGISTRY_ADDRESS
    export ANCHOR_INTERVAL_SECS
    export MIN_EVENTS_FOR_ANCHOR
    export HEALTH_PORT

    if [ "$use_mock" = true ]; then
        export SEQUENCER_API_URL="${SEQUENCER_API_URL:-http://localhost:$mock_port}"
        start_mock_sequencer "$mock_port"
    fi

    trap cleanup EXIT INT TERM
    run_anchor_foreground
}

cmd_smoke() {
    local mock_port="${MOCK_SEQUENCER_PORT:-3001}"
    local health_port="${HEALTH_PORT:-9091}"
    local max_wait="${ANCHOR_SMOKE_TIMEOUT_SECS:-20}"

    L2_RPC_URL="${L2_RPC_URL:-${RPC_URL:-$DEFAULT_RPC_URL}}"
    SEQUENCER_PRIVATE_KEY="${SEQUENCER_PRIVATE_KEY:-$DEFAULT_SEQUENCER_KEY}"
    SEQUENCER_ADDRESS="${SEQUENCER_ADDRESS:-$DEFAULT_SEQUENCER_ADDR}"
    ANCHOR_INTERVAL_SECS=1
    MIN_EVENTS_FOR_ANCHOR=1

    export L2_RPC_URL
    export SEQUENCER_PRIVATE_KEY
    export SEQUENCER_ADDRESS
    export ANCHOR_INTERVAL_SECS
    export MIN_EVENTS_FOR_ANCHOR
    export HEALTH_PORT="$health_port"
    export SEQUENCER_API_URL="http://localhost:$mock_port"
    export MOCK_EVENT_COUNT=1

    require_cmd curl
    require_cmd jq

    RPC_URL="$L2_RPC_URL" "$SCRIPT_DIR/dev.sh" deploy

    SET_REGISTRY_ADDRESS="$(get_registry_address)"
    if [ -z "$SET_REGISTRY_ADDRESS" ]; then
        echo "SET_REGISTRY_ADDRESS not found after deployment."
        exit 1
    fi
    export SET_REGISTRY_ADDRESS

    local cast_cmd=()
    if command -v cast >/dev/null 2>&1; then
        cast_cmd=(cast)
    elif command -v docker >/dev/null 2>&1; then
        cast_cmd=(docker run --rm --network=host ghcr.io/foundry-rs/foundry:stable cast)
    else
        echo "cast not found. Install Foundry or use Docker."
        exit 1
    fi

    local before after
    before=$("${cast_cmd[@]}" call "$SET_REGISTRY_ADDRESS" \
        "totalCommitments()(uint256)" --rpc-url "$L2_RPC_URL" | tr -d '\r\n ')

    start_mock_sequencer "$mock_port"
    trap cleanup EXIT INT TERM
    start_anchor_background

    for _ in $(seq 1 10); do
        if curl -sf "http://localhost:$health_port/health" >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done

    local waited=0
    while [ "$waited" -lt "$max_wait" ]; do
        after=$("${cast_cmd[@]}" call "$SET_REGISTRY_ADDRESS" \
            "totalCommitments()(uint256)" --rpc-url "$L2_RPC_URL" | tr -d '\r\n ')

        if [ "$after" != "$before" ]; then
            echo "Anchor smoke succeeded: totalCommitments $before -> $after"
            return
        fi

        sleep 1
        waited=$((waited + 1))
    done

    echo "Anchor smoke timed out after ${max_wait}s."
    if [ -f /tmp/set-anchor.log ]; then
        tail -n 200 /tmp/set-anchor.log || true
    fi
    exit 1
}

usage() {
    echo "Usage: $0 <start|smoke> [options]"
    echo "  start [--no-mock] [--mock-port <port>]"
    echo "  smoke"
}

main() {
    load_env

    case "${1:-}" in
        start)
            shift
            cmd_start "$@"
            ;;
        smoke)
            shift
            cmd_smoke "$@"
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
