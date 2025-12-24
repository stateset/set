# MEV Protection Client

Guide to using the MEV protection SDK for frontrunning-resistant transactions.

## Overview

The MEV Protection Client provides:

- Transaction encryption with threshold keys
- Protected transaction submission
- Execution status monitoring
- Forced inclusion via L1

## Creating a Client

```typescript
import { createMEVProtectionClient } from "@setchain/sdk";
import { Wallet, JsonRpcProvider } from "ethers";

const provider = new JsonRpcProvider("https://rpc.testnet.setchain.io");
const wallet = new Wallet(PRIVATE_KEY, provider);

const mevClient = createMEVProtectionClient(
    {
        encryptedMempool: "0x...",
        thresholdKeyRegistry: "0x..."
    },
    wallet
);
```

## Methods

### isAvailable

Check if MEV protection is currently available.

```typescript
async isAvailable(): Promise<boolean>
```

**Example:**
```typescript
if (await mevClient.isAvailable()) {
    // Submit protected transaction
} else {
    // Fall back to standard submission
    console.warn("MEV protection unavailable");
}
```

### getStatus

Get current MEV protection system status.

```typescript
async getStatus(): Promise<MEVStatus>

interface MEVStatus {
    phase: "private" | "attestation" | "encrypted" | "full";
    encryptionEnabled: boolean;
    forcedInclusionEnabled: boolean;
    currentEpoch: bigint;
    keyperCount: number;
    threshold: number;
    publicKey: string | null;
}
```

**Example:**
```typescript
const status = await mevClient.getStatus();

console.log(`Protection Phase: ${status.phase}`);
console.log(`Encryption: ${status.encryptionEnabled ? "Yes" : "No"}`);
console.log(`Keypers: ${status.threshold}/${status.keyperCount}`);
```

### submit

Submit an encrypted transaction for MEV protection.

```typescript
async submit(
    target: string,
    data: string,
    value: bigint,
    options?: SubmitOptions
): Promise<SubmitResult>

interface SubmitOptions {
    gasLimit?: bigint;
    maxFeePerGas?: bigint;
    maxPriorityFeePerGas?: bigint;
}

interface SubmitResult {
    txId: string;           // Encrypted transaction ID
    submitTxHash: string;   // L2 submission tx hash
    encryptedPayload: string;
    estimatedExecutionBlock: bigint;
}
```

**Example:**
```typescript
import { parseEther, parseUnits } from "ethers";

// Encrypt and submit a swap transaction
const swapData = router.interface.encodeFunctionData("swap", [
    tokenIn,
    tokenOut,
    amountIn,
    minAmountOut,
    deadline
]);

const result = await mevClient.submit(
    routerAddress,
    swapData,
    parseEther("0"),
    {
        gasLimit: 300000n,
        maxFeePerGas: parseUnits("10", "gwei")
    }
);

console.log(`Submitted: ${result.txId}`);
console.log(`Expected execution: block ${result.estimatedExecutionBlock}`);
```

### waitForExecution

Wait for an encrypted transaction to be executed.

```typescript
async waitForExecution(
    txId: string,
    options?: WaitOptions
): Promise<ExecutionResult>

interface WaitOptions {
    timeout?: number;       // Timeout in ms (default: 60000)
    pollInterval?: number;  // Poll interval in ms (default: 2000)
}

interface ExecutionResult {
    txId: string;
    success: boolean;
    executionTxHash: string;
    blockNumber: bigint;
    gasUsed: bigint;
    returnData: string;
    error?: string;
}
```

**Example:**
```typescript
const result = await mevClient.waitForExecution(txId, {
    timeout: 120000  // 2 minutes
});

if (result.success) {
    console.log(`Executed in block ${result.blockNumber}`);
    console.log(`Tx: ${result.executionTxHash}`);
    console.log(`Gas used: ${result.gasUsed}`);
} else {
    console.error(`Execution failed: ${result.error}`);
}
```

### getTransactionStatus

Get status of a submitted transaction.

```typescript
async getTransactionStatus(txId: string): Promise<TransactionStatus>

interface TransactionStatus {
    txId: string;
    state: "pending" | "ordered" | "decrypted" | "executed" | "failed" | "expired";
    submitBlock: bigint;
    orderingBlock?: bigint;
    executionBlock?: bigint;
    error?: string;
}
```

**Example:**
```typescript
const status = await mevClient.getTransactionStatus(txId);

switch (status.state) {
    case "pending":
        console.log("Waiting for ordering...");
        break;
    case "ordered":
        console.log("Ordering committed, awaiting decryption...");
        break;
    case "decrypted":
        console.log("Decrypted, awaiting execution...");
        break;
    case "executed":
        console.log(`Executed in block ${status.executionBlock}`);
        break;
    case "failed":
        console.error(`Failed: ${status.error}`);
        break;
    case "expired":
        console.error("Transaction expired without execution");
        break;
}
```

### encrypt

Encrypt transaction data without submitting.

```typescript
async encrypt(payload: TransactionPayload): Promise<EncryptedPayload>

interface TransactionPayload {
    target: string;
    data: string;
    value: bigint;
}

interface EncryptedPayload {
    ciphertext: string;
    ephemeralPublicKey: string;
    epoch: bigint;
}
```

**Example:**
```typescript
// Encrypt for later submission
const encrypted = await mevClient.encrypt({
    target: ssUSDAddress,
    data: ssUSD.interface.encodeFunctionData("transfer", [recipient, amount]),
    value: 0n
});

console.log(`Encrypted for epoch ${encrypted.epoch}`);
// Store encrypted.ciphertext for later...
```

## Forced Inclusion Client

For censorship-resistant transactions via L1.

### Creating the Client

```typescript
import { createForcedInclusionClient } from "@setchain/sdk";
import { JsonRpcProvider, Wallet } from "ethers";

// L1 provider (Ethereum mainnet or Sepolia)
const l1Provider = new JsonRpcProvider("https://eth-sepolia.example.com");
const l1Wallet = new Wallet(PRIVATE_KEY, l1Provider);

const forcedClient = createForcedInclusionClient(
    "0x...", // ForcedInclusion contract on L1
    l1Wallet
);
```

### forceTransaction

Submit a forced transaction via L1.

```typescript
async forceTransaction(
    target: string,
    data: string,
    gasLimit: bigint,
    options?: ForceOptions
): Promise<ForceResult>

interface ForceOptions {
    value?: bigint;  // ETH to send with L2 call (default: 0)
}

interface ForceResult {
    txId: string;
    l1TxHash: string;
    bondAmount: bigint;
    deadline: number;  // Unix timestamp
}
```

**Example:**
```typescript
import { parseEther } from "ethers";

// Force a transfer if sequencer is censoring
const result = await forcedClient.forceTransaction(
    ssUSDAddress,  // L2 target
    ssUSD.interface.encodeFunctionData("transfer", [recipient, amount]),
    100000n,       // L2 gas limit
    { value: parseEther("0.01") }  // Bond
);

console.log(`Forced tx submitted: ${result.txId}`);
console.log(`L1 tx: ${result.l1TxHash}`);
console.log(`Bond: ${formatEther(result.bondAmount)} ETH`);
console.log(`Deadline: ${new Date(result.deadline * 1000)}`);
```

### getStatus

Check forced transaction status.

```typescript
async getStatus(txId: string): Promise<ForceStatus>

interface ForceStatus {
    txId: string;
    state: "pending" | "included" | "expired" | "claimed";
    l2BlockNumber?: bigint;
    deadline: number;
    bondAmount: bigint;
}
```

**Example:**
```typescript
const status = await forcedClient.getStatus(txId);

if (status.state === "included") {
    console.log(`Included at L2 block ${status.l2BlockNumber}`);
} else if (status.state === "expired") {
    console.log("Sequencer failed to include - can claim bond + penalty");
}
```

### claimExpired

Claim bond + penalty for expired forced transaction.

```typescript
async claimExpired(txId: string): Promise<ClaimResult>

interface ClaimResult {
    l1TxHash: string;
    amountClaimed: bigint;  // Bond + penalty
}
```

**Example:**
```typescript
const status = await forcedClient.getStatus(txId);

if (status.state === "expired") {
    const claim = await forcedClient.claimExpired(txId);
    console.log(`Claimed: ${formatEther(claim.amountClaimed)} ETH`);
}
```

### proveInclusion

Prove forced transaction was included (to recover bond).

```typescript
async proveInclusion(
    txId: string,
    l2BlockNumber: bigint,
    inclusionProof: string
): Promise<string>  // L1 tx hash
```

## Complete Example

```typescript
import {
    createMEVProtectionClient,
    createForcedInclusionClient
} from "@setchain/sdk";
import { parseEther, parseUnits, formatEther } from "ethers";

async function protectedSwap(
    router: Contract,
    tokenIn: string,
    tokenOut: string,
    amountIn: bigint,
    minAmountOut: bigint
) {
    const mev = createMEVProtectionClient(mevAddresses, wallet);

    // Check MEV protection availability
    const status = await mev.getStatus();
    console.log(`MEV Protection: ${status.phase}`);

    if (!status.encryptionEnabled) {
        console.warn("Encryption not enabled, falling back to standard tx");
        return router.swap(tokenIn, tokenOut, amountIn, minAmountOut, deadline);
    }

    // Build swap calldata
    const deadline = Math.floor(Date.now() / 1000) + 300; // 5 minutes
    const swapData = router.interface.encodeFunctionData("swap", [
        tokenIn,
        tokenOut,
        amountIn,
        minAmountOut,
        deadline
    ]);

    // Submit encrypted
    console.log("Submitting encrypted transaction...");
    const submitResult = await mev.submit(
        router.target,
        swapData,
        0n,
        { gasLimit: 300000n }
    );

    console.log(`Submitted: ${submitResult.txId}`);
    console.log("Waiting for execution...");

    // Wait for execution
    const execResult = await mev.waitForExecution(submitResult.txId, {
        timeout: 120000
    });

    if (execResult.success) {
        console.log("Swap executed successfully!");
        console.log(`Block: ${execResult.blockNumber}`);
        console.log(`Gas: ${execResult.gasUsed}`);
        return execResult;
    } else {
        throw new Error(`Swap failed: ${execResult.error}`);
    }
}

// With forced inclusion fallback
async function protectedSwapWithFallback(
    router: Contract,
    tokenIn: string,
    tokenOut: string,
    amountIn: bigint,
    minAmountOut: bigint
) {
    const mev = createMEVProtectionClient(mevAddresses, l2Wallet);
    const forced = createForcedInclusionClient(forcedAddress, l1Wallet);

    try {
        // Try normal encrypted submission
        return await protectedSwap(router, tokenIn, tokenOut, amountIn, minAmountOut);
    } catch (error) {
        console.error("Normal submission failed, trying forced inclusion...");

        // Build calldata
        const deadline = Math.floor(Date.now() / 1000) + 86400; // 24 hours
        const swapData = router.interface.encodeFunctionData("swap", [
            tokenIn,
            tokenOut,
            amountIn,
            minAmountOut,
            deadline
        ]);

        // Force via L1
        const forceResult = await forced.forceTransaction(
            router.target,
            swapData,
            300000n,
            { value: parseEther("0.01") }
        );

        console.log(`Forced submission: ${forceResult.txId}`);
        console.log(`Must be included by: ${new Date(forceResult.deadline * 1000)}`);

        // Poll for inclusion
        while (true) {
            await sleep(60000); // Check every minute

            const status = await forced.getStatus(forceResult.txId);

            if (status.state === "included") {
                console.log("Transaction included!");
                return status;
            }

            if (status.state === "expired") {
                const claim = await forced.claimExpired(forceResult.txId);
                console.log(`Sequencer censored! Claimed ${formatEther(claim.amountClaimed)} ETH`);
                throw new Error("Sequencer censorship detected");
            }

            console.log("Still waiting for inclusion...");
        }
    }
}

function sleep(ms: number) {
    return new Promise(resolve => setTimeout(resolve, ms));
}
```

## Error Handling

```typescript
import {
    isSDKError,
    MEVUnavailableError,
    EncryptionFailedError,
    TransactionExpiredError
} from "@setchain/sdk";

try {
    await mevClient.submit(target, data, value);
} catch (error) {
    if (isSDKError(error)) {
        if (error instanceof MEVUnavailableError) {
            console.error("MEV protection not available");
            // Fall back to standard transaction
        } else if (error instanceof EncryptionFailedError) {
            console.error("Encryption failed - key may have rotated");
        } else if (error instanceof TransactionExpiredError) {
            console.error("Transaction expired before execution");
        }
    }
    throw error;
}
```

## Security Considerations

### Key Rotation

Threshold keys rotate periodically. Encrypted transactions must be submitted and executed within the same epoch:

```typescript
const status = await mevClient.getStatus();
console.log(`Current epoch: ${status.currentEpoch}`);

// Encrypt and submit quickly to avoid epoch change
const result = await mevClient.submit(target, data, value);
```

### Bond Requirements

Forced inclusion requires a bond:
- Standard bond: 0.01 ETH
- Returned if transaction included
- Returned with penalty if sequencer censors

### Gas Estimation

Encrypted transactions require slightly more gas:
- ~50% overhead for encryption/decryption
- Consider this when setting gas limits

## Related

- [MEV Protection Overview](../mev/overview.md)
- [Encrypted Mempool](../mev/encrypted-mempool.md)
- [Forced Inclusion](../mev/forced-inclusion.md)
- [MEV Contracts](../contracts/mev-contracts.md)
