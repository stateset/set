#!/usr/bin/env bash
set -euo pipefail

# Alloy 0.8 pins lru 0.12.5. The two exceptions below are documented with reachability,
# compensating controls, and an expiry in docs/security-exceptions.md. All other unsound
# advisories fail the build.
cargo audit --deny unsound \
    --ignore RUSTSEC-2026-0002 \
    --ignore RUSTSEC-2026-0253 \
    "$@"
