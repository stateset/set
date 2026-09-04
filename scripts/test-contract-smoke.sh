#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONTRACTS_DIR="$ROOT_DIR/contracts"

# shellcheck source=./foundry-common.sh
. "$SCRIPT_DIR/foundry-common.sh"

run_suite() {
    local name="$1"
    local source_dir="$2"
    local test_path="$3"
    local cache_dir="cache/smoke-${name}"
    local out_dir="out_smoke_${name}"

    echo "==> ${name}: ${test_path}"
    run_foundry_tool forge test \
        --contracts "$source_dir" \
        --match-path "$test_path" \
        --via-ir \
        --optimizer-runs 50 \
        --cache-path "$cache_dir" \
        --out "$out_dir" \
        -vv
}

cd "$CONTRACTS_DIR"
run_suite registry test/smoke test/smoke/SetRegistryAccounting.t.sol
run_suite escrow commerce test/OrderEscrow.t.sol
run_suite fx commerce test/FxOracle.t.sol
run_suite reserves stablecoin test/stablecoin/v2/ProofOfReservesV2.t.sol

echo "All critical contract smoke suites passed."
