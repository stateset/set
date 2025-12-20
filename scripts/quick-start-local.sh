#!/bin/bash
# =============================================================================
# quick-start-local.sh
# Quick start a minimal Set Chain L2 local devnet
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$ROOT_DIR/docker/config"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Chain configuration
CHAIN_ID=84532001
BLOCK_TIME=2

echo "=============================================="
echo "  Set Chain L2 - Local Devnet Quick Start"
echo "=============================================="
echo ""

# Check Docker
if ! command -v docker &> /dev/null; then
    log_error "Docker not found. Please install Docker."
    exit 1
fi

if ! docker info &> /dev/null; then
    log_error "Docker daemon not running. Please start Docker."
    exit 1
fi

log_info "Docker is available"

# Create config directory
mkdir -p "$CONFIG_DIR"

# Generate JWT secret
log_info "Generating JWT secret..."
if [ ! -f "$CONFIG_DIR/jwt.txt" ]; then
    openssl rand -hex 32 > "$CONFIG_DIR/jwt.txt"
    log_success "JWT secret created"
else
    log_info "JWT secret already exists"
fi

# Generate test accounts
log_info "Setting up test accounts..."

# Pre-defined test accounts (DO NOT USE IN PRODUCTION)
# These are derived from mnemonic: "test test test test test test test test test test test junk"
ADMIN_ADDRESS="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
ADMIN_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

SEQUENCER_ADDRESS="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
SEQUENCER_KEY="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"

BATCHER_ADDRESS="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
BATCHER_KEY="0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"

PROPOSER_ADDRESS="0x90F79bf6EB2c4f870365E785982E1f101E93b906"
PROPOSER_KEY="0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6"

# Create genesis.json for op-geth
log_info "Creating genesis configuration..."
cat > "$CONFIG_DIR/genesis.json" << EOF
{
  "config": {
    "chainId": $CHAIN_ID,
    "homesteadBlock": 0,
    "eip150Block": 0,
    "eip155Block": 0,
    "eip158Block": 0,
    "byzantiumBlock": 0,
    "constantinopleBlock": 0,
    "petersburgBlock": 0,
    "istanbulBlock": 0,
    "muirGlacierBlock": 0,
    "berlinBlock": 0,
    "londonBlock": 0,
    "arrowGlacierBlock": 0,
    "grayGlacierBlock": 0,
    "mergeNetsplitBlock": 0,
    "shanghaiTime": 0,
    "cancunTime": 0,
    "terminalTotalDifficulty": 0,
    "terminalTotalDifficultyPassed": true,
    "optimism": {
      "eip1559Elasticity": 6,
      "eip1559Denominator": 50,
      "eip1559DenominatorCanyon": 250
    }
  },
  "nonce": "0x0",
  "timestamp": "0x0",
  "extraData": "0x",
  "gasLimit": "0x1c9c380",
  "difficulty": "0x0",
  "mixHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "coinbase": "0x0000000000000000000000000000000000000000",
  "alloc": {
    "$ADMIN_ADDRESS": {
      "balance": "0x200000000000000000000000000000000000000000000000000000000000000"
    },
    "$SEQUENCER_ADDRESS": {
      "balance": "0x200000000000000000000000000000000000000000000000000000000000000"
    },
    "$BATCHER_ADDRESS": {
      "balance": "0x200000000000000000000000000000000000000000000000000000000000000"
    },
    "$PROPOSER_ADDRESS": {
      "balance": "0x200000000000000000000000000000000000000000000000000000000000000"
    }
  },
  "number": "0x0",
  "gasUsed": "0x0",
  "parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "baseFeePerGas": "0x3b9aca00"
}
EOF
log_success "Genesis configuration created"

# Create rollup.json for op-node
log_info "Creating rollup configuration..."
cat > "$CONFIG_DIR/rollup.json" << EOF
{
  "genesis": {
    "l1": {
      "hash": "0x0000000000000000000000000000000000000000000000000000000000000000",
      "number": 0
    },
    "l2": {
      "hash": "0x0000000000000000000000000000000000000000000000000000000000000000",
      "number": 0
    },
    "l2_time": 0,
    "system_config": {
      "batcherAddr": "$BATCHER_ADDRESS",
      "overhead": "0x00000000000000000000000000000000000000000000000000000000000000bc",
      "scalar": "0x00000000000000000000000000000000000000000000000000000000000a6fe0",
      "gasLimit": 30000000
    }
  },
  "block_time": $BLOCK_TIME,
  "max_sequencer_drift": 600,
  "seq_window_size": 3600,
  "channel_timeout": 300,
  "l1_chain_id": 1337,
  "l2_chain_id": $CHAIN_ID,
  "regolith_time": 0,
  "canyon_time": 0,
  "delta_time": 0,
  "ecotone_time": 0,
  "fjord_time": 0,
  "batch_inbox_address": "0xff00000000000000000000000000000000084532",
  "deposit_contract_address": "0x0000000000000000000000000000000000000000",
  "l1_system_config_address": "0x0000000000000000000000000000000000000000"
}
EOF
log_success "Rollup configuration created"

# Create .env file for docker-compose
log_info "Creating environment file..."
cat > "$ROOT_DIR/docker/.env" << EOF
# Set Chain Local Devnet Configuration
# Generated by quick-start-local.sh

# Chain
L2_CHAIN_ID=$CHAIN_ID

# L1 (local geth dev node)
L1_RPC_URL=http://l1-geth:8545
L1_BEACON_URL=http://l1-geth:8545

# Accounts (TEST ONLY - DO NOT USE IN PRODUCTION)
ADMIN_ADDRESS=$ADMIN_ADDRESS
ADMIN_PRIVATE_KEY=$ADMIN_KEY
SEQUENCER_ADDRESS=$SEQUENCER_ADDRESS
SEQUENCER_PRIVATE_KEY=$SEQUENCER_KEY
BATCHER_ADDRESS=$BATCHER_ADDRESS
BATCHER_PRIVATE_KEY=$BATCHER_KEY
PROPOSER_ADDRESS=$PROPOSER_ADDRESS
PROPOSER_PRIVATE_KEY=$PROPOSER_KEY

# Contracts (placeholder - not deployed in minimal mode)
L2_OUTPUT_ORACLE_ADDRESS=0x0000000000000000000000000000000000000000
SET_REGISTRY_ADDRESS=0x0000000000000000000000000000000000000000

# Anchor service
SEQUENCER_API_URL=http://host.docker.internal:3000
EOF
log_success "Environment file created"

# Start the devnet
log_info "Starting Set Chain local devnet..."
cd "$ROOT_DIR/docker"

# Start just L1 and L2 execution layer first
docker compose up -d l1-geth op-geth

log_info "Waiting for L1 to be ready..."
sleep 5

# Check if L1 is running
if docker compose ps l1-geth | grep -q "running"; then
    log_success "L1 (local geth) is running"
else
    log_error "L1 failed to start"
    docker compose logs l1-geth
    exit 1
fi

# Check if op-geth is running
if docker compose ps op-geth | grep -q "running"; then
    log_success "L2 (op-geth) is running"
else
    log_warn "op-geth may still be initializing..."
fi

# Wait for op-geth to be ready
log_info "Waiting for L2 to be ready..."
for i in {1..30}; do
    if curl -sf http://localhost:8547 -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' > /dev/null 2>&1; then
        log_success "L2 RPC is responding"
        break
    fi
    sleep 2
    echo -n "."
done
echo ""

# Get chain info
log_info "Checking chain status..."
CHAIN_ID_RESPONSE=$(curl -sf http://localhost:8547 -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' 2>/dev/null || echo '{"result":"error"}')

BLOCK_NUMBER=$(curl -sf http://localhost:8547 -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | grep -o '"result":"[^"]*"' | cut -d'"' -f4 || echo "0x0")

echo ""
echo "=============================================="
echo "  Set Chain Local Devnet Running!"
echo "=============================================="
echo ""
echo "Chain ID:        $CHAIN_ID"
echo "Block Number:    $BLOCK_NUMBER"
echo ""
echo "RPC Endpoints:"
echo "  L1 HTTP:       http://localhost:8545"
echo "  L2 HTTP:       http://localhost:8547"
echo "  L2 WebSocket:  ws://localhost:8548"
echo ""
echo "Test Accounts (pre-funded):"
echo "  Admin:         $ADMIN_ADDRESS"
echo "  Sequencer:     $SEQUENCER_ADDRESS"
echo "  Batcher:       $BATCHER_ADDRESS"
echo "  Proposer:      $PROPOSER_ADDRESS"
echo ""
echo "Commands:"
echo "  View logs:     cd docker && docker compose logs -f"
echo "  Stop:          cd docker && docker compose down"
echo "  Check block:   cast block-number --rpc-url http://localhost:8547"
echo ""
echo "Next steps:"
echo "  1. Deploy SetRegistry:  ./scripts/deploy-set-contracts.sh"
echo "  2. Start anchor:        docker compose --profile anchor up -d"
echo ""
