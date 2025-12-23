#!/bin/bash
# Fault Proof Exercise Script for Set Chain
# Tests the dispute resolution mechanism on OP Stack

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
L1_RPC_URL="${L1_RPC_URL:-http://localhost:8545}"
L2_RPC_URL="${L2_RPC_URL:-http://localhost:8547}"
CHALLENGER_KEY="${CHALLENGER_KEY:-}"
DISPUTE_GAME_FACTORY="${DISPUTE_GAME_FACTORY:-}"
ANCHOR_STATE_REGISTRY="${ANCHOR_STATE_REGISTRY:-}"

echo -e "${BLUE}=============================================${NC}"
echo -e "${BLUE}  Set Chain Fault Proof Exercise${NC}"
echo -e "${BLUE}=============================================${NC}"
echo ""

# Check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"

    # Check cast is available
    if ! command -v cast &> /dev/null; then
        echo -e "${RED}Error: cast not found. Install Foundry.${NC}"
        exit 1
    fi

    # Check L1 RPC
    if ! cast chain-id --rpc-url "$L1_RPC_URL" &> /dev/null; then
        echo -e "${RED}Error: Cannot connect to L1 RPC at $L1_RPC_URL${NC}"
        exit 1
    fi

    # Check L2 RPC
    if ! cast chain-id --rpc-url "$L2_RPC_URL" &> /dev/null; then
        echo -e "${RED}Error: Cannot connect to L2 RPC at $L2_RPC_URL${NC}"
        exit 1
    fi

    echo -e "${GREEN}Prerequisites OK${NC}"
    echo ""
}

# Get current L2 state
get_l2_state() {
    echo -e "${YELLOW}Fetching current L2 state...${NC}"

    L2_BLOCK=$(cast block-number --rpc-url "$L2_RPC_URL")
    L2_STATE_ROOT=$(cast block --rpc-url "$L2_RPC_URL" -f stateRoot)
    L2_BLOCK_HASH=$(cast block --rpc-url "$L2_RPC_URL" -f hash)

    echo "  L2 Block Number: $L2_BLOCK"
    echo "  L2 State Root:   $L2_STATE_ROOT"
    echo "  L2 Block Hash:   $L2_BLOCK_HASH"
    echo ""
}

# List active dispute games
list_disputes() {
    echo -e "${YELLOW}Listing active dispute games...${NC}"

    if [ -z "$DISPUTE_GAME_FACTORY" ]; then
        echo -e "${RED}DISPUTE_GAME_FACTORY not set${NC}"
        return 1
    fi

    # Get game count
    GAME_COUNT=$(cast call "$DISPUTE_GAME_FACTORY" "gameCount()(uint256)" --rpc-url "$L1_RPC_URL" 2>/dev/null || echo "0")
    echo "  Total games: $GAME_COUNT"

    if [ "$GAME_COUNT" != "0" ]; then
        echo ""
        echo "  Recent games:"
        for i in $(seq 0 $((GAME_COUNT > 5 ? 4 : GAME_COUNT - 1))); do
            GAME=$(cast call "$DISPUTE_GAME_FACTORY" "gameAtIndex(uint256)(address,uint32,uint64)" "$i" --rpc-url "$L1_RPC_URL" 2>/dev/null || echo "unknown")
            echo "    [$i] $GAME"
        done
    fi
    echo ""
}

# Create a test dispute (for exercise purposes only)
create_test_dispute() {
    echo -e "${YELLOW}Creating test dispute...${NC}"
    echo -e "${RED}WARNING: This is for testing only. Do not run on mainnet.${NC}"
    echo ""

    if [ -z "$CHALLENGER_KEY" ]; then
        echo -e "${RED}CHALLENGER_KEY not set${NC}"
        return 1
    fi

    if [ -z "$DISPUTE_GAME_FACTORY" ]; then
        echo -e "${RED}DISPUTE_GAME_FACTORY not set${NC}"
        return 1
    fi

    # Get the latest output proposal
    echo "  Fetching latest output..."

    # Create dispute with a known-bad claim (for testing)
    # In a real scenario, this would be triggered by op-challenger detecting a bad output
    BAD_CLAIM="0x0000000000000000000000000000000000000000000000000000000000000bad"

    echo "  Creating dispute game with bad claim: $BAD_CLAIM"
    echo "  (This should be challenged and resolved)"
    echo ""

    # Note: Actual dispute creation requires specific game type and parameters
    # This is a placeholder for the exercise documentation
    echo -e "${YELLOW}To create a real dispute, use op-challenger:${NC}"
    echo "  op-challenger \\"
    echo "    --l1-eth-rpc \$L1_RPC_URL \\"
    echo "    --game-factory-address $DISPUTE_GAME_FACTORY \\"
    echo "    --private-key \$CHALLENGER_KEY \\"
    echo "    --trace-type cannon"
    echo ""
}

# Monitor a dispute game
monitor_dispute() {
    GAME_ADDRESS="${1:-}"

    if [ -z "$GAME_ADDRESS" ]; then
        echo -e "${RED}Usage: $0 monitor <game_address>${NC}"
        return 1
    fi

    echo -e "${YELLOW}Monitoring dispute game: $GAME_ADDRESS${NC}"

    # Get game status
    STATUS=$(cast call "$GAME_ADDRESS" "status()(uint8)" --rpc-url "$L1_RPC_URL" 2>/dev/null || echo "unknown")
    ROOT_CLAIM=$(cast call "$GAME_ADDRESS" "rootClaim()(bytes32)" --rpc-url "$L1_RPC_URL" 2>/dev/null || echo "unknown")
    CREATED_AT=$(cast call "$GAME_ADDRESS" "createdAt()(uint64)" --rpc-url "$L1_RPC_URL" 2>/dev/null || echo "unknown")

    echo "  Status:     $STATUS (0=In Progress, 1=Challenger Wins, 2=Defender Wins)"
    echo "  Root Claim: $ROOT_CLAIM"
    echo "  Created At: $CREATED_AT"
    echo ""
}

# Run full exercise
run_exercise() {
    echo "Starting fault proof exercise..."
    echo ""

    check_prerequisites
    get_l2_state
    list_disputes

    echo -e "${BLUE}=============================================${NC}"
    echo -e "${BLUE}  Exercise Complete${NC}"
    echo -e "${BLUE}=============================================${NC}"
    echo ""
    echo "Next steps to complete the fault proof exercise:"
    echo ""
    echo "1. Deploy op-challenger pointing at your L1 contracts:"
    echo "   docker compose -f docker/docker-compose.yml --profile challenger up"
    echo ""
    echo "2. Submit a fraudulent output (on testnet only):"
    echo "   cast send \$L2_OUTPUT_ORACLE \"proposeL2Output(bytes32,uint256,bytes32,uint256)\" \\"
    echo "     0xbad... \$L2_BLOCK_NUMBER 0x... \$L1_BLOCK_NUMBER \\"
    echo "     --private-key \$PROPOSER_KEY --rpc-url \$L1_RPC_URL"
    echo ""
    echo "3. Observe op-challenger detect and dispute the bad output"
    echo ""
    echo "4. Wait for the dispute game to resolve (challenger should win)"
    echo ""
    echo "5. Document the exercise in docs/fault-proof-exercise.md"
    echo ""
}

# Generate exercise report
generate_report() {
    REPORT_FILE="$PROJECT_ROOT/reports/fault-proof-exercise-$(date +%Y%m%d-%H%M%S).md"
    mkdir -p "$(dirname "$REPORT_FILE")"

    cat > "$REPORT_FILE" << EOF
# Fault Proof Exercise Report

**Date:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")
**Network:** ${NETWORK:-sepolia}
**L1 RPC:** $L1_RPC_URL
**L2 RPC:** $L2_RPC_URL

## Environment

- Dispute Game Factory: $DISPUTE_GAME_FACTORY
- Anchor State Registry: $ANCHOR_STATE_REGISTRY
- Challenger Version: $(op-challenger --version 2>/dev/null || echo "N/A")

## L2 State at Exercise Start

$(get_l2_state 2>&1)

## Dispute Games

$(list_disputes 2>&1)

## Exercise Steps Completed

- [ ] Deployed op-challenger
- [ ] Submitted test fraudulent output
- [ ] Observed dispute detection
- [ ] Verified dispute resolution
- [ ] Confirmed honest state prevailed

## Observations

_Add observations from the exercise here_

## Lessons Learned

_Add lessons learned here_

## Evidence

- Dispute game address:
- L1 transaction hashes:
- Screenshots:

EOF

    echo -e "${GREEN}Report generated: $REPORT_FILE${NC}"
    echo "Edit this file to document your exercise results."
}

# Help
show_help() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  check      Check prerequisites"
    echo "  state      Show current L2 state"
    echo "  list       List active dispute games"
    echo "  monitor    Monitor a dispute game (requires game address)"
    echo "  exercise   Run the full exercise walkthrough"
    echo "  report     Generate an exercise report template"
    echo "  help       Show this help"
    echo ""
    echo "Environment variables:"
    echo "  L1_RPC_URL              L1 RPC endpoint"
    echo "  L2_RPC_URL              L2 RPC endpoint"
    echo "  CHALLENGER_KEY          Private key for challenger"
    echo "  DISPUTE_GAME_FACTORY    DisputeGameFactory address"
    echo "  ANCHOR_STATE_REGISTRY   AnchorStateRegistry address"
    echo ""
}

# Main
case "${1:-help}" in
    check)
        check_prerequisites
        ;;
    state)
        get_l2_state
        ;;
    list)
        list_disputes
        ;;
    monitor)
        monitor_dispute "$2"
        ;;
    create)
        create_test_dispute
        ;;
    exercise)
        run_exercise
        ;;
    report)
        generate_report
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
