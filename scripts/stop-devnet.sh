#!/bin/bash
# Set Chain - Stop Local Devnet
# Stops all OP Stack components

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PID_DIR="$PROJECT_DIR/.pids"

echo "=== Stopping Set Chain Devnet ==="
echo ""

# Stop a process by PID file
stop_process() {
    local name=$1
    local pid_file="$PID_DIR/$name.pid"

    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Stopping $name (PID: $pid)..."
            kill "$pid"
            sleep 1
            # Force kill if still running
            if kill -0 "$pid" 2>/dev/null; then
                kill -9 "$pid" 2>/dev/null || true
            fi
            echo "  $name stopped"
        else
            echo "  $name already stopped"
        fi
        rm "$pid_file"
    else
        echo "  $name not running"
    fi
}

# Stop all components (reverse order)
stop_process "op-proposer"
stop_process "op-batcher"
stop_process "op-node"
stop_process "op-geth"

echo ""
echo "Devnet stopped"
