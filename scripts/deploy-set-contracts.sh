#!/bin/bash
# =============================================================================
# deploy-set-contracts.sh
# Deploy SetRegistry and SetPaymaster contracts to Set Chain L2
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

# =============================================================================
# Configuration
# =============================================================================

# Load environment
if [ -f "$ROOT_DIR/config/sepolia.env" ]; then
    source "$ROOT_DIR/config/sepolia.env"
fi

# Default to local devnet if not configured
L2_RPC_URL="${L2_RPC_URL:-http://localhost:8547}"
DEPLOYER_PRIVATE_KEY="${DEPLOYER_PRIVATE_KEY:-$ADMIN_PRIVATE_KEY}"

# Contract deployment parameters
INITIAL_SEQUENCER="${INITIAL_SEQUENCER:-$SEQUENCER_ADDRESS}"
TREASURY_ADDRESS="${TREASURY_ADDRESS:-$ADMIN_ADDRESS}"

# =============================================================================
# Validation
# =============================================================================

validate_environment() {
    log_info "Validating environment..."

    # Check for required tools
    if ! command -v forge &> /dev/null; then
        log_error "forge not found. Install Foundry: https://getfoundry.sh"
        exit 1
    fi

    if ! command -v cast &> /dev/null; then
        log_error "cast not found. Install Foundry: https://getfoundry.sh"
        exit 1
    fi

    # Check for private key
    if [ -z "$DEPLOYER_PRIVATE_KEY" ]; then
        log_error "DEPLOYER_PRIVATE_KEY or ADMIN_PRIVATE_KEY not set"
        log_info "Set in config/sepolia.env or export directly"
        exit 1
    fi

    # Derive deployer address
    DEPLOYER_ADDRESS=$(cast wallet address "$DEPLOYER_PRIVATE_KEY" 2>/dev/null)
    if [ -z "$DEPLOYER_ADDRESS" ]; then
        log_error "Failed to derive deployer address from private key"
        exit 1
    fi
    log_info "Deployer address: $DEPLOYER_ADDRESS"

    # Check L2 connectivity
    log_info "Checking L2 RPC connectivity..."
    if ! cast chain-id --rpc-url "$L2_RPC_URL" &> /dev/null; then
        log_error "Cannot connect to L2 at $L2_RPC_URL"
        log_info "Make sure the L2 node is running"
        exit 1
    fi

    L2_CHAIN_ID=$(cast chain-id --rpc-url "$L2_RPC_URL")
    log_info "L2 Chain ID: $L2_CHAIN_ID"

    # Check deployer balance
    BALANCE=$(cast balance "$DEPLOYER_ADDRESS" --rpc-url "$L2_RPC_URL")
    BALANCE_ETH=$(cast from-wei "$BALANCE")
    log_info "Deployer balance: $BALANCE_ETH ETH"

    if [ "$BALANCE" = "0" ]; then
        log_error "Deployer has no balance on L2"
        log_info "Bridge ETH from L1 or use the devnet faucet"
        exit 1
    fi

    # Validate sequencer address
    if [ -z "$INITIAL_SEQUENCER" ]; then
        log_warn "INITIAL_SEQUENCER not set, using deployer address"
        INITIAL_SEQUENCER="$DEPLOYER_ADDRESS"
    fi

    # Validate treasury address
    if [ -z "$TREASURY_ADDRESS" ]; then
        log_warn "TREASURY_ADDRESS not set, using deployer address"
        TREASURY_ADDRESS="$DEPLOYER_ADDRESS"
    fi

    log_success "Environment validated"
}

# =============================================================================
# Build Contracts
# =============================================================================

build_contracts() {
    log_info "Building contracts..."

    cd "$CONTRACTS_DIR"

    # Install dependencies if needed
    if [ ! -d "lib/forge-std" ]; then
        log_info "Installing forge-std..."
        forge install foundry-rs/forge-std --no-commit
    fi

    if [ ! -d "lib/openzeppelin-contracts" ]; then
        log_info "Installing OpenZeppelin contracts..."
        forge install OpenZeppelin/openzeppelin-contracts --no-commit
    fi

    if [ ! -d "lib/openzeppelin-contracts-upgradeable" ]; then
        log_info "Installing OpenZeppelin upgradeable contracts..."
        forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-commit
    fi

    # Build
    forge build

    if [ $? -ne 0 ]; then
        log_error "Contract build failed"
        exit 1
    fi

    log_success "Contracts built successfully"
}

# =============================================================================
# Deploy Contracts
# =============================================================================

deploy_set_registry() {
    log_info "Deploying SetRegistry..."

    cd "$CONTRACTS_DIR"

    # Deploy implementation
    log_info "Deploying SetRegistry implementation..."
    REGISTRY_IMPL=$(forge create SetRegistry \
        --private-key "$DEPLOYER_PRIVATE_KEY" \
        --rpc-url "$L2_RPC_URL" \
        --json | jq -r '.deployedTo')

    if [ -z "$REGISTRY_IMPL" ] || [ "$REGISTRY_IMPL" = "null" ]; then
        log_error "Failed to deploy SetRegistry implementation"
        exit 1
    fi
    log_info "SetRegistry implementation: $REGISTRY_IMPL"

    # Prepare initialization data
    INIT_DATA=$(cast calldata "initialize(address,address)" "$DEPLOYER_ADDRESS" "$INITIAL_SEQUENCER")

    # Deploy proxy
    log_info "Deploying SetRegistry proxy..."
    REGISTRY_PROXY=$(forge create lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
        --constructor-args "$REGISTRY_IMPL" "$INIT_DATA" \
        --private-key "$DEPLOYER_PRIVATE_KEY" \
        --rpc-url "$L2_RPC_URL" \
        --json | jq -r '.deployedTo')

    if [ -z "$REGISTRY_PROXY" ] || [ "$REGISTRY_PROXY" = "null" ]; then
        log_error "Failed to deploy SetRegistry proxy"
        exit 1
    fi

    log_success "SetRegistry deployed at: $REGISTRY_PROXY"
    SET_REGISTRY_ADDRESS="$REGISTRY_PROXY"
}

deploy_set_paymaster() {
    log_info "Deploying SetPaymaster..."

    cd "$CONTRACTS_DIR"

    # Deploy implementation
    log_info "Deploying SetPaymaster implementation..."
    PAYMASTER_IMPL=$(forge create commerce/SetPaymaster.sol:SetPaymaster \
        --private-key "$DEPLOYER_PRIVATE_KEY" \
        --rpc-url "$L2_RPC_URL" \
        --json | jq -r '.deployedTo')

    if [ -z "$PAYMASTER_IMPL" ] || [ "$PAYMASTER_IMPL" = "null" ]; then
        log_error "Failed to deploy SetPaymaster implementation"
        exit 1
    fi
    log_info "SetPaymaster implementation: $PAYMASTER_IMPL"

    # Prepare initialization data
    INIT_DATA=$(cast calldata "initialize(address,address)" "$DEPLOYER_ADDRESS" "$TREASURY_ADDRESS")

    # Deploy proxy
    log_info "Deploying SetPaymaster proxy..."
    PAYMASTER_PROXY=$(forge create lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
        --constructor-args "$PAYMASTER_IMPL" "$INIT_DATA" \
        --private-key "$DEPLOYER_PRIVATE_KEY" \
        --rpc-url "$L2_RPC_URL" \
        --json | jq -r '.deployedTo')

    if [ -z "$PAYMASTER_PROXY" ] || [ "$PAYMASTER_PROXY" = "null" ]; then
        log_error "Failed to deploy SetPaymaster proxy"
        exit 1
    fi

    log_success "SetPaymaster deployed at: $PAYMASTER_PROXY"
    SET_PAYMASTER_ADDRESS="$PAYMASTER_PROXY"
}

# =============================================================================
# Verification
# =============================================================================

verify_deployment() {
    log_info "Verifying deployments..."

    # Verify SetRegistry
    log_info "Verifying SetRegistry..."
    REGISTRY_OWNER=$(cast call "$SET_REGISTRY_ADDRESS" "owner()(address)" --rpc-url "$L2_RPC_URL")
    if [ "$REGISTRY_OWNER" != "$DEPLOYER_ADDRESS" ]; then
        log_warn "SetRegistry owner mismatch: expected $DEPLOYER_ADDRESS, got $REGISTRY_OWNER"
    else
        log_success "SetRegistry owner verified"
    fi

    IS_SEQUENCER=$(cast call "$SET_REGISTRY_ADDRESS" "authorizedSequencers(address)(bool)" "$INITIAL_SEQUENCER" --rpc-url "$L2_RPC_URL")
    if [ "$IS_SEQUENCER" = "true" ]; then
        log_success "Initial sequencer authorized"
    else
        log_warn "Initial sequencer not authorized"
    fi

    # Verify SetPaymaster
    log_info "Verifying SetPaymaster..."
    PAYMASTER_OWNER=$(cast call "$SET_PAYMASTER_ADDRESS" "owner()(address)" --rpc-url "$L2_RPC_URL")
    if [ "$PAYMASTER_OWNER" != "$DEPLOYER_ADDRESS" ]; then
        log_warn "SetPaymaster owner mismatch: expected $DEPLOYER_ADDRESS, got $PAYMASTER_OWNER"
    else
        log_success "SetPaymaster owner verified"
    fi

    TREASURY=$(cast call "$SET_PAYMASTER_ADDRESS" "treasury()(address)" --rpc-url "$L2_RPC_URL")
    log_info "SetPaymaster treasury: $TREASURY"

    NEXT_TIER=$(cast call "$SET_PAYMASTER_ADDRESS" "nextTierId()(uint256)" --rpc-url "$L2_RPC_URL")
    log_info "SetPaymaster has $NEXT_TIER tiers configured"

    log_success "Deployment verification complete"
}

# =============================================================================
# Save Deployment Info
# =============================================================================

save_deployment() {
    log_info "Saving deployment information..."

    DEPLOYMENTS_FILE="$ROOT_DIR/deployments/l2-contracts.json"
    mkdir -p "$(dirname "$DEPLOYMENTS_FILE")"

    cat > "$DEPLOYMENTS_FILE" << EOF
{
  "network": "set-chain",
  "chainId": $L2_CHAIN_ID,
  "deployedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "deployer": "$DEPLOYER_ADDRESS",
  "contracts": {
    "SetRegistry": {
      "address": "$SET_REGISTRY_ADDRESS",
      "implementation": "$REGISTRY_IMPL"
    },
    "SetPaymaster": {
      "address": "$SET_PAYMASTER_ADDRESS",
      "implementation": "$PAYMASTER_IMPL"
    }
  },
  "config": {
    "initialSequencer": "$INITIAL_SEQUENCER",
    "treasury": "$TREASURY_ADDRESS"
  }
}
EOF

    log_success "Deployment info saved to $DEPLOYMENTS_FILE"

    # Update sepolia.env with contract addresses
    if [ -f "$ROOT_DIR/config/sepolia.env" ]; then
        # Remove old entries if they exist
        sed -i '/^SET_REGISTRY_ADDRESS=/d' "$ROOT_DIR/config/sepolia.env" 2>/dev/null || true
        sed -i '/^SET_PAYMASTER_ADDRESS=/d' "$ROOT_DIR/config/sepolia.env" 2>/dev/null || true

        # Add new entries
        echo "" >> "$ROOT_DIR/config/sepolia.env"
        echo "# L2 Contract Addresses (deployed $(date +%Y-%m-%d))" >> "$ROOT_DIR/config/sepolia.env"
        echo "SET_REGISTRY_ADDRESS=$SET_REGISTRY_ADDRESS" >> "$ROOT_DIR/config/sepolia.env"
        echo "SET_PAYMASTER_ADDRESS=$SET_PAYMASTER_ADDRESS" >> "$ROOT_DIR/config/sepolia.env"

        log_info "Updated config/sepolia.env with contract addresses"
    fi
}

# =============================================================================
# Fund Paymaster (Optional)
# =============================================================================

fund_paymaster() {
    if [ "$FUND_PAYMASTER" = "true" ]; then
        FUND_AMOUNT="${FUND_AMOUNT:-0.1}"
        log_info "Funding SetPaymaster with $FUND_AMOUNT ETH..."

        cast send "$SET_PAYMASTER_ADDRESS" \
            --value "${FUND_AMOUNT}ether" \
            --private-key "$DEPLOYER_PRIVATE_KEY" \
            --rpc-url "$L2_RPC_URL" \
            > /dev/null

        NEW_BALANCE=$(cast call "$SET_PAYMASTER_ADDRESS" "balance()(uint256)" --rpc-url "$L2_RPC_URL")
        NEW_BALANCE_ETH=$(cast from-wei "$NEW_BALANCE")
        log_success "SetPaymaster balance: $NEW_BALANCE_ETH ETH"
    fi
}

# =============================================================================
# Run Tests (Optional)
# =============================================================================

run_tests() {
    if [ "$RUN_TESTS" = "true" ]; then
        log_info "Running contract tests..."
        cd "$CONTRACTS_DIR"
        forge test -vvv
        log_success "Tests passed"
    fi
}

# =============================================================================
# Usage
# =============================================================================

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy SetRegistry and SetPaymaster contracts to Set Chain L2"
    echo ""
    echo "Options:"
    echo "  --test              Run tests before deployment"
    echo "  --fund [AMOUNT]     Fund paymaster after deployment (default: 0.1 ETH)"
    echo "  --rpc-url URL       Override L2 RPC URL"
    echo "  --sequencer ADDR    Override initial sequencer address"
    echo "  --treasury ADDR     Override treasury address"
    echo "  --help              Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  DEPLOYER_PRIVATE_KEY  Private key for deployment"
    echo "  L2_RPC_URL            L2 RPC endpoint"
    echo "  INITIAL_SEQUENCER     Address authorized as sequencer"
    echo "  TREASURY_ADDRESS      Treasury for paymaster withdrawals"
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo "=============================================="
    echo "  Set Chain - L2 Contract Deployment"
    echo "=============================================="
    echo ""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --test)
                RUN_TESTS=true
                shift
                ;;
            --fund)
                FUND_PAYMASTER=true
                if [[ $2 != --* ]] && [[ -n $2 ]]; then
                    FUND_AMOUNT="$2"
                    shift
                fi
                shift
                ;;
            --rpc-url)
                L2_RPC_URL="$2"
                shift 2
                ;;
            --sequencer)
                INITIAL_SEQUENCER="$2"
                shift 2
                ;;
            --treasury)
                TREASURY_ADDRESS="$2"
                shift 2
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    validate_environment
    build_contracts

    if [ "$RUN_TESTS" = "true" ]; then
        run_tests
    fi

    deploy_set_registry
    deploy_set_paymaster
    verify_deployment
    save_deployment
    fund_paymaster

    echo ""
    echo "=============================================="
    echo "  Deployment Complete!"
    echo "=============================================="
    echo ""
    echo "SetRegistry:   $SET_REGISTRY_ADDRESS"
    echo "SetPaymaster:  $SET_PAYMASTER_ADDRESS"
    echo ""
    echo "Next steps:"
    echo "  1. Update anchor service config with SET_REGISTRY_ADDRESS"
    echo "  2. Fund SetPaymaster for gas sponsorship"
    echo "  3. Sponsor merchants via SetPaymaster"
    echo ""
}

main "$@"
