#!/bin/bash
# Set Chain - L1 Contract Deployment Script
# Deploys OP Stack contracts to Ethereum Sepolia

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DEPLOYER_DIR="$PROJECT_DIR/op-stack/deployer"

echo "=== Set Chain L1 Contract Deployment ==="
echo ""

# Load environment
if [ -f "$PROJECT_DIR/config/sepolia.env" ]; then
    source "$PROJECT_DIR/config/sepolia.env"
else
    echo "Error: sepolia.env not found. Copy from template and configure."
    exit 1
fi

# Validate required environment variables
validate_env() {
    local missing=0

    for var in L1_RPC_URL DEPLOYER_PRIVATE_KEY ADMIN_ADDRESS BATCHER_ADDRESS \
               PROPOSER_ADDRESS SEQUENCER_ADDRESS CHALLENGER_ADDRESS; do
        if [ -z "${!var}" ] || [[ "${!var}" == "0x00000000"* ]]; then
            echo "Error: $var is not configured"
            missing=1
        fi
    done

    if [ $missing -eq 1 ]; then
        echo ""
        echo "Please configure all required addresses and keys in config/sepolia.env"
        echo ""
        echo "To generate new accounts:"
        echo "  cast wallet new"
        echo ""
        echo "Fund accounts with Sepolia ETH from faucet:"
        echo "  https://sepoliafaucet.com/"
        echo "  https://www.alchemy.com/faucets/ethereum-sepolia"
        exit 1
    fi

    echo "Environment validation passed"
}

# Check deployer balance
check_balance() {
    echo ""
    echo "Checking deployer balance..."

    local balance=$(cast balance --rpc-url "$L1_RPC_URL" "$DEPLOYER_ADDRESS" 2>/dev/null || echo "0")
    local balance_eth=$(cast from-wei "$balance" ether 2>/dev/null || echo "0")

    echo "Deployer balance: $balance_eth ETH"

    # Need at least 1.5 ETH for deployment
    local min_balance="1500000000000000000"  # 1.5 ETH in wei
    if [ "$balance" -lt "$min_balance" ] 2>/dev/null; then
        echo "Warning: Low balance. Deployment requires ~1.5-3.5 ETH"
        echo "Fund deployer address: $DEPLOYER_ADDRESS"
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Substitute environment variables in intent.toml
prepare_intent() {
    echo ""
    echo "Preparing intent.toml..."

    # Create a processed intent file with substituted variables
    envsubst < "$DEPLOYER_DIR/intent.toml" > "$DEPLOYER_DIR/intent.processed.toml"

    echo "Intent file prepared at: $DEPLOYER_DIR/intent.processed.toml"
}

# Initialize deployment
init_deployment() {
    echo ""
    echo "Initializing op-deployer..."

    cd "$DEPLOYER_DIR"

    # Initialize if state.json doesn't exist
    if [ ! -f "state.json" ]; then
        op-deployer init \
            --l1-chain-id "$L1_CHAIN_ID" \
            --l2-chain-ids "$L2_CHAIN_ID" \
            --outdir . \
            --intent-config-type standard-overrides

        echo "Deployment initialized"
    else
        echo "state.json already exists, skipping init"
    fi
}

# Apply deployment
apply_deployment() {
    echo ""
    echo "Applying deployment to L1..."

    cd "$DEPLOYER_DIR"

    # Use the processed intent file
    op-deployer apply \
        --l1-rpc-url "$L1_RPC_URL" \
        --private-key "$DEPLOYER_PRIVATE_KEY" \
        --intent-file intent.processed.toml \
        --outdir . \
        --confirm

    echo ""
    echo "Deployment complete!"
}

# Extract deployed addresses
extract_addresses() {
    echo ""
    echo "Extracting deployed contract addresses..."

    cd "$DEPLOYER_DIR"

    if [ ! -f "state.json" ]; then
        echo "Error: state.json not found after deployment"
        exit 1
    fi

    # Extract addresses using jq
    local portal=$(jq -r '.deployedAddresses.optimismPortal // empty' state.json)
    local oracle=$(jq -r '.deployedAddresses.l2OutputOracle // empty' state.json)
    local config=$(jq -r '.deployedAddresses.systemConfig // empty' state.json)
    local bridge=$(jq -r '.deployedAddresses.l1StandardBridge // empty' state.json)
    local messenger=$(jq -r '.deployedAddresses.l1CrossDomainMessenger // empty' state.json)

    echo ""
    echo "=== Deployed Contract Addresses ==="
    echo "OPTIMISM_PORTAL_ADDRESS=$portal"
    echo "L2_OUTPUT_ORACLE_ADDRESS=$oracle"
    echo "SYSTEM_CONFIG_ADDRESS=$config"
    echo "L1_STANDARD_BRIDGE_ADDRESS=$bridge"
    echo "L1_CROSS_DOMAIN_MESSENGER_ADDRESS=$messenger"

    # Update env file
    echo ""
    echo "Updating sepolia.env with deployed addresses..."

    sed -i "s|^OPTIMISM_PORTAL_ADDRESS=.*|OPTIMISM_PORTAL_ADDRESS=$portal|" "$PROJECT_DIR/config/sepolia.env"
    sed -i "s|^L2_OUTPUT_ORACLE_ADDRESS=.*|L2_OUTPUT_ORACLE_ADDRESS=$oracle|" "$PROJECT_DIR/config/sepolia.env"
    sed -i "s|^SYSTEM_CONFIG_ADDRESS=.*|SYSTEM_CONFIG_ADDRESS=$config|" "$PROJECT_DIR/config/sepolia.env"
    sed -i "s|^L1_STANDARD_BRIDGE_ADDRESS=.*|L1_STANDARD_BRIDGE_ADDRESS=$bridge|" "$PROJECT_DIR/config/sepolia.env"
    sed -i "s|^L1_CROSS_DOMAIN_MESSENGER_ADDRESS=.*|L1_CROSS_DOMAIN_MESSENGER_ADDRESS=$messenger|" "$PROJECT_DIR/config/sepolia.env"

    echo "Environment file updated"
}

# Verify deployment
verify_deployment() {
    echo ""
    echo "Verifying deployment..."

    cd "$DEPLOYER_DIR"

    # Check if state.json has deployment data
    local deployed_count=$(jq '.deployedAddresses | length' state.json 2>/dev/null || echo "0")

    if [ "$deployed_count" -gt 0 ]; then
        echo "Verification passed: $deployed_count contracts deployed"
    else
        echo "Warning: No contracts found in state.json"
    fi
}

# Print next steps
print_next_steps() {
    echo ""
    echo "=== Deployment Complete ==="
    echo ""
    echo "Next steps:"
    echo "  1. Generate genesis files:"
    echo "     ./scripts/generate-genesis.sh"
    echo ""
    echo "  2. Start the local devnet:"
    echo "     ./scripts/start-devnet.sh"
    echo ""
    echo "  3. Deploy Set Chain custom contracts:"
    echo "     ./scripts/deploy-set-contracts.sh"
    echo ""
}

# Main deployment flow
main() {
    validate_env
    check_balance
    prepare_intent
    init_deployment
    apply_deployment
    extract_addresses
    verify_deployment
    print_next_steps
}

main "$@"
