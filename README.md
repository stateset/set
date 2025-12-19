# Set Chain (SSC)

Set Chain is an Ethereum Layer-2 (L2) network built on the **OP Stack**, designed for **commerce and supply chain decentralized applications**. It offers faster, cheaper, and cryptographically verifiable transactions by leveraging optimistic rollups with Merkle root anchoring.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         SET CHAIN L2                             │
│                    (Commerce-Optimized OP Stack)                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │   op-geth    │  │   op-node    │  │  op-batcher  │           │
│  │  (execution) │  │  (consensus) │  │   (batches)  │           │
│  └──────────────┘  └──────────────┘  └──────────────┘           │
│         │                │                  │                    │
│         └────────────────┼──────────────────┘                    │
│                          │                                       │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              SetRegistry Contract                         │   │
│  │    (Merkle root anchoring from stateset-sequencer)        │   │
│  └──────────────────────────────────────────────────────────┘   │
│                          │                                       │
└──────────────────────────┼───────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ETHEREUM SEPOLIA (L1)                         │
│       OptimismPortal │ L2OutputOracle │ SystemConfig             │
└─────────────────────────────────────────────────────────────────┘
```

## Key Features

- **2-second block times** - Fast confirmations for commerce operations
- **Low gas fees** - Optimized for merchant transactions
- **Merkle root anchoring** - Verifiable event commitments from stateset-sequencer
- **Multi-tenant isolation** - Per-tenant/store state tracking
- **Inclusion proof verification** - On-chain verification of off-chain events

## Chain Configuration

| Parameter | Value |
|-----------|-------|
| Chain ID | 84532001 |
| Block Time | 2 seconds |
| Gas Limit | 30M gas/block |
| L1 Settlement | Ethereum Sepolia |
| Native Token | ETH |

## Directory Structure

```
set/
├── contracts/              # Solidity smart contracts
│   ├── SetRegistry.sol     # Merkle root anchoring
│   └── commerce/
│       └── SetPaymaster.sol # Gas abstraction for merchants
├── op-stack/               # OP Stack configuration
│   ├── deployer/           # op-deployer files
│   └── sequencer/          # op-geth/op-node config
├── docker/                 # Docker Compose files
├── scripts/                # Deployment and management scripts
├── config/                 # Chain configuration
├── anchor/                 # Rust anchor service
└── docs/                   # Documentation
```

## Quick Start

### Prerequisites

- Go 1.21+
- Rust 1.70+
- Docker & Docker Compose
- 2+ ETH on Sepolia (for deployment)

### 1. Install OP Stack Binaries

```bash
./scripts/install-op-stack.sh
```

### 2. Configure Environment

```bash
cp config/sepolia.env.example config/sepolia.env
# Edit sepolia.env with your addresses and keys
```

### 3. Deploy L1 Contracts

```bash
./scripts/deploy-l1.sh
```

### 4. Generate Genesis

```bash
./scripts/generate-genesis.sh
```

### 5. Start the Devnet

```bash
# Using scripts
./scripts/start-devnet.sh

# Or using Docker
cd docker && docker-compose up -d
```

### 6. Verify Chain is Running

```bash
# Check L2 block number
cast block-number --rpc-url http://localhost:8547

# Get chain ID
cast chain-id --rpc-url http://localhost:8547
# Should return: 84532001
```

## Smart Contracts

### SetRegistry

The SetRegistry contract stores batch commitments from the stateset-sequencer, enabling on-chain verification of off-chain commerce events.

**Key Functions:**
- `commitBatch()` - Submit a batch commitment with Merkle roots
- `verifyInclusion()` - Verify an event is included in a committed batch
- `getLatestStateRoot()` - Get current state root for a tenant/store

**Example:**
```solidity
// Verify an order event was included in a batch
bool valid = registry.verifyInclusion(
    batchId,
    orderEventHash,
    merkleProof,
    leafIndex
);
```

### SetPaymaster

Gas abstraction for sponsored commerce transactions.

**Features:**
- Tiered sponsorship (Starter, Growth, Enterprise)
- Per-transaction and daily/monthly limits
- Automatic refund of unused gas

## Anchor Service

The anchor service (`set-anchor`) bridges the stateset-sequencer to the SetRegistry contract.

```bash
# Build
cd anchor && cargo build --release

# Run
SET_REGISTRY_ADDRESS=0x... \
SEQUENCER_PRIVATE_KEY=0x... \
./target/release/set-anchor
```

## Integration with stateset-sequencer

Set Chain integrates with stateset-sequencer through:

1. **Batch Commitments**: Sequencer creates BatchCommitments with Merkle roots
2. **Anchor Service**: Periodically submits commitments to SetRegistry
3. **Notification**: Sequencer receives chain_tx_hash after anchoring

**API Endpoints:**
- `GET /v1/commitments/pending` - List unanchored commitments
- `POST /v1/commitments/{id}/anchored` - Notify of successful anchoring

## Development

### Local Devnet

```bash
# Start all components
./scripts/start-devnet.sh

# Check status
./scripts/start-devnet.sh status

# Stop
./scripts/stop-devnet.sh
```

### Docker Development

```bash
cd docker

# Local devnet (includes L1)
docker-compose up -d

# Sepolia testnet (connects to real L1)
docker-compose -f docker-compose.sepolia.yml up -d

# With block explorer
docker-compose --profile explorer up -d

# With anchor service
docker-compose --profile anchor up -d
```

### Testing Contracts

```bash
cd contracts
forge test
```

## Deployment Checklist

1. [ ] Generate 5 Ethereum accounts (admin, batcher, proposer, challenger, sequencer)
2. [ ] Fund each with 0.5+ Sepolia ETH
3. [ ] Configure Sepolia RPC endpoint
4. [ ] Run `deploy-l1.sh`
5. [ ] Run `generate-genesis.sh`
6. [ ] Start L2 nodes
7. [ ] Deploy SetRegistry to L2
8. [ ] Start anchor service

## Monitoring

### Key Metrics

- **Block production**: L2 blocks should be produced every 2 seconds
- **Batch submission**: Batches posted to L1 every few minutes
- **Anchor lag**: Time between sequencer commitment and on-chain anchoring

### Logs

```bash
# op-geth logs
tail -f logs/op-geth.log

# op-node logs
tail -f logs/op-node.log

# Anchor service logs
docker-compose logs -f set-anchor
```

## Security

- **Multi-sig admin**: Consider using a multisig for admin/owner roles
- **Key management**: Never commit private keys; use environment variables
- **Audits**: Smart contracts should be audited before mainnet deployment

## Resources

- [OP Stack Documentation](https://docs.optimism.io/operators/chain-operators)
- [Optimism Monorepo](https://github.com/ethereum-optimism/optimism)
- [StateSet Sequencer PRD](../STATESET_SEQUENCER_PRD.md)
- [StateSet Network Plan](../STATESET_NETWORK_PLAN.md)

## License

MIT
