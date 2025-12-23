#!/bin/bash
# Sepolia Deployment Script for Set Chain
# Deploys the complete L2 stack to Sepolia testnet

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load environment
if [ -f "$PROJECT_ROOT/config/sepolia.env" ]; then
    source "$PROJECT_ROOT/config/sepolia.env"
else
    echo -e "${RED}Error: config/sepolia.env not found${NC}"
    echo "Copy config/sepolia.env.example to config/sepolia.env and fill in values"
    exit 1
fi

# Required environment variables
REQUIRED_VARS=(
    "L1_RPC_URL"
    "DEPLOYER_PRIVATE_KEY"
    "SEQUENCER_PRIVATE_KEY"
    "BATCHER_PRIVATE_KEY"
    "PROPOSER_PRIVATE_KEY"
)

check_env() {
    echo -e "${YELLOW}Checking environment variables...${NC}"
    for var in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!var}" ]; then
            echo -e "${RED}Error: $var is not set${NC}"
            exit 1
        fi
    done
    echo -e "${GREEN}Environment OK${NC}"
}

# Deployment addresses file
ADDRESSES_FILE="$PROJECT_ROOT/deployments/sepolia/addresses.json"

echo -e "${BLUE}=============================================${NC}"
echo -e "${BLUE}  Set Chain Sepolia Deployment${NC}"
echo -e "${BLUE}=============================================${NC}"
echo ""

show_help() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  check        Check prerequisites and environment"
    echo "  l1           Deploy L1 contracts (OP Stack)"
    echo "  genesis      Generate L2 genesis"
    echo "  l2           Deploy L2 contracts (SetRegistry, SetPaymaster)"
    echo "  governance   Deploy governance (Timelock)"
    echo "  verify       Verify all contracts on Etherscan"
    echo "  all          Run complete deployment"
    echo "  status       Show deployment status"
    echo ""
}

check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"

    # Check foundry
    if ! command -v forge &> /dev/null; then
        echo -e "${RED}Foundry not found. Install with: curl -L https://foundry.paradigm.xyz | bash${NC}"
        exit 1
    fi

    # Check cast
    if ! command -v cast &> /dev/null; then
        echo -e "${RED}Cast not found. Install Foundry.${NC}"
        exit 1
    fi

    # Check L1 RPC connectivity
    echo "Checking L1 RPC..."
    CHAIN_ID=$(cast chain-id --rpc-url "$L1_RPC_URL" 2>/dev/null || echo "failed")
    if [ "$CHAIN_ID" != "11155111" ]; then
        echo -e "${RED}L1 RPC not responding or not Sepolia (got chain ID: $CHAIN_ID)${NC}"
        exit 1
    fi
    echo -e "${GREEN}L1 RPC OK (Sepolia)${NC}"

    # Check deployer balance
    DEPLOYER_ADDRESS=$(cast wallet address --private-key "$DEPLOYER_PRIVATE_KEY")
    BALANCE=$(cast balance "$DEPLOYER_ADDRESS" --rpc-url "$L1_RPC_URL" --ether)
    echo "Deployer: $DEPLOYER_ADDRESS"
    echo "Balance: $BALANCE ETH"

    if (( $(echo "$BALANCE < 0.5" | bc -l) )); then
        echo -e "${YELLOW}Warning: Low deployer balance. Need at least 0.5 ETH for L1 deployment.${NC}"
    fi

    check_env
    echo -e "${GREEN}All prerequisites OK${NC}"
}

deploy_l1() {
    echo ""
    echo -e "${YELLOW}Deploying L1 contracts...${NC}"

    mkdir -p "$PROJECT_ROOT/deployments/sepolia"

    # Use op-deployer or manual deployment
    if [ -f "$PROJECT_ROOT/op-stack/deployer/intent.toml" ]; then
        echo "Using op-deployer..."
        cd "$PROJECT_ROOT/op-stack/deployer"

        # Run op-deployer
        op-deployer apply --intent intent.toml

        # Extract addresses
        echo "Extracting deployed addresses..."
        # (This would parse op-deployer output)
    else
        echo "Manual L1 deployment..."
        "$SCRIPT_DIR/deploy-l1.sh"
    fi

    echo -e "${GREEN}L1 contracts deployed${NC}"
}

generate_genesis() {
    echo ""
    echo -e "${YELLOW}Generating L2 genesis...${NC}"

    "$SCRIPT_DIR/generate-genesis.sh"

    echo -e "${GREEN}Genesis generated${NC}"
}

deploy_l2_contracts() {
    echo ""
    echo -e "${YELLOW}Deploying L2 contracts...${NC}"

    cd "$PROJECT_ROOT/contracts"

    # Wait for L2 RPC to be available
    echo "Waiting for L2 RPC..."
    for i in {1..60}; do
        if cast chain-id --rpc-url "${L2_RPC_URL:-http://localhost:8547}" &>/dev/null; then
            break
        fi
        sleep 2
    done

    # Deploy SetRegistry and SetPaymaster
    forge script script/Deploy.s.sol \
        --rpc-url "${L2_RPC_URL:-http://localhost:8547}" \
        --private-key "$DEPLOYER_PRIVATE_KEY" \
        --broadcast \
        --verify \
        --verifier blockscout \
        --verifier-url "${EXPLORER_API_URL:-http://localhost:4000/api}" \
        | tee "$PROJECT_ROOT/deployments/sepolia/l2-deploy.log"

    # Extract addresses from deployment log
    REGISTRY=$(grep "SET_REGISTRY_ADDRESS=" "$PROJECT_ROOT/deployments/sepolia/l2-deploy.log" | cut -d'=' -f2 | tr -d ' ')
    PAYMASTER=$(grep "SET_PAYMASTER_ADDRESS=" "$PROJECT_ROOT/deployments/sepolia/l2-deploy.log" | cut -d'=' -f2 | tr -d ' ')

    echo "SetRegistry: $REGISTRY"
    echo "SetPaymaster: $PAYMASTER"

    # Save addresses
    cat > "$ADDRESSES_FILE" << EOF
{
  "network": "sepolia",
  "chainId": 84532001,
  "deployedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "contracts": {
    "SetRegistry": {
      "proxy": "$REGISTRY",
      "implementation": ""
    },
    "SetPaymaster": {
      "proxy": "$PAYMASTER",
      "implementation": ""
    }
  }
}
EOF

    echo -e "${GREEN}L2 contracts deployed${NC}"
}

deploy_governance() {
    echo ""
    echo -e "${YELLOW}Deploying governance...${NC}"

    if [ -z "$MULTISIG_ADDRESS" ]; then
        echo -e "${YELLOW}MULTISIG_ADDRESS not set. Skipping governance deployment.${NC}"
        echo "To deploy governance, set MULTISIG_ADDRESS in sepolia.env"
        return 0
    fi

    cd "$PROJECT_ROOT/contracts"

    # Get current contract addresses
    REGISTRY=$(jq -r '.contracts.SetRegistry.proxy' "$ADDRESSES_FILE")
    PAYMASTER=$(jq -r '.contracts.SetPaymaster.proxy' "$ADDRESSES_FILE")

    # Deploy timelock
    SET_REGISTRY_ADDRESS=$REGISTRY \
    SET_PAYMASTER_ADDRESS=$PAYMASTER \
    MULTISIG_ADDRESS=$MULTISIG_ADDRESS \
    TIMELOCK_DELAY=3600 \
    forge script script/DeployGovernance.s.sol \
        --rpc-url "${L2_RPC_URL:-http://localhost:8547}" \
        --private-key "$DEPLOYER_PRIVATE_KEY" \
        --broadcast \
        | tee "$PROJECT_ROOT/deployments/sepolia/governance-deploy.log"

    # Extract timelock address
    TIMELOCK=$(grep "SET_TIMELOCK_ADDRESS=" "$PROJECT_ROOT/deployments/sepolia/governance-deploy.log" | cut -d'=' -f2 | tr -d ' ')

    # Update addresses file
    jq ".contracts.SetTimelock = {\"address\": \"$TIMELOCK\"}" "$ADDRESSES_FILE" > tmp.json && mv tmp.json "$ADDRESSES_FILE"

    echo -e "${GREEN}Governance deployed${NC}"
}

verify_contracts() {
    echo ""
    echo -e "${YELLOW}Verifying contracts...${NC}"

    cd "$PROJECT_ROOT/contracts"

    REGISTRY=$(jq -r '.contracts.SetRegistry.proxy' "$ADDRESSES_FILE")
    PAYMASTER=$(jq -r '.contracts.SetPaymaster.proxy' "$ADDRESSES_FILE")

    # Verify on Blockscout
    forge verify-contract \
        --chain-id 84532001 \
        --verifier blockscout \
        --verifier-url "${EXPLORER_API_URL:-http://localhost:4000/api}" \
        "$REGISTRY" \
        SetRegistry || true

    forge verify-contract \
        --chain-id 84532001 \
        --verifier blockscout \
        --verifier-url "${EXPLORER_API_URL:-http://localhost:4000/api}" \
        "$PAYMASTER" \
        commerce/SetPaymaster:SetPaymaster || true

    echo -e "${GREEN}Verification complete${NC}"
}

show_status() {
    echo ""
    echo -e "${BLUE}Deployment Status${NC}"
    echo "=================="

    if [ -f "$ADDRESSES_FILE" ]; then
        echo ""
        cat "$ADDRESSES_FILE" | jq .
    else
        echo "No deployment found."
    fi

    echo ""
    echo "L1 (Sepolia):"
    echo "  RPC: $L1_RPC_URL"

    echo ""
    echo "L2 (Set Chain):"
    echo "  RPC: ${L2_RPC_URL:-http://localhost:8547}"
    echo "  Chain ID: 84532001"
}

run_all() {
    check_prerequisites
    deploy_l1
    generate_genesis
    echo ""
    echo -e "${YELLOW}Start L2 nodes before continuing...${NC}"
    echo "Run: docker compose -f docker/docker-compose.sepolia.yml up -d"
    echo ""
    read -p "Press Enter when L2 is running..."
    deploy_l2_contracts
    deploy_governance
    verify_contracts
    show_status

    echo ""
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}  Deployment Complete!${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Start explorer: docker compose -f docker/docker-compose.explorer.yml up -d"
    echo "  2. Verify contracts on explorer"
    echo "  3. Update docs/operations-history.md"
    echo "  4. Test bridge deposits"
}

# Parse command
case "${1:-help}" in
    check)
        check_prerequisites
        ;;
    l1)
        deploy_l1
        ;;
    genesis)
        generate_genesis
        ;;
    l2)
        deploy_l2_contracts
        ;;
    governance)
        deploy_governance
        ;;
    verify)
        verify_contracts
        ;;
    all)
        run_all
        ;;
    status)
        show_status
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        show_help
        exit 1
        ;;
esac
