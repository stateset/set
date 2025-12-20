# Set Chain Local Testing Guide

This guide covers how to run and test the Set Chain L2 locally using Anvil (Foundry's local Ethereum node).

## Prerequisites

- Docker installed and running
- curl and jq for command-line interactions

Foundry tools (forge, anvil, cast) run via Docker to avoid GLIBC compatibility issues.

## Quick Start

```bash
# 1. Start the local node
./scripts/dev.sh start

# 2. In another terminal, deploy contracts
./scripts/dev.sh deploy

# 3. Check status
./scripts/dev.sh status
```

## Starting the Local Node

Start Anvil with Set Chain configuration:

```bash
./scripts/dev.sh start
# Or directly:
./scripts/start-local-anvil.sh
```

This starts Anvil with:
- **Chain ID:** 84532001
- **Block Time:** 2 seconds
- **Gas Limit:** 30M per block
- **RPC URL:** http://localhost:8545
- **10 pre-funded accounts** with 10,000 ETH each

## Deploying Contracts

With Anvil running, deploy the contracts:

```bash
./scripts/dev.sh deploy
```

This deploys:
- **SetRegistry** - Merkle root anchoring for commerce events
- **SetPaymaster** - Gas sponsorship for merchants

### Deployed Addresses (deterministic)

| Contract | Address |
|----------|---------|
| SetRegistry (proxy) | `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512` |
| SetRegistry (impl) | `0x5FbDB2315678afecb367f032d93F642f64180aa3` |
| SetPaymaster (proxy) | `0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9` |
| SetPaymaster (impl) | `0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0` |

## Test Accounts

Anvil provides pre-funded accounts for testing:

| Role | Address | Private Key |
|------|---------|-------------|
| Admin/Deployer | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` | `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` |
| Sequencer | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` | `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d` |
| Batcher | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` | `0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a` |
| Proposer | `0x90F79bf6EB2c4f870365E785982E1f101E93b906` | `0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6` |
| User 5 | `0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65` | `0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a` |

View all accounts:
```bash
./scripts/dev.sh accounts
```

## Helper Commands

The `dev.sh` script provides convenient commands:

```bash
./scripts/dev.sh start       # Start Anvil node
./scripts/dev.sh deploy      # Deploy all contracts
./scripts/dev.sh test        # Run Foundry tests
./scripts/dev.sh status      # Check node status
./scripts/dev.sh accounts    # Show test accounts
./scripts/dev.sh fund <addr> # Send 100 ETH to address
./scripts/dev.sh console     # Open cast shell
```

## Interacting with Contracts

### Using curl (JSON-RPC)

Check chain ID:
```bash
curl -s http://localhost:8545 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' | jq
```

Get block number:
```bash
curl -s http://localhost:8545 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq
```

### Using cast (via Docker)

Read SetRegistry owner:
```bash
docker run --rm --network=host ghcr.io/foundry-rs/foundry:stable \
  cast call 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 "owner()" \
  --rpc-url http://localhost:8545
```

Check if sequencer is authorized:
```bash
docker run --rm --network=host ghcr.io/foundry-rs/foundry:stable \
  cast call 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 \
  "authorizedSequencers(address)" 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
  --rpc-url http://localhost:8545
```

### Committing a Batch (as Sequencer)

```bash
# Using the sequencer's private key
docker run --rm --network=host ghcr.io/foundry-rs/foundry:stable \
  cast send 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 \
  "commitBatch(bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,uint64,uint64,uint32)" \
  0x0000000000000000000000000000000000000000000000000000000000000001 \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890 \
  1 100 100 \
  --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d \
  --rpc-url http://localhost:8545
```

## Running Tests

Run the Foundry test suite:

```bash
./scripts/dev.sh test

# Or with specific options
./scripts/dev.sh test --match-test testCommitBatch
./scripts/dev.sh test -vvvv  # Extra verbosity
```

Run tests directly via Docker:
```bash
docker run --rm -v $(pwd)/contracts:/app -w /app \
  ghcr.io/foundry-rs/foundry:stable \
  forge test -vvv
```

## Environment Variables

Create a `.env` file for custom configuration:

```bash
# .env
RPC_URL=http://localhost:8545
DEPLOYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
SEQUENCER_ADDRESS=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
TREASURY_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
```

## Integration with Anchor Service

To connect the anchor service to the local node:

```bash
# In anchor service config
SET_REGISTRY_ADDRESS=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
L2_RPC_URL=http://localhost:8545
SEQUENCER_PRIVATE_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
```

## Troubleshooting

### Node not responding
```bash
# Check if Anvil is running
curl -s http://localhost:8545 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'

# Restart the node
./scripts/dev.sh start
```

### Contract deployment fails
```bash
# Ensure output directories exist with correct permissions
mkdir -p contracts/out contracts/cache contracts/broadcast
chmod 777 contracts/out contracts/cache contracts/broadcast
```

### "GLIBC not found" errors
Foundry binaries require newer GLIBC. Use Docker-based commands instead:
```bash
# Instead of: forge build
docker run --rm -v $(pwd)/contracts:/app -w /app \
  ghcr.io/foundry-rs/foundry:stable forge build

# Instead of: cast call ...
docker run --rm --network=host ghcr.io/foundry-rs/foundry:stable \
  cast call ...
```

### Reset state
Restart Anvil to reset all blockchain state:
```bash
# Kill existing Anvil process
pkill anvil

# Start fresh
./scripts/dev.sh start
```

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Local Development                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   ┌──────────────┐     ┌──────────────────────────────┐     │
│   │   Anvil      │     │  Deployed Contracts          │     │
│   │  (Local L2)  │────▶│  - SetRegistry (proxy)       │     │
│   │              │     │  - SetPaymaster (proxy)      │     │
│   │ Chain: 84532001    │                              │     │
│   │ RPC: :8545   │     └──────────────────────────────┘     │
│   └──────────────┘                                          │
│          ▲                                                   │
│          │                                                   │
│   ┌──────┴───────┐                                          │
│   │ dev.sh       │                                          │
│   │ Helper       │                                          │
│   │ Scripts      │                                          │
│   └──────────────┘                                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Next Steps

1. **Run the test suite** to verify everything works
2. **Connect the anchor service** to submit batch commitments
3. **Integrate with stateset-sequencer** for end-to-end testing
4. **Deploy to Base Sepolia** when ready for testnet
