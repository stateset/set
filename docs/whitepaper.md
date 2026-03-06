# SET Chain: A Commerce-Optimized Layer 2 for Verifiable Agent Transactions

**Chain ID 84532001 | OP Stack v1.8.0 | March 2026**

---

## Abstract

SET Chain is an Ethereum Layer 2 network purpose-built for commerce. Built on the OP Stack, it inherits Ethereum's security guarantees while providing 2-second block times, sub-cent transaction fees, and native infrastructure for the three primitives that autonomous commerce requires: verifiable event commitments (SetRegistry), gas-abstracted merchant transactions (SetPaymaster), and a yield-bearing stablecoin (ssUSD) backed by U.S. Treasury Bills.

Unlike general-purpose L2s that optimize for DeFi or gaming, SET Chain is designed for a specific future: one where AI agents conduct commerce on behalf of businesses and consumers. In this future, every order, payment, and inventory adjustment must be cryptographically verifiable, gas costs must be invisible to end users, and the settlement currency must be stable, compliant, and yield-bearing.

This paper describes the chain architecture, smart contract design, stablecoin system, gas economics, anchoring protocol, and decentralization roadmap.

### The StateSet Trilogy

SET Chain is the third layer in a vertically integrated stack — the **StateSet Trilogy** — that spans from application logic to on-chain settlement:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          THE STATESET TRILOGY                                │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  Layer 3 — Application         StateSet iCommerce                    │   │
│   │                                 AI agents, MCP tools, A2A protocol   │   │
│   │                                 Policy DSL, workflows, storefront    │   │
│   └──────────────────────────┬──────────────────────────────────────────┘   │
│                               │ VES events (signed, encrypted)               │
│                               ▼                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  Layer 2 — Ordering           StateSet Sequencer                     │   │
│   │                                Deterministic ordering, Merkle trees   │   │
│   │                                STARK compliance proofs, sync protocol │   │
│   └──────────────────────────┬──────────────────────────────────────────┘   │
│                               │ Merkle commitments (batched)                 │
│                               ▼                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  Layer 1 — Settlement          SET Chain L2                          │   │
│   │                                 SetRegistry, SetPaymaster, ssUSD     │   │
│   │                                 On-chain anchoring, gas abstraction   │   │
│   └──────────────────────────┬──────────────────────────────────────────┘   │
│                               │ State roots, fault proofs                    │
│                               ▼                                              │
│                        ┌──────────────┐                                      │
│                        │   Ethereum    │                                      │
│                        │   (L1 DA)    │                                      │
│                        └──────────────┘                                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

An AI agent in iCommerce places an order → the event is signed and sent to the Sequencer → the Sequencer batches events into Merkle trees and produces STARK compliance proofs → the anchor service writes the Merkle root to SetRegistry on SET Chain → SET Chain settles to Ethereum. Every layer is independently verifiable. No layer trusts the one above it.

---

## 1. Why a Commerce-Specific L2?

General-purpose blockchains are poor commerce infrastructure for three reasons:

**Gas friction.** When a merchant processes an order, the customer should not think about gas. On Ethereum mainnet, a single `commitBatch` call costs $5-50 depending on congestion. On SET Chain, the same call costs fractions of a cent, and the SetPaymaster can sponsor it entirely — the merchant pays in fiat, the paymaster handles gas.

**Verification gaps.** Traditional commerce relies on database assertions: "this order was placed at this time." There is no mechanism for a third party to independently verify the claim. SET Chain closes this gap by anchoring Merkle commitments from the StateSet Sequencer — every batch of commerce events is permanently recorded on-chain, and any party can verify inclusion.

**Settlement mismatch.** Commerce operates in dollars. DeFi operates in volatile tokens. SET Chain bridges this gap with ssUSD, a rebasing stablecoin backed 1:1 by U.S. Treasury Bills, yielding ~5% APY. Merchants receive stable value. Holders earn yield. DeFi protocols integrate via the wssUSD ERC-4626 wrapper.

### 1.1 Why Not Deploy on Base?

A natural question: why operate a sovereign L2 instead of deploying contracts on an existing chain like Base, Arbitrum, or Optimism mainnet?

The answer is **enshrined primitives**. On a general-purpose L2, SetRegistry, SetPaymaster, and ssUSD are ordinary smart contracts — they compete for block space, are subject to external gas market volatility, and cannot influence chain-level parameters. On a sovereign L2, these primitives are enshrined at the network level:

| Capability | On Base/Arbitrum | On SET Chain |
|------------|------------------|--------------|
| Gas pricing | Subject to external market | Tuned for commerce (EIP-1559 denominator = 50) |
| Paymaster | Must bid for inclusion | Enshrined, priority gas lane (roadmap) |
| Block time | Shared with all dApps | 2s, optimized for order latency |
| MEV protection | Shared sequencer, no guarantees | Threshold encrypted mempool (Phase 2) |
| Commitment throughput | Competes for gas | Guaranteed capacity |
| Upgrade governance | Subject to chain operator | Controlled by StateSet governance |
| STARK proof storage | Arbitrary calldata | First-class `commitStarkProof()` |

The sovereign L2 provides **vertical integration** that a dApp on another chain cannot achieve: the chain's parameters, fee market, sequencing policy, and upgrade cadence are all aligned with commerce requirements. The cost is operational responsibility for chain infrastructure — a cost that is justified by the control it provides.

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         SET Chain L2 (84532001)                          │
│                    Commerce-Optimized OP Stack v1.8.0                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐  ┌───────────┐              │
│  │ op-geth  │  │ op-node  │  │ op-batcher│  │op-proposer│              │
│  │(execute) │  │(derive)  │  │ (batch)   │  │ (state)   │              │
│  └──────────┘  └──────────┘  └───────────┘  └───────────┘              │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                        Smart Contracts                              │ │
│  │  ┌────────────────┐  ┌────────────────┐  ┌──────────────────────┐ │ │
│  │  │  SetRegistry   │  │  SetPaymaster  │  │   ssUSD / wssUSD     │ │ │
│  │  │  (commitments) │  │  (gas sponsor) │  │   (stablecoin)       │ │ │
│  │  └────────────────┘  └────────────────┘  └──────────────────────┘ │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                          │                                               │
└──────────────────────────┼───────────────────────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        ▼                  │                  ▼
┌───────────────┐          │        ┌──────────────────┐
│ Anchor Service│          │        │ StateSet          │
│ (Rust)        │◄─────────┴───────►│ Sequencer         │
│               │  pending batches  │ (off-chain events) │
└───────┬───────┘                   └──────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                   ETHEREUM SEPOLIA (L1) — Chain 11155111                  │
│           OptimismPortal │ L2OutputOracle │ SystemConfig                  │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.1 OP Stack Components

SET Chain runs the standard OP Stack v1.8.0 with commerce-tuned parameters:

| Component | Role |
|-----------|------|
| **op-geth** | EVM execution engine (Cancun-compatible) |
| **op-node** | Consensus/derivation from L1 data |
| **op-batcher** | Submits L2 transaction batches to L1 |
| **op-proposer** | Publishes L2 state roots to L1 |
| **op-challenger** | Disputes invalid state roots via fault proofs |

### 2.2 Chain Parameters

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Chain ID | `84532001` | Unique, derived from Base Sepolia + 1 |
| Block time | 2 seconds | Fast enough for real-time commerce |
| Gas limit | 30M gas/block | Standard OP Stack capacity |
| Max sequencer drift | 600 seconds | 10-minute tolerance for ordering |
| EIP-1559 denominator | 50 | Stable, predictable fees |
| L1 settlement | Ethereum Sepolia | Inherits Ethereum security |
| Native token | ETH | Standard gas token |

### 2.3 Data Availability

SET Chain utilizes **Ethereum EIP-4844 Blob space** for Data Availability (DA). The op-batcher submits L2 transaction data as blobs rather than calldata, reducing DA costs by approximately 10-100x compared to pre-Dencun calldata posting.

| DA Strategy | Cost | Security | Trade-off |
|-------------|------|----------|-----------|
| **EIP-4844 Blobs** (current) | ~$0.001-0.01/batch | Ethereum-grade | 18-day blob retention window |
| L1 calldata (fallback) | ~$0.10-1.00/batch | Ethereum-grade | Higher cost, permanent retention |
| Alt-DA (Celestia/EigenDA) | Sub-cent | External validator set | Weaker security assumptions |

SET Chain defaults to blob posting for cost efficiency. If blob space becomes congested, the batcher falls back to L1 calldata automatically. We intentionally avoid third-party DA layers (Celestia, EigenDA) to maintain **Ethereum-equivalent security** — the same security model that protects trillions in DeFi value protects commerce commitments.

For long-term data retention beyond the 18-day blob window, the StateSet Sequencer maintains a complete event log, and Merkle roots anchored in SetRegistry provide permanent verifiability even after blob data expires.

---

## 3. SetRegistry: On-Chain Commitment Storage

The SetRegistry is the cryptographic anchor point for the entire StateSet commerce system. It stores Merkle commitments from the StateSet Sequencer, enabling any third party to verify that a specific commerce event (an order, a payment, an inventory adjustment) was included in a committed batch — without trusting the sequencer, the database, or any single party.

### 3.1 Contract Design

SetRegistry is a UUPS-upgradeable contract with the following capabilities:

| Function | Description |
|----------|-------------|
| `commitBatch()` | Submit a batch commitment with Merkle roots |
| `commitStarkProof()` | Submit a STARK compliance proof for a batch |
| `commitBatchWithStarkProof()` | Atomic batch + proof submission |
| `verifyInclusion()` | Verify an event is included in a committed batch |
| `getLatestStateRoot()` | Get current state root for a tenant/store |
| `setSequencerAuthorization()` | Authorize or revoke sequencer addresses |
| `setStrictMode()` | Enable/disable state chain continuity verification |

### 3.2 Batch Commitment Structure

Each batch commitment stores:

```solidity
struct BatchCommitment {
    bytes32 eventsRoot;       // Merkle root of event leaves
    bytes32 prevStateRoot;    // Previous batch's state root (chaining)
    bytes32 newStateRoot;     // This batch's state root
    uint64  sequenceStart;    // First sequence number
    uint64  sequenceEnd;      // Last sequence number
    uint32  eventCount;       // Number of events in batch
    uint256 timestamp;        // Block timestamp
    address submitter;        // Authorized sequencer address
}
```

### 3.3 State Chain Continuity

When strict mode is enabled, the contract enforces that each batch's `prevStateRoot` matches the previous batch's `newStateRoot` for the same `(tenantId, storeId)` pair. This prevents forked histories: if the sequencer tries to anchor two conflicting event logs for the same stream, the second submission is rejected.

Tenant/store isolation is achieved via `keccak256(tenantId, storeId)` — each stream has an independent chain of commitments.

### 3.4 Merkle Inclusion Verification

```solidity
// Verify an order event was included in a committed batch
bool valid = registry.verifyInclusion(
    batchId,
    orderEventLeafHash,
    merkleProof,
    leafIndex
);
```

This enables use cases like: a lending protocol verifying that a purchase order exists before extending trade finance, or a customs authority confirming an export event without accessing the full dataset.

### 3.5 STARK Proof Support

The registry can store STARK proof commitments alongside batch commitments:

```solidity
struct StarkProofCommitment {
    bytes32 proofHash;
    bytes32 policyHash;      // Compliance policy identifier
    uint64  policyLimit;
    bool    allCompliant;    // All events satisfy policy
    uint64  proofSize;
    uint64  provingTimeMs;
}
```

This enables zero-knowledge compliance proofs: a merchant can prove that all transactions in a batch satisfy tax collection rules without revealing transaction details.

### 3.6 Why Optimistic Rollup + STARK Proofs?

SET Chain is an **optimistic** rollup (OP Stack) that stores **validity proofs** (STARKs) inside its state. This is a deliberate architectural choice, not a contradiction:

**Why OP Stack today:**
- **Mature EVM tooling.** Forge, Hardhat, viem, wagmi — the entire Ethereum developer ecosystem works out of the box. Commerce applications need reliability, not cutting-edge ZK circuits.
- **Stable infrastructure.** OP Stack v1.8.0 is battle-tested across Optimism mainnet, Base, and dozens of L2s. The op-node, op-batcher, and op-proposer are production-grade.
- **Immediate time-to-market.** ZK rollups require bespoke proving infrastructure, circuit audits, and prover economics. OP Stack lets SET Chain launch now and evolve toward ZK later.

**Why STARKs inside the optimistic state:**
- The STARKs stored in SetRegistry are **application-level compliance proofs**, not rollup validity proofs. They prove that a batch of commerce events satisfies a specific policy (e.g., "all invoices have VAT collected") without revealing event details.
- These proofs are generated by the StateSet Sequencer using Winterfell, stored on-chain via `commitStarkProof()`, and verified off-chain by any interested party.
- The optimistic rollup handles **state validity** (is the L2 state correct?). The STARKs handle **commerce compliance** (do events satisfy business rules?). These are orthogonal concerns.

**Migration path:** The long-term roadmap (Section 16) includes evaluating a full ZK rollup migration. When ZK rollup infrastructure matures to OP Stack's level of tooling maturity, SET Chain can migrate — gaining faster finality (~minutes vs. 7-day challenge period) without changing application-level contracts.

### 3.7 Gas Economics

| Operation | Gas Cost | At $0.001/gas | Note |
|-----------|----------|---------------|------|
| `commitBatch` | 60-80k | <$0.08 | Per batch of 100+ events |
| `commitStarkProof` | 40-50k | <$0.05 | STARK proof metadata only |
| `verifyInclusion` | ~200 | <$0.001 | Merkle proof verification |

**Cost per event:** ~600-800 gas when batching 100 events. At SET Chain's low fee parameters, this translates to fractions of a cent per commerce event anchored on-chain.

---

## 4. SetPaymaster: Gas Abstraction for Commerce

Merchants should not think about gas. Customers should not think about gas. The SetPaymaster implements ERC-4337 gas sponsorship with tiered controls designed specifically for commerce operations.

### 4.1 Sponsorship Tiers

| Tier | Per-Transaction | Daily Limit | Monthly Limit |
|------|-----------------|-------------|---------------|
| **Starter** | 0.001 ETH | 0.01 ETH | 0.1 ETH |
| **Growth** | 0.005 ETH | 0.05 ETH | 0.5 ETH |
| **Enterprise** | 0.01 ETH | 0.1 ETH | 1.0 ETH |

Limits reset on 1-day and 30-day rolling windows. Spend tracking is per-merchant: `spentToday`, `spentThisMonth`, `totalSponsored`.

### 4.2 Operation Types

The paymaster tracks sponsorship by operation type, enabling merchants to allocate gas budgets across commerce operations:

| Operation | Description |
|-----------|-------------|
| `ORDER_CREATE` | New order placement |
| `ORDER_UPDATE` | Order status transitions |
| `PAYMENT_PROCESS` | Payment execution |
| `INVENTORY_UPDATE` | Stock adjustments |
| `RETURN_PROCESS` | Return processing |
| `COMMITMENT_ANCHOR` | Batch commitment anchoring |

### 4.3 Batch Operations

The paymaster supports efficient batch operations for high-volume merchants:

- `batchSponsorMerchants()` — sponsor up to 100 merchants in one transaction.
- `batchExecuteSponsorship()` — non-reverting batch processing that records per-merchant success/failure.
- `batchRefundUnusedGas()` — reclaim unused allocations.

### 4.4 User Experience

From the merchant's perspective, gas is invisible:

1. Merchant registers with a tier (or is auto-assigned by the platform).
2. A relayer submits transactions on the merchant's behalf.
3. SetPaymaster verifies the operation type and spend limits.
4. Gas is deducted from the merchant's sponsored allocation.
5. Unused gas is refundable.

The result: AI agents transacting on SET Chain can focus on commerce logic. Gas is a platform cost, not a user cost.

---

## 5. ssUSD: A Yield-Bearing Commerce Stablecoin

Commerce operates in dollars. SET Chain provides a native dollar-denominated stablecoin that earns yield from U.S. Treasury Bills.

### 5.1 Dual-Token Architecture

| Token | Type | Yield Mechanism | Best For |
|-------|------|----------------|----------|
| **ssUSD** | Rebasing | Balance auto-increases | Payments, holding, transfers |
| **wssUSD** | Non-rebasing (ERC-4626) | Share price accrues | DeFi, AMMs, lending |

Both tokens represent the same underlying value. Users wrap/unwrap freely between them.

### 5.2 How Yield Works

ssUSD uses a shares-based accounting model:

```
ssUSD balance = shares × NAV_per_share
```

The company holds U.S. Treasury Bills off-chain. A designated attestor submits daily NAV reports to the NAVOracle contract, reflecting T-Bill yield. As the NAV per share increases, ssUSD balances rebase upward automatically.

```
Day 0:  Balance = 1,000.00 ssUSD  (1,000 shares × $1.00 NAV)
Day 30: Balance = 1,004.11 ssUSD  (1,000 shares × $1.00411 NAV, ~5% APY)
```

For wssUSD, the balance stays constant but the share price increases — making it compatible with AMMs, lending protocols, and vaults that expect constant-balance tokens.

### 5.3 Contract Architecture

| Contract | Purpose |
|----------|---------|
| **TokenRegistry** | Verified token list and collateral whitelist |
| **NAVOracle** | Daily NAV attestation from authorized attestors |
| **ssUSD** | Rebasing stablecoin (minting/burning gated by TreasuryVault) |
| **wssUSD** | ERC-4626 wrapper for DeFi compatibility |
| **TreasuryVault** | Collateral management, deposit/redemption, fee control |

### 5.4 Collateral and Minting

Accepted collateral: USDC and USDT (bridged via OP Standard Bridge).

```
User deposits 1,000 USDC → TreasuryVault → Mints ~1,000 ssUSD
                                              (normalized from 6→18 decimals)
```

Minting is 1:1 minus configurable fees (default 0%).

### 5.5 Redemption

Redemptions follow a T+1 delay to protect against bank-run scenarios:

1. User approves ssUSD and calls `requestRedemption()`.
2. 24-hour delay (configurable).
3. Operator processes the redemption → collateral sent to user.
4. Users can cancel pending redemptions.

### 5.6 Safety Mechanisms

- **NAV staleness:** If NAV is not updated within 24 hours, deposits may be restricted. Redemptions always function.
- **Pause controls:** Deposits and redemptions can be independently paused for emergency response.
- **Access control:** Only TreasuryVault can mint/burn ssUSD. Only authorized attestors can update NAV. Upgrades require timelock governance.
- **Full collateralization:** Every ssUSD is backed 1:1 by either on-chain USDC/USDT collateral or off-chain T-Bill holdings (attested via NAVOracle).

### 5.7 Compliance and Minting Access

ssUSD occupies a regulatory position similar to tokenized money market funds: the underlying asset is U.S. Treasury Bills, and the yield distribution constitutes a financial return. Accordingly, **minting and redemption are permissioned**, while **on-chain transfers are permissionless**:

| Operation | Access | Rationale |
|-----------|--------|-----------|
| **Mint** (USDC → ssUSD) | KYC/KYB verified entities only | Securities/money transmission compliance |
| **Redeem** (ssUSD → USDC) | KYC/KYB verified entities only | AML/CTF obligations on fiat off-ramp |
| **Transfer** (ssUSD → ssUSD) | Permissionless | On-chain token transfer, no custodial act |
| **Wrap/Unwrap** (ssUSD ↔ wssUSD) | Permissionless | Pure accounting transformation |
| **DeFi integration** (wssUSD) | Permissionless | Composable ERC-4626 vault share |

The TreasuryVault enforces minting/redemption access via an allowlist managed by the protocol operator. Entities seeking to mint or redeem must complete KYC (individuals) or KYB (businesses) verification through an approved provider. Once ssUSD is minted, it circulates freely — AI agents, merchants, and smart contracts can transfer it without restrictions.

This design mirrors the structure used by established tokenized T-Bill protocols: permissioned issuance with permissionless circulation. It ensures regulatory compliance at the on-ramp/off-ramp boundary while preserving the programmability and composability that makes on-chain commerce practical.

### 5.8 ssUSD Yield Flow

The following diagram illustrates the complete lifecycle of capital backing ssUSD, from merchant deposit to yield distribution:

```
┌────────────────────────────────────────────────────────────────────────────┐
│                          ssUSD YIELD FLOW                                   │
│                                                                             │
│  ┌───────────┐    USDC     ┌───────────────┐    USD     ┌──────────────┐  │
│  │  Merchant  │───────────►│ TreasuryVault  │──────────►│  Custodian    │  │
│  │  (KYC/KYB) │            │  (on-chain)    │           │  (off-chain)  │  │
│  └───────────┘             └───────┬───────┘           └──────┬───────┘  │
│       ▲                            │                           │          │
│       │                     Mints ssUSD                 Purchases         │
│       │                            │                    T-Bills           │
│       │                            ▼                           │          │
│       │                    ┌───────────────┐                   ▼          │
│       │                    │    ssUSD      │          ┌──────────────┐    │
│       │  Balance rebases   │   (ERC-20)    │          │  U.S. T-Bills │   │
│       │  upward daily      │               │          │  (~5% APY)    │   │
│       │◄───────────────────│  shares × NAV │          └──────┬───────┘   │
│       │                    └───────────────┘                  │           │
│       │                            ▲                    Daily yield       │
│       │                            │                    report            │
│       │                    ┌───────┴───────┐                  │           │
│       │                    │  NAVOracle    │◄─────────────────┘           │
│       │                    │  (attestor)   │                              │
│       │                    └───────────────┘                              │
│       │                                                                   │
│       │  Protocol fee: ~0.20% of yield (T-Bills 5.20% → ssUSD 5.00%)    │
│       │                                                                   │
└───────┴───────────────────────────────────────────────────────────────────┘
```

**Example (30-day cycle):**
1. Merchant deposits 100,000 USDC into TreasuryVault (KYC verified).
2. TreasuryVault mints 100,000 ssUSD to merchant's wallet.
3. Custodian purchases $100,000 in U.S. Treasury Bills (~5.20% APY).
4. NAVOracle receives daily attestation: NAV per share increases.
5. After 30 days: merchant's ssUSD balance rebases to ~100,427 ssUSD (~5.00% net APY).
6. Protocol retains ~$17 (~0.20% annualized spread) as revenue.

---

## 6. The Anchor Service: Bridging Off-Chain to On-Chain

The anchor service is a Rust daemon that bridges the StateSet Sequencer (off-chain) to the SetRegistry contract (on-chain). It is the component that transforms database assertions into on-chain facts.

### 6.1 Operation Cycle

Every 60 seconds (configurable):

1. **Fetch** pending commitments from the sequencer via `GET /v1/commitments/pending`.
2. **Filter** by minimum event count (default: 100 events per batch).
3. **Submit** `commitBatch()` to the SetRegistry with exponential backoff retries (5s → 10s → 15s, max 3 attempts).
4. **Notify** the sequencer of successful anchoring via `POST /v1/commitments/{id}/anchored` with the chain transaction hash.

### 6.2 Resilience

The anchor service implements a circuit breaker state machine:

```
Closed (normal)  ──[5 failures]──►  Open (skip submissions)
      ▲                                    │
      │                              [60s timeout]
      │                                    ▼
      └──────[3 successes]────────  Half-Open (test)
```

Additional resilience features:
- **Gas price limits:** Skip anchoring cycles when gas exceeds a configurable threshold.
- **Health monitoring:** HTTP endpoints at `/health`, `/ready`, `/metrics`, `/stats`.
- **Prometheus metrics:** Track anchored batches, failures, events anchored, average anchor time, and circuit breaker state.
- **Authorization verification:** On startup, confirm the configured key is authorized in the SetRegistry.

### 6.3 Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `ANCHOR_INTERVAL_SECS` | 60 | Polling interval |
| `MIN_EVENTS_FOR_ANCHOR` | 100 | Minimum batch size |
| `MAX_RETRIES` | 3 | Retry attempts per batch |
| `MAX_GAS_PRICE_GWEI` | 0 (unlimited) | Gas price ceiling |
| `CIRCUIT_BREAKER_FAILURE_THRESHOLD` | 5 | Failures before open |
| `TX_CONFIRMATION_TIMEOUT_SECS` | 60 | On-chain confirmation wait |

---

## 7. Bridge and Asset Transfer

SET Chain uses the OP Stack Standard Bridge for asset transfers between Ethereum L1 and the L2.

### 7.1 Deposit Flow (L1 → L2)

| Step | Time | Description |
|------|------|-------------|
| L1 transaction confirmed | ~15 seconds | Standard Ethereum confirmation |
| L2 deposit relayed | 2-5 minutes | Funds appear on SET Chain |

ETH and ERC-20 tokens (USDC, USDT) can be bridged via `StandardBridge.depositETH()` and `StandardBridge.depositERC20()`.

### 7.2 Withdrawal Flow (L2 → L1)

| Step | Time | Description |
|------|------|-------------|
| Initiate on L2 | ~2 seconds | One L2 block confirmation |
| State root published | ~1 hour | L2 state posted to L1 |
| Prove withdrawal | ~15 seconds | Submit Merkle proof to L1 |
| Challenge period | 7 days | Security window for disputes |
| Finalize | ~15 seconds | Claim funds on Ethereum |

The 7-day challenge period is an inherent security property of optimistic rollups — it provides time for anyone to dispute an invalid state root.

### 7.3 Bridge UI

Multiple options are supported:
- **Superbridge** — production-ready bridge UI.
- **OP Bridge SDK** — programmatic bridge interactions via viem.
- **Blockscout widget** — integrated into the block explorer.

---

## 8. MEV Protection

Commerce transactions are particularly vulnerable to MEV (Maximal Extractable Value) — front-running large orders, sandwich attacks on price-sensitive operations. SET Chain implements a phased MEV protection strategy:

### Phase 1 (Current): Private Sequencer

The single sequencer provides implicit MEV protection by controlling transaction ordering. A `SequencerAttestation` contract allows the sequencer to commit to block orderings, enabling retroactive auditing.

### Phase 2 (Implemented): Threshold Encrypted Mempool

A `ThresholdKeyRegistry` manages distributed key generation (DKG) among registered keypers. Users encrypt transactions with the current epoch public key. The sequencer commits to ordering without seeing transaction contents. Keypers decrypt after ordering is finalized. Execution follows the committed order.

```
User → Encrypt(tx, epoch_pubkey) → EncryptedMempool
  → Sequencer commits ordering → Keypers decrypt → Execute in order
```

### Phase 3 (Planned): Forced L1 Inclusion

Users can force-include transactions via L1 deposits, bypassing the sequencer entirely. This prevents censorship while maintaining ordering guarantees.

### Phase 4 (Future): Shared Sequencing

Integration with shared sequencing protocols (Espresso, Astria) for decentralized ordering with cross-chain atomicity.

---

## 9. Security Model

### 9.1 Trust Boundaries

| Component | Trust Assumption | Mitigation |
|-----------|-----------------|------------|
| Sequencer | Trusted for ordering | Receipts, monitoring, multi-sequencer (roadmap) |
| L1 settlement | Ethereum security | OP Stack fault proofs |
| SetRegistry | Contract correctness | UUPS upgradeable, audited, timelock governance |
| SetPaymaster | Spend limit enforcement | On-chain limits, operator gating |
| ssUSD NAV | Attestor honesty | Daily attestation, 24h staleness check |
| Anchor service | Liveness | Circuit breaker, health monitoring, retry logic |

### 9.2 Governance

Production deployments follow a multi-layered governance model:

1. **Multisig (Safe):** M-of-N signers for governance proposals.
2. **Timelock (48h+):** Review window before execution.
3. **Pause guardian:** Separate key for emergency pause actions.
4. **Sequencer key rotation:** Via SetRegistry `setSequencerAuthorization()` through the timelock.

SetRegistry and SetPaymaster are UUPS-upgradeable, with the timelock as the upgrade authority. Direct EOA control is explicitly discouraged for production.

### 9.3 Emergency Procedures

- **Revoke sequencer:** Halt commitment anchoring immediately.
- **Pause SetRegistry:** Prevent new batch commitments.
- **Pause SetPaymaster:** Halt gas sponsorship.
- **Pause ssUSD deposits:** Restrict new minting while preserving redemptions.

### 9.4 Fault Proofs

SET Chain inherits OP Stack fault proof mechanisms. The `op-challenger` monitors L2 outputs and can dispute invalid state via the `DisputeGameFactory` on L1. Configuration validation:

```bash
./scripts/validate-ops-config.sh --mode testnet --require-fault-proofs
./scripts/check-l1-settlement.sh --env-file config/sepolia.env --require-addresses
```

---

## 10. Monitoring and SLOs

### 10.1 Key Metrics

| Metric | Expected | Alert Threshold |
|--------|----------|-----------------|
| Block production | Every 2 seconds | > 10s gap |
| Batch submission to L1 | Every few minutes | > 30 min gap |
| Anchor lag | < 5 minutes | > 15 minutes |
| L2 safe head lag | < 10 blocks | > 100 blocks |
| Anchor service health | Healthy | Circuit breaker open |

### 10.2 Anchor Service Observability

The anchor service exposes Prometheus-format metrics and JSON statistics:

```
GET /health    — liveness probe
GET /ready     — readiness (connected to chain + sequencer)
GET /metrics   — Prometheus metrics
GET /stats     — JSON: anchored count, failures, avg time, circuit breaker state
```

---

## 11. Use Cases

### 11.1 Verifiable Order Fulfillment

An AI agent processes an order. The event is signed (Ed25519), sequenced by the StateSet Sequencer, committed into a Merkle batch, and anchored to SET Chain via the anchor service. A logistics partner can verify the order's existence and timestamp by checking the on-chain Merkle proof — without accessing the merchant's database.

### 11.2 Trade Finance

A lending protocol extends credit against purchase orders. The protocol verifies purchase order events are anchored in SetRegistry before disbursing funds. The STARK compliance proof confirms tax compliance without revealing order details. Settlement occurs in ssUSD, earning yield during the financing period.

### 11.3 Cross-Border Customs

A customs authority needs to verify that an export declaration was filed and matches the shipment. The authority verifies the Merkle inclusion proof for the declaration event on SET Chain. The zero-knowledge compliance proof confirms regulatory compliance without revealing commercial terms.

### 11.4 Gas-Sponsored Agent Commerce

An AI shopping agent operates on behalf of a consumer. The merchant sponsors all gas costs via SetPaymaster. The agent places orders, processes payments, and handles returns — all on SET Chain — without the consumer ever holding ETH or interacting with blockchain infrastructure.

---

## 12. Decentralization Roadmap

### Phase 0: Single Sequencer (Current)

A centralized sequencer with explicit authorization. P2P disabled. Suitable for devnet and initial production.

### Phase 1: Backup Sequencer

A secondary sequencer key is authorized in SetRegistry. Operational runbooks govern failover. Monitoring tracks both sequencers.

### Phase 2: Shared Sequencer Set

P2P enabled (`sequencer.p2p_enabled = true`). L1 confirmation depth required (`l1_confs >= 1`). Node operation guides published with hardware requirements.

### Phase 3: Permissionless Participation

On-chain governance for sequencer admission. Timelock-controlled upgrades and authorization. Formalized incentives and dispute resolution. Economic security via staking.

---

## 13. Deployment Architecture

### 13.1 Required Accounts

| Account | Role |
|---------|------|
| Admin | Contract ownership (should be timelock) |
| Batcher | Submits L2 transaction batches to L1 |
| Proposer | Publishes L2 state roots to L1 |
| Challenger | Disputes invalid state (fault proofs) |
| Sequencer | L2 block production |

Each account requires Sepolia ETH funding (0.5+ ETH recommended).

### 13.2 Deployment Sequence

1. Configure Sepolia RPC endpoint and JWT secret.
2. Deploy L1 contracts (OP Stack): `deploy-l1.sh`.
3. Generate L2 genesis block: `generate-genesis.sh`.
4. Start L2 nodes: op-geth, op-node.
5. Start op-batcher and op-proposer.
6. Deploy SetRegistry to L2.
7. Deploy SetPaymaster to L2.
8. Deploy stablecoin system (TokenRegistry, NAVOracle, ssUSD, wssUSD, TreasuryVault).
9. Start anchor service.

### 13.3 Docker Deployment

```bash
# Local devnet (includes L1)
cd docker && docker-compose up -d

# Sepolia testnet
docker-compose -f docker-compose.sepolia.yml up -d

# With anchor service
docker-compose --profile anchor up -d

# With block explorer
docker-compose --profile explorer up -d
```

Alternative L1 clients: Nethermind, Reth.

---

## 14. Technology Stack

| Component | Technology | Version |
|-----------|------------|---------|
| Smart contracts | Solidity | 0.8.20 |
| Contract framework | Foundry (Forge) | Latest |
| Anchor service | Rust | 2021 Edition |
| Async runtime | Tokio | Full features |
| Ethereum client | Alloy | 0.9 |
| Health server | Axum | 0.8 |
| SDK | TypeScript | 5.4+ |
| L2 execution | op-geth | OP Stack v1.8.0 |
| L2 consensus | op-node | OP Stack v1.8.0 |
| Contract dependencies | OpenZeppelin | Latest |

---

## 15. Business Model and Value Accrual

SET Chain generates revenue through two primary mechanisms, both aligned with usage rather than speculation:

### 15.1 ssUSD Yield Spread

The protocol retains a spread between gross T-Bill yield and net ssUSD yield distributed to holders:

| Component | Rate | Example ($10M TVL) |
|-----------|------|---------------------|
| Gross T-Bill yield | ~5.20% APY | $520,000/year |
| Net yield to ssUSD holders | ~5.00% APY | $500,000/year |
| **Protocol revenue** | **~0.20% spread** | **$20,000/year** |

This spread scales linearly with ssUSD TVL. At $100M TVL, protocol revenue reaches ~$200,000/year from yield alone. The spread is configurable by governance and intentionally kept thin to maximize merchant adoption.

### 15.2 Paymaster Premium

The SetPaymaster charges merchants a configurable premium over base L2 gas costs. Merchants pay for gas sponsorship in fiat (via API billing), and the platform converts to ETH for on-chain execution:

| Tier | Base Gas Cost | Merchant Charge | Platform Margin |
|------|---------------|-----------------|-----------------|
| Starter | ~$0.001/tx | ~$0.003/tx | ~$0.002/tx |
| Growth | ~$0.001/tx | ~$0.002/tx | ~$0.001/tx |
| Enterprise | ~$0.001/tx | Custom SLA | Negotiated |

At scale (1M transactions/month across merchants), Paymaster premium contributes ~$1,000-2,000/month in margin.

### 15.3 Revenue Summary

| Revenue Source | Mechanism | Scales With |
|----------------|-----------|-------------|
| Yield spread | T-Bill APY minus ssUSD APY | ssUSD TVL |
| Paymaster premium | Merchant gas markup | Transaction volume |
| Anchor fees (future) | Per-batch anchoring charges | Event volume |
| Bridge fees (future) | Cross-chain transfer tolls | Asset flow |

The model is designed so that **value accrues with commerce activity**, not token speculation. As more merchants use ssUSD for settlement and more agents transact via the Paymaster, protocol revenue grows proportionally.

---

## 16. Roadmap

### Near-Term (Q1-Q2 2026)

- **ssUSD mainnet launch** — T-Bill-backed stablecoin with live yield.
- **Paymaster production tier** — Enterprise tier with custom limits.
- **Bridge UI** — Superbridge deployment for seamless L1↔L2 asset transfer.
- **Fiat onramps** — MoonPay/Transak integration for direct fiat→SET Chain deposits.

### Medium-Term (Q3-Q4 2026)

- **Shared sequencer set** — Phase 2 decentralization with P2P and L1 confirmation requirements.
- **Threshold encrypted mempool** — MEV-protected commerce transactions.
- **Cross-chain bridge expansion** — Direct bridges to Base, Arbitrum, and Solana.
- **Compliance proof automation** — On-chain STARK verification for tax and regulatory proofs.

### Long-Term (2027+)

- **Permissionless sequencing** — Open participation with staking and slashing.
- **Formal verification** — Machine-checked proofs of SetRegistry and SetPaymaster invariants.
- **ZK rollup migration** — Evaluate transition from optimistic to ZK proofs for faster finality.
- **Multi-chain ssUSD** — Native ssUSD deployment on additional L2s.

---

## 17. Conclusion

SET Chain is infrastructure for the age of autonomous commerce. It is not a general-purpose blockchain — it is a commerce-specific settlement layer where AI agents transact with cryptographic guarantees, merchants operate without gas friction, and every transaction earns yield in a stable, compliant currency.

> **The thesis is simple: commerce is moving from human-operated databases to agent-operated verifiable ledgers. SET Chain provides the three primitives this transition requires — verifiable commitments, gas abstraction, and stable settlement — on an Ethereum-secured L2 with 2-second finality.**

---

## Appendix A: Contract Interfaces

### SetRegistry

```solidity
interface ISetRegistry {
    function commitBatch(
        bytes32 batchId, bytes32 tenantId, bytes32 storeId,
        bytes32 eventsRoot, bytes32 prevStateRoot, bytes32 newStateRoot,
        uint64 sequenceStart, uint64 sequenceEnd, uint32 eventCount
    ) external;

    function verifyInclusion(
        bytes32 batchId, bytes32 leaf, bytes32[] calldata proof, uint256 index
    ) external view returns (bool);

    function getLatestStateRoot(bytes32 tenantId, bytes32 storeId)
        external view returns (bytes32);

    function setSequencerAuthorization(address sequencer, bool authorized)
        external;

    function setStrictMode(bool enabled) external;

    function isAnchored(bytes32 batchId) external view returns (bool);
}
```

### SetPaymaster

```solidity
interface ISetPaymaster {
    function sponsorMerchant(address merchant, uint8 tier) external;

    function batchSponsorMerchants(
        address[] calldata merchants, uint8[] calldata tiers
    ) external;

    function batchRefundUnusedGas(address[] calldata merchants) external;

    function getMerchantStats(address merchant)
        external view returns (
            uint256 spentToday, uint256 spentThisMonth, uint256 totalSponsored
        );
}
```

## Appendix B: Anchor Service Health Endpoints

| Endpoint | Method | Response |
|----------|--------|----------|
| `/health` | GET | `200 OK` if service is running |
| `/ready` | GET | `200 OK` if connected to chain and sequencer |
| `/metrics` | GET | Prometheus-format metrics |
| `/stats` | GET | JSON: `total_anchored`, `total_failed`, `avg_anchor_time_ms`, `circuit_breaker_state` |

## Appendix C: ssUSD Contract Addresses

| Network | Contract | Address |
|---------|----------|---------|
| SET Chain Testnet | TokenRegistry | TBD |
| SET Chain Testnet | NAVOracle | TBD |
| SET Chain Testnet | ssUSD | TBD |
| SET Chain Testnet | wssUSD | TBD |
| SET Chain Testnet | TreasuryVault | TBD |
