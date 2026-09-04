#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONTRACTS_DIR="$ROOT_DIR/contracts"
REPORT_DIR="$CONTRACTS_DIR/coverage-reports"

# shellcheck source=scripts/foundry-common.sh
. "$SCRIPT_DIR/foundry-common.sh"

assert_line_coverage() {
    local report="$1"
    local target="$2"
    local minimum="$3"

    awk -v target="$target" -v minimum="$minimum" '
        $0 == "SF:" target { active = 1; next }
        active && /^LF:/ { split($0, fields, ":"); found = fields[2] }
        active && /^LH:/ { split($0, fields, ":"); hit = fields[2] }
        active && /^end_of_record/ {
            if (found == 0) {
                printf "No coverable lines found for %s\n", target > "/dev/stderr"
                exit 2
            }
            percent = (100 * hit) / found
            printf "%s line coverage: %.2f%% (%d/%d), required: %.2f%%\n", \
                target, percent, hit, found, minimum
            if (percent + 0.00001 < minimum) {
                exit 1
            }
            passed = 1
            exit 0
        }
        END {
            if (!passed && !active) {
                printf "Coverage record missing for %s\n", target > "/dev/stderr"
                exit 2
            }
        }
    ' "$report"
}

run_suite() {
    local name="$1"
    local profile="$2"
    local target="$3"
    local minimum="$4"
    shift 4

    echo "==> ${name}: ${target} (minimum ${minimum}% lines)"
    FOUNDRY_PROFILE="$profile" run_foundry_tool forge coverage \
        --ir-minimum \
        --exclude-tests \
        --report summary \
        --report lcov \
        --cache-path "cache/coverage-${name}" \
        --out "out_coverage_${name}" \
        "$@"

    mv lcov.info "$REPORT_DIR/${name}.lcov"
    assert_line_coverage "$REPORT_DIR/${name}.lcov" "$target" "$minimum"
}

mkdir -p "$REPORT_DIR"
cd "$CONTRACTS_DIR"

common_skips=(
    --skip script
    --skip governance
    --skip mev
)

run_suite registry coverage_registry SetRegistry.sol 65 \
    "${common_skips[@]}" \
    --skip stablecoin \
    --skip commerce \
    --skip coverage-src/escrow \
    --skip coverage-src/fx \
    --skip coverage-src/reserves \
    --skip coverage-test/escrow \
    --skip coverage-test/fx \
    --skip coverage-test/reserves

run_suite escrow coverage_escrow commerce/OrderEscrow.sol 90 \
    "${common_skips[@]}" \
    --skip SetRegistry.sol \
    --skip stablecoin \
    --skip commerce/FxOracle.sol \
    --skip commerce/SetPaymaster.sol \
    --skip commerce/SetPaymentBatch.sol \
    --skip coverage-src/registry \
    --skip coverage-src/fx \
    --skip coverage-src/reserves \
    --skip coverage-test/registry \
    --skip coverage-test/fx \
    --skip coverage-test/reserves

run_suite fx coverage_fx commerce/FxOracle.sol 95 \
    "${common_skips[@]}" \
    --skip SetRegistry.sol \
    --skip stablecoin \
    --skip commerce/OrderEscrow.sol \
    --skip commerce/SetPaymaster.sol \
    --skip commerce/SetPaymentBatch.sol \
    --skip coverage-src/registry \
    --skip coverage-src/escrow \
    --skip coverage-src/reserves \
    --skip coverage-test/registry \
    --skip coverage-test/escrow \
    --skip coverage-test/reserves

run_suite reserves coverage_reserves stablecoin/v2/ProofOfReservesV2.sol 80 \
    "${common_skips[@]}" \
    --skip SetRegistry.sol \
    --skip commerce \
    --skip coverage-src/registry \
    --skip coverage-src/escrow \
    --skip coverage-src/fx \
    --skip coverage-test/registry \
    --skip coverage-test/escrow \
    --skip coverage-test/fx

echo "All critical contract coverage thresholds passed."
