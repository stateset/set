# Data Flow

Understanding how data flows through Set Chain's architecture.

## Overview

Set Chain handles three primary data flows:

1. **Transaction Flow** - User transactions through the L2
2. **VES Anchoring Flow** - Off-chain events to on-chain proofs
3. **Stablecoin Flow** - Deposits, rebasing, and redemptions

## Transaction Flow

### Standard Transaction

```
┌──────┐     ┌───────────┐     ┌──────────┐     ┌─────────┐
│ User │────▶│ Sequencer │────▶│ op-geth  │────▶│  State  │
└──────┘     └───────────┘     └──────────┘     └─────────┘
                  │
                  ▼
            ┌───────────┐     ┌──────────┐
            │ op-batcher│────▶│ Ethereum │
            └───────────┘     └──────────┘
```

**Steps:**

1. **Submission**: User signs and submits transaction to sequencer RPC
2. **Ordering**: Sequencer orders transaction in a block
3. **Execution**: op-geth executes transaction, updates state
4. **Batching**: op-batcher compresses and posts batch to L1
5. **Finalization**: After challenge period, state is finalized

### MEV-Protected Transaction

```
┌──────┐     ┌───────────┐     ┌─────────────┐     ┌──────────┐
│ User │────▶│ Encrypt   │────▶│ Sequencer   │────▶│ Ordering │
└──────┘     │ (client)  │     │ (encrypted) │     │ Commit   │
             └───────────┘     └─────────────┘     └────┬─────┘
                                                       │
┌──────────┐     ┌─────────────┐     ┌──────────┐     │
│ Execute  │◀────│  Decrypt    │◀────│ Keypers  │◀────┘
└──────────┘     └─────────────┘     └──────────┘
```

**Steps:**

1. **Encryption**: User encrypts transaction with threshold public key
2. **Submission**: Encrypted payload sent to EncryptedMempool
3. **Ordering**: Sequencer commits ordering (can't see contents)
4. **Decryption**: Keypers release key shares after ordering committed
5. **Execution**: Transaction decrypted and executed in committed order

## VES Anchoring Flow

### Event Generation to Anchoring

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Commerce    │────▶│   Anchor     │────▶│  SetRegistry │
│  Application │     │   Service    │     │  (on-chain)  │
└──────────────┘     └──────────────┘     └──────────────┘
       │                    │                     │
       ▼                    ▼                     ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Generate     │     │ Batch &      │     │ Verify       │
│ Events       │     │ Merkle Tree  │     │ Inclusion    │
└──────────────┘     └──────────────┘     └──────────────┘
```

**Detailed Flow:**

```typescript
// 1. Commerce app generates events
const events = [
    { type: "order_created", orderId: "123", amount: 100 },
    { type: "payment_received", orderId: "123", txHash: "0x..." },
    { type: "order_fulfilled", orderId: "123", trackingId: "ABC" }
];

// 2. Events stored in off-chain database
await eventStore.appendEvents(tenantId, storeId, events);

// 3. Anchor service batches events periodically
const batch = await eventStore.getBatchForAnchoring(tenantId, storeId);

// 4. Build Merkle tree
const leaves = batch.events.map(e => keccak256(serialize(e)));
const tree = new MerkleTree(leaves);
const merkleRoot = tree.getRoot();

// 5. Submit to SetRegistry
const batchId = await registry.submitBatch(tenantId, storeId, {
    merkleRoot,
    stateRoot: computeStateRoot(batch),
    previousStateRoot: batch.previousStateRoot,
    eventCount: batch.events.length,
    startSequence: batch.startSeq,
    endSequence: batch.endSeq,
    timestamp: Date.now(),
    metadata: encodeMetadata(batch)
});

// 6. Later: Verify event inclusion
const proof = tree.getProof(eventIndex);
const isValid = await registry.verifyInclusion(
    batchId,
    eventHash,
    proof,
    eventIndex
);
```

### Verification Flow

```
┌──────────┐     ┌──────────────┐     ┌──────────────┐
│ Verifier │────▶│  Get Proof   │────▶│  Verify On   │
│          │     │  (off-chain) │     │  Chain       │
└──────────┘     └──────────────┘     └──────────────┘
                        │                     │
                        ▼                     ▼
                 ┌──────────────┐     ┌──────────────┐
                 │ Event Data   │     │ SetRegistry  │
                 │ + Merkle     │     │ .verifyIncl  │
                 │ Proof        │     │ usion()      │
                 └──────────────┘     └──────────────┘
```

## Stablecoin Flow

### Deposit Flow

```
┌──────┐     ┌──────────┐     ┌──────────────┐     ┌────────┐
│ User │────▶│ Approve  │────▶│ Treasury     │────▶│ ssUSD  │
│      │     │ USDC     │     │ .deposit()   │     │ minted │
└──────┘     └──────────┘     └──────────────┘     └────────┘
                                    │
                                    ▼
                             ┌──────────────┐
                             │ TokenRegistry│
                             │ .update()    │
                             └──────────────┘
```

**Steps:**

```typescript
// 1. User approves USDC spending
await usdc.approve(treasuryAddress, amount);

// 2. Treasury validates
//    - Token in TokenRegistry
//    - Deposits not paused
//    - NAV not stale
//    - Deposit cap not exceeded

// 3. Treasury pulls USDC
await usdc.transferFrom(user, treasury, amount);

// 4. Calculate shares based on current NAV
const shares = amount * 1e18 / currentNAV;

// 5. Mint ssUSD shares to user
await ssUSD.mint(user, shares);

// 6. Update TokenRegistry deposits
await tokenRegistry.incrementDeposits(token, amount);

// 7. Emit Deposit event
emit Deposit(user, token, amount, ssUSDMinted);
```

### Rebasing Flow

```
┌───────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│ Attestor  │────▶│ NAVOracle│────▶│  ssUSD   │────▶│ Balances │
│ (daily)   │     │ .update  │     │ .rebase  │     │ Updated  │
└───────────┘     └──────────┘     └──────────┘     └──────────┘
```

**Steps:**

```typescript
// 1. Attestor submits daily NAV report
const report = {
    reportId: 100,
    nav: parseUnits("1.000137", 18),  // 0.0137% daily increase
    totalAssets: parseUnits("50000000", 18),
    totalShares: parseUnits("49993150", 18),
    timestamp: Date.now(),
    proofHash: keccak256("audit-proof-100")
};

// 2. NAVOracle verifies and stores
await navOracle.updateNAV(report, attestorSignature);

// 3. ssUSD reads new NAV
const newNav = await navOracle.currentNAV();

// 4. User balances automatically reflect new NAV
// balanceOf(user) = sharesOf(user) * newNav / 1e18
// No transactions needed - balances just "grow"
```

### Redemption Flow

```
┌──────┐     ┌──────────────┐     ┌──────────┐     ┌──────────┐
│ User │────▶│ Treasury     │────▶│ ssUSD    │────▶│ USDC     │
│      │     │ .redeem()    │     │ burned   │     │ received │
└──────┘     └──────────────┘     └──────────┘     └──────────┘
                   │
                   ▼
            ┌──────────────┐
            │ Fee deducted │
            │ (10 bps)     │
            └──────────────┘
```

### Wrapping Flow (ssUSD → wssUSD)

```
┌──────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│ User │────▶│ Approve  │────▶│ wssUSD   │────▶│ wssUSD   │
│      │     │ ssUSD    │     │ .deposit │     │ minted   │
└──────┘     └──────────┘     └──────────┘     └──────────┘
                                   │
                                   ▼
                             ┌──────────────┐
                             │ ssUSD locked │
                             │ in wssUSD    │
                             └──────────────┘
```

**Key Difference:**
- ssUSD: Balance increases with NAV (rebasing)
- wssUSD: Balance stays constant, redeemable value increases

## Cross-System Flow

### Complete Commerce Transaction

```
┌────────────────────────────────────────────────────────────────┐
│                    E-Commerce Purchase                          │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Customer initiates payment                                  │
│     ┌──────────┐                                               │
│     │ Customer │                                               │
│     └────┬─────┘                                               │
│          │                                                      │
│  2. Pay with ssUSD (gas sponsored by merchant)                 │
│          │      ┌──────────────┐                               │
│          └─────▶│ SetPaymaster │ checks policy                 │
│                 └──────┬───────┘                               │
│                        │                                        │
│  3. Transfer ssUSD to merchant                                  │
│                        │      ┌──────────┐                     │
│                        └─────▶│  ssUSD   │                     │
│                               └────┬─────┘                     │
│                                    │                            │
│  4. Commerce app logs events                                    │
│                                    │      ┌──────────────┐     │
│                                    └─────▶│ Event Store  │     │
│                                           └──────┬───────┘     │
│                                                  │              │
│  5. Anchor service batches and submits                         │
│                                                  │              │
│                                           ┌──────▼───────┐     │
│                                           │ SetRegistry  │     │
│                                           └──────────────┘     │
│                                                                 │
│  6. Auditor verifies transaction later                          │
│     ┌─────────┐     ┌───────────┐     ┌──────────────┐        │
│     │ Auditor │────▶│ Get Proof │────▶│ Verify Chain │        │
│     └─────────┘     └───────────┘     └──────────────┘        │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
```

## Data Storage

### On-Chain Data

| Data | Contract | Size |
|------|----------|------|
| Batch commitments | SetRegistry | ~256 bytes/batch |
| ssUSD shares | ssUSD | 32 bytes/user |
| NAV reports | NAVOracle | ~192 bytes/report |
| Merchant policies | SetPaymaster | ~320 bytes/merchant |

### Off-Chain Data

| Data | Storage | Size |
|------|---------|------|
| Raw events | Event Store DB | Variable |
| Merkle proofs | Event Store DB | ~1KB/event |
| Transaction details | Standard indexer | Variable |

## Message Queues

### Event Processing Pipeline

```
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│  Events  │────▶│  Queue   │────▶│ Processor│────▶│  Batch   │
│ Generated│     │ (Kafka)  │     │          │     │ Builder  │
└──────────┘     └──────────┘     └──────────┘     └──────────┘
                                                        │
                                                        ▼
                                                  ┌──────────┐
                                                  │ Anchor   │
                                                  │ Service  │
                                                  └──────────┘
```

## Latency Expectations

| Operation | Typical Latency |
|-----------|-----------------|
| Transaction confirmation | 2-4 seconds |
| Batch anchoring | 1-5 minutes |
| NAV update | Once daily |
| L1 data availability | 2-12 minutes |
| Withdrawal finalization | 7 days |

## Related

- [Architecture Overview](./overview.md)
- [OP Stack Integration](./op-stack.md)
- [Trust Model](./trust-model.md)
