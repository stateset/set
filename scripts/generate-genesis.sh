#!/bin/bash
# Set Chain - Genesis Generation Script
# Generates genesis.json and rollup.json from deployment state

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DEPLOYER_DIR="$PROJECT_DIR/op-stack/deployer"
SEQUENCER_DIR="$PROJECT_DIR/op-stack/sequencer"

echo "=== Set Chain Genesis Generation ==="
echo ""

# Load environment
if [ -f "$PROJECT_DIR/config/sepolia.env" ]; then
    source "$PROJECT_DIR/config/sepolia.env"
else
    echo "Error: sepolia.env not found"
    exit 1
fi

# Check state.json exists
check_state() {
    if [ ! -f "$DEPLOYER_DIR/state.json" ]; then
        echo "Error: state.json not found. Run deploy-l1.sh first."
        exit 1
    fi

    echo "Found deployment state: $DEPLOYER_DIR/state.json"
}

# Generate genesis.json
generate_genesis() {
    echo ""
    echo "Generating genesis.json..."

    mkdir -p "$SEQUENCER_DIR/op-geth"

    op-deployer inspect genesis \
        --workdir "$DEPLOYER_DIR" \
        "$L2_CHAIN_ID" > "$SEQUENCER_DIR/op-geth/genesis.json"

    echo "Genesis generated: $SEQUENCER_DIR/op-geth/genesis.json"

    # Validate genesis
    local block_num=$(jq '.number' "$SEQUENCER_DIR/op-geth/genesis.json" 2>/dev/null || echo "null")
    local chain_id=$(jq '.config.chainId' "$SEQUENCER_DIR/op-geth/genesis.json" 2>/dev/null || echo "null")

    echo "  Chain ID: $chain_id"
    echo "  Genesis block: $block_num"
}

# Generate rollup.json
generate_rollup() {
    echo ""
    echo "Generating rollup.json..."

    mkdir -p "$SEQUENCER_DIR/op-node"

    op-deployer inspect rollup \
        --workdir "$DEPLOYER_DIR" \
        "$L2_CHAIN_ID" > "$SEQUENCER_DIR/op-node/rollup.json"

    echo "Rollup config generated: $SEQUENCER_DIR/op-node/rollup.json"

    # Validate rollup config
    local l2_chain_id=$(jq '.l2_chain_id' "$SEQUENCER_DIR/op-node/rollup.json" 2>/dev/null || echo "null")
    local block_time=$(jq '.block_time' "$SEQUENCER_DIR/op-node/rollup.json" 2>/dev/null || echo "null")

    echo "  L2 Chain ID: $l2_chain_id"
    echo "  Block time: ${block_time}s"
}

# Generate JWT secret
generate_jwt() {
    echo ""
    echo "Generating JWT secret..."

    local jwt_file="$SEQUENCER_DIR/op-geth/jwt.txt"

    if [ -f "$jwt_file" ]; then
        echo "JWT secret already exists, skipping"
    else
        openssl rand -hex 32 > "$jwt_file"
        echo "JWT secret generated: $jwt_file"
    fi

    # Update sepolia.env with JWT secret
    local jwt_secret=$(cat "$jwt_file")
    sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$jwt_secret|" "$PROJECT_DIR/config/sepolia.env"
}

# Generate P2P key
generate_p2p_key() {
    echo ""
    echo "Generating P2P node key..."

    local p2p_file="$SEQUENCER_DIR/op-node/p2p-node-key.txt"

    if [ -f "$p2p_file" ]; then
        echo "P2P key already exists, skipping"
    else
        openssl rand -hex 32 > "$p2p_file"
        echo "P2P key generated: $p2p_file"
    fi
}

# Initialize op-geth data directory
init_geth() {
    echo ""
    echo "Initializing op-geth data directory..."

    local geth_data="$SEQUENCER_DIR/op-geth/data"
    mkdir -p "$geth_data"

    # Check if already initialized
    if [ -d "$geth_data/geth" ]; then
        echo "op-geth already initialized, skipping"
        return
    fi

    # Initialize with genesis
    if command -v op-geth &> /dev/null; then
        op-geth init \
            --datadir "$geth_data" \
            "$SEQUENCER_DIR/op-geth/genesis.json"
        echo "op-geth initialized"
    else
        echo "Warning: op-geth not found in PATH"
        echo "Run ./scripts/install-op-stack.sh first"
        echo "Then manually initialize:"
        echo "  op-geth init --datadir $geth_data $SEQUENCER_DIR/op-geth/genesis.json"
    fi
}

# Create batcher/proposer environment files
create_component_configs() {
    echo ""
    echo "Creating component configuration files..."

    # Batcher config
    cat > "$PROJECT_DIR/op-stack/batcher/.env" << EOF
# op-batcher configuration
L1_ETH_RPC=$L1_RPC_URL
L2_ETH_RPC=$L2_RPC_URL
ROLLUP_RPC=http://localhost:9545
PRIVATE_KEY=$BATCHER_PRIVATE_KEY
POLL_INTERVAL=1s
SUB_SAFETY_MARGIN=$SUB_SAFETY_MARGIN
NUM_CONFIRMATIONS=1
SAFE_ABORT_NONCE_TOO_LOW_COUNT=3
LOG_LEVEL=info
EOF
    echo "  Created: op-stack/batcher/.env"

    # Proposer config
    cat > "$PROJECT_DIR/op-stack/proposer/.env" << EOF
# op-proposer configuration
L1_ETH_RPC=$L1_RPC_URL
ROLLUP_RPC=http://localhost:9545
PRIVATE_KEY=$PROPOSER_PRIVATE_KEY
L2OO_ADDRESS=$L2_OUTPUT_ORACLE_ADDRESS
POLL_INTERVAL=${PROPOSER_POLL_INTERVAL}s
LOG_LEVEL=info
EOF
    echo "  Created: op-stack/proposer/.env"

    # Challenger config (optional)
    cat > "$PROJECT_DIR/op-stack/challenger/.env" << EOF
# op-challenger configuration
L1_ETH_RPC=$L1_RPC_URL
L2_ETH_RPC=$L2_RPC_URL
ROLLUP_RPC=http://localhost:9545
PRIVATE_KEY=$CHALLENGER_PRIVATE_KEY
DISPUTE_GAME_FACTORY=$DISPUTE_GAME_FACTORY_ADDRESS
LOG_LEVEL=info
EOF
    echo "  Created: op-stack/challenger/.env"
}

# Print summary
print_summary() {
    echo ""
    echo "=== Genesis Generation Complete ==="
    echo ""
    echo "Generated files:"
    echo "  - $SEQUENCER_DIR/op-geth/genesis.json"
    echo "  - $SEQUENCER_DIR/op-node/rollup.json"
    echo "  - $SEQUENCER_DIR/op-geth/jwt.txt"
    echo "  - $SEQUENCER_DIR/op-node/p2p-node-key.txt"
    echo ""
    echo "Next steps:"
    echo "  1. Start the devnet:"
    echo "     ./scripts/start-devnet.sh"
    echo ""
    echo "  Or use Docker:"
    echo "     cd docker && docker-compose up -d"
    echo ""
}

# Main flow
main() {
    check_state
    generate_genesis
    generate_rollup
    generate_jwt
    generate_p2p_key
    init_geth
    create_component_configs
    print_summary
}

main "$@"
