# Encrypted Mempool

Deep dive into Set Chain's encrypted transaction system.

## Overview

The encrypted mempool prevents MEV extraction by hiding transaction contents until ordering is committed:

```
Traditional Mempool:          Set Chain Encrypted Mempool:
┌─────────────────┐           ┌─────────────────┐
│ Tx visible to   │           │ Tx encrypted    │
│ everyone        │           │ until ordered   │
│                 │           │                 │
│ → Frontrunning  │           │ → No frontrun   │
│ → Sandwich      │           │ → No sandwich   │
│ → Reordering    │           │ → Fair ordering │
└─────────────────┘           └─────────────────┘
```

## How It Works

### Transaction Lifecycle

```
┌──────────────────────────────────────────────────────────────┐
│                  Encrypted Transaction Flow                   │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  1. ENCRYPT                    2. SUBMIT                      │
│  ┌─────────────┐              ┌─────────────┐                │
│  │ User creates│              │ Encrypted   │                │
│  │ transaction │─────────────▶│ payload     │                │
│  │ + encrypts  │              │ on-chain    │                │
│  └─────────────┘              └──────┬──────┘                │
│                                      │                        │
│  3. ORDER                     4. COMMIT                       │
│  ┌─────────────┐              ┌─────────────┐                │
│  │ Sequencer   │              │ Ordering    │                │
│  │ orders txs  │◀─────────────│ commitment  │                │
│  │ (blind)     │              │ published   │                │
│  └─────────────┘              └──────┬──────┘                │
│                                      │                        │
│  5. DECRYPT                   6. EXECUTE                      │
│  ┌─────────────┐              ┌─────────────┐                │
│  │ Keypers     │              │ Transaction │                │
│  │ release     │─────────────▶│ executed in │                │
│  │ key shares  │              │ committed   │                │
│  └─────────────┘              │ order       │                │
│                               └─────────────┘                │
└──────────────────────────────────────────────────────────────┘
```

## Encryption

### Threshold Encryption Scheme

Set Chain uses threshold encryption where:
- Anyone can encrypt with the public key
- Decryption requires k-of-n keyper shares (e.g., 3-of-5)

```typescript
import { encrypt } from "@setchain/mev-client";

// Get current threshold public key
const publicKey = await keyRegistry.getCurrentPublicKey();

// Encrypt transaction
const payload = {
    target: routerAddress,
    data: router.interface.encodeFunctionData("swap", [
        tokenIn,
        tokenOut,
        amountIn,
        minAmountOut,
        deadline
    ]),
    value: 0n
};

const encrypted = await encrypt(payload, publicKey);
// encrypted.ciphertext contains the encrypted payload
// encrypted.ephemeralPublicKey for decryption
```

### Encryption Algorithm

```
1. Generate ephemeral keypair (sender)
2. Derive shared secret: ECDH(ephemeral_private, threshold_public)
3. Derive encryption key: KDF(shared_secret)
4. Encrypt payload: AES-GCM(key, payload)
5. Output: (ephemeral_public, ciphertext, nonce, tag)
```

### Security Properties

- **Confidentiality**: Transaction contents hidden from everyone
- **Binding**: Cannot change transaction after encryption
- **Non-malleability**: Cannot modify ciphertext without detection

## Submission

### EncryptedMempool Contract

```solidity
function submit(
    bytes calldata encryptedPayload,
    uint256 gasLimit
) external payable returns (bytes32 txId) {
    // Generate unique transaction ID
    txId = keccak256(abi.encode(
        msg.sender,
        encryptedPayload,
        block.number,
        nonces[msg.sender]++
    ));

    // Store encrypted transaction
    transactions[txId] = EncryptedTx({
        txId: txId,
        sender: msg.sender,
        encryptedPayload: encryptedPayload,
        gasLimit: gasLimit,
        value: msg.value,
        submitBlock: block.number,
        orderingBlock: 0,
        state: TxState.PENDING,
        target: address(0),
        data: ""
    });

    emit TransactionSubmitted(
        txId,
        msg.sender,
        encryptedPayload,
        gasLimit,
        block.number
    );
}
```

### Gas Payment

Users pay gas upfront when submitting:

```typescript
// Estimate gas cost
const gasPrice = await provider.getGasPrice();
const estimatedCost = gasLimit * gasPrice;

// Submit with gas payment
const tx = await encryptedMempool.submit(encrypted, gasLimit, {
    value: estimatedCost * 120n / 100n  // 20% buffer
});
```

## Ordering

### Blind Ordering

The sequencer orders transactions without seeing contents:

```
Sequencer sees:
- Transaction ID (hash)
- Sender address
- Gas limit
- Submission time

Sequencer CANNOT see:
- Target contract
- Function being called
- Parameters
- Value being transferred
```

### Ordering Commitment

Sequencer commits to ordering before decryption:

```solidity
// In SequencerAttestation contract
function commitOrdering(
    uint256 blockNumber,
    bytes32 txOrderingRoot,  // Merkle root of ordered tx IDs
    uint32 txCount,
    bytes calldata signature
) external {
    // Verify sequencer signature
    require(
        _verifySequencerSignature(blockNumber, txOrderingRoot, txCount, signature),
        "InvalidSignature"
    );

    // Store commitment
    commitments[blockNumber] = OrderingCommitment({
        blockNumber: blockNumber,
        txOrderingRoot: txOrderingRoot,
        txCount: txCount,
        timestamp: block.timestamp,
        signature: signature,
        verified: false
    });

    emit OrderingCommitted(blockNumber, txOrderingRoot, txCount, signature);

    // Mark transactions as ordered
    _markTransactionsOrdered(blockNumber, txOrderingRoot);
}
```

## Decryption

### Key Share Release

After ordering is committed, keypers release decryption shares:

```solidity
// Keyper releases their share
function releaseKeyShare(
    uint256 blockNumber,
    bytes calldata keyShare
) external onlyKeyper {
    require(
        commitments[blockNumber].timestamp > 0,
        "OrderingNotCommitted"
    );

    keyShares[blockNumber][msg.sender] = keyShare;

    emit DecryptionKeyReleased(blockNumber, keccak256(keyShare), msg.sender);
}
```

### Threshold Decryption

Once enough shares are collected:

```typescript
// Collect key shares from keypers
const keyShares = await Promise.all(
    keyperAddresses.map(k => encryptedMempool.getKeyShare(blockNumber, k))
);

// Filter to threshold amount
const validShares = keyShares.filter(s => s.length > 0).slice(0, threshold);

// Decrypt
await encryptedMempool.decrypt(txId, validShares);
```

### Decryption Contract Logic

```solidity
function decrypt(
    bytes32 txId,
    bytes[] calldata keyShares
) external {
    EncryptedTx storage tx = transactions[txId];

    require(tx.state == TxState.ORDERED, "NotOrdered");
    require(keyShares.length >= threshold, "InsufficientShares");

    // Combine key shares to reconstruct decryption key
    bytes memory decryptionKey = _combineKeyShares(keyShares);

    // Decrypt payload
    (address target, bytes memory data, uint256 value) = _decrypt(
        tx.encryptedPayload,
        decryptionKey
    );

    // Store decrypted data
    tx.target = target;
    tx.data = data;
    tx.state = TxState.DECRYPTED;

    emit TransactionDecrypted(txId, target, data, value);
}
```

## Execution

### Execute Decrypted Transaction

```solidity
function execute(bytes32 txId) external returns (bool success, bytes memory returnData) {
    EncryptedTx storage tx = transactions[txId];

    require(tx.state == TxState.DECRYPTED, "NotDecrypted");
    require(block.number <= tx.orderingBlock + executionWindow, "ExecutionExpired");

    // Execute the transaction
    (success, returnData) = tx.target.call{value: tx.value, gas: tx.gasLimit}(tx.data);

    tx.state = success ? TxState.EXECUTED : TxState.FAILED;

    emit TransactionExecuted(txId, success, returnData);

    // Refund unused gas
    _refundExcessGas(tx.sender, tx.gasLimit);
}
```

### Batch Execution

```solidity
function decryptAndExecuteBatch(
    bytes32[] calldata txIds,
    bytes[][] calldata keyShareSets
) external returns (bool[] memory successes) {
    require(txIds.length == keyShareSets.length, "LengthMismatch");

    successes = new bool[](txIds.length);

    for (uint256 i = 0; i < txIds.length; i++) {
        // Decrypt
        decrypt(txIds[i], keyShareSets[i]);

        // Execute
        (bool success, ) = execute(txIds[i]);
        successes[i] = success;
    }
}
```

## SDK Usage

### Complete Flow

```typescript
import { createMEVProtectionClient } from "@setchain/sdk";

const mevClient = createMEVProtectionClient(addresses, wallet);

// 1. Check availability
const status = await mevClient.getStatus();
if (!status.encryptionEnabled) {
    throw new Error("Encryption not available");
}

// 2. Build transaction
const swapData = router.interface.encodeFunctionData("swap", [
    tokenIn,
    tokenOut,
    amountIn,
    minAmountOut,
    deadline
]);

// 3. Submit encrypted
const result = await mevClient.submit(
    routerAddress,
    swapData,
    0n,  // value
    { gasLimit: 300000n }
);

console.log(`Transaction submitted: ${result.txId}`);

// 4. Wait for execution
const execution = await mevClient.waitForExecution(result.txId);

if (execution.success) {
    console.log(`Executed in block ${execution.blockNumber}`);
} else {
    console.error(`Failed: ${execution.error}`);
}
```

### Monitoring Status

```typescript
// Check transaction status
const status = await mevClient.getTransactionStatus(txId);

console.log(`State: ${status.state}`);
// "pending" | "ordered" | "decrypted" | "executed" | "failed" | "expired"

if (status.state === "ordered") {
    console.log(`Ordering block: ${status.orderingBlock}`);
}

if (status.state === "executed") {
    console.log(`Execution block: ${status.executionBlock}`);
}
```

## Security Considerations

### Timing

- Transactions should be executed within the execution window
- Expired transactions are not executed (gas refunded)
- Users should monitor their transactions

### Key Rotation

- Threshold keys rotate periodically (epochs)
- Encrypt transactions for current epoch
- Old epoch keys are destroyed

### Failure Modes

| Failure | Impact | Mitigation |
|---------|--------|------------|
| Keypers offline | Cannot decrypt | Redundant keypers |
| Sequencer censors | Tx not ordered | Forced inclusion |
| Invalid encryption | Tx rejected | Client validation |
| Execution fails | Tx reverts | Standard EVM revert |

## Configuration

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| Threshold | 3 | Key shares needed |
| Keyper count | 5 | Total keypers |
| Execution window | 100 blocks | Blocks to execute after decrypt |
| Min gas limit | 21000 | Minimum gas for submission |
| Max queue size | 10000 | Maximum pending transactions |
| Max submissions/block | 5 | Rate limit per user per block |

## Rate Limiting

The EncryptedMempool includes spam protection:

### Per-User Rate Limiting

```typescript
// Check if user can submit
const { canSubmit, remaining } = await mempool.canUserSubmit(userAddress);

if (!canSubmit) {
    console.log("Rate limited - wait for next block");
    return;
}

console.log(`Can submit ${remaining} more transactions this block`);
```

### Queue Size Limits

```typescript
// Check queue status
const status = await mempool.getMempoolStatus();

console.log(`Pending: ${status.pendingCount}`);
console.log(`Queue capacity: ${status.queueCapacity}`);
console.log(`Is paused: ${status.isPaused}`);
```

### Monitoring Functions

```typescript
// Get transaction status with details
const { status, statusName, blocksUntilExpiry, canExecute } =
    await mempool.getTxStatus(txId);

// Batch status check
const statuses = await mempool.getBatchTxStatuses([txId1, txId2, txId3]);

// Success rate
const successRate = await mempool.getSuccessRate();
console.log(`Success rate: ${successRate / 100}%`);
```

## Related

- [MEV Protection Overview](./overview.md)
- [Threshold Keys](./threshold-keys.md)
- [Forced Inclusion](./forced-inclusion.md)
- [MEV Contracts API](../contracts/mev-contracts.md)
