FROM node:20-bookworm-slim

# RPC-to-ledger integration uses the Python standard-library SQLite driver.
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/*
