#!/bin/bash
# =============================================================================
# dev.sh
# Set Chain local development helper
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONTRACTS_DIR="$ROOT_DIR/contracts"

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

# Default RPC
RPC_URL="${RPC_URL:-http://localhost:8545}"

usage() {
    echo "Set Chain Development Helper"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  start       Start local Anvil node"
    echo "  deploy      Deploy contracts to local node"
    echo "  test        Run contract tests"
    echo "  status      Check local node status"
    echo "  accounts    Show test accounts"
    echo "  fund        Fund an address with test ETH"
    echo "  console     Open interactive console"
    echo ""
    echo "Examples:"
    echo "  $0 start                    # Start Anvil"
    echo "  $0 deploy                   # Deploy all contracts"
    echo "  $0 test                     # Run Foundry tests"
    echo "  $0 fund 0x123...            # Send 100 ETH to address"
    echo "  $0 status                   # Check node status"
    echo ""
}

cmd_start() {
    exec "$SCRIPT_DIR/start-local-anvil.sh"
}

cmd_deploy() {
    log_info "Checking connection to $RPC_URL..."

    if ! curl -sf "$RPC_URL" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' > /dev/null 2>&1; then
        log_error "Cannot connect to $RPC_URL"
        log_info "Start the local node first: $0 start"
        exit 1
    fi

    CHAIN_ID=$(curl -sf "$RPC_URL" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' | jq -r '.result' | xargs printf "%d")

    log_success "Connected to chain ID: $CHAIN_ID"
    echo ""

    cd "$CONTRACTS_DIR"

    # Install dependencies if needed
    if [ ! -d "lib/forge-std" ]; then
        log_info "Installing Foundry dependencies..."
        forge install foundry-rs/forge-std --no-commit 2>/dev/null || true
        forge install OpenZeppelin/openzeppelin-contracts --no-commit 2>/dev/null || true
        forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-commit 2>/dev/null || true
    fi

    log_info "Deploying contracts..."
    echo ""

    forge script script/Deploy.s.sol \
        --rpc-url "$RPC_URL" \
        --broadcast \
        -vvv

    echo ""
    log_success "Deployment complete!"
}

cmd_test() {
    cd "$CONTRACTS_DIR"

    log_info "Running contract tests..."
    echo ""

    # Install dependencies if needed
    if [ ! -d "lib/forge-std" ]; then
        log_info "Installing Foundry dependencies..."
        forge install foundry-rs/forge-std --no-commit 2>/dev/null || true
        forge install OpenZeppelin/openzeppelin-contracts --no-commit 2>/dev/null || true
        forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-commit 2>/dev/null || true
    fi

    forge test -vvv "$@"
}

cmd_status() {
    echo "Checking node at $RPC_URL..."
    echo ""

    if ! curl -sf "$RPC_URL" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' > /dev/null 2>&1; then
        log_error "Node not responding at $RPC_URL"
        exit 1
    fi

    CHAIN_ID=$(curl -sf "$RPC_URL" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' | jq -r '.result' | xargs printf "%d")

    BLOCK=$(curl -sf "$RPC_URL" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result' | xargs printf "%d")

    GAS_PRICE=$(curl -sf "$RPC_URL" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_gasPrice","params":[],"id":1}' | jq -r '.result' | xargs printf "%d")

    echo -e "${GREEN}Node Status: ONLINE${NC}"
    echo ""
    echo "Chain ID:     $CHAIN_ID"
    echo "Block Number: $BLOCK"
    echo "Gas Price:    $GAS_PRICE wei"
    echo "RPC URL:      $RPC_URL"
}

cmd_accounts() {
    echo "Test Accounts (10,000 ETH each)"
    echo "================================"
    echo ""
    echo "Account                                      | Private Key"
    echo "---------------------------------------------|--------------------------------------------------------------------"
    echo "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266  | 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
    echo "0x70997970C51812dc3A010C7d01b50e0d17dc79C8  | 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
    echo "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC  | 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
    echo "0x90F79bf6EB2c4f870365E785982E1f101E93b906  | 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6"
    echo "0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65  | 0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a"
    echo ""
    echo "Roles:"
    echo "  Account 0: Admin/Deployer"
    echo "  Account 1: Sequencer"
    echo "  Account 2: Batcher"
    echo "  Account 3: Proposer"
}

cmd_fund() {
    if [ -z "$1" ]; then
        log_error "Usage: $0 fund <address> [amount_eth]"
        exit 1
    fi

    ADDRESS="$1"
    AMOUNT="${2:-100}"

    log_info "Sending $AMOUNT ETH to $ADDRESS..."

    # Use cast to send from first account
    cast send "$ADDRESS" \
        --value "${AMOUNT}ether" \
        --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
        --rpc-url "$RPC_URL"

    log_success "Sent $AMOUNT ETH to $ADDRESS"
}

cmd_console() {
    log_info "Opening Foundry console..."
    cd "$CONTRACTS_DIR"
    cast shell --rpc-url "$RPC_URL"
}

# Main
case "${1:-}" in
    start)
        cmd_start
        ;;
    deploy)
        cmd_deploy
        ;;
    test)
        shift
        cmd_test "$@"
        ;;
    status)
        cmd_status
        ;;
    accounts)
        cmd_accounts
        ;;
    fund)
        shift
        cmd_fund "$@"
        ;;
    console)
        cmd_console
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac
