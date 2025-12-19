#!/bin/bash
# Set Chain - Start Local Devnet
# Starts all OP Stack components for local development

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SEQUENCER_DIR="$PROJECT_DIR/op-stack/sequencer"

echo "=== Set Chain Local Devnet ==="
echo ""

# Load environment
if [ -f "$PROJECT_DIR/config/sepolia.env" ]; then
    source "$PROJECT_DIR/config/sepolia.env"
else
    echo "Error: sepolia.env not found"
    exit 1
fi

# Log directory
LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"

# PID file directory
PID_DIR="$PROJECT_DIR/.pids"
mkdir -p "$PID_DIR"

# Check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."

    # Check genesis exists
    if [ ! -f "$SEQUENCER_DIR/op-geth/genesis.json" ]; then
        echo "Error: genesis.json not found. Run generate-genesis.sh first."
        exit 1
    fi

    # Check rollup config exists
    if [ ! -f "$SEQUENCER_DIR/op-node/rollup.json" ]; then
        echo "Error: rollup.json not found. Run generate-genesis.sh first."
        exit 1
    fi

    # Check JWT secret exists
    if [ ! -f "$SEQUENCER_DIR/op-geth/jwt.txt" ]; then
        echo "Error: jwt.txt not found. Run generate-genesis.sh first."
        exit 1
    fi

    # Check binaries
    for binary in op-geth op-node; do
        if ! command -v $binary &> /dev/null; then
            echo "Error: $binary not found. Run install-op-stack.sh first."
            exit 1
        fi
    done

    echo "Prerequisites OK"
}

# Start op-geth
start_op_geth() {
    echo ""
    echo "Starting op-geth (execution client)..."

    local data_dir="$SEQUENCER_DIR/op-geth/data"
    local jwt_file="$SEQUENCER_DIR/op-geth/jwt.txt"

    # Stop existing if running
    if [ -f "$PID_DIR/op-geth.pid" ]; then
        local pid=$(cat "$PID_DIR/op-geth.pid")
        kill "$pid" 2>/dev/null || true
        rm "$PID_DIR/op-geth.pid"
    fi

    op-geth \
        --datadir "$data_dir" \
        --networkid "$L2_CHAIN_ID" \
        --http \
        --http.addr 0.0.0.0 \
        --http.port 8547 \
        --http.api eth,net,web3,debug,txpool,engine \
        --http.corsdomain "*" \
        --http.vhosts "*" \
        --ws \
        --ws.addr 0.0.0.0 \
        --ws.port 8548 \
        --ws.api eth,net,web3,debug,txpool,engine \
        --ws.origins "*" \
        --authrpc.addr 0.0.0.0 \
        --authrpc.port 8551 \
        --authrpc.jwtsecret "$jwt_file" \
        --authrpc.vhosts "*" \
        --rollup.disabletxpoolgossip=true \
        --gcmode archive \
        --nodiscover \
        --maxpeers 0 \
        --verbosity 3 \
        > "$LOG_DIR/op-geth.log" 2>&1 &

    echo $! > "$PID_DIR/op-geth.pid"
    echo "  PID: $(cat "$PID_DIR/op-geth.pid")"
    echo "  RPC: http://localhost:8547"
    echo "  WS:  ws://localhost:8548"
    echo "  Engine: http://localhost:8551"
    echo "  Log: $LOG_DIR/op-geth.log"

    # Wait for op-geth to start
    echo "  Waiting for op-geth to start..."
    sleep 5
}

# Start op-node
start_op_node() {
    echo ""
    echo "Starting op-node (consensus client)..."

    local rollup_config="$SEQUENCER_DIR/op-node/rollup.json"
    local jwt_file="$SEQUENCER_DIR/op-geth/jwt.txt"
    local p2p_key="$SEQUENCER_DIR/op-node/p2p-node-key.txt"

    # Stop existing if running
    if [ -f "$PID_DIR/op-node.pid" ]; then
        local pid=$(cat "$PID_DIR/op-node.pid")
        kill "$pid" 2>/dev/null || true
        rm "$PID_DIR/op-node.pid"
    fi

    op-node \
        --l1 "$L1_RPC_URL" \
        --l1.beacon "$L1_BEACON_URL" \
        --l2 http://localhost:8551 \
        --l2.jwt-secret "$jwt_file" \
        --rollup.config "$rollup_config" \
        --rpc.addr 0.0.0.0 \
        --rpc.port 9545 \
        --p2p.disable \
        --sequencer.enabled \
        --sequencer.l1-confs 0 \
        --verifier.l1-confs 0 \
        --log.level info \
        > "$LOG_DIR/op-node.log" 2>&1 &

    echo $! > "$PID_DIR/op-node.pid"
    echo "  PID: $(cat "$PID_DIR/op-node.pid")"
    echo "  RPC: http://localhost:9545"
    echo "  Log: $LOG_DIR/op-node.log"

    # Wait for op-node to start
    echo "  Waiting for op-node to start..."
    sleep 5
}

# Start op-batcher (optional for devnet)
start_op_batcher() {
    echo ""
    echo "Starting op-batcher (batch submitter)..."

    if [ -z "$BATCHER_PRIVATE_KEY" ] || [[ "$BATCHER_PRIVATE_KEY" == "0x00000"* ]]; then
        echo "  Skipping: BATCHER_PRIVATE_KEY not configured"
        return
    fi

    # Stop existing if running
    if [ -f "$PID_DIR/op-batcher.pid" ]; then
        local pid=$(cat "$PID_DIR/op-batcher.pid")
        kill "$pid" 2>/dev/null || true
        rm "$PID_DIR/op-batcher.pid"
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
        > "$LOG_DIR/op-batcher.log" 2>&1 &

    echo $! > "$PID_DIR/op-batcher.pid"
    echo "  PID: $(cat "$PID_DIR/op-batcher.pid")"
    echo "  Log: $LOG_DIR/op-batcher.log"
}

# Start op-proposer (optional for devnet)
start_op_proposer() {
    echo ""
    echo "Starting op-proposer (state proposer)..."

    if [ -z "$PROPOSER_PRIVATE_KEY" ] || [[ "$PROPOSER_PRIVATE_KEY" == "0x00000"* ]]; then
        echo "  Skipping: PROPOSER_PRIVATE_KEY not configured"
        return
    fi

    if [ -z "$L2_OUTPUT_ORACLE_ADDRESS" ]; then
        echo "  Skipping: L2_OUTPUT_ORACLE_ADDRESS not configured"
        return
    fi

    # Stop existing if running
    if [ -f "$PID_DIR/op-proposer.pid" ]; then
        local pid=$(cat "$PID_DIR/op-proposer.pid")
        kill "$pid" 2>/dev/null || true
        rm "$PID_DIR/op-proposer.pid"
    fi

    op-proposer \
        --l1-eth-rpc "$L1_RPC_URL" \
        --rollup-rpc http://localhost:9545 \
        --private-key "$PROPOSER_PRIVATE_KEY" \
        --l2oo-address "$L2_OUTPUT_ORACLE_ADDRESS" \
        --poll-interval 12s \
        --log.level info \
        > "$LOG_DIR/op-proposer.log" 2>&1 &

    echo $! > "$PID_DIR/op-proposer.pid"
    echo "  PID: $(cat "$PID_DIR/op-proposer.pid")"
    echo "  Log: $LOG_DIR/op-proposer.log"
}

# Check status
check_status() {
    echo ""
    echo "=== Devnet Status ==="

    # Check op-geth
    if [ -f "$PID_DIR/op-geth.pid" ]; then
        local pid=$(cat "$PID_DIR/op-geth.pid")
        if kill -0 "$pid" 2>/dev/null; then
            echo "  op-geth:    RUNNING (PID: $pid)"
        else
            echo "  op-geth:    STOPPED"
        fi
    else
        echo "  op-geth:    NOT STARTED"
    fi

    # Check op-node
    if [ -f "$PID_DIR/op-node.pid" ]; then
        local pid=$(cat "$PID_DIR/op-node.pid")
        if kill -0 "$pid" 2>/dev/null; then
            echo "  op-node:    RUNNING (PID: $pid)"
        else
            echo "  op-node:    STOPPED"
        fi
    else
        echo "  op-node:    NOT STARTED"
    fi

    # Check op-batcher
    if [ -f "$PID_DIR/op-batcher.pid" ]; then
        local pid=$(cat "$PID_DIR/op-batcher.pid")
        if kill -0 "$pid" 2>/dev/null; then
            echo "  op-batcher: RUNNING (PID: $pid)"
        else
            echo "  op-batcher: STOPPED"
        fi
    else
        echo "  op-batcher: NOT STARTED"
    fi

    # Check op-proposer
    if [ -f "$PID_DIR/op-proposer.pid" ]; then
        local pid=$(cat "$PID_DIR/op-proposer.pid")
        if kill -0 "$pid" 2>/dev/null; then
            echo "  op-proposer: RUNNING (PID: $pid)"
        else
            echo "  op-proposer: STOPPED"
        fi
    else
        echo "  op-proposer: NOT STARTED"
    fi
}

# Print usage info
print_usage() {
    echo ""
    echo "=== Set Chain Devnet Started ==="
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
