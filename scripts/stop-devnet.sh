#!/bin/bash
# Set Chain - Stop Local Devnet
# Stops only recorded and identity-verified local OP Stack processes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROCESS_PYTHON="${LOCAL_ROLLUP_PYTHON:-python3}"
PID_DIR="$PROJECT_DIR/.pids"
source "$SCRIPT_DIR/local-lifecycle.sh"
umask 077
acquire_local_lifecycle_lock

echo "=== Stopping Set Chain Devnet ==="
echo ""

# Try every component, but never report global success after any refusal.
errors=0
for component in op-proposer op-batcher op-node op-geth; do
    "$PROCESS_PYTHON" "$SCRIPT_DIR/local-process.py" stop "$component" || errors=$((errors + 1))
done
if [ "$errors" -ne 0 ]; then
    echo "Stop incomplete: $errors ownership checks or stops failed; records retained."
    exit 1
fi

echo ""
echo "Devnet stopped"
