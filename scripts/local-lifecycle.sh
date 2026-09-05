#!/bin/bash
# Shared advisory lock for the local OP Stack start/stop helpers.
# Descriptor 9 must be closed in long-running children so they do not retain it.
acquire_local_lifecycle_lock() {
    command -v flock >/dev/null 2>&1 || {
        echo "Error: flock is required for local lifecycle operations." >&2
        return 1
    }
    if [ -L "$PID_DIR" ] || [ -L "$PID_DIR/lifecycle.lock" ]; then
        echo "Error: symlinked lifecycle directory or lock; refusing operation." >&2
        return 1
    fi
    mkdir -p "$PID_DIR"
    if [ -e "$PID_DIR/lifecycle.lock" ] && [ ! -f "$PID_DIR/lifecycle.lock" ]; then
        echo "Error: lifecycle lock must be a regular file." >&2
        return 1
    fi
    exec 9>>"$PID_DIR/lifecycle.lock"
    if ! flock -n 9; then
        echo "Error: another local start/stop operation is active." >&2
        exec 9>&-
        return 1
    fi
}
