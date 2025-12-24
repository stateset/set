# Validium-style Event Sourcing (VES)

Set Chain implements a **Validium-style Event Sourcing (VES)** system for anchoring commerce events with cryptographic proofs while keeping event data off-chain.

## Overview

VES combines:
- **Event Sourcing**: Immutable log of commerce events
- **Validium**: Data availability off-chain, commitments on-chain
- **Merkle Proofs**: Cryptographic inclusion verification

```
┌─────────────────────────────────────────────────────────────┐
│                    Off-Chain (Data Layer)                    │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Commerce Event Stream                     │  │
│  │                                                        │  │
│  │  Event 1: OrderCreated { id: "ord_123", ... }         │  │
│  │  Event 2: PaymentReceived { orderId: "ord_123", ... } │  │
│  │  Event 3: InventoryUpdated { sku: "SKU001", ... }     │  │
│  │  Event 4: OrderShipped { id: "ord_123", ... }         │  │
│  │  ...                                                   │  │
│  └──────────────────────────────────────────────────────┘  │
│                           │                                  │
│                           ▼                                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Batch Formation                           │  │
│  │                                                        │  │
│  │  • Group events by tenant/store                       │  │
│  │  • Build Merkle tree of event hashes                  │  │
│  │  • Compute state transition                           │  │
│  │  • Generate batch commitment                          │  │
│  └──────────────────────────────────────────────────────┘  │
│                           │                                  │
└───────────────────────────┼──────────────────────────────────┘
                            │
                            │ Anchor
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    On-Chain (Commitment Layer)               │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              SetRegistry Contract                      │  │
│  │                                                        │  │
│  │  Batch Commitment:                                     │  │
│  │  ├─ batchId: 0x1234...                                │  │
│  │  ├─ tenantId: 0xabcd...                               │  │
│  │  ├─ storeId: 0x5678...                                │  │
│  │  ├─ eventsRoot: 0xMERKLE_ROOT                         │  │
│  │  ├─ prevStateRoot: 0xSTATE_BEFORE                     │  │
│  │  ├─ newStateRoot: 0xSTATE_AFTER                       │  │
│  │  ├─ sequenceStart: 1001                               │  │
│  │  ├─ sequenceEnd: 1100                                 │  │
│  │  └─ eventCount: 100                                   │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Why VES?

### Traditional Approaches

| Approach | Data Location | Proof | Cost | Privacy |
|----------|--------------|-------|------|---------|
| **On-chain** | All on L1/L2 | Direct | Very High | None |
| **Rollup** | Calldata/Blobs | Fraud/ZK proof | High | None |
| **Validium** | Off-chain DAC | Validity proof | Low | High |
| **VES** | Off-chain + Merkle | Inclusion proof | Very Low | High |

### VES Advantages for Commerce

1. **Cost Efficiency**: Only store 32-byte roots, not full event data
2. **Privacy**: Event details not exposed on-chain
3. **Verifiability**: Merkle proofs enable trustless verification
4. **Scalability**: Millions of events per batch
5. **Compliance**: STARK proofs for regulatory attestation

## Batch Commitment Structure

### BatchCommitment

```solidity
struct BatchCommitment {
    bytes32 batchId;        // Unique identifier
    bytes32 tenantId;       // Multi-tenant isolation
    bytes32 storeId;        // Store-level grouping
    bytes32 eventsRoot;     // Merkle root of events
    bytes32 prevStateRoot;  // State before batch
    bytes32 newStateRoot;   // State after batch
    uint64 sequenceStart;   // First sequence number
    uint64 sequenceEnd;     // Last sequence number
    uint32 eventCount;      // Number of events
    uint64 timestamp;       // Commitment time
    address submitter;      // Authorized sequencer
}
```

### State Root Chaining

Each batch creates a state chain:

```
Genesis State
     │
     ▼
┌─────────────────┐
│ Batch 1         │
│ prev: GENESIS   │
│ new: STATE_1    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Batch 2         │
│ prev: STATE_1   │
│ new: STATE_2    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Batch 3         │
│ prev: STATE_2   │
│ new: STATE_3    │
└─────────────────┘
```

**Strict Mode**: When enabled, `prevStateRoot` must match the current state root, ensuring continuous state chain.

## Merkle Tree Construction

### Event Hashing

Each commerce event is hashed:

```typescript
function hashEvent(event: CommerceEvent): bytes32 {
  return keccak256(abi.encode(
    event.type,           // e.g., "OrderCreated"
    event.id,             // Unique event ID
    event.timestamp,      // Event timestamp
    event.data            // Serialized event data
  ));
}
```

### Tree Building

Events are organized into a binary Merkle tree:

```
                    eventsRoot
                   /          \
                 /              \
            Hash(0,1)          Hash(2,3)
           /        \         /        \
         H(E0)    H(E1)    H(E2)    H(E3)
          │        │        │        │
       Event0   Event1   Event2   Event3
```

### Proof Generation

For any event, generate a Merkle proof:

```typescript
const proof = generateMerkleProof(events, eventIndex);
// proof = [sibling0, sibling1, ..., siblingN]
// index = position in tree (used for left/right ordering)
```

## Inclusion Verification

### On-Chain Verification

```solidity
function verifyInclusion(
    bytes32 _batchId,
    bytes32 _leaf,
    bytes32[] calldata _proof,
    uint256 _index
) external view returns (bool valid) {
    BatchCommitment storage batch = commitments[_batchId];
    if (batch.timestamp == 0) {
        revert BatchNotCommitted();
    }

    // Verify Merkle proof
    bytes32 computedRoot = _computeMerkleRoot(_leaf, _proof, _index);
    return computedRoot == batch.eventsRoot;
}

function _computeMerkleRoot(
    bytes32 _leaf,
    bytes32[] calldata _proof,
    uint256 _index
) internal pure returns (bytes32 computedHash) {
    computedHash = _leaf;

    for (uint256 i = 0; i < _proof.length; i++) {
        bytes32 proofElement = _proof[i];

        if (_index % 2 == 0) {
            computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
        } else {
            computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
        }

        _index = _index / 2;
    }
}
```

### SDK Verification

```typescript
import { verifyInclusion } from "@setchain/sdk";

// Verify an event was included in a batch
const isValid = await registry.verifyInclusion(
  batchId,
  eventHash,
  merkleProof,
  leafIndex
);

if (isValid) {
  console.log("Event cryptographically proven to exist in batch");
}
```

## STARK Proof Integration

For regulatory compliance, batches can include STARK proofs:

```solidity
struct StarkProofCommitment {
    bytes32 proofHash;       // Hash of STARK proof
    bytes32 policyHash;      // Compliance policy used
    uint64 policyLimit;      // Policy threshold
    bool allCompliant;       // All events passed
    uint64 proofSize;        // Proof size in bytes
    uint64 provingTimeMs;    // Generation time
    uint64 timestamp;        // Submission time
    address submitter;       // Prover address
}
```

### Compliance Flow

```
1. Batch Created
   │
   │ Events include compliance-relevant data
   ▼
2. STARK Prover
   │
   │ • Verify each event against policy
   │ • Generate ZK proof of compliance
   │ • No sensitive data revealed
   ▼
3. commitStarkProof()
   │
   │ • Links proof to batch
   │ • Records compliance status
   │ • Enables regulatory verification
   ▼
4. Auditor Verification
   │
   │ • Fetch proof hash
   │ • Verify against off-chain proof
   │ • Confirm compliance
```

## Anchor Service

The Rust anchor service bridges off-chain sequencer to on-chain registry:

### Configuration

```toml
# anchor/config.toml
[anchor]
l2_rpc_url = "http://localhost:8547"
set_registry_address = "0x..."
sequencer_private_key = "0x..."
sequencer_api_url = "http://localhost:3000"
anchor_interval_secs = 60
min_events_for_anchor = 100
max_retries = 3
```

### Anchoring Loop

```rust
loop {
    // 1. Fetch pending commitments
    let commitments = sequencer_client
        .get_pending_commitments()
        .await?;

    // 2. Filter by minimum events
    let ready = commitments
        .iter()
        .filter(|c| c.event_count >= config.min_events_for_anchor);

    // 3. Anchor each batch
    for commitment in ready {
        let result = registry
            .commit_batch(commitment)
            .await;

        // 4. Notify sequencer
        if result.is_ok() {
            sequencer_client
                .notify_anchored(commitment.batch_id, result.tx_hash)
                .await;
        }
    }

    sleep(config.anchor_interval_secs).await;
}
```

## Query Patterns

### Get Latest State

```typescript
// Get current state root for a tenant/store
const stateRoot = await registry.getLatestStateRoot(tenantId, storeId);

// Get head sequence number
const sequence = await registry.getHeadSequence(tenantId, storeId);
```

### Verify Historical Event

```typescript
// 1. Application provides event details
const event = {
  type: "OrderCreated",
  id: "ord_123",
  timestamp: 1703001234,
  data: { ... }
};

// 2. Compute event hash
const eventHash = hashEvent(event);

// 3. Fetch proof from sequencer
const { batchId, proof, index } = await sequencer.getInclusionProof(event.id);

// 4. Verify on-chain
const isValid = await registry.verifyInclusion(batchId, eventHash, proof, index);
```

### Batch Multiple Verifications

```typescript
// Verify multiple events in one call
const results = await registry.verifyMultipleInclusions(
  batchId,
  [eventHash1, eventHash2, eventHash3],
  [proof1, proof2, proof3],
  [index1, index2, index3]
);
```

## Best Practices

### For Application Developers

1. **Store event IDs**: Keep track of event identifiers for later verification
2. **Cache proofs**: Merkle proofs don't change, cache them
3. **Batch verifications**: Use `verifyMultipleInclusions` for efficiency
4. **Handle timing**: Events may take 1-2 minutes to be anchored

### For Operators

1. **Monitor anchor lag**: Alert if anchoring falls behind
2. **Set appropriate thresholds**: Balance cost vs. latency
3. **Backup sequencer data**: Event data is off-chain, ensure durability
4. **Regular proof verification**: Spot-check proofs for integrity

## Next Steps

- [SetRegistry Contract Reference](../contracts/set-registry.md)
- [Data Flow Details](./data-flow.md)
- [STARK Proof System](../contracts/set-registry.md#stark-proofs)
