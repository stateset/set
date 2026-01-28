# Set L2 on Arc L1 — Architecture & Deployment Checklist

This document describes the architecture and end-to-end deployment of
Set (OP Stack L2, chain `84532001`) with settlement on the Arc L1 testnet
(chain `5042002`), replacing Ethereum Sepolia as the settlement layer.

---

## Architecture Overview

### Layer Topology

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        ARC L1 TESTNET (5042002)                        │
│                      Native gas token: USDC (6 dec)                    │
│                                                                        │
│  ┌──────────────────────────────────┐  ┌────────────────────────────┐  │
│  │     OP Stack Settlement Layer    │  │   x402 Payment Settlement  │  │
│  │                                  │  │                            │  │
│  │  OptimismPortal                  │  │  SetRegistry (proxy)       │  │
│  │  L2OutputOracle                  │  │  SetPaymentBatch (proxy)   │  │
│  │  SystemConfig                    │  │                            │  │
│  │  L1StandardBridge                │  │  Settles payment intents   │  │
│  │  DisputeGameFactory              │  │  via Merkle proof + USDC   │  │
│  │  AnchorStateRegistry             │  │  transfers                 │  │
│  │  ForcedInclusion (escape hatch)  │  │                            │  │
│  └──────────────────────────────────┘  └────────────────────────────┘  │
└────────────────────────────┬───────────────────────────────────────────┘
                             │
                   L1 Settlement / State Roots
                   Forced Inclusion (censorship resistance)
                   Dispute Games (fault proofs)
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         SET L2 (84532001)                              │
│              OP Stack  •  2s blocks  •  30M gas limit                  │
│                                                                        │
│  ┌──────────────────┐ ┌──────────────────┐ ┌────────────────────────┐ │
│  │  Core Commerce   │ │   Stablecoin     │ │    MEV Protection      │ │
│  │                  │ │                  │ │                        │ │
│  │  SetRegistry     │ │  ssUSD (rebase)  │ │  EncryptedMempool      │ │
│  │  SetPaymaster    │ │  wssUSD (ERC4626)│ │  (threshold encrypt)   │ │
│  │  SetTimelock     │ │  NAVOracle       │ │                        │ │
│  └──────────────────┘ └──────────────────┘ └────────────────────────┘ │
└────────────────────────────┬───────────────────────────────────────────┘
                             │
                    commitBatch() calls
                    via Anchor Service
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                       ANCHOR SERVICE (Rust)                            │
│               Circuit breaker  •  Health/metrics on :9090              │
│                                                                        │
│   ┌──────────────────────────────────────────────────────────────┐     │
│   │  Poll Loop                                                   │     │
│   │  1. GET  /v1/commitments/pending   → fetch unanchored batches│     │
│   │  2. Call SetRegistry.commitBatch() → anchor on-chain         │     │
│   │  3. POST /v1/commitments/{id}/anchored → notify sequencer    │     │
│   └──────────────────────────────────────────────────────────────┘     │
└────────────────────────────┬───────────────────────────────────────────┘
                             │
                     Batch Commitments
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     STATESET SEQUENCER (off-chain)                     │
│                                                                        │
│  Commerce event processing  •  Merkle tree construction                │
│  Payment intent validation  •  Multi-tenant isolation                  │
│  STARK proof generation     •  Fair ordering                           │
└─────────────────────────────────────────────────────────────────────────┘
```

### Contract Deployment Map

| Contract | Layer | Chain ID | Purpose |
|---|---|---|---|
| OptimismPortal | Arc L1 | 5042002 | Cross-domain messaging and finality |
| L2OutputOracle | Arc L1 | 5042002 | Stores L2 state roots for verification |
| SystemConfig | Arc L1 | 5042002 | L2 parameter configuration |
| L1StandardBridge | Arc L1 | 5042002 | ETH/ERC-20 bridging between L1 and L2 |
| DisputeGameFactory | Arc L1 | 5042002 | Fault proof game resolution |
| AnchorStateRegistry | Arc L1 | 5042002 | Anchored L2 state for dispute games |
| ForcedInclusion | Arc L1 | 5042002 | Censorship resistance escape hatch |
| SetRegistry (x402) | Arc L1 | 5042002 | Payment batch Merkle root anchoring |
| SetPaymentBatch | Arc L1 | 5042002 | x402 payment intent settlement (USDC) |
| SetRegistry | Set L2 | 84532001 | Commerce event Merkle root anchoring |
| SetPaymaster | Set L2 | 84532001 | Gas sponsorship for merchants |
| SetTimelock | Set L2 | 84532001 | Governance timelock (2-day delay) |
| EncryptedMempool | Set L2 | 84532001 | Threshold-encrypted transaction ordering |
| ssUSD | Set L2 | 84532001 | Rebasing stablecoin (T-Bill backed) |
| wssUSD | Set L2 | 84532001 | Non-rebasing ERC4626 wrapper for ssUSD |
| NAVOracle | Set L2 | 84532001 | Daily Net Asset Value attestation |

### Cross-Layer Communication

```
                    Arc L1                          Set L2
              ┌──────────────┐              ┌──────────────────┐
              │              │   Deposit     │                  │
     User ──► │ L1Standard   │ ───────────► │  L2 Balance      │
              │ Bridge       │              │                  │
              │              │ ◄─────────── │                  │
              │              │   Withdraw    │                  │
              └──────────────┘              └──────────────────┘

              ┌──────────────┐              ┌──────────────────┐
              │ L2Output     │ ◄─────────── │  op-proposer     │
              │ Oracle       │  State roots  │  (every N blocks)│
              └──────────────┘              └──────────────────┘

              ┌──────────────┐              ┌──────────────────┐
              │ Forced       │ ───────────► │  Sequencer must  │
              │ Inclusion    │  Force-include│  include within  │
              │ (0.01 ETH    │  after 24h   │  24h or penalty  │
              │  bond)       │              │                  │
              └──────────────┘              └──────────────────┘

              ┌──────────────┐
              │ Dispute      │  Challenge window for
              │ Game         │  state root validity
              │ Factory      │  (fault proofs)
              └──────────────┘
```

### Data Flow: Commerce Event Lifecycle

```
  Merchant/AI Agent
       │
       │ 1. Create order / payment / inventory event
       ▼
  stateset-sequencer
       │
       │ 2. Validate, sequence, build Merkle tree
       │    BatchCommitment {
       │      eventsRoot, prevStateRoot, newStateRoot,
       │      sequenceStart, sequenceEnd, eventCount
       │    }
       ▼
  Anchor Service (Rust)
       │
       │ 3. Poll GET /v1/commitments/pending
       │ 4. Submit SetRegistry.commitBatch() on Set L2
       │ 5. Notify POST /v1/commitments/{id}/anchored
       ▼
  Set L2 — SetRegistry
       │
       │ 6. Batch stored on-chain
       │    verifyInclusion(batchId, leaf, proof[], index) → bool
       ▼
  Arc L1 — L2OutputOracle
       │
       │ 7. State root submitted by op-proposer
       │ 8. Finalized after dispute window
       ▼
  Settlement complete — verifiable on L1
```

### Data Flow: x402 Payment Settlement

```
  AI Agent
       │
       │ 1. Sign PaymentIntent { intentId, payer, payee,
       │      amount, token, nonce, validUntil, signingHash }
       ▼
  stateset-sequencer
       │
       │ 2. Validate signature, check nonce, sequence
       │ 3. Include in payment batch Merkle tree
       ▼
  Arc L1 — SetPaymentBatch
       │
       │ 4. settleBatch() with Merkle root + proofs
       │ 5. Verify each intent via Merkle proof
       │ 6. Transfer USDC from payer → payee
       │ 7. Mark nonces as used (replay protection)
       ▼
  Settlement complete — USDC transferred on Arc L1
```

### Anchor Service Internals

```
  ┌─────────────────────────────────────────────────────┐
  │               Anchor Service (Rust)                  │
  │                                                      │
  │  ┌──────────┐    ┌──────────────┐    ┌───────────┐  │
  │  │ Config   │    │ Poll Loop    │    │ Health    │  │
  │  │          │    │              │    │ Server    │  │
  │  │ L2_RPC   │───►│ interval:    │    │           │  │
  │  │ REGISTRY │    │  60s prod    │    │ /health   │  │
  │  │ SEQ_KEY  │    │  1s local    │    │ /ready    │  │
  │  │ SEQ_API  │    │              │    │ /metrics  │  │
  │  │          │    │ min_events:  │    │ /stats    │  │
  │  └──────────┘    │  100 prod    │    └───────────┘  │
  │                  │  1 local     │                    │
  │                  └──────┬───────┘                    │
  │                         │                            │
  │                  ┌──────▼───────┐                    │
  │                  │ Circuit      │                    │
  │                  │ Breaker      │                    │
  │                  │              │                    │
  │                  │ Closed ──►   │                    │
  │                  │   Open ──►   │                    │
  │                  │   HalfOpen   │                    │
  │                  │              │                    │
  │                  │ 5 failures   │                    │
  │                  │ → trip open  │                    │
  │                  │ 60s timeout  │                    │
  │                  │ → half-open  │                    │
  │                  └──────────────┘                    │
  └─────────────────────────────────────────────────────┘
```

### Key Configuration Parameters

| Parameter | Local | Sepolia/Arc | Description |
|---|---|---|---|
| `L1_RPC_URL` | localhost:8545 | Arc RPC | Arc L1 RPC endpoint |
| `L1_CHAIN_ID` | 31337 | 5042002 | Arc chain ID |
| `L2_CHAIN_ID` | 84532001 | 84532001 | Set L2 chain ID |
| `L2_BLOCK_TIME` | 2 | 2 | Block time in seconds |
| `ANCHOR_INTERVAL_SECS` | 1 | 60 | Poll interval for pending batches |
| `MIN_EVENTS_FOR_ANCHOR` | 1 | 100 | Min events before anchoring |
| `CIRCUIT_BREAKER_FAILURE_THRESHOLD` | 3 | 5 | Failures before circuit opens |
| `CIRCUIT_BREAKER_RESET_TIMEOUT_SECS` | 30 | 60 | Seconds before half-open |
| `HEALTH_PORT` | 9090 | 9090 | Anchor health server port |

### Operator Roles

| Role | Key | Responsibility |
|---|---|---|
| Deployer | `DEPLOYER_PRIVATE_KEY` | Deploy L1 and L2 contracts |
| Batcher | `BATCHER_PRIVATE_KEY` | Submit L2 transaction batches to L1 |
| Proposer | `PROPOSER_PRIVATE_KEY` | Submit L2 state roots to L2OutputOracle |
| Sequencer | `SEQUENCER_PRIVATE_KEY` | Produce L2 blocks, anchor batches |
| Challenger | `CHALLENGER_PRIVATE_KEY` | Dispute invalid state roots |

All roles must be funded with Arc's native gas token (USDC) on L1.

---

## Deployment Checklist

### Phase 0 — Network Validation

- [ ] Confirm Arc testnet `chainId` (5042002), RPC/WS endpoints, explorer URL
- [ ] Confirm Arc native gas token is USDC (6 decimals) at `0x3600...`
- [ ] Verify OP Stack compatibility:
  - L1 contract deployment support
  - Dispute game factory compatibility
  - Beacon chain endpoint (if supported)
- [ ] Decide final `L2_CHAIN_ID` (keep `84532001` or assign new)
- [ ] Test basic transaction submission to Arc testnet

### Phase 1 — Environment Configuration

- [ ] Create `config/arc.env` from `config/sepolia.env.example`
- [ ] Set Arc L1 values:
  ```
  L1_RPC_URL=https://rpc.testnet.arc.network
  L1_CHAIN_ID=5042002
  L1_BEACON_URL=<if supported>
  L1_BLOCK_TIME=<arc block time>
  ```
- [ ] Set L2 values:
  ```
  L2_CHAIN_ID=84532001
  L2_BLOCK_TIME=2
  L2_RPC_URL=http://localhost:8547
  L2_WS_URL=ws://localhost:8548
  L2_ENGINE_URL=http://localhost:8551
  ```
- [ ] Generate or assign operator keys:
  - `DEPLOYER_PRIVATE_KEY`
  - `BATCHER_PRIVATE_KEY`
  - `PROPOSER_PRIVATE_KEY`
  - `SEQUENCER_PRIVATE_KEY`
  - `CHALLENGER_PRIVATE_KEY`
- [ ] Set `JWT_SECRET` for engine API auth
- [ ] Fund all operator accounts with USDC on Arc testnet

### Phase 2 — Deployment Scripts

- [ ] Generalize `scripts/deploy-sepolia.sh`:
  - Replace hardcoded Sepolia chain ID `11155111` with `$L1_CHAIN_ID`
  - Use gas-token-neutral balance checks (USDC, not ETH)
  - Source env from `config/arc.env`
- [ ] Create `scripts/deploy-arc.sh` entrypoint
- [ ] Update `contracts/script/DeployX402Arc.s.sol` with final Arc addresses
- [ ] Verify `foundry.toml` rpc_endpoints include Arc:
  ```toml
  [rpc_endpoints]
  arc_testnet = "${ARC_TESTNET_RPC_URL}"
  ```

### Phase 3 — OP Stack L1 Contracts on Arc

Deploy order matters. The OP Stack contracts form the settlement backbone.

```
Deploy Order:
  1. ProxyAdmin
  2. SystemConfig
  3. OptimismPortal (proxy)
  4. L2OutputOracle (proxy)
  5. L1StandardBridge (proxy)
  6. DisputeGameFactory (proxy)
  7. AnchorStateRegistry
```

- [ ] Create `op-stack/deployer/intent.arc.toml` with Arc-specific parameters
- [ ] Deploy OP Stack L1 contracts to Arc:
  - `OptimismPortal`
  - `L2OutputOracle`
  - `SystemConfig`
  - `L1StandardBridge`
  - `DisputeGameFactory`
  - `AnchorStateRegistry`
- [ ] Deploy `ForcedInclusion` contract on Arc L1
- [ ] Record all L1 contract addresses in `config/arc.env`
- [ ] Verify contracts on Arc explorer (if available)

### Phase 4 — L2 Genesis

- [ ] Run `scripts/generate-genesis.sh` using Arc L1 contract addresses
- [ ] Confirm genesis artifacts written to `op-stack/` or `deployments/`
- [ ] Verify genesis block references correct L1 addresses
- [ ] Store genesis hash for node configuration

### Phase 5 — L2 Node Stack

```
Docker Compose Services:
  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
  │  op-geth    │  │  op-node    │  │  op-batcher  │
  │  (exec)     │  │  (consensus)│  │  (L1 submit) │
  └─────────────┘  └─────────────┘  └─────────────┘
  ┌─────────────┐  ┌─────────────┐
  │ op-proposer │  │  anchor-svc │
  │ (state root)│  │  (Rust)     │
  └─────────────┘  └─────────────┘
```

- [ ] Create `docker/docker-compose.arc.yml`
- [ ] Configure all services to use Arc L1 RPC endpoints
- [ ] Start stack: `docker compose -f docker/docker-compose.arc.yml up -d`
- [ ] Verify L2 block production:
  - `eth_chainId` returns `84532001`
  - Block height is advancing every 2s
- [ ] Verify batcher is submitting to Arc L1
- [ ] Verify proposer is posting state roots to L2OutputOracle

### Phase 6 — Set Contracts on L2

Deploy the commerce application layer on Set L2.

```
Deploy Order:
  1. SetRegistry (ERC1967 proxy)
  2. SetPaymaster (ERC1967 proxy)
  3. NAVOracle
  4. ssUSD
  5. wssUSD (ERC4626 vault)
  6. EncryptedMempool
```

- [ ] Deploy `SetRegistry` with proxy
- [ ] Deploy `SetPaymaster` with proxy and tier configuration:
  - Starter: 0.1 ETH deposit
  - Growth: 1.0 ETH deposit
  - Enterprise: 10.0 ETH deposit
- [ ] Deploy `NAVOracle` with attestor set
- [ ] Deploy `ssUSD` rebasing stablecoin
- [ ] Deploy `wssUSD` ERC4626 vault wrapper
- [ ] Deploy `EncryptedMempool` for MEV protection
- [ ] Authorize sequencer address on SetRegistry
- [ ] Persist all addresses in `deployments/arc/addresses.json`

### Phase 7 — x402 Payment Contracts on Arc L1

- [ ] Deploy `SetRegistry` (x402 variant) on Arc L1 via `DeployX402Arc.s.sol`
- [ ] Deploy `SetPaymentBatch` on Arc L1 with supported assets:
  - USDC (`0x3600...` — Arc native)
  - ssUSD (bridged from L2)
- [ ] Configure daily volume limits per asset
- [ ] Authorize payment settlement operators
- [ ] Persist Arc L1 contract addresses in `deployments/arc/l1-addresses.json`

### Phase 8 — Anchor Service

- [ ] Build anchor service: `cargo build --release -p anchor`
- [ ] Configure anchor for Arc deployment:
  ```
  L2_RPC_URL=http://localhost:8547
  SET_REGISTRY_ADDRESS=<from Phase 6>
  SEQUENCER_PRIVATE_KEY=<from Phase 1>
  SEQUENCER_API_URL=http://localhost:3001
  ANCHOR_INTERVAL_SECS=60
  MIN_EVENTS_FOR_ANCHOR=100
  EXPECTED_L2_CHAIN_ID=84532001
  HEALTH_PORT=9090
  ```
- [ ] Start anchor service
- [ ] Verify health endpoints:
  - `GET /health` returns 200
  - `GET /ready` returns 200 (L2 + sequencer connected)
  - `GET /metrics` returns Prometheus output
- [ ] Submit a test batch and confirm anchoring

### Phase 9 — Governance

- [ ] Set `MULTISIG_ADDRESS` in `config/arc.env`
- [ ] Deploy `SetTimelock` (2-day delay)
- [ ] Transfer ownership of all L2 contracts to timelock + multisig:
  - SetRegistry
  - SetPaymaster
  - NAVOracle
  - EncryptedMempool
- [ ] Transfer ownership of Arc L1 x402 contracts to multisig

### Phase 10 — Fault-Proof Exercise

- [ ] Set `DISPUTE_GAME_FACTORY` and `ANCHOR_STATE_REGISTRY` in env
- [ ] Run fault-proof checks:
  ```
  ./scripts/fault-proof-exercise.sh check
  ./scripts/fault-proof-exercise.sh exercise
  ./scripts/fault-proof-exercise.sh report
  ```
- [ ] Save logs and evidence under `reports/arc/`

### Phase 11 — Monitoring & Observability

- [ ] Configure Prometheus scrape for anchor `/metrics` endpoint
- [ ] Set up alerting for:
  - `set_anchor_circuit_breaker_state != 0` (circuit breaker tripped)
  - `set_anchor_consecutive_failures > 3`
  - `set_anchor_success_rate < 0.99`
  - L2 block gap > 3s
  - Batch submission gap > 30 minutes
- [ ] Verify SLO targets:
  | SLO | Target |
  |---|---|
  | L2 block production | 99.9% (2s interval, max 3s gap) |
  | Batch submission to L1 | < 30 min between submissions |
  | Anchor service uptime | 99.9% |
  | Anchor success rate | > 0.99 |
  | Anchor lag | < 15 min from sequencer to on-chain |

### Phase 12 — Contract Verification

- [ ] Configure Arc explorer verifier settings in `foundry.toml`
- [ ] Verify all L1 contracts on Arc explorer
- [ ] Verify all L2 contracts on Set explorer (if available)

### Phase 13 — Documentation

- [ ] Record Arc deployment in `docs/operations-history.md`
- [ ] Record fault-proof exercise results in `docs/fault-proof-exercise.md`
- [ ] Update `README.md` to state Arc as L1 settlement layer
- [ ] Update `docs/monitoring.md` with Arc-specific endpoints

### Phase 14 — Scorecard

- [ ] Confirm all phases complete
- [ ] Arc L1 settlement functional
- [ ] Fault-proof evidence recorded
- [ ] Update `docs/scorecard.md`
