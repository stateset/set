# MEV Protection Contracts

Complete API reference for the MEV protection system contracts.

## Contract Overview

| Contract | Purpose | Status |
|----------|---------|--------|
| [EncryptedMempool](#encryptedmempool) | Threshold-encrypted transaction submission | Ready |
| [ThresholdKeyRegistry](#thresholdkeyregistry) | Keyper network management | Ready |
| [SequencerAttestation](#sequencerattestation) | Ordering commitment proofs | Active |
| [ForcedInclusion](#forcedinclusion) | L1 censorship resistance | Ready |

---

## EncryptedMempool

Manages submission and execution of threshold-encrypted transactions.

### Interface

```solidity
interface IEncryptedMempool {
    // Events
    event TransactionSubmitted(
        bytes32 indexed txId,
        address indexed sender,
        bytes encryptedPayload,
        uint256 gasLimit,
        uint256 submitBlock
    );
    event TransactionDecrypted(
        bytes32 indexed txId,
        address target,
        bytes data,
        uint256 value
    );
    event TransactionExecuted(
        bytes32 indexed txId,
        bool success,
        bytes returnData
    );
    event DecryptionKeyReleased(
        uint256 indexed blockNumber,
        bytes32 keyShare,
        address indexed keyper
    );

    // Submit encrypted transaction
    function submit(
        bytes calldata encryptedPayload,
        uint256 gasLimit
    ) external payable returns (bytes32 txId);

    // Decrypt after ordering committed
    function decrypt(
        bytes32 txId,
        bytes[] calldata keyShares
    ) external;

    // Execute decrypted transaction
    function execute(bytes32 txId) external returns (bool success, bytes memory returnData);

    // Batch operations
    function decryptAndExecuteBatch(
        bytes32[] calldata txIds,
        bytes[][] calldata keyShareSets
    ) external returns (bool[] memory successes);

    // Queries
    function getTransaction(bytes32 txId) external view returns (EncryptedTx memory);
    function getTransactionState(bytes32 txId) external view returns (TxState);
    function getPendingCount() external view returns (uint256);
    function getDecryptionThreshold() external view returns (uint256);
}

struct EncryptedTx {
    bytes32 txId;
    address sender;
    bytes encryptedPayload;
    uint256 gasLimit;
    uint256 value;
    uint256 submitBlock;
    uint256 orderingBlock;
    TxState state;
    // Decrypted fields (populated after decryption)
    address target;
    bytes data;
}

enum TxState {
    PENDING,      // Submitted, awaiting ordering
    ORDERED,      // Ordering committed
    DECRYPTED,    // Decrypted, ready for execution
    EXECUTED,     // Successfully executed
    FAILED,       // Execution failed
    EXPIRED       // Not executed within timeout
}
```

### Key Functions

#### submit

```solidity
function submit(
    bytes calldata encryptedPayload,
    uint256 gasLimit
) external payable returns (bytes32 txId);
```

Submit an encrypted transaction.

**Parameters:**
- `encryptedPayload`: Transaction encrypted with threshold public key
- `gasLimit`: Maximum gas for execution

**Requirements:**
- `msg.value` covers gas cost
- Encryption uses current epoch's public key

**Example:**
```typescript
import { encrypt } from "@setchain/mev-client";

// Get current threshold public key
const publicKey = await keyRegistry.getCurrentPublicKey();

// Encrypt transaction
const payload = {
    target: ssUSDAddress,
    data: ssUSD.interface.encodeFunctionData("transfer", [recipient, amount]),
    value: 0n
};

const encrypted = await encrypt(payload, publicKey);

// Submit
const tx = await encryptedMempool.submit(encrypted, 200000n, {
    value: parseEther("0.01")
});
const receipt = await tx.wait();
const txId = receipt.logs[0].args.txId;
```

#### decrypt

```solidity
function decrypt(
    bytes32 txId,
    bytes[] calldata keyShares
) external;
```

Decrypt a transaction after ordering is committed.

**Parameters:**
- `txId`: Transaction ID
- `keyShares`: Threshold decryption key shares from keypers

**Requirements:**
- Transaction must be in ORDERED state
- Sufficient key shares (threshold)
- Key shares must be valid

**Example:**
```typescript
// Collect key shares from keypers
const keyShares = await collectKeyShares(txId);

// Decrypt
await encryptedMempool.decrypt(txId, keyShares);
```

#### execute

```solidity
function execute(bytes32 txId) external returns (bool success, bytes memory returnData);
```

Execute a decrypted transaction.

**Parameters:**
- `txId`: Transaction ID

**Returns:**
- `success`: Whether execution succeeded
- `returnData`: Return data from call

**Requirements:**
- Transaction must be in DECRYPTED state
- Within execution window

**Example:**
```typescript
const [success, returnData] = await encryptedMempool.execute.staticCall(txId);

if (success) {
    await encryptedMempool.execute(txId);
    console.log("Transaction executed successfully");
} else {
    console.error("Would fail:", returnData);
}
```

---

## ThresholdKeyRegistry

Manages the keyper network and distributed key generation.

### Interface

```solidity
interface IThresholdKeyRegistry {
    // Events
    event KeyperRegistered(address indexed keyper, bytes publicKeyShare);
    event KeyperRemoved(address indexed keyper);
    event DKGInitiated(uint256 indexed epoch, uint256 deadline);
    event DKGCompleted(uint256 indexed epoch, bytes aggregatePublicKey);
    event KeyShareSubmitted(uint256 indexed epoch, address indexed keyper);

    // Keyper Management
    function registerKeyper(bytes calldata publicKeyShare) external;
    function removeKeyper(address keyper) external;
    function isKeyper(address account) external view returns (bool);
    function getKeypers() external view returns (address[] memory);
    function keyperCount() external view returns (uint256);

    // DKG (Distributed Key Generation)
    function initiateDKG() external returns (uint256 epoch);
    function submitKeyShare(uint256 epoch, bytes calldata share) external;
    function finalizeDKG(uint256 epoch) external;
    function getCurrentEpoch() external view returns (uint256);
    function getDKGState(uint256 epoch) external view returns (DKGState);

    // Keys
    function getCurrentPublicKey() external view returns (bytes memory);
    function getPublicKey(uint256 epoch) external view returns (bytes memory);
    function getThreshold() external view returns (uint256);

    // Configuration
    function setThreshold(uint256 newThreshold) external;
    function setDKGDeadline(uint256 blocks) external;
}

enum DKGState {
    INACTIVE,
    INITIATED,
    SHARES_SUBMITTED,
    FINALIZED,
    FAILED
}
```

### Key Functions

#### getCurrentPublicKey

```solidity
function getCurrentPublicKey() external view returns (bytes memory);
```

Get the current aggregate public key for encryption.

**Returns:** BLS public key bytes

**Example:**
```typescript
const publicKey = await keyRegistry.getCurrentPublicKey();
// Use for encrypting transactions
```

#### getThreshold

```solidity
function getThreshold() external view returns (uint256);
```

Get the number of key shares required for decryption.

**Returns:** Threshold (e.g., 3 for 3-of-5)

**Example:**
```typescript
const threshold = await keyRegistry.getThreshold();
const keyperCount = await keyRegistry.keyperCount();
console.log(`Threshold: ${threshold} of ${keyperCount}`);
```

#### initiateDKG

```solidity
function initiateDKG() external returns (uint256 epoch);
```

Start a new distributed key generation ceremony.

**Returns:** New epoch number

**Requirements:**
- Caller must have DKG_INITIATOR_ROLE
- No DKG currently in progress

---

## SequencerAttestation

Records and verifies sequencer ordering commitments.

### Interface

```solidity
interface ISequencerAttestation {
    // Events
    event OrderingCommitted(
        uint256 indexed blockNumber,
        bytes32 txOrderingRoot,
        uint32 txCount,
        bytes signature
    );
    event AttestationVerified(
        uint256 indexed blockNumber,
        bytes32 txOrderingRoot,
        bool valid
    );
    event SequencerUpdated(address indexed oldSequencer, address indexed newSequencer);

    // Commit ordering
    function commitOrdering(
        uint256 blockNumber,
        bytes32 txOrderingRoot,
        uint32 txCount,
        bytes calldata signature
    ) external;

    // Verify
    function verifyOrdering(
        uint256 blockNumber,
        bytes32[] calldata txHashes,
        uint256[] calldata positions
    ) external view returns (bool);

    function getOrderingCommitment(uint256 blockNumber)
        external view returns (OrderingCommitment memory);

    // Queries
    function sequencer() external view returns (address);
    function getLatestCommitment() external view returns (OrderingCommitment memory);
    function hasCommitment(uint256 blockNumber) external view returns (bool);

    // Admin
    function setSequencer(address newSequencer) external;
}

struct OrderingCommitment {
    uint256 blockNumber;
    bytes32 txOrderingRoot;  // Merkle root of tx order
    uint32 txCount;
    uint256 timestamp;
    bytes signature;
    bool verified;
}
```

### Key Functions

#### commitOrdering

```solidity
function commitOrdering(
    uint256 blockNumber,
    bytes32 txOrderingRoot,
    uint32 txCount,
    bytes calldata signature
) external;
```

Commit transaction ordering for a block.

**Parameters:**
- `blockNumber`: L2 block number
- `txOrderingRoot`: Merkle root of ordered transaction hashes
- `txCount`: Number of transactions
- `signature`: Sequencer's signature

**Requirements:**
- Caller is authorized submitter
- Block number is sequential
- Signature is valid

**Example:**
```typescript
// Sequencer commits ordering
await attestation.commitOrdering(
    blockNumber,
    txOrderingRoot,
    txCount,
    signature
);
```

#### verifyOrdering

```solidity
function verifyOrdering(
    uint256 blockNumber,
    bytes32[] calldata txHashes,
    uint256[] calldata positions
) external view returns (bool);
```

Verify that transactions were ordered as committed.

**Parameters:**
- `blockNumber`: Block to verify
- `txHashes`: Transaction hashes
- `positions`: Expected positions in ordering

**Returns:** `true` if ordering matches commitment

**Example:**
```typescript
const valid = await attestation.verifyOrdering(
    blockNumber,
    [txHash1, txHash2],
    [0, 1]
);

if (!valid) {
    console.error("Ordering mismatch - sequencer may have reordered!");
}
```

---

## ForcedInclusion

Enables users to force transaction inclusion via L1.

### Interface

```solidity
interface IForcedInclusion {
    // Events
    event TransactionForced(
        bytes32 indexed txId,
        address indexed sender,
        address target,
        bytes data,
        uint256 gasLimit,
        uint256 deadline
    );
    event TransactionIncluded(bytes32 indexed txId, uint256 l2BlockNumber);
    event TransactionExpired(bytes32 indexed txId);
    event BondClaimed(bytes32 indexed txId, address indexed claimer, uint256 amount);

    // Force transaction (called on L1)
    function forceTransaction(
        address target,
        bytes calldata data,
        uint256 gasLimit
    ) external payable returns (bytes32 txId);

    // Prove inclusion (called after inclusion)
    function proveInclusion(
        bytes32 txId,
        uint256 l2BlockNumber,
        bytes calldata inclusionProof
    ) external;

    // Claim expired (called if not included)
    function claimExpired(bytes32 txId) external returns (uint256 bondAmount);

    // Queries
    function getForceRequest(bytes32 txId) external view returns (ForceRequest memory);
    function getStatus(bytes32 txId) external view returns (ForceStatus);
    function getBondAmount() external view returns (uint256);
    function getInclusionDeadline() external view returns (uint256);
    function isExpired(bytes32 txId) external view returns (bool);

    // Configuration
    function setBondAmount(uint256 newBond) external;
    function setInclusionDeadline(uint256 newDeadline) external;
}

struct ForceRequest {
    bytes32 txId;
    address sender;
    address target;
    bytes data;
    uint256 gasLimit;
    uint256 bond;
    uint256 deadline;
    ForceStatus status;
    uint256 l2BlockNumber;  // Set after inclusion
}

enum ForceStatus {
    PENDING,    // Waiting for inclusion
    INCLUDED,   // Included on L2
    EXPIRED,    // Deadline passed without inclusion
    CLAIMED     // Bond claimed after expiry
}
```

### Key Functions

#### forceTransaction

```solidity
function forceTransaction(
    address target,
    bytes calldata data,
    uint256 gasLimit
) external payable returns (bytes32 txId);
```

Force a transaction via L1 (called on Ethereum mainnet/Sepolia).

**Parameters:**
- `target`: Target contract on L2
- `data`: Calldata for L2 call
- `gasLimit`: Gas limit for L2 execution

**Requirements:**
- `msg.value >= bondAmount` (typically 0.01 ETH)
- Valid target address

**Example:**
```typescript
// On L1 - force a transfer that sequencer is censoring
const tx = await forcedInclusion.forceTransaction(
    ssUSDAddress,  // L2 address
    ssUSD.interface.encodeFunctionData("transfer", [recipient, amount]),
    100000n,
    { value: parseEther("0.01") }  // Bond
);

const receipt = await tx.wait();
const txId = receipt.logs[0].args.txId;
console.log(`Forced tx: ${txId}`);
console.log("Must be included within 24 hours");
```

#### proveInclusion

```solidity
function proveInclusion(
    bytes32 txId,
    uint256 l2BlockNumber,
    bytes calldata inclusionProof
) external;
```

Prove that a forced transaction was included on L2.

**Parameters:**
- `txId`: Force request transaction ID
- `l2BlockNumber`: L2 block where included
- `inclusionProof`: Merkle proof of inclusion

**Example:**
```typescript
// After inclusion on L2, prove it on L1 to get bond back
await forcedInclusion.proveInclusion(
    txId,
    l2BlockNumber,
    inclusionProof
);
```

#### claimExpired

```solidity
function claimExpired(bytes32 txId) external returns (uint256 bondAmount);
```

Claim bond + penalty if sequencer failed to include.

**Parameters:**
- `txId`: Expired force request ID

**Returns:** Total amount claimed (bond + penalty)

**Requirements:**
- Deadline must have passed
- Transaction not included

**Example:**
```typescript
// If sequencer censored and deadline passed
if (await forcedInclusion.isExpired(txId)) {
    const claimed = await forcedInclusion.claimExpired(txId);
    console.log(`Claimed: ${formatEther(claimed)} ETH`);
    // Includes original bond + penalty from sequencer
}
```

### Forced Inclusion Flow

```
L1 (Ethereum)                    L2 (Set Chain)
     │                                │
     │  forceTransaction()            │
     ├────────────────────────────────┤
     │  Bond deposited                │
     │  L1→L2 message queued          │
     │                                │
     │      24 hour deadline          │
     │         starts                 │
     │                                │
     │                                │ Sequencer MUST
     │                                │ include tx
     │                                │
     │                    ┌───────────┤
     │                    │ Transaction│
     │                    │ executed   │
     │                    └───────────┤
     │                                │
     │  proveInclusion()              │
     ├────────────────────────────────┤
     │  Bond returned                 │
     │                                │

     --- OR if censored ---

     │                                │
     │  claimExpired()                │
     ├────────────────────────────────┤
     │  Bond + penalty                │
     │  returned to user              │
```

---

## Security Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Encryption Threshold | 3-of-5 | Key shares needed for decryption |
| Inclusion Deadline | 24 hours | Time to include forced tx |
| Bond Amount | 0.01 ETH | Required for force requests |
| Censorship Penalty | 0.1 ETH | Paid by sequencer if censoring |
| DKG Deadline | 100 blocks | Time to complete key generation |

---

## Error Codes

| Contract | Error | Description |
|----------|-------|-------------|
| EncryptedMempool | `InvalidEncryption()` | Payload not properly encrypted |
| EncryptedMempool | `NotOrdered()` | Transaction not yet ordered |
| EncryptedMempool | `AlreadyDecrypted()` | Transaction already decrypted |
| EncryptedMempool | `AlreadyExecuted()` | Transaction already executed |
| EncryptedMempool | `ExecutionExpired()` | Execution window passed |
| ThresholdKeyRegistry | `NotKeyper()` | Caller is not a keyper |
| ThresholdKeyRegistry | `DKGInProgress()` | DKG already in progress |
| ThresholdKeyRegistry | `InvalidKeyShare()` | Key share validation failed |
| SequencerAttestation | `InvalidSignature()` | Sequencer signature invalid |
| SequencerAttestation | `BlockAlreadyCommitted()` | Ordering already committed |
| ForcedInclusion | `InsufficientBond()` | Bond below required amount |
| ForcedInclusion | `NotExpired()` | Deadline not yet passed |
| ForcedInclusion | `AlreadyClaimed()` | Bond already claimed |
| ForcedInclusion | `AlreadyIncluded()` | Transaction was included |

---

## Related

- [MEV Protection Overview](../mev/overview.md)
- [Encrypted Mempool Guide](../mev/encrypted-mempool.md)
- [Threshold Keys](../mev/threshold-keys.md)
- [Forced Inclusion Guide](../mev/forced-inclusion.md)
