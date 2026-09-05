# Set Chain Local Testing Guide

This guide covers Set Chain application testing using Anvil (Foundry's local
Ethereum node). Anvil is not a multi-node OP Stack deployment and does not provide
evidence of rollup settlement, disputes or finalized withdrawals.

## Prerequisites

- Docker installed and running, or a valid local Foundry install
- curl and jq for command-line interactions

`./scripts/dev.sh` and `./scripts/start-local-anvil.sh` auto-detect a usable
Foundry backend. They prefer a real local `forge`/`cast`/`anvil` install, and
fall back to the official Docker image when the local binary is missing or is
not actually Foundry (for example, Electron Forge on `PATH`).

Set `FOUNDRY_USE_DOCKER=1` to force the Docker backend. Set
`FOUNDRY_DOCKER_IMAGE` if you want to pin a specific GHCR tag or digest.

## Toolchain Versions

Pinned tool versions for reproducible builds live in `docs/toolchain.md`.

## Quick Start

```bash
# 1. Start the local node
./scripts/dev.sh start

# 2. In another terminal, deploy contracts
./scripts/dev.sh deploy

# 3. (Optional) Validate config
./scripts/dev.sh validate

# 4. Check status
./scripts/dev.sh status
```

## Starting the Local Node

Start Anvil with Set Chain configuration:

```bash
./scripts/dev.sh start
# Or directly:
./scripts/start-local-anvil.sh
```

The script reads chain parameters from `config/chain-config.toml` to keep the
local devnet in sync with the repository defaults.

The launcher binds to `127.0.0.1` on the host. The Docker backend also publishes
only `127.0.0.1:8545`; its internal listener remains container-wide. These accounts
have publicly known development keys: never fund them on a public network or
expose this RPC through a proxy or tunnel.

Starting Anvil never stops another node or removes an existing container to
claim a name or port. A conflict fails the launch; inspect and explicitly stop
the intended process yourself. The host backend executes the exact Foundry binary
it validated, including a binary found through `FOUNDRY_BIN_DIR`.

The separate `docker/docker-compose.local.yml` is also execution-only, not a
complete rollup. Its default project is `set-local-execution`, with project-scoped
volumes, networks and container names. HTTP/WebSocket ports bind to loopback;
Engine RPC is not host-published, and application RPC excludes debug/engine APIs.
The old global `set-op-geth-data` volume and `set-chain-network` network are not
reused automatically, migrated or deleted. Existing installations need explicit
data-migration planning; do not use `down -v` or Docker pruning to resolve this.
Other Compose profiles are not covered by these launch-safety guarantees.

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

These addresses are deterministic on a fresh Anvil instance; redeploying will
produce new addresses.

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
./scripts/dev.sh test-critical # Run isolated registry/escrow/FX/reserve security suites
./scripts/dev.sh status      # Check node status
./scripts/dev.sh validate    # Validate config vs live node
./scripts/dev.sh smoke       # Deploy + commit batch + verify multiproof
./scripts/dev.sh anchor-start # Run anchor service with mock sequencer
./scripts/dev.sh anchor-smoke # Anchor service smoke test
./scripts/dev.sh reset       # Reset devnet and restart Anvil
./scripts/dev.sh accounts    # Show test accounts
./scripts/dev.sh fund <addr> # Send 100 ETH to address
./scripts/dev.sh console     # Open cast shell
```

Smoke overrides (optional):

```bash
EVENT_LEAF_0=0x... EVENT_LEAF_1=0x... TENANT_ID=0x... STORE_ID=0x... \
NEW_STATE_ROOT=0x... ./scripts/dev.sh smoke
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
docker run --rm --entrypoint cast --network=host ghcr.io/foundry-rs/foundry:nightly \
  call 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 "owner()" \
  --rpc-url http://localhost:8545
```

Check if sequencer is authorized:
```bash
docker run --rm --entrypoint cast --network=host ghcr.io/foundry-rs/foundry:nightly \
  call 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 \
  "authorizedSequencers(address)" 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
  --rpc-url http://localhost:8545
```

### Committing a Batch (as Sequencer)

```bash
# Using the sequencer's private key
docker run --rm --entrypoint cast --network=host ghcr.io/foundry-rs/foundry:nightly \
  send 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 \
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

For fast feedback on the security-critical paths, use the focused smoke gate:

```bash
./scripts/dev.sh test-critical
```

It runs registry accounting, order escrow, FX conversion, and proof-of-reserves
tests with separate Foundry caches. The full suite remains the release gate.

Run tests directly via Docker:
```bash
docker run --rm --entrypoint forge -v $(pwd)/contracts:/app -w /app \
  ghcr.io/foundry-rs/foundry:nightly test -vvv
```

SDK tests require Node 20+. The SDK Vitest wrapper will use a local Node 20+
binary when available, or fall back to Docker if `docker` is installed.

## Resetting the Devnet

Stop your intended Anvil process explicitly first (for example, Ctrl+C in its
foreground terminal), and stop any builds/deployments writing local artifacts.
Then archive local artifacts and restart Anvil:

```bash
./scripts/dev.sh reset
```

To skip the confirmation prompt:

```bash
./scripts/dev.sh reset --force
```

To reset without restarting:

```bash
./scripts/reset-devnet.sh --no-start
```

Reset never kills a process or removes a Docker container. It reserves local
IPv4/IPv6 port 8545 while archiving; an occupied port or reservation error fails
before artifacts move. `--force` only skips confirmation. If the port remains
unavailable immediately after shutdown, wait for its existing connections to
close instead of bypassing the check.

Only `contracts/cache`, `contracts/out`, and
`contracts/broadcast/<script>/<configured-chain-id>` are moved into a unique
`.devnet-reset-archive/reset-*` directory. Other chains' broadcast records are
untouched. The archive is ignored by Git and has a journal written before each
rename. No repository artifacts are recursively deleted and no volume is pruned.

On partial failure, reset does not restart Anvil: review both the original paths
and the printed archive's `manifest.jsonl`. An entry records an attempted move,
not proof it completed. Restore a directory by moving it from the archive back
to its original relative path only after verifying that the original path is
absent; never overwrite fresh build or deployment output. Archives consume disk
space until you explicitly manage them.

This is not an atomic snapshot across all artifact directories, a backup of
Anvil's in-memory chain, or protection against simultaneous manual filesystem
changes. Keep artifact writers stopped throughout reset. A competing node can
win the RPC port after archival; restart then fails without stopping that node.
Reset requires Python 3; use `LOCAL_RESET_PYTHON=python3.10` to select it explicitly.

## Environment Variables

For local devnet, start from `config/local.env.example`:

```bash
cp config/local.env.example config/local.env
# Then source it when needed:
source config/local.env
```

Create a `.env` file for custom configuration (optional):

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
# Run anchor service against local devnet (includes mock sequencer)
./scripts/dev.sh anchor-start

# Smoke test the anchor service
./scripts/dev.sh anchor-smoke
```

Environment variables are loaded from `config/local.env` when present. The mock
sequencer listens on `http://localhost:3001` by default.

`anchor-smoke` starts a mock sequencer, runs the anchor service, and waits for
the on-chain commitment to be recorded.

The mock sequencer requires `python3` (or `python`) to be available locally.

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
docker run --rm --entrypoint forge -v $(pwd)/contracts:/app -w /app \
  ghcr.io/foundry-rs/foundry:nightly build

# Instead of: cast call ...
docker run --rm --entrypoint cast --network=host ghcr.io/foundry-rs/foundry:nightly \
  call ...
```

### Wrong `forge` binary on `PATH`
If `forge --version` resolves to Electron Forge or another non-Foundry tool,
the repo wrappers will ignore it and use Docker automatically. To force that
behavior explicitly:

```bash
FOUNDRY_USE_DOCKER=1 ./scripts/dev.sh test
```

### Reset state
Restart Anvil to reset all blockchain state:
```bash
# First stop the intended node and artifact writers; then archive and restart
./scripts/dev.sh reset --force
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
