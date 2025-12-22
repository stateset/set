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

# Ensure Foundry dependencies are available (handles empty submodule dirs)
ensure_deps() {
    if [ ! -d "lib/forge-std/src" ] || \
       [ ! -d "lib/openzeppelin-contracts/contracts" ] || \
       [ ! -d "lib/openzeppelin-contracts-upgradeable/contracts" ]; then
        log_info "Installing Foundry dependencies..."
        forge install foundry-rs/forge-std --no-commit 2>/dev/null || true
        forge install OpenZeppelin/openzeppelin-contracts --no-commit 2>/dev/null || true
        forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-commit 2>/dev/null || true
    fi
}

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
    echo "  validate    Validate local devnet config"
    echo "  smoke       Deploy and run smoke checks"
    echo "  anchor-start Start anchor service against local devnet"
    echo "  anchor-smoke Run anchor service smoke test"
    echo "  reset       Reset devnet state and restart Anvil"
    echo "  accounts    Show test accounts"
    echo "  fund        Fund an address with test ETH"
    echo "  console     Open interactive console"
    echo ""
    echo "Examples:"
    echo "  $0 start                    # Start Anvil"
    echo "  $0 deploy                   # Deploy all contracts"
    echo "  $0 test                     # Run Foundry tests"
    echo "  $0 validate                 # Validate devnet config"
    echo "  $0 smoke                    # Deploy and run smoke checks"
    echo "  $0 anchor-start             # Run anchor service locally"
    echo "  $0 anchor-smoke             # Anchor service smoke test"
    echo "  $0 reset                    # Reset devnet and restart Anvil"
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

    ensure_deps

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

    ensure_deps

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

    "$SCRIPT_DIR/validate-devnet.sh"
    echo ""

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

cmd_validate() {
    "$SCRIPT_DIR/validate-devnet.sh"
}

cmd_smoke() {
    log_info "Running devnet smoke test..."
    echo ""

    cmd_deploy
    echo ""

    "$SCRIPT_DIR/validate-devnet.sh" --require-contracts
    echo ""

    CHAIN_ID=$(curl -sf "$RPC_URL" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' | jq -r '.result' | xargs printf "%d")

    BROADCAST_FILE="$CONTRACTS_DIR/broadcast/Deploy.s.sol/$CHAIN_ID/run-latest.json"

    if [ ! -f "$BROADCAST_FILE" ]; then
        log_error "Missing deploy broadcast file: $BROADCAST_FILE"
        log_error "Run: $0 deploy"
        exit 1
    fi

    REGISTRY_PROXY=$(jq -r '.transactions[] | select(.contractName=="ERC1967Proxy") | .contractAddress' \
        "$BROADCAST_FILE" | sed -n '1p')
    PAYMASTER_PROXY=$(jq -r '.transactions[] | select(.contractName=="ERC1967Proxy") | .contractAddress' \
        "$BROADCAST_FILE" | sed -n '2p')

    if [ -z "$REGISTRY_PROXY" ]; then
        log_error "SetRegistry proxy not found in $BROADCAST_FILE"
        exit 1
    fi

    if command -v cast >/dev/null 2>&1; then
        CAST_CMD=(cast)
    elif command -v docker >/dev/null 2>&1; then
        CAST_CMD=(docker run --rm --network=host ghcr.io/foundry-rs/foundry:stable cast)
    else
        log_error "cast not found. Install Foundry or use Docker."
        exit 1
    fi

    SEQUENCER_ADDRESS="${SEQUENCER_ADDRESS:-0x70997970C51812dc3A010C7d01b50e0d17dc79C8}"
    SEQUENCER_PRIVATE_KEY="${SEQUENCER_PRIVATE_KEY:-0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d}"
    TENANT_ID="${TENANT_ID:-0x00000000000000000000000000000000000000000000000000000000000000a1}"
    STORE_ID="${STORE_ID:-0x00000000000000000000000000000000000000000000000000000000000000b2}"
    EVENT_LEAF_0="${EVENT_LEAF_0:-${EVENT_LEAF:-}}"
    EVENT_LEAF_1="${EVENT_LEAF_1:-}"
    PREV_STATE_ROOT="${PREV_STATE_ROOT:-0x0000000000000000000000000000000000000000000000000000000000000000}"

    if [ -z "$SEQUENCER_PRIVATE_KEY" ]; then
        log_error "SEQUENCER_PRIVATE_KEY is required for smoke test"
        exit 1
    fi

    SEQUENCER_ADDRESS_NORMALIZED="$(echo "$SEQUENCER_ADDRESS" | tr 'A-F' 'a-f')"
    SEQUENCER_FROM_KEY=$("${CAST_CMD[@]}" wallet address --private-key "$SEQUENCER_PRIVATE_KEY" 2>/dev/null \
        | tr -d '\r\n ' | tr 'A-F' 'a-f' || true)

    if [ -n "$SEQUENCER_FROM_KEY" ] && [ "$SEQUENCER_FROM_KEY" != "$SEQUENCER_ADDRESS_NORMALIZED" ]; then
        log_error "SEQUENCER_ADDRESS does not match SEQUENCER_PRIVATE_KEY"
        log_error "SEQUENCER_ADDRESS: $SEQUENCER_ADDRESS_NORMALIZED"
        log_error "Derived Address:   $SEQUENCER_FROM_KEY"
        exit 1
    elif [ -z "$SEQUENCER_FROM_KEY" ]; then
        log_warn "Unable to derive address from SEQUENCER_PRIVATE_KEY"
    fi

    random_bytes32() {
        if command -v od >/dev/null 2>&1; then
            echo "0x$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
        else
            printf "0x%064x" "$(date +%s)"
        fi
    }

    if [ -z "${NEW_STATE_ROOT:-}" ]; then
        NEW_STATE_ROOT="$(random_bytes32)"
    fi

    if [ -z "$EVENT_LEAF_0" ]; then
        EVENT_LEAF_0="$(random_bytes32)"
    fi

    if [ -z "$EVENT_LEAF_1" ]; then
        EVENT_LEAF_1="$(random_bytes32)"
    fi

    EVENT_LEAF_0_HEX="${EVENT_LEAF_0#0x}"
    EVENT_LEAF_1_HEX="${EVENT_LEAF_1#0x}"
    EVENTS_ROOT=$("${CAST_CMD[@]}" keccak "0x${EVENT_LEAF_0_HEX}${EVENT_LEAF_1_HEX}" | tr -d '\r\n ')

    log_info "SetRegistry owner:"
    "${CAST_CMD[@]}" call "$REGISTRY_PROXY" "owner()(address)" --rpc-url "$RPC_URL"
    log_info "SetRegistry authorizedSequencers:"
    AUTHORIZED=$("${CAST_CMD[@]}" call "$REGISTRY_PROXY" "authorizedSequencers(address)(bool)" \
        "$SEQUENCER_ADDRESS" --rpc-url "$RPC_URL" | tr -d '\r\n ')

    if [ "$AUTHORIZED" != "true" ] && [ "$AUTHORIZED" != "1" ]; then
        log_error "Sequencer $SEQUENCER_ADDRESS is not authorized"
        exit 1
    fi
    log_success "Sequencer authorized"

    if [ -n "$PAYMASTER_PROXY" ]; then
        log_info "SetPaymaster owner:"
        "${CAST_CMD[@]}" call "$PAYMASTER_PROXY" "owner()(address)" --rpc-url "$RPC_URL"
        log_info "SetPaymaster treasury:"
        "${CAST_CMD[@]}" call "$PAYMASTER_PROXY" "treasury()(address)" --rpc-url "$RPC_URL"
    else
        log_warn "SetPaymaster proxy not found in $BROADCAST_FILE"
    fi

    HEAD_SEQ_BEFORE=$("${CAST_CMD[@]}" call "$REGISTRY_PROXY" \
        "getHeadSequence(bytes32,bytes32)(uint64)" \
        "$TENANT_ID" "$STORE_ID" --rpc-url "$RPC_URL" | tr -d '\r\n ')

    if [[ "$HEAD_SEQ_BEFORE" =~ ^[0-9]+$ ]] && [ "$HEAD_SEQ_BEFORE" -gt 0 ]; then
        PREV_STATE_ROOT=$("${CAST_CMD[@]}" call "$REGISTRY_PROXY" \
            "getLatestStateRoot(bytes32,bytes32)(bytes32)" \
            "$TENANT_ID" "$STORE_ID" --rpc-url "$RPC_URL" | tr -d '\r\n ')
        SEQUENCE_START=$((HEAD_SEQ_BEFORE + 1))
    else
        SEQUENCE_START=1
    fi

    EVENT_COUNT=2
    SEQUENCE_END=$((SEQUENCE_START + EVENT_COUNT - 1))

    if [ -z "${BATCH_ID:-}" ]; then
        BATCH_ID="$(random_bytes32)"
    fi

    log_info "Committing test batch..."
    "${CAST_CMD[@]}" send "$REGISTRY_PROXY" \
        "commitBatch(bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,uint64,uint64,uint32)" \
        "$BATCH_ID" "$TENANT_ID" "$STORE_ID" "$EVENTS_ROOT" "$PREV_STATE_ROOT" "$NEW_STATE_ROOT" \
        "$SEQUENCE_START" "$SEQUENCE_END" "$EVENT_COUNT" \
        --private-key "$SEQUENCER_PRIVATE_KEY" \
        --rpc-url "$RPC_URL"

    log_info "Verifying multiproof..."
    MULTI_LEAVES="[$EVENT_LEAF_0,$EVENT_LEAF_1]"
    MULTI_PROOFS="[[${EVENT_LEAF_1}],[${EVENT_LEAF_0}]]"
    MULTI_INDICES="[0,1]"
    MULTI_RESULT=$("${CAST_CMD[@]}" call "$REGISTRY_PROXY" \
        "verifyMultipleInclusions(bytes32,bytes32[],bytes32[][],uint256[])(bool)" \
        "$BATCH_ID" "$MULTI_LEAVES" "$MULTI_PROOFS" "$MULTI_INDICES" \
        --rpc-url "$RPC_URL" | tr -d '\r\n ')

    if [ "$MULTI_RESULT" != "true" ] && [ "$MULTI_RESULT" != "1" ]; then
        log_error "verifyMultipleInclusions returned: $MULTI_RESULT"
        exit 1
    fi
    log_success "Multiproof verified"

    log_info "Verifying single inclusion..."
    INCLUSION_RESULT=$("${CAST_CMD[@]}" call "$REGISTRY_PROXY" \
        "verifyInclusion(bytes32,bytes32,bytes32[],uint256)(bool)" \
        "$BATCH_ID" "$EVENT_LEAF_0" "[$EVENT_LEAF_1]" 0 \
        --rpc-url "$RPC_URL" | tr -d '\r\n ')

    if [ "$INCLUSION_RESULT" != "true" ] && [ "$INCLUSION_RESULT" != "1" ]; then
        log_error "verifyInclusion returned: $INCLUSION_RESULT"
        exit 1
    fi
    log_success "Inclusion proof verified"

    LATEST_STATE=$("${CAST_CMD[@]}" call "$REGISTRY_PROXY" \
        "getLatestStateRoot(bytes32,bytes32)(bytes32)" \
        "$TENANT_ID" "$STORE_ID" --rpc-url "$RPC_URL" | tr -d '\r\n ' | tr 'A-F' 'a-f')
    EXPECTED_STATE="$(echo "$NEW_STATE_ROOT" | tr 'A-F' 'a-f')"

    if [ "$LATEST_STATE" != "$EXPECTED_STATE" ]; then
        log_error "Latest state root mismatch: expected $EXPECTED_STATE, got $LATEST_STATE"
        exit 1
    fi
    log_success "Latest state root matches"

    HEAD_SEQ_AFTER=$("${CAST_CMD[@]}" call "$REGISTRY_PROXY" \
        "getHeadSequence(bytes32,bytes32)(uint64)" \
        "$TENANT_ID" "$STORE_ID" --rpc-url "$RPC_URL" | tr -d '\r\n ')

    if [ "$HEAD_SEQ_AFTER" != "$SEQUENCE_END" ]; then
        log_error "Head sequence mismatch: expected $SEQUENCE_END, got $HEAD_SEQ_AFTER"
        exit 1
    fi
    log_success "Head sequence matches"

    log_success "Smoke test complete!"
}

cmd_reset() {
    "$SCRIPT_DIR/reset-devnet.sh" "$@"
}

cmd_anchor_start() {
    "$SCRIPT_DIR/anchor-devnet.sh" start "$@"
}

cmd_anchor_smoke() {
    "$SCRIPT_DIR/anchor-devnet.sh" smoke "$@"
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
    validate)
        cmd_validate
        ;;
    smoke)
        cmd_smoke
        ;;
    reset)
        shift
        cmd_reset "$@"
        ;;
    anchor-start)
        shift
        cmd_anchor_start "$@"
        ;;
    anchor-smoke)
        shift
        cmd_anchor_smoke "$@"
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
