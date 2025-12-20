#!/bin/bash
# =============================================================================
# test-anchor.sh
# Run anchor service tests
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANCHOR_DIR="$(dirname "$SCRIPT_DIR")/anchor"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

cd "$ANCHOR_DIR"

# Parse arguments
RUN_ALL=false
RUN_IGNORED=false
VERBOSE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            RUN_ALL=true
            shift
            ;;
        --ignored)
            RUN_IGNORED=true
            shift
            ;;
        -v|--verbose)
            VERBOSE="--nocapture"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

echo "=============================================="
echo "  Anchor Service Test Suite"
echo "=============================================="
echo ""

# Check if anvil is available
ANVIL_AVAILABLE=false
if command -v anvil &> /dev/null; then
    ANVIL_AVAILABLE=true
    log_info "Anvil found - contract tests available"
else
    log_warn "Anvil not found - contract tests will be skipped"
    log_info "Install with: curl -L https://foundry.paradigm.xyz | bash && foundryup"
fi

# Run unit tests
log_info "Running unit tests..."
cargo test --lib $VERBOSE
log_success "Unit tests passed"

# Run integration tests (mock API)
log_info "Running integration tests (mock API)..."
cargo test --test integration $VERBOSE
log_success "Integration tests passed"

# Run contract tests if requested and anvil available
if [ "$RUN_ALL" = true ] || [ "$RUN_IGNORED" = true ]; then
    if [ "$ANVIL_AVAILABLE" = true ]; then
        log_info "Running contract integration tests..."
        cargo test --test integration -- --ignored $VERBOSE
        log_success "Contract tests passed"
    else
        log_warn "Skipping contract tests - anvil not available"
    fi
fi

echo ""
echo "=============================================="
echo "  All Tests Passed!"
echo "=============================================="
