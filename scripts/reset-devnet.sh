#!/bin/bash
# =============================================================================
# reset-devnet.sh
# Archive local devnet artifacts while idle and optionally restart Anvil
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$ROOT_DIR/config/chain-config.toml"

CHAIN_ID_DEFAULT=84532001
FORCE=false
NO_START=false

usage() {
    echo "Usage: $0 [--force] [--no-start]"
    echo "Stop your local node explicitly first. Artifacts are archived, not deleted."
    echo "--force skips confirmation only; busy ports and unsafe paths still fail."
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
            gsub(/"/, "", val)
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
    echo "This requires an idle port 8545 and archives local artifacts."
    if [ "$NO_START" = false ]; then
        echo "Anvil will then be restarted."
    fi
    read -r -p "Continue? [y/N] " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Aborted."
        exit 1
    fi
fi

args=(--chain-id "$CHAIN_ID")
if [ "$NO_START" = true ]; then
    args+=(--no-start)
fi
exec "${LOCAL_RESET_PYTHON:-python3}" "$SCRIPT_DIR/reset-local-artifacts.py" "${args[@]}"
