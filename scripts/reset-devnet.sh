#!/bin/bash
# =============================================================================
# reset-devnet.sh
# Reset local devnet artifacts and restart Anvil
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$ROOT_DIR/config/chain-config.toml"

CHAIN_ID_DEFAULT=84532001
FORCE=false
NO_START=false

usage() {
    echo "Usage: $0 [--force] [--no-start]"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --force)
            FORCE=true
            ;;
        --no-start)
            NO_START=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

read_toml_value() {
    local section="$1"
    local key="$2"

    if [ ! -f "$CONFIG_FILE" ]; then
        return 0
    fi

    awk -v section="$section" -v key="$key" '
        $0 ~ "^[[:space:]]*\\[" {
            in_section = ($0 ~ "^[[:space:]]*\\[" section "\\][[:space:]]*$")
        }
        in_section && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            split($0, parts, "=")
            val = parts[2]
            sub(/#.*/, "", val)
            gsub(/[[:space:]]+/, "", val)
            gsub(/\"/, "", val)
            print val
            exit
        }
    ' "$CONFIG_FILE"
}

CHAIN_ID="$(read_toml_value chain chain_id)"
if [ -z "$CHAIN_ID" ]; then
    CHAIN_ID="$CHAIN_ID_DEFAULT"
fi

if [ "$FORCE" = false ]; then
    echo "This will stop Anvil on port 8545, remove local artifacts, and restart."
    read -r -p "Continue? [y/N] " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Aborted."
        exit 1
    fi
fi

PIDS=""
if command -v lsof >/dev/null 2>&1; then
    PIDS="$(lsof -ti tcp:8545 || true)"
elif command -v pgrep >/dev/null 2>&1; then
    PIDS="$(pgrep -f "anvil.*--port 8545" || true)"
fi

if [ -n "$PIDS" ]; then
    echo "Stopping Anvil..."
    for pid in $PIDS; do
        kill "$pid" 2>/dev/null || true
    done
    sleep 1
else
    echo "No Anvil process found on port 8545."
fi

echo "Removing devnet artifacts..."
if [ -d "$ROOT_DIR/contracts/broadcast" ]; then
    find "$ROOT_DIR/contracts/broadcast" -maxdepth 2 -type d -name "$CHAIN_ID" -exec rm -rf {} +
fi
rm -rf "$ROOT_DIR/contracts/cache"
rm -rf "$ROOT_DIR/contracts/out"

if [ "$NO_START" = true ]; then
    echo "Reset complete. Skipping restart."
    exit 0
fi

exec "$SCRIPT_DIR/start-local-anvil.sh"
