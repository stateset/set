#!/bin/bash
# Security Analysis Script for Set Chain Contracts
# Runs static analysis tools and generates reports

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONTRACTS_DIR="$PROJECT_ROOT/contracts"
REPORTS_DIR="$PROJECT_ROOT/reports/security"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=============================================${NC}"
echo -e "${BLUE}  Set Chain Security Analysis${NC}"
echo -e "${BLUE}=============================================${NC}"
echo ""

# Create reports directory
mkdir -p "$REPORTS_DIR"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for slither
run_slither() {
    echo -e "${YELLOW}Running Slither static analysis...${NC}"

    if ! command_exists slither; then
        echo -e "${RED}Slither not found. Install with: pip install slither-analyzer${NC}"
        echo -e "Skipping Slither analysis..."
        return 1
    fi

    cd "$CONTRACTS_DIR"

    # Run slither with JSON output
    echo "Analyzing SetRegistry.sol..."
    slither SetRegistry.sol \
        --config-file slither.config.json \
        --json "$REPORTS_DIR/slither-registry.json" \
        --markdown-root . \
        2>&1 | tee "$REPORTS_DIR/slither-registry.log" || true

    echo "Analyzing commerce/SetPaymaster.sol..."
    slither commerce/SetPaymaster.sol \
        --config-file slither.config.json \
        --json "$REPORTS_DIR/slither-paymaster.json" \
        --markdown-root . \
        2>&1 | tee "$REPORTS_DIR/slither-paymaster.log" || true

    echo "Analyzing governance/SetTimelock.sol..."
    slither governance/SetTimelock.sol \
        --config-file slither.config.json \
        --json "$REPORTS_DIR/slither-timelock.json" \
        --markdown-root . \
        2>&1 | tee "$REPORTS_DIR/slither-timelock.log" || true

    echo -e "${GREEN}Slither analysis complete. Reports saved to $REPORTS_DIR${NC}"
}

# Run Aderyn (Rust-based analyzer)
run_aderyn() {
    echo ""
    echo -e "${YELLOW}Running Aderyn static analysis...${NC}"

    if ! command_exists aderyn; then
        echo -e "${RED}Aderyn not found. Install with: cargo install aderyn${NC}"
        echo -e "Skipping Aderyn analysis..."
        return 1
    fi

    cd "$CONTRACTS_DIR"

    aderyn . \
        --output "$REPORTS_DIR/aderyn-report.md" \
        --exclude "lib/,test/,script/" \
        2>&1 | tee "$REPORTS_DIR/aderyn.log" || true

    echo -e "${GREEN}Aderyn analysis complete. Report saved to $REPORTS_DIR/aderyn-report.md${NC}"
}

# Run forge test with gas reporting
run_forge_tests() {
    echo ""
    echo -e "${YELLOW}Running Forge tests with gas reporting...${NC}"

    cd "$CONTRACTS_DIR"

    forge test --gas-report 2>&1 | tee "$REPORTS_DIR/forge-test-gas.log"

    echo -e "${GREEN}Forge tests complete.${NC}"
}

# Generate contract summary
generate_summary() {
    echo ""
    echo -e "${YELLOW}Generating contract summary...${NC}"

    cd "$CONTRACTS_DIR"

    # Contract sizes
    forge build --sizes 2>&1 | tee "$REPORTS_DIR/contract-sizes.log"

    # Storage layout
    forge inspect SetRegistry storage --pretty > "$REPORTS_DIR/storage-registry.txt" 2>/dev/null || true
    forge inspect SetPaymaster storage --pretty > "$REPORTS_DIR/storage-paymaster.txt" 2>/dev/null || true

    echo -e "${GREEN}Summary generated.${NC}"
}

# Generate markdown report
generate_markdown_report() {
    echo ""
    echo -e "${YELLOW}Generating markdown summary...${NC}"

    REPORT_FILE="$REPORTS_DIR/security-summary.md"

    cat > "$REPORT_FILE" << 'EOF'
# Set Chain Security Analysis Report

**Generated:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## Overview

This report summarizes the results of automated security analysis tools.

## Tools Used

| Tool | Purpose | Status |
|------|---------|--------|
| Slither | Static analysis for Solidity | See slither-*.json |
| Aderyn | Rust-based static analyzer | See aderyn-report.md |
| Forge | Test coverage and gas | See forge-test-gas.log |

## Contracts Analyzed

- SetRegistry.sol - Merkle root anchoring
- SetPaymaster.sol - Gas sponsorship
- SetTimelock.sol - Governance timelock

## Key Findings

Review the individual tool reports for detailed findings:

- `slither-registry.json` - SetRegistry findings
- `slither-paymaster.json` - SetPaymaster findings
- `slither-timelock.json` - SetTimelock findings
- `aderyn-report.md` - Cross-contract analysis

## Recommendations

1. Address all HIGH severity findings before deployment
2. Review MEDIUM findings and document accepted risks
3. Consider LOW findings during code review
4. Re-run analysis after any contract changes

## Next Steps

- [ ] Review and triage findings
- [ ] Fix critical issues
- [ ] Document accepted risks in threat model
- [ ] Schedule external audit
EOF

    # Replace the date placeholder
    sed -i "s/\$(date -u +\"%Y-%m-%d %H:%M:%S UTC\")/$(date -u +"%Y-%m-%d %H:%M:%S UTC")/" "$REPORT_FILE"

    echo -e "${GREEN}Report saved to $REPORT_FILE${NC}"
}

# Main execution
main() {
    echo "Starting security analysis..."
    echo ""

    run_slither
    run_aderyn
    run_forge_tests
    generate_summary
    generate_markdown_report

    echo ""
    echo -e "${BLUE}=============================================${NC}"
    echo -e "${GREEN}  Security Analysis Complete!${NC}"
    echo -e "${BLUE}=============================================${NC}"
    echo ""
    echo -e "Reports saved to: ${YELLOW}$REPORTS_DIR${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Review $REPORTS_DIR/security-summary.md"
    echo "  2. Triage findings in Slither JSON reports"
    echo "  3. Address HIGH/CRITICAL issues"
    echo "  4. Update docs/audit-report.md with self-audit findings"
    echo ""
}

# Parse arguments
case "${1:-all}" in
    slither)
        run_slither
        ;;
    aderyn)
        run_aderyn
        ;;
    tests)
        run_forge_tests
        ;;
    summary)
        generate_summary
        ;;
    all)
        main
        ;;
    *)
        echo "Usage: $0 {slither|aderyn|tests|summary|all}"
        exit 1
        ;;
esac
