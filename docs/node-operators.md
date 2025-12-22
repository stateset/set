# Set Chain Node Operator Guide

## Scope
This guide covers running an L2 node for verification and monitoring. It does
not cover sequencer operations.

## Hardware and Network
- CPU: 4+ cores
- RAM: 16+ GB
- Storage: 1 TB SSD (fast NVMe preferred)
- Network: stable broadband with low latency

## Required Ports
- L2 RPC: 8547 (HTTP)
- L2 WS: 8548 (WebSocket)
- Engine API: 8551 (op-node to op-geth)
- P2P: configured per OP Stack defaults

## Configuration
- `config/chain-config.toml`: set `sequencer.p2p_enabled = true` for shared
  networks and `sequencer.l1_confs >= 1` for safer derivation.
- `config/sepolia.env`: ensure L1 and L2 RPC endpoints are set.

## Running a Node
You can run a node using the docker configs in `docker/` or with binaries
installed via `scripts/install-op-stack.sh`.

1. Configure environment variables in `config/sepolia.env`.
2. Start op-geth and op-node (see `docker/docker-compose.sepolia.yml`).
3. Confirm sync status:

```bash
curl -s http://localhost:9545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"optimism_syncStatus","params":[],"id":1}' | jq
```

## Incentives
Operator incentives are governed by the fee vault recipients configured in
`config/chain-config.toml` and the governance policy in `docs/security.md`.
Specific distribution schedules will be set by governance.
