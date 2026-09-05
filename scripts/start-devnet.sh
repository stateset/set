#!/bin/bash
# Set Chain - Start Local Devnet
# Legacy local-only launcher; not a complete fault-proof rollup deployment

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SEQUENCER_DIR="$PROJECT_DIR/op-stack/sequencer"

echo "=== Set Chain Local Devnet ==="
echo ""

# Log directory
LOG_DIR="$PROJECT_DIR/logs"

# PID file directory
PID_DIR="$PROJECT_DIR/.pids"
PROCESS_PYTHON="${LOCAL_ROLLUP_PYTHON:-python3}"
source "$SCRIPT_DIR/local-lifecycle.sh"
STARTED_COMPONENTS=()

rollback_failed_start() {
    local result=$?
    if [ "$result" -ne 0 ] && [ "${#STARTED_COMPONENTS[@]}" -gt 0 ]; then
        echo "Startup failed; stopping only identity-verified components from this attempt." >&2
        local index
        for ((index=${#STARTED_COMPONENTS[@]}-1; index>=0; index--)); do
            "$PROCESS_PYTHON" "$SCRIPT_DIR/local-process.py" stop "${STARTED_COMPONENTS[$index]}" || \
                echo "Ownership record retained for review: ${STARTED_COMPONENTS[$index]}" >&2
        done
    fi
    return "$result"
}

# Check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."

    # Never infer permission for a public network from a command called devnet.
    local env_file="$PROJECT_DIR/config/local-rollup.env"
    if [ ! -f "$env_file" ]; then
        echo "Error: config/local-rollup.env is required; Sepolia configuration is never loaded."
        exit 1
    fi
    # Do not inherit public-network endpoints or signing keys from the shell.
    unset L1_RPC_URL L1_BEACON_URL L1_CHAIN_ID L2_CHAIN_ID
    unset BATCHER_PRIVATE_KEY PROPOSER_PRIVATE_KEY L2_OUTPUT_ORACLE_ADDRESS
    source "$env_file"
    "$PROCESS_PYTHON" "$SCRIPT_DIR/local-process.py" check
    : "${L1_RPC_URL:?Local execution endpoint required}"
    : "${L1_BEACON_URL:?Local beacon endpoint required}"
    : "${L1_CHAIN_ID:?Local L1 chain ID required}"
    : "${L2_CHAIN_ID:?Local L2 chain ID required}"

    # Check genesis exists
    if [ ! -f "$SEQUENCER_DIR/op-geth/genesis.json" ]; then
        echo "Error: local genesis.json missing. See docs/l2-readiness-gaps.md; do not use Sepolia artifacts."
        exit 1
    fi

    # Check rollup config exists
    if [ ! -f "$SEQUENCER_DIR/op-node/rollup.json" ]; then
        echo "Error: local rollup.json missing. See docs/l2-readiness-gaps.md; do not use Sepolia artifacts."
        exit 1
    fi

    # Check JWT secret exists
    if [ ! -f "$SEQUENCER_DIR/op-geth/jwt.txt" ]; then
        echo "Error: local Engine JWT missing; provision a dedicated local secret."
        exit 1
    fi

    # Check binaries
    for binary in op-geth op-node; do
        if ! command -v $binary &> /dev/null; then
            echo "Error: $binary not found. A compatible pinned local toolchain is required."
            exit 1
        fi
    done
    if [ -n "${BATCHER_PRIVATE_KEY:-}" ] && [[ "$BATCHER_PRIVATE_KEY" != "0x00000"* ]]; then
        command -v op-batcher >/dev/null || { echo "Error: configured batcher binary missing."; exit 1; }
    fi
    if [ -n "${PROPOSER_PRIVATE_KEY:-}" ] && [[ "$PROPOSER_PRIVATE_KEY" != "0x00000"* ]] && \
       [ -n "${L2_OUTPUT_ORACLE_ADDRESS:-}" ]; then
        command -v op-proposer >/dev/null || { echo "Error: configured proposer binary missing."; exit 1; }
    fi

    python3 "$SCRIPT_DIR/validate-rollup-config.py" \
        --genesis "$SEQUENCER_DIR/op-geth/genesis.json" \
        --rollup "$SEQUENCER_DIR/op-node/rollup.json" \
        --l1-chain-id "$L1_CHAIN_ID" --l2-chain-id "$L2_CHAIN_ID"
    python3 "$SCRIPT_DIR/validate-local-l1.py" \
        --execution "$L1_RPC_URL" --beacon "$L1_BEACON_URL" \
        --chain-id "$L1_CHAIN_ID" --rollup "$SEQUENCER_DIR/op-node/rollup.json"

    acquire_local_lifecycle_lock
    # Ownership checks run while the shared start/stop lock is held.
    for component in op-geth op-node op-batcher op-proposer; do
        if [ -e "$PID_DIR/$component.pid" ] || [ -L "$PID_DIR/$component.pid" ] || \
           [ -e "$PID_DIR/$component.identity.json" ] || [ -L "$PID_DIR/$component.identity.json" ]; then
            echo "Error: existing $component PID file; verify ownership and stop it explicitly before starting."
            exit 1
        fi
    done
    mkdir -p "$LOG_DIR" "$PID_DIR"
    cd "$PROJECT_DIR"

    echo "Prerequisites OK"
}

# Start op-geth
start_op_geth() {
    echo ""
    echo "Starting op-geth (execution client)..."

    local data_dir="$SEQUENCER_DIR/op-geth/data"
    local jwt_file="$SEQUENCER_DIR/op-geth/jwt.txt"

    op-geth \
        --datadir "$data_dir" \
        --networkid "$L2_CHAIN_ID" \
        --http \
        --http.addr 127.0.0.1 \
        --http.port 8547 \
        --http.api eth,net,web3 \
        --http.vhosts localhost,127.0.0.1 \
        --ws \
        --ws.addr 127.0.0.1 \
        --ws.port 8548 \
        --ws.api eth,net,web3 \
        --authrpc.addr 127.0.0.1 \
        --authrpc.port 8551 \
        --authrpc.jwtsecret "$jwt_file" \
        --authrpc.vhosts localhost,127.0.0.1 \
        --rollup.disabletxpoolgossip=true \
        --gcmode archive \
        --nodiscover \
        --maxpeers 0 \
        --verbosity 3 \
        9>&- > "$LOG_DIR/op-geth.log" 2>&1 &

    echo $! > "$PID_DIR/op-geth.pid"
    STARTED_COMPONENTS+=(op-geth)
    "$PROCESS_PYTHON" "$SCRIPT_DIR/local-process.py" record op-geth
    echo "  PID: $(cat "$PID_DIR/op-geth.pid")"
    echo "  RPC: http://localhost:8547"
    echo "  WS:  ws://localhost:8548"
    echo "  Engine: http://localhost:8551"
    echo "  Log: $LOG_DIR/op-geth.log"

    echo "  Checking execution RPC identity..."
    "$PROCESS_PYTHON" "$SCRIPT_DIR/check-local-rpc-ready.py" \
        --execution http://127.0.0.1:8547 --config "$SEQUENCER_DIR/op-node/rollup.json"
    "$PROCESS_PYTHON" "$SCRIPT_DIR/local-process.py" status op-geth
}

# Start op-node
start_op_node() {
    echo ""
    echo "Starting op-node (consensus client)..."

    local rollup_config="$SEQUENCER_DIR/op-node/rollup.json"
    local jwt_file="$SEQUENCER_DIR/op-geth/jwt.txt"
    local p2p_key="$SEQUENCER_DIR/op-node/p2p-node-key.txt"

    op-node \
        --l1 "$L1_RPC_URL" \
        --l1.beacon "$L1_BEACON_URL" \
        --l2 http://localhost:8551 \
        --l2.jwt-secret "$jwt_file" \
        --rollup.config "$rollup_config" \
        --rpc.addr 127.0.0.1 \
        --rpc.port 9545 \
        --p2p.disable \
        --sequencer.enabled \
        --sequencer.l1-confs 0 \
        --verifier.l1-confs 0 \
        --log.level info \
        9>&- > "$LOG_DIR/op-node.log" 2>&1 &

    echo $! > "$PID_DIR/op-node.pid"
    STARTED_COMPONENTS+=(op-node)
    "$PROCESS_PYTHON" "$SCRIPT_DIR/local-process.py" record op-node
    echo "  PID: $(cat "$PID_DIR/op-node.pid")"
    echo "  RPC: http://localhost:9545"
    echo "  Log: $LOG_DIR/op-node.log"

    echo "  Checking rollup RPC configuration and execution head agreement..."
    "$PROCESS_PYTHON" "$SCRIPT_DIR/check-local-rpc-ready.py" \
        --execution http://127.0.0.1:8547 --rollup-rpc http://127.0.0.1:9545 \
        --config "$SEQUENCER_DIR/op-node/rollup.json"
    "$PROCESS_PYTHON" "$SCRIPT_DIR/local-process.py" status op-node
}

# Start op-batcher (optional for devnet)
start_op_batcher() {
    echo ""
    echo "Starting op-batcher (batch submitter)..."

    if [ -z "${BATCHER_PRIVATE_KEY:-}" ] || [[ "$BATCHER_PRIVATE_KEY" == "0x00000"* ]]; then
        echo "  Skipping: BATCHER_PRIVATE_KEY not configured"
        return
    fi

    op-batcher \
        --l1-eth-rpc "$L1_RPC_URL" \
        --l2-eth-rpc http://localhost:8547 \
        --rollup-rpc http://localhost:9545 \
        --private-key "$BATCHER_PRIVATE_KEY" \
        --poll-interval 1s \
        --sub-safety-margin 6 \
        --num-confirmations 1 \
        --safe-abort-nonce-too-low-count 3 \
        --log.level info \
        9>&- > "$LOG_DIR/op-batcher.log" 2>&1 &

    echo $! > "$PID_DIR/op-batcher.pid"
    STARTED_COMPONENTS+=(op-batcher)
    "$PROCESS_PYTHON" "$SCRIPT_DIR/local-process.py" record op-batcher
    echo "  PID: $(cat "$PID_DIR/op-batcher.pid")"
    echo "  Log: $LOG_DIR/op-batcher.log"
}

# Start op-proposer (optional for devnet)
start_op_proposer() {
    echo ""
    echo "Starting op-proposer (state proposer)..."

    if [ -z "${PROPOSER_PRIVATE_KEY:-}" ] || [[ "$PROPOSER_PRIVATE_KEY" == "0x00000"* ]]; then
        echo "  Skipping: PROPOSER_PRIVATE_KEY not configured"
        return
    fi

    if [ -z "${L2_OUTPUT_ORACLE_ADDRESS:-}" ]; then
        echo "  Skipping: L2_OUTPUT_ORACLE_ADDRESS not configured"
        return
    fi

    op-proposer \
        --l1-eth-rpc "$L1_RPC_URL" \
        --rollup-rpc http://localhost:9545 \
        --private-key "$PROPOSER_PRIVATE_KEY" \
        --l2oo-address "$L2_OUTPUT_ORACLE_ADDRESS" \
        --poll-interval 12s \
        --log.level info \
        9>&- > "$LOG_DIR/op-proposer.log" 2>&1 &

    echo $! > "$PID_DIR/op-proposer.pid"
    STARTED_COMPONENTS+=(op-proposer)
    "$PROCESS_PYTHON" "$SCRIPT_DIR/local-process.py" record op-proposer
    echo "  PID: $(cat "$PID_DIR/op-proposer.pid")"
    echo "  Log: $LOG_DIR/op-proposer.log"
}

# Check status
check_status() {
    echo ""
    echo "=== Devnet Status ==="
    local component errors=0
    for component in op-geth op-node op-batcher op-proposer; do
        if [ -e "$PID_DIR/$component.pid" ] || [ -L "$PID_DIR/$component.pid" ] || \
           [ -e "$PID_DIR/$component.identity.json" ] || [ -L "$PID_DIR/$component.identity.json" ]; then
            "$PROCESS_PYTHON" "$SCRIPT_DIR/local-process.py" status "$component" || errors=$((errors + 1))
        else
            echo "  $component: NOT STARTED"
            if [ "$component" = op-geth ] || [ "$component" = op-node ]; then
                errors=$((errors + 1))
            fi
        fi
    done
    [ "$errors" -eq 0 ]
}

# Print usage info
print_usage() {
    echo ""
    echo "=== Legacy local launcher finished; settlement is not certified ==="
    echo ""
    echo "RPC Endpoints:"
    echo "  L2 HTTP RPC:  http://localhost:8547"
    echo "  L2 WS RPC:    ws://localhost:8548"
    echo "  Rollup RPC:   http://localhost:9545"
    echo ""
    echo "Useful commands:"
    echo "  # Check L2 block number"
    echo "  cast block-number --rpc-url http://localhost:8547"
    echo ""
    echo "  # Get L2 chain ID"
    echo "  cast chain-id --rpc-url http://localhost:8547"
    echo ""
    echo "  # View logs"
    echo "  tail -f $LOG_DIR/op-geth.log"
    echo "  tail -f $LOG_DIR/op-node.log"
    echo ""
    echo "  # Stop devnet"
    echo "  ./scripts/stop-devnet.sh"
    echo ""
}

# Main
main() {
    case "${1:-start}" in
        start)
            trap rollback_failed_start EXIT
            trap 'exit 130' INT
            trap 'exit 143' TERM
            check_prerequisites
            start_op_geth
            start_op_node
            start_op_batcher
            start_op_proposer
            check_status
            print_usage
            ;;
        status)
            check_status
            ;;
        *)
            echo "Usage: $0 [start|status]"
            exit 1
            ;;
    esac
}

main "$@"
