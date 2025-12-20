#!/bin/bash
# =============================================================================
# start-local-anvil.sh
# Start Anvil with Set Chain configuration for local development
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Set Chain Configuration
CHAIN_ID=84532001
BLOCK_TIME=2
GAS_LIMIT=30000000

# Test accounts (same as Foundry/Hardhat default)
# Mnemonic: "test test test test test test test test test test test junk"

echo -e "${BLUE}"
echo "=============================================="
echo "  Set Chain L2 - Local Development (Anvil)"
echo "=============================================="
echo -e "${NC}"

# Check for anvil
if ! command -v anvil &> /dev/null; then
    echo "Anvil not found. Installing Foundry..."
    curl -L https://foundry.paradigm.xyz | bash
    source ~/.bashrc
    foundryup
fi

echo ""
echo "Configuration:"
echo "  Chain ID:     $CHAIN_ID"
echo "  Block Time:   ${BLOCK_TIME}s"
echo "  Gas Limit:    $GAS_LIMIT"
echo ""

# Stop any existing Docker L2 to avoid port conflicts
if docker ps | grep -q "set-op-geth"; then
    echo -e "${YELLOW}Stopping Docker op-geth to avoid port conflicts...${NC}"
    cd "$ROOT_DIR/docker" && docker compose -f docker-compose.local.yml down 2>/dev/null || true
fi

echo "Starting Anvil..."
echo ""
echo -e "${GREEN}Pre-funded Test Accounts:${NC}"
echo "  (0) 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 (Admin)"
echo "  (1) 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 (Sequencer)"
echo "  (2) 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC (Batcher)"
echo "  (3) 0x90F79bf6EB2c4f870365E785982E1f101E93b906 (Proposer)"
echo ""
echo "Private Keys:"
echo "  (0) 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
echo "  (1) 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
echo "  (2) 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
echo "  (3) 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6"
echo ""
echo -e "${GREEN}RPC Endpoints:${NC}"
echo "  HTTP:      http://localhost:8545"
echo "  WebSocket: ws://localhost:8545"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
echo ""

# Start Anvil
exec anvil \
    --chain-id $CHAIN_ID \
    --block-time $BLOCK_TIME \
    --gas-limit $GAS_LIMIT \
    --accounts 10 \
    --balance 10000 \
    --host 0.0.0.0 \
    --port 8545
