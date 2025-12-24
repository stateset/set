# SetRegistry Contract

The SetRegistry contract is the core anchoring contract for Set Chain's VES (Validium-style Event Sourcing) system. It stores batch commitments and enables Merkle proof verification.

## Overview

| Property | Value |
|----------|-------|
| **Contract** | `SetRegistry.sol` |
| **Type** | UUPS Upgradeable |
| **License** | MIT |
| **Solidity** | ^0.8.20 |

## State Variables

```solidity
/// @notice Authorized sequencers who can submit commitments
mapping(address => bool) public authorizedSequencers;

/// @notice Batch commitments by ID
mapping(bytes32 => BatchCommitment) public commitments;

/// @notice STARK proof commitments by batch ID
mapping(bytes32 => StarkProofCommitment) public starkProofs;

/// @notice Latest state root per tenant/store
mapping(bytes32 => mapping(bytes32 => bytes32)) public stateRoots;

/// @notice Latest sequence number per tenant/store
mapping(bytes32 => mapping(bytes32 => uint64)) public headSequence;

/// @notice Strict mode (require state root continuity)
bool public strictModeEnabled;

/// @notice Total batches committed
uint256 public totalBatches;

/// @notice Total events anchored
uint256 public totalEvents;
```

## Structs

### BatchCommitment

```solidity
struct BatchCommitment {
    bytes32 batchId;        // Unique batch identifier
    bytes32 tenantId;       // Multi-tenant isolation
    bytes32 storeId;        // Store-level grouping
    bytes32 eventsRoot;     // Merkle root of event hashes
    bytes32 prevStateRoot;  // State root before batch
    bytes32 newStateRoot;   // State root after batch
    uint64 sequenceStart;   // First sequence number
    uint64 sequenceEnd;     // Last sequence number
    uint32 eventCount;      // Number of events in batch
    uint64 timestamp;       // Block timestamp
    address submitter;      // Authorized sequencer
}
```

### StarkProofCommitment

```solidity
struct StarkProofCommitment {
    bytes32 proofHash;      // Hash of STARK proof
    bytes32 policyHash;     // Compliance policy hash
    uint64 policyLimit;     // Policy threshold
    bool allCompliant;      // All events passed
    uint64 proofSize;       // Proof size in bytes
    uint64 provingTimeMs;   // Generation time
    uint64 timestamp;       // Submission time
    address submitter;      // Prover address
}
```

## Functions

### commitBatch

Commit a batch of commerce events.

```solidity
function commitBatch(
    bytes32 _batchId,
    bytes32 _tenantId,
    bytes32 _storeId,
    bytes32 _eventsRoot,
    bytes32 _prevStateRoot,
    bytes32 _newStateRoot,
    uint64 _sequenceStart,
    uint64 _sequenceEnd,
    uint32 _eventCount
) external nonReentrant
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `_batchId` | bytes32 | Unique batch identifier |
| `_tenantId` | bytes32 | Tenant identifier |
| `_storeId` | bytes32 | Store identifier |
| `_eventsRoot` | bytes32 | Merkle root of events |
| `_prevStateRoot` | bytes32 | Previous state root |
| `_newStateRoot` | bytes32 | New state root |
| `_sequenceStart` | uint64 | First sequence number |
| `_sequenceEnd` | uint64 | Last sequence number |
| `_eventCount` | uint32 | Event count |

**Requirements:**
- Caller must be authorized sequencer
- Batch ID must not already exist
- If strict mode: `_prevStateRoot` must match current state root
- Sequence numbers must be valid (end >= start)

**Events:**
```solidity
event BatchCommitted(
    bytes32 indexed batchId,
    bytes32 indexed tenantId,
    bytes32 indexed storeId,
    bytes32 eventsRoot,
    bytes32 prevStateRoot,
    bytes32 newStateRoot,
    uint64 sequenceStart,
    uint64 sequenceEnd,
    uint32 eventCount
);
```

**Example:**
```typescript
const tx = await registry.commitBatch(
    batchId,
    tenantId,
    storeId,
    eventsRoot,
    prevStateRoot,
    newStateRoot,
    1001n,
    1100n,
    100
);
await tx.wait();
```

---

### verifyInclusion

Verify an event is included in a committed batch.

```solidity
function verifyInclusion(
    bytes32 _batchId,
    bytes32 _leaf,
    bytes32[] calldata _proof,
    uint256 _index
) external view returns (bool valid)
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `_batchId` | bytes32 | Batch to verify against |
| `_leaf` | bytes32 | Event hash (leaf) |
| `_proof` | bytes32[] | Merkle proof siblings |
| `_index` | uint256 | Leaf index in tree |

**Returns:** `true` if proof is valid

**Example:**
```typescript
const eventHash = keccak256(encodedEvent);
const isValid = await registry.verifyInclusion(
    batchId,
    eventHash,
    merkleProof,
    leafIndex
);
```

---

### verifyMultipleInclusions

Verify multiple events in a single call.

```solidity
function verifyMultipleInclusions(
    bytes32 _batchId,
    bytes32[] calldata _leaves,
    bytes32[][] calldata _proofs,
    uint256[] calldata _indices
) external view returns (bool allValid)
```

**Returns:** `true` if all proofs are valid

---

### commitStarkProof

Submit a STARK proof for compliance verification.

```solidity
function commitStarkProof(
    bytes32 _batchId,
    bytes32 _proofHash,
    bytes32 _prevStateRoot,
    bytes32 _newStateRoot,
    bytes32 _policyHash,
    uint64 _policyLimit,
    bool _allCompliant,
    uint64 _proofSize,
    uint64 _provingTimeMs
) external nonReentrant
```

**Requirements:**
- Caller must be authorized sequencer
- Batch must exist
- State roots must match batch commitment
- No existing STARK proof for batch

**Events:**
```solidity
event StarkProofCommitted(
    bytes32 indexed batchId,
    bytes32 proofHash,
    bytes32 policyHash,
    bool allCompliant,
    uint64 proofSize
);
```

---

### getCommitment

Get batch commitment details.

```solidity
function getCommitment(
    bytes32 _batchId
) external view returns (BatchCommitment memory)
```

---

### getLatestStateRoot

Get current state root for a tenant/store.

```solidity
function getLatestStateRoot(
    bytes32 _tenantId,
    bytes32 _storeId
) external view returns (bytes32 stateRoot)
```

---

### getHeadSequence

Get latest sequence number for a tenant/store.

```solidity
function getHeadSequence(
    bytes32 _tenantId,
    bytes32 _storeId
) external view returns (uint64 sequence)
```

---

### Admin Functions

#### setSequencerAuthorization

```solidity
function setSequencerAuthorization(
    address _sequencer,
    bool _authorized
) external onlyOwner
```

Authorize or revoke a sequencer address.

#### setStrictMode

```solidity
function setStrictMode(bool _enabled) external onlyOwner
```

Enable/disable state root continuity enforcement.

## Events

```solidity
event BatchCommitted(
    bytes32 indexed batchId,
    bytes32 indexed tenantId,
    bytes32 indexed storeId,
    bytes32 eventsRoot,
    bytes32 prevStateRoot,
    bytes32 newStateRoot,
    uint64 sequenceStart,
    uint64 sequenceEnd,
    uint32 eventCount
);

event StarkProofCommitted(
    bytes32 indexed batchId,
    bytes32 proofHash,
    bytes32 policyHash,
    bool allCompliant,
    uint64 proofSize
);

event SequencerAuthorized(
    address indexed sequencer,
    bool authorized
);

event StrictModeChanged(bool enabled);
```

## Errors

```solidity
error NotAuthorizedSequencer();
error BatchAlreadyCommitted();
error BatchNotCommitted();
error InvalidSequenceRange();
error StateRootMismatch();
error StarkProofAlreadyCommitted();
error StateRootMismatchInProof();
error InvalidProof();
```

## Usage Examples

### Commit a Batch

```typescript
import { ethers } from "ethers";

const registry = new ethers.Contract(registryAddress, registryABI, signer);

// Prepare batch data
const batchId = ethers.id("batch-2024-01-15-001");
const tenantId = ethers.id("tenant-acme");
const storeId = ethers.id("store-main");
const eventsRoot = computeMerkleRoot(events);
const prevStateRoot = await registry.getLatestStateRoot(tenantId, storeId);
const newStateRoot = computeNewStateRoot(prevStateRoot, events);

// Commit batch
const tx = await registry.commitBatch(
    batchId,
    tenantId,
    storeId,
    eventsRoot,
    prevStateRoot,
    newStateRoot,
    1001n,
    1100n,
    100
);

const receipt = await tx.wait();
console.log("Batch committed:", receipt.hash);
```

### Verify Event Inclusion

```typescript
// Event to verify
const event = {
    type: "OrderCreated",
    id: "ord_123",
    timestamp: 1705334400,
    data: { amount: 100, currency: "USD" }
};

// Compute event hash
const eventHash = ethers.keccak256(
    ethers.AbiCoder.defaultAbiCoder().encode(
        ["string", "string", "uint256", "bytes"],
        [event.type, event.id, event.timestamp, ethers.toUtf8Bytes(JSON.stringify(event.data))]
    )
);

// Get proof from sequencer API
const { proof, index } = await fetch(`${SEQUENCER_URL}/v1/proofs/${event.id}`).then(r => r.json());

// Verify on-chain
const isValid = await registry.verifyInclusion(batchId, eventHash, proof, index);
console.log("Event verified:", isValid);
```

### Query State

```typescript
// Get current state
const stateRoot = await registry.getLatestStateRoot(tenantId, storeId);
const headSeq = await registry.getHeadSequence(tenantId, storeId);

console.log("Current state root:", stateRoot);
console.log("Head sequence:", headSeq);

// Get batch details
const batch = await registry.getCommitment(batchId);
console.log("Batch events:", batch.eventCount);
console.log("Batch timestamp:", new Date(Number(batch.timestamp) * 1000));
```

## Security Considerations

### Access Control

- Only authorized sequencers can commit batches
- Owner can authorize/revoke sequencers
- Upgrades protected by timelock

### Data Integrity

- Merkle proofs ensure event inclusion
- State root chaining ensures continuity (strict mode)
- STARK proofs provide compliance attestation

### Attack Vectors

| Attack | Mitigation |
|--------|------------|
| Unauthorized commitment | `authorizedSequencers` mapping |
| Duplicate batch | Check `commitments[batchId].timestamp != 0` |
| State manipulation | Strict mode requires chained roots |
| Proof forgery | Cryptographic Merkle verification |

## Gas Costs

| Operation | Approximate Gas |
|-----------|-----------------|
| `commitBatch` | ~150,000 |
| `verifyInclusion` | ~30,000 |
| `commitStarkProof` | ~100,000 |

## Related

- [VES Anchoring System](../architecture/ves-anchoring.md)
- [Anchor Service](../operations/deployment.md#anchor-service)
- [STARK Proofs](#stark-proofs)
