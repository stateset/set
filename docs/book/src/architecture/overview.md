# Architecture Overview

Set Chain is a commerce-optimized Layer 2 built on the OP Stack. This document describes the high-level architecture and how components interact.

## System Components

### 1. OP Stack Foundation

Set Chain inherits the standard OP Stack components:

| Component | Role |
|-----------|------|
| **op-geth** | Execution layer (modified Geth) |
| **op-node** | Derivation and consensus |
| **op-batcher** | Batches L2 transactions to L1 |
| **op-proposer** | Publishes L2 state roots to L1 |
| **op-challenger** | Fault proof challenges |

### 2. Set Chain Extensions

On top of the OP Stack, Set Chain adds:

| Component | Contract/Service | Purpose |
|-----------|------------------|---------|
| **SetRegistry** | `SetRegistry.sol` | Anchor batch commitments |
| **SetPaymaster** | `SetPaymaster.sol` | Gas sponsorship |
| **Anchor Service** | `set-anchor` (Rust) | Bridge sequencer → on-chain |
| **Stablecoin System** | Multiple contracts | ssUSD yield-bearing stablecoin |
| **MEV Protection** | Multiple contracts | Encrypted mempool, forced inclusion |
| **Governance** | `SetTimelock.sol` | Upgrade timelock |

### 3. Off-Chain Components

| Component | Description |
|-----------|-------------|
| **stateset-sequencer** | Batches commerce events into commitments |
| **NAV Attestor** | Attests daily T-Bill NAV for ssUSD |
| **Keyper Network** | Threshold encryption key holders |

## Component Interactions

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Off-Chain Layer                              │
│                                                                      │
│  ┌────────────────────┐        ┌────────────────────┐               │
│  │ stateset-sequencer │        │    NAV Attestor    │               │
│  │                    │        │                    │               │
│  │ • Order events     │        │ • Daily T-Bill NAV │               │
│  │ • Payment events   │        │ • Proof generation │               │
│  │ • Inventory events │        │                    │               │
│  │ • Batch creation   │        │                    │               │
│  └─────────┬──────────┘        └─────────┬──────────┘               │
│            │                             │                           │
│            │ HTTP API                    │ attestNAV()               │
│            ▼                             ▼                           │
│  ┌────────────────────┐                                             │
│  │   Anchor Service   │ ◄──────────────────────────────────────────┤
│  │   (Rust binary)    │                                             │
│  │                    │                                             │
│  │ • Poll pending     │                                             │
│  │ • Submit to chain  │                                             │
│  │ • Retry logic      │                                             │
│  │ • Health metrics   │                                             │
│  └─────────┬──────────┘                                             │
└────────────┼────────────────────────────────────────────────────────┘
             │
             │ commitBatch()
             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        Set Chain L2 (On-Chain)                       │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                      Core Contracts                            │  │
│  │                                                                │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐    │  │
│  │  │ SetRegistry  │  │ SetPaymaster │  │   SetTimelock    │    │  │
│  │  │              │  │              │  │                  │    │  │
│  │  │ commitBatch  │  │ sponsor      │  │ schedule         │    │  │
│  │  │ verify       │  │ execute      │  │ execute          │    │  │
│  │  │ starkProof   │  │ tiers        │  │ cancel           │    │  │
│  │  └──────────────┘  └──────────────┘  └──────────────────┘    │  │
│  │                                                                │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    Stablecoin System                           │  │
│  │                                                                │  │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐ │  │
│  │  │TokenRegistry│ │ NAVOracle │ │   ssUSD    │ │  wssUSD    │ │  │
│  │  │            │ │           │ │            │ │  (ERC4626) │ │  │
│  │  │ whitelist  │ │ attestNAV │ │ rebasing   │ │ wrap/unwrap│ │  │
│  │  │ collateral │ │ history   │ │ shares     │ │ DeFi-ready │ │  │
│  │  └────────────┘ └────────────┘ └────────────┘ └────────────┘ │  │
│  │                                                                │  │
│  │  ┌─────────────────────────────────────────────────────────┐  │  │
│  │  │                   TreasuryVault                          │  │  │
│  │  │  deposit() │ requestRedemption() │ processRedemption()   │  │  │
│  │  └─────────────────────────────────────────────────────────┘  │  │
│  │                                                                │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    MEV Protection                              │  │
│  │                                                                │  │
│  │  ┌────────────────┐ ┌──────────────────┐ ┌────────────────┐  │  │
│  │  │EncryptedMempool│ │ThresholdKeyRegistry│ │ForcedInclusion│  │  │
│  │  │                │ │                  │ │                │  │  │
│  │  │ submitEncrypted│ │ registerKeyper   │ │ forceTransaction│  │  │
│  │  │ decrypt        │ │ DKG ceremony     │ │ confirmInclusion│  │  │
│  │  │ execute        │ │ epoch keys       │ │ claimExpired   │  │  │
│  │  └────────────────┘ └──────────────────┘ └────────────────┘  │  │
│  │                                                                │  │
│  │  ┌─────────────────────────────────────────────────────────┐  │  │
│  │  │              SequencerAttestation                        │  │  │
│  │  │  commitOrdering() │ verifyTxPosition() │ slashSequencer()│  │  │
│  │  └─────────────────────────────────────────────────────────┘  │  │
│  │                                                                │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                      │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                │ L2 outputs, batches
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        Ethereum L1                                   │
│                                                                      │
│  ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐    │
│  │  OptimismPortal  │ │  L2OutputOracle  │ │   SystemConfig   │    │
│  │                  │ │                  │ │                  │    │
│  │  deposits        │ │  state roots     │ │  chain params    │    │
│  │  withdrawals     │ │  dispute games   │ │  gas config      │    │
│  └──────────────────┘ └──────────────────┘ └──────────────────┘    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Data Flow

### Commerce Event Anchoring

```
1. Commerce Application
   │
   │ createOrder(), processPayment(), updateInventory()
   ▼
2. stateset-sequencer
   │
   │ • Validates events
   │ • Builds Merkle tree
   │ • Creates batch commitment
   │ • Exposes via HTTP API
   ▼
3. Anchor Service
   │
   │ • Polls GET /v1/commitments/pending
   │ • Submits commitBatch() to SetRegistry
   │ • Notifies sequencer of anchoring
   ▼
4. SetRegistry (on-chain)
   │
   │ • Stores commitment
   │ • Emits BatchCommitted event
   │ • Enables inclusion proofs
   ▼
5. Verification
   │
   │ verifyInclusion(batchId, leaf, proof, index)
   ▼
   Returns: true/false
```

### Stablecoin Flow

```
1. User deposits USDC
   │
   │ deposit(USDC, amount, recipient)
   ▼
2. TreasuryVault
   │
   │ • Validates collateral
   │ • Transfers USDC in
   │ • Mints ssUSD shares
   ▼
3. ssUSD (rebasing)
   │
   │ • User holds shares
   │ • Balance = shares × NAV
   ▼
4. NAVOracle (daily)
   │
   │ • Attestor submits new NAV
   │ • NAV per share increases
   │ • User balance auto-increases
   ▼
5. Redemption
   │
   │ requestRedemption() → wait delay → processRedemption()
   ▼
   User receives USDC minus fee
```

## Security Model

### Trust Assumptions

| Component | Trust Level | Notes |
|-----------|-------------|-------|
| L1 Ethereum | Trustless | Secured by Ethereum consensus |
| OP Stack | Trust-minimized | Fault proofs enable verification |
| Sequencer | Trusted (Phase 0) | Will be decentralized |
| NAV Attestor | Trusted | Company-operated, auditable |
| Anchor Service | Trusted | Authorized sequencer key |

### Upgrade Security

All upgradeable contracts use:
- UUPS proxy pattern
- Timelock delay (24h mainnet, 1h testnet)
- Multisig authorization (target: 3/5)

### Emergency Controls

- **Pause mechanisms**: Deposits, redemptions can be paused
- **Emergency withdrawal**: Owner can recover stuck funds
- **Circuit breakers**: NAV staleness limits, rate limits

## Network Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| Block time | 2s | OP Stack default |
| Gas limit | 30M | Per block |
| Base fee | Dynamic | EIP-1559 |
| L1 data | Blob | EIP-4844 blobs |
| Finality | ~12 min | L1 finality |
| Challenge period | 7 days | Fault proof window |

## Next Steps

- [VES Anchoring System](./ves-anchoring.md) - Deep dive into event anchoring
- [OP Stack Integration](./op-stack.md) - How Set Chain extends OP Stack
- [Trust Model](./trust-model.md) - Detailed security analysis
