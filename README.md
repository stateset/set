# Set Chain (SSC)

[![Solidity](https://img.shields.io/badge/Solidity-0.8.20-blue)](https://soliditylang.org/)
[![Rust](https://img.shields.io/badge/Rust-2021-orange)](https://www.rust-lang.org/)
[![OP Stack](https://img.shields.io/badge/OP%20Stack-v1.8.0-red)](https://docs.optimism.io/)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

Set Chain is an Ethereum Layer-2 (L2) network built on the **OP Stack**, designed for **commerce**. It offers faster, cheaper, and cryptographically verifiable transactions by leveraging optimistic rollups with Merkle root anchoring.

## Table of Contents

- [Architecture](#architecture)
- [Key Features](#key-features)
- [Chain Configuration](#chain-configuration)
- [Directory Structure](#directory-structure)
- [Technology Stack](#technology-stack)
- [Quick Start](#quick-start)
  - [Local Development (Anvil)](#local-development-anvil)
  - [Full Devnet](#full-devnet)
- [Smart Contracts](#smart-contracts)
  - [SetRegistry](#setregistry)
  - [SetPaymaster](#setpaymaster)
- [Anchor Service](#anchor-service)
- [Integration with stateset-sequencer](#integration-with-stateset-sequencer)
- [Docker Deployment](#docker-deployment)
- [Testing](#testing)
- [Deployment Checklist](#deployment-checklist)
- [Monitoring](#monitoring)
- [Security](#security)
- [Decentralization and Fault Proofs](#decentralization-and-fault-proofs)
- [Scorecard](#scorecard)
- [Troubleshooting](#troubleshooting)
- [Resources](#resources)

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           SET CHAIN L2 (84532001)                       │
│                      (Commerce-Optimized OP Stack)                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐ │
│  │   op-geth    │  │   op-node    │  │  op-batcher  │  │ op-proposer │ │
│  │  (execution) │  │  (consensus) │  │   (batches)  │  │   (state)   │ │
│  └──────────────┘  └──────────────┘  └──────────────┘  └─────────────┘ │
│         │                │                  │                │         │
│         └────────────────┼──────────────────┴────────────────┘         │
│                          │                                              │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                    Smart Contracts                                │  │
│  │  ┌─────────────────────────┐  ┌────────────────────────────────┐ │  │
│  │  │      SetRegistry        │  │         SetPaymaster           │ │  │
│  │  │  (Merkle root anchoring │  │  (Gas abstraction for          │ │  │
│  │  │   from sequencer)       │  │   merchant transactions)       │ │  │
│  │  └─────────────────────────┘  └────────────────────────────────┘ │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                          │                                              │
└──────────────────────────┼──────────────────────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  │                  ▼
┌───────────────────┐      │      ┌─────────────────────────┐
│  Anchor Service   │      │      │  stateset-sequencer     │
│  (Rust)           │◄─────┴─────►│  (Off-chain commerce    │
│  - Health metrics │             │   event processing)     │
│  - Batch anchoring│             └─────────────────────────┘
└───────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      ETHEREUM SEPOLIA (L1) - 11155111                   │
│         OptimismPortal │ L2OutputOracle │ SystemConfig                  │
└─────────────────────────────────────────────────────────────────────────┘
```

## Key Features

| Feature | Description |
|---------|-------------|
| **2-second block times** | Fast confirmations optimized for commerce operations |
| **Low gas fees** | EIP-1559 parameters tuned for merchant transactions |
| **Merkle root anchoring** | Verifiable event commitments from stateset-sequencer |
| **Multi-tenant isolation** | Per-tenant/store state tracking via `keccak256(tenantId, storeId)` |
| **Inclusion proof verification** | On-chain verification of off-chain events |
| **Gas sponsorship** | Merchants can sponsor user transactions via SetPaymaster |
| **Strict mode verification** | State chain continuity checking to prevent gaps/forks |

## Chain Configuration

| Parameter | Value |
|-----------|-------|
| Chain ID | `84532001` |
| Block Time | 2 seconds |
| Gas Limit | 30M gas/block |
| L1 Settlement | Ethereum Sepolia (11155111) |
| Native Token | ETH |
| EVM Version | Cancun |
| OP Contracts Version | v1.8.0 |

## Directory Structure

```
set/
├── anchor/                     # Rust anchor service
│   ├── src/
│   │   ├── main.rs            # Entry point
│   │   ├── config.rs          # Configuration from env vars
│   │   ├── client.rs          # Sequencer API client
│   │   ├── service.rs         # Main anchor logic
│   │   ├── health.rs          # Health/metrics HTTP server
│   │   └── types.rs           # Data structures
│   └── tests/
│       └── integration.rs     # Integration tests
├── contracts/                  # Solidity smart contracts
│   ├── src/
│   │   ├── SetRegistry.sol    # Merkle root anchoring (433 lines)
│   │   └── commerce/
│   │       └── SetPaymaster.sol # Gas abstraction (558 lines)
│   ├── test/
│   │   ├── SetRegistry.t.sol  # Registry tests
│   │   └── SetPaymaster.t.sol # Paymaster tests
│   └── lib/                   # Dependencies (git submodules)
│       ├── forge-std/         # Foundry testing framework
│       └── openzeppelin-contracts/
├── op-stack/                   # OP Stack configuration
│   ├── deployer/              # op-deployer intent files
│   ├── batcher/               # Batch submission config
│   ├── proposer/              # State root submission config
│   ├── challenger/            # Dispute resolution config
│   └── sequencer/             # op-geth/op-node config
├── docker/                     # Docker Compose files
│   ├── docker-compose.yml     # Main local devnet
│   ├── docker-compose.sepolia.yml
│   ├── docker-compose.local.yml
│   └── config/                # JWT and node configs
├── scripts/                    # Deployment and management
│   ├── dev.sh                 # Local Anvil development helper
│   ├── anchor-devnet.sh       # Anchor service local helper
│   ├── deploy-set-contracts.sh
│   ├── deploy-l1.sh
│   ├── generate-genesis.sh
│   ├── reset-devnet.sh
│   ├── start-devnet.sh
│   ├── stop-devnet.sh
│   ├── quick-start-local.sh
│   └── install-op-stack.sh
├── config/                     # Chain configuration
│   ├── chain-config.toml     # L2 chain parameters
│   ├── local.env.example     # Local devnet env template
│   └── sepolia.env.example   # Sepolia env template
└── docs/                       # Documentation
    ├── README.md              # Architecture overview
    └── local_testing_guide.md # Anvil testing guide
```

## Technology Stack

### Languages & Frameworks

| Component | Technology | Version |
|-----------|------------|---------|
| Smart Contracts | Solidity | 0.8.20 |
| Contract Framework | Foundry (Forge) | Latest |
| Anchor Service | Rust | 2021 Edition |
| Async Runtime | Tokio | Full features |
| Ethereum Client | Alloy | 0.9 |
| HTTP Server | Axum | 0.8 |
| Scripting | Bash | - |

### OP Stack Components

| Component | Purpose |
|-----------|---------|
| op-geth | L2 execution client (EVM) |
| op-node | L2 consensus client |
| op-batcher | Submits transaction batches to L1 |
| op-proposer | Submits state roots to L1 |
| op-challenger | Dispute resolution |

### Dependencies

**Solidity:**
- OpenZeppelin Contracts (Upgradeable patterns)
- Forge-std (Testing)

**Rust:**
- `tokio` - Async runtime
- `alloy` - Ethereum interactions
- `axum` - HTTP server for health endpoints
- `tracing` - Structured logging
- `serde` - Serialization
- `reqwest` - HTTP client

## Quick Start

### Local Development (Anvil)

The fastest way to get started for development and testing:

```bash
# 1. Start local Anvil node (Chain ID: 84532001, 2s blocks)
./scripts/dev.sh start

# 2. Deploy contracts to local Anvil
./scripts/dev.sh deploy

# 3. Run contract tests
./scripts/dev.sh test

# 4. Check node status
./scripts/dev.sh status

# 5. Fund a test account
./scripts/dev.sh fund 0xYourAddress

# Other commands
./scripts/dev.sh accounts  # List pre-funded accounts
./scripts/dev.sh console   # Open Foundry console
```

**Pre-funded Test Accounts:**

| Account | Address | Private Key |
|---------|---------|-------------|
| Account 0 | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` | `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` |
| Account 1 | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` | `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d` |
| ... | See `./scripts/dev.sh accounts` for all 10 accounts |

### Full Devnet

For a complete L2 environment with all OP Stack components:

**Prerequisites:**
- Go 1.21+
- Rust 1.70+
- Docker & Docker Compose
- 2+ ETH on Sepolia (for deployment)

```bash
# 1. Install OP Stack binaries
./scripts/install-op-stack.sh

# 2. Configure environment
cp config/sepolia.env.example config/sepolia.env
# Edit sepolia.env with your addresses and private keys

# 3. Deploy L1 contracts to Sepolia
./scripts/deploy-l1.sh

# 4. Generate L2 genesis
./scripts/generate-genesis.sh

# 5. Start the devnet
./scripts/start-devnet.sh

# Or use quick-start for minimal setup
./scripts/quick-start-local.sh
```

**Verify Chain is Running:**

```bash
# Check L2 block number
cast block-number --rpc-url http://localhost:8547

# Get chain ID (should return 84532001)
cast chain-id --rpc-url http://localhost:8547

# Check sync status
curl -s http://localhost:8547 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'
```

## Smart Contracts

### SetRegistry

The SetRegistry contract stores batch commitments from the stateset-sequencer, enabling on-chain verification of off-chain commerce events.

**Key Features:**
- Multi-sequencer authorization
- State chain continuity verification
- Merkle inclusion proof verification
- Per-tenant/store isolation

**Core Functions:**

| Function | Description |
|----------|-------------|
| `commitBatch()` | Submit a batch commitment with Merkle roots |
| `verifyInclusion()` | Verify an event is included in a committed batch |
| `getLatestStateRoot()` | Get current state root for a tenant/store |
| `setSequencerAuthorization()` | Admin: authorize/revoke sequencers |
| `setStrictMode()` | Enable/disable state chain verification |

**Example Usage:**

```solidity
// Verify an order event was included in a batch
bool valid = registry.verifyInclusion(
    batchId,
    orderEventHash,
    merkleProof,
    leafIndex
);

// Get latest state root for a tenant/store
bytes32 stateRoot = registry.getLatestStateRoot(tenantId, storeId);
```

**Interact via CLI:**

```bash
# Check if a sequencer is authorized
cast call $REGISTRY_ADDRESS "authorizedSequencers(address)" $SEQUENCER_ADDRESS

# Get batch commitment
cast call $REGISTRY_ADDRESS "batchCommitments(bytes32)" $BATCH_ID
```

### SetPaymaster

Gas abstraction for sponsored commerce transactions, allowing merchants to pay for user gas fees.

**Sponsorship Tiers:**

| Tier | Monthly Limit | Per-Tx Limit |
|------|---------------|--------------|
| Starter | 0.1 ETH | 0.001 ETH |
| Growth | 1 ETH | 0.01 ETH |
| Enterprise | 10 ETH | 0.1 ETH |

**Supported Operation Types:**

| Operation | Description |
|-----------|-------------|
| `ORDER_CREATE` | Creating new orders |
| `ORDER_UPDATE` | Updating order status |
| `PAYMENT_PROCESS` | Processing payments |
| `INVENTORY_UPDATE` | Updating inventory |
| `RETURN_PROCESS` | Processing returns |
| `COMMITMENT_ANCHOR` | Anchoring commitments |
| `OTHER` | Other operations |

**Features:**
- Per-transaction and daily/monthly spend limits
- Automatic refund of unused gas
- Category-based sponsorship
- Merchant dashboards

## Anchor Service

The anchor service (`set-anchor`) is a Rust service that bridges the stateset-sequencer to the SetRegistry contract on-chain.

### Building

```bash
cd anchor
cargo build --release
```

### Running

```bash
# Set required environment variables
export SET_REGISTRY_ADDRESS=0x...
export SEQUENCER_PRIVATE_KEY=0x...
export SEQUENCER_API_URL=http://localhost:3000
export L2_RPC_URL=http://localhost:8547
export ANCHOR_INTERVAL_SECS=60  # seconds
export MIN_EVENTS_FOR_ANCHOR=100

# Run the service
./target/release/set-anchor
```

**Local devnet:**

```bash
./scripts/dev.sh anchor-start
./scripts/dev.sh anchor-smoke
```

Smoke overrides (optional):

```bash
EVENT_LEAF_0=0x... EVENT_LEAF_1=0x... TENANT_ID=0x... STORE_ID=0x... \
NEW_STATE_ROOT=0x... ./scripts/dev.sh smoke
```

### Health Endpoints

The anchor service exposes health and metrics endpoints:

| Endpoint | Description |
|----------|-------------|
| `GET /health` | Liveness probe (service is running) |
| `GET /ready` | Readiness probe (connected to chain and sequencer) |
| `GET /metrics` | Prometheus-format metrics |
| `GET /stats` | JSON statistics (anchored count, last anchor time, etc.) |

**Example:**

```bash
# Check if service is ready
curl http://localhost:9090/ready

# Get metrics
curl http://localhost:9090/metrics
```

## Integration with stateset-sequencer

Set Chain integrates with the stateset-sequencer through a two-phase process:

```
stateset-sequencer                    Anchor Service                    SetRegistry
       │                                    │                                │
       │  1. Create BatchCommitment         │                                │
       │     with Merkle roots              │                                │
       │                                    │                                │
       │  2. GET /v1/commitments/pending    │                                │
       │◄───────────────────────────────────│                                │
       │     Return unanchored batches      │                                │
       │                                    │                                │
       │                                    │  3. commitBatch(...)           │
       │                                    │───────────────────────────────►│
       │                                    │     Returns tx hash            │
       │                                    │◄───────────────────────────────│
       │                                    │                                │
       │  4. POST /v1/commitments/{id}/anchored                              │
       │◄───────────────────────────────────│                                │
       │     with chain_tx_hash             │                                │
       │                                    │                                │
```

**API Endpoints:**

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/v1/commitments/pending` | GET | List unanchored commitments |
| `/v1/commitments/{id}/anchored` | POST | Notify of successful anchoring |

## Docker Deployment

### Local Devnet

```bash
cd docker

# Start full local devnet (includes L1)
docker-compose up -d

# Check logs
docker-compose logs -f op-geth

# Stop
docker-compose down
```

### Sepolia Testnet

```bash
cd docker

# Connects to real Ethereum Sepolia
docker-compose -f docker-compose.sepolia.yml up -d
```

### With Optional Services

```bash
# With block explorer
docker-compose --profile explorer up -d

# With anchor service
docker-compose --profile anchor up -d
```

### Alternative L1 Clients

```bash
# Using Nethermind as L1
docker-compose -f docker-compose.nethermind.yml up -d

# Using Reth as L1
docker-compose -f docker-compose.reth.yml up -d
```

## Testing

### Contract Tests

```bash
cd contracts

# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test testCommitBatch

# Run with gas reporting
forge test --gas-report

# Generate coverage
forge coverage
```

### Anchor Service Tests

```bash
cd anchor

# Run unit tests
cargo test

# Run integration tests (requires Anvil running)
cargo test --test integration

# Run with logs
RUST_LOG=debug cargo test
```

## Deployment Checklist

### Accounts Setup

1. [ ] Generate 5 Ethereum accounts:
   - Admin (owns contracts)
   - Batcher (submits batches to L1)
   - Proposer (submits state roots)
   - Challenger (dispute resolution)
   - Sequencer (L2 block production)

2. [ ] Fund each account with 0.5+ Sepolia ETH

### Infrastructure

3. [ ] Configure Sepolia RPC endpoint (Infura/Alchemy)
4. [ ] Set up JWT secret for engine API authentication
5. [ ] Prepare data directories for persistent storage

### Deployment

6. [ ] Run `deploy-l1.sh` - Deploy OP Stack contracts to Sepolia
7. [ ] Run `generate-genesis.sh` - Create L2 genesis block
8. [ ] Start L2 nodes (op-geth, op-node)
9. [ ] Start op-batcher and op-proposer
10. [ ] Deploy SetRegistry to L2
11. [ ] Deploy SetPaymaster to L2
12. [ ] Start anchor service

### Verification

13. [ ] Verify L2 is producing blocks (2s intervals)
14. [ ] Verify batches are being submitted to L1
15. [ ] Test anchor service connectivity
16. [ ] Verify contract deployments with `cast`

## Monitoring

See `docs/monitoring.md` for SLOs, alert suggestions, and metric definitions.

### Key Metrics

| Metric | Expected | Alert Threshold |
|--------|----------|-----------------|
| Block production | Every 2 seconds | > 10s gap |
| Batch submission | Every few minutes | > 30 min gap |
| Anchor lag | < 5 minutes | > 15 minutes |
| L2 safe head lag | < 10 blocks | > 100 blocks |

### Viewing Logs

```bash
# op-geth logs
tail -f logs/op-geth.log

# op-node logs
tail -f logs/op-node.log

# Anchor service logs
docker-compose logs -f set-anchor

# All OP Stack logs
./scripts/start-devnet.sh logs
```

### Anchor Service Metrics

```bash
# Prometheus metrics (HEALTH_PORT, default 9090)
curl http://localhost:9090/metrics

# JSON stats
curl http://localhost:9090/stats | jq
```

## Security

### Best Practices

- **Multi-sig admin**: Use a multisig wallet for admin/owner roles in production
- **Key management**: Never commit private keys; use environment variables or secret managers
- **Sequencer authorization**: Only authorize trusted sequencer addresses
- **Strict mode**: Enable strict mode in production to prevent state gaps
- **Threat model**: Review and maintain `docs/threat-model.md`
- **Operations runbook**: Keep `docs/runbook.md` current with incident response steps
- **Governance policy**: Maintain `docs/security.md` for upgrade and key management

### Pre-Production Checklist

- [ ] Smart contract audit completed
- [ ] Penetration testing of anchor service
- [ ] Key rotation procedures documented
- [ ] Incident response plan prepared
- [ ] Monitoring and alerting configured

## Decentralization and Fault Proofs

See `docs/decentralization.md` and `docs/fault-proofs.md` for the phased
decentralization plan and fault-proof operations. Validate production config with:

```bash
./scripts/validate-ops-config.sh --mode testnet --require-fault-proofs --require-admin-policy
```

Verify L1 settlement contracts:

```bash
./scripts/check-l1-settlement.sh --env-file config/sepolia.env --mode testnet --require-addresses
```

## Scorecard

See `docs/scorecard.md` for the 10/10 rubric and progress tracking. Supporting
docs include `docs/threat-model.md`, `docs/security.md`, `docs/runbook.md`, and
`docs/architecture.md`.

## Troubleshooting

### Common Issues

**L2 not producing blocks:**
```bash
# Check op-node sync status
curl -s http://localhost:9545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"optimism_syncStatus","params":[],"id":1}' | jq

# Verify L1 connection
curl -s http://localhost:8545 -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

**Anchor service not connecting:**
```bash
# Check health endpoint
curl http://localhost:9090/ready

# Verify environment variables
echo $SET_REGISTRY_ADDRESS
echo $L2_RPC_URL

# Check sequencer API
curl http://localhost:3000/v1/commitments/pending
```

**Contract deployment failing:**
```bash
# Ensure you have ETH
cast balance $DEPLOYER_ADDRESS --rpc-url http://localhost:8547

# Check gas prices
cast gas-price --rpc-url http://localhost:8547

# Verify RPC is responding
cast chain-id --rpc-url http://localhost:8547
```

**Tests failing:**
```bash
# Update dependencies
cd contracts && forge update

# Clean and rebuild
forge clean && forge build

# Run with more verbosity
forge test -vvvv
```

## Resources

### Documentation

- [OP Stack Documentation](https://docs.optimism.io/operators/chain-operators)
- [Optimism Monorepo](https://github.com/ethereum-optimism/optimism)
- [Foundry Book](https://book.getfoundry.sh/)
- [Alloy Documentation](https://alloy.rs/)

### Project Documentation

- [Local Testing Guide](docs/local_testing_guide.md)
- [Architecture Overview](docs/architecture.md)
- [Scorecard](docs/scorecard.md)
- [Toolchain Versions](docs/toolchain.md)
- [Monitoring and SLOs](docs/monitoring.md)
- [Security and Governance](docs/security.md)
- [Node Operator Guide](docs/node-operators.md)
- [Integration Example](docs/integration-example.md)
- [Block Explorer and Indexing](docs/explorer.md)
- [Bridge and Onramp Support](docs/bridge.md)
- [Operations History](docs/operations-history.md)
- [SDK](sdk/README.md)
- [Audit Report](docs/audit-report.md)
- [Governance Evidence](docs/governance-evidence.md)
- [Fault Proof Exercise Log](docs/fault-proof-exercise.md)
- [Decentralization Roadmap](docs/decentralization.md)
- [Fault Proof Operations](docs/fault-proofs.md)
- [Threat Model](docs/threat-model.md)
- [Operations Runbook](docs/runbook.md)

### Related Projects

- [StateSet Sequencer](../stateset-sequencer/) - Off-chain commerce event processing
- [StateSet Network](../) - Parent project documentation

## License

MIT
