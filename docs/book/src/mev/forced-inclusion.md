# Forced Inclusion

Censorship resistance through L1-based transaction forcing.

## Overview

Forced inclusion ensures users can always get their transactions included on Set Chain, even if the sequencer attempts censorship:

```
Normal Path:                    Forced Inclusion Path:
┌─────────────┐                 ┌─────────────┐
│ User → L2   │                 │ User → L1   │
│ Sequencer   │                 │ → L2        │
│ includes tx │                 │ Sequencer   │
│             │                 │ MUST include│
└─────────────┘                 └─────────────┘
```

## When to Use

### Use Forced Inclusion When:

- Sequencer is not responding
- Your transactions are being censored
- Urgent transaction needed
- Testing censorship resistance

### Don't Use When:

- Normal transactions work fine
- Cost-sensitive (forced inclusion costs more)
- Time-sensitive (24-hour deadline)

## How It Works

### Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                   Forced Inclusion Flow                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  L1 (Ethereum)                        L2 (Set Chain)            │
│  ┌────────────────┐                   ┌────────────────┐        │
│  │ 1. User calls  │                   │                │        │
│  │ forceTransaction│                   │                │        │
│  │ + deposits bond│                   │                │        │
│  └───────┬────────┘                   │                │        │
│          │                            │                │        │
│          ▼                            │                │        │
│  ┌────────────────┐                   │                │        │
│  │ 2. L1 contract │                   │                │        │
│  │ queues message │──────────────────▶│ 3. L1→L2      │        │
│  │ to L2          │                   │    message    │        │
│  └────────────────┘                   │    received   │        │
│                                       │                │        │
│                                       └───────┬────────┘        │
│                                               │                  │
│                                               ▼                  │
│                                       ┌────────────────┐        │
│                                       │ 4. Sequencer   │        │
│                                       │ MUST include   │        │
│                                       │ within 24h     │        │
│                                       └───────┬────────┘        │
│                                               │                  │
│                       ┌───────────────────────┼──────────────┐  │
│                       │                       │              │  │
│                       ▼                       ▼              │  │
│               ┌──────────────┐       ┌──────────────┐       │  │
│               │ INCLUDED     │       │ NOT INCLUDED │       │  │
│               │              │       │ (EXPIRED)    │       │  │
│               │ 5a. Prove    │       │              │       │  │
│               │ inclusion    │       │ 5b. Claim    │       │  │
│               │ → bond back  │       │ bond + penalty│       │  │
│               └──────────────┘       └──────────────┘       │  │
│                                                              │  │
└─────────────────────────────────────────────────────────────────┘
```

## Using Forced Inclusion

### Step 1: Submit Force Request

On Ethereum L1:

```typescript
import { Contract, parseEther } from "ethers";

const forcedInclusion = new Contract(
    FORCED_INCLUSION_ADDRESS,  // L1 contract
    ForcedInclusionABI,
    l1Signer
);

// Build the L2 transaction
const l2Target = ssUSDAddress;  // Contract on L2
const l2Data = ssUSD.interface.encodeFunctionData("transfer", [
    recipientAddress,
    parseUnits("100", 18)
]);
const l2GasLimit = 100000n;

// Get required bond
const bondAmount = await forcedInclusion.getBondAmount();
console.log(`Required bond: ${formatEther(bondAmount)} ETH`);

// Force the transaction
const tx = await forcedInclusion.forceTransaction(
    l2Target,
    l2Data,
    l2GasLimit,
    { value: bondAmount }
);

const receipt = await tx.wait();
const event = receipt.logs.find(l =>
    l.topics[0] === forcedInclusion.interface.getEventTopic("TransactionForced")
);
const { txId, deadline } = forcedInclusion.interface.decodeEventLog(
    "TransactionForced",
    event.data,
    event.topics
);

console.log(`Force request submitted: ${txId}`);
console.log(`Must be included by: ${new Date(Number(deadline) * 1000)}`);
```

### Step 2: Wait for Inclusion

Monitor the L2 for inclusion:

```typescript
async function waitForInclusion(txId: string, deadline: number) {
    const forcedInclusion = new Contract(FORCED_INCLUSION_ADDRESS, ForcedInclusionABI, l1Provider);

    while (true) {
        // Check status
        const status = await forcedInclusion.getStatus(txId);

        if (status.state === "included") {
            console.log(`Transaction included at L2 block ${status.l2BlockNumber}`);
            return { included: true, blockNumber: status.l2BlockNumber };
        }

        if (status.state === "expired") {
            console.log("Transaction expired - sequencer failed to include");
            return { included: false, expired: true };
        }

        // Check if deadline passed
        if (Date.now() / 1000 > deadline) {
            console.log("Deadline passed, checking final status...");
            await new Promise(r => setTimeout(r, 60000));  // Wait 1 more minute
            continue;
        }

        console.log("Waiting for inclusion...");
        await new Promise(r => setTimeout(r, 60000));  // Check every minute
    }
}
```

### Step 3a: Prove Inclusion (if included)

If the transaction was included, prove it to get your bond back:

```typescript
async function proveAndRecoverBond(txId: string, l2BlockNumber: bigint) {
    // Get inclusion proof from L2
    const proof = await getInclusionProof(txId, l2BlockNumber);

    // Prove on L1
    const tx = await forcedInclusion.proveInclusion(
        txId,
        l2BlockNumber,
        proof
    );
    await tx.wait();

    console.log("Bond recovered successfully");
}
```

### Step 3b: Claim Expired (if not included)

If the sequencer failed to include:

```typescript
async function claimExpiredBond(txId: string) {
    const tx = await forcedInclusion.claimExpired(txId);
    const receipt = await tx.wait();

    const event = receipt.logs.find(l =>
        l.topics[0] === forcedInclusion.interface.getEventTopic("BondClaimed")
    );
    const { amount } = forcedInclusion.interface.decodeEventLog(
        "BondClaimed",
        event.data,
        event.topics
    );

    console.log(`Claimed: ${formatEther(amount)} ETH (bond + penalty)`);
}
```

## SDK Integration

### Using MEV Protection Client

```typescript
import { createForcedInclusionClient } from "@setchain/sdk";

const forcedClient = createForcedInclusionClient(
    FORCED_INCLUSION_ADDRESS,
    l1Wallet
);

// Force a transaction
const result = await forcedClient.forceTransaction(
    l2Target,
    l2Data,
    l2GasLimit
);

console.log(`Forced: ${result.txId}`);
console.log(`Deadline: ${new Date(result.deadline * 1000)}`);

// Monitor status
const status = await forcedClient.waitForInclusion(result.txId);

if (status.included) {
    await forcedClient.proveInclusion(result.txId, status.l2BlockNumber);
    console.log("Bond recovered");
} else {
    const claimed = await forcedClient.claimExpired(result.txId);
    console.log(`Claimed ${formatEther(claimed)} ETH`);
}
```

## Contract Interface

### ForcedInclusion Contract

```solidity
interface IForcedInclusion {
    // Force a transaction
    function forceTransaction(
        address target,
        bytes calldata data,
        uint256 gasLimit
    ) external payable returns (bytes32 txId);

    // Prove inclusion to recover bond
    function proveInclusion(
        bytes32 txId,
        uint256 l2BlockNumber,
        bytes calldata inclusionProof
    ) external;

    // Claim expired if sequencer censored
    function claimExpired(bytes32 txId) external returns (uint256 amount);

    // View functions
    function getStatus(bytes32 txId) external view returns (ForceStatus memory);
    function getBondAmount() external view returns (uint256);
    function getInclusionDeadline() external view returns (uint256);
    function isExpired(bytes32 txId) external view returns (bool);
}

struct ForceStatus {
    bytes32 txId;
    address sender;
    address target;
    bytes data;
    uint256 gasLimit;
    uint256 bond;
    uint256 deadline;
    ForceState state;  // pending | included | expired | claimed
    uint256 l2BlockNumber;  // Set if included
}
```

## Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Bond Amount | 0.01 ETH | Required deposit |
| Inclusion Deadline | 24 hours | Time to include |
| Sequencer Penalty | 0.1 ETH | Penalty if censors |
| Min Gas Limit | 21000 | Minimum gas |
| Max Gas Limit | 5000000 | Maximum gas |
| Max Pending Txs | 1000 | Circuit breaker limit |
| Max Txs/User/Hour | 10 | User rate limit |

## Monitoring Functions

### System Status

```typescript
// Get comprehensive system status
const {
    pendingCount,
    totalForced,
    totalIncluded,
    totalExpired,
    bondsLocked,
    isPaused,
    circuitBreakerCapacity
} = await forcedInclusion.getSystemStatus();

console.log(`Pending: ${pendingCount} / Capacity: ${circuitBreakerCapacity}`);
console.log(`Inclusion rate: ${(totalIncluded * 100n / totalForced)}%`);
```

### Transaction Details

```typescript
// Get detailed transaction info
const {
    sender,
    target,
    bond,
    deadline,
    isResolved,
    isExpiredNow,
    timeRemaining
} = await forcedInclusion.getTxDetails(txId);

if (timeRemaining > 0n) {
    console.log(`Time remaining: ${timeRemaining / 3600n} hours`);
}
```

### Batch Operations

```typescript
// Check multiple transactions at once
const { resolved, expired } = await forcedInclusion.getBatchTxStatuses([
    txId1, txId2, txId3
]);

// Get user summary
const {
    totalSubmitted,
    pendingCount,
    currentRateUsed,
    canSubmitNow
} = await forcedInclusion.getUserSummary(userAddress);
```

### Rate Limiting

```typescript
// Check rate limit status
const { limited, remaining } = await forcedInclusion.isRateLimited(userAddress);

if (limited) {
    console.log("Rate limited - wait an hour");
} else {
    console.log(`Can submit ${remaining} more forced transactions`);
}
```

## Inclusion Proof

### Proof Structure

```typescript
interface InclusionProof {
    l2BlockNumber: bigint;
    l2TransactionIndex: number;
    l2BlockHash: string;
    l1OutputIndex: bigint;
    l1OutputProof: string[];  // Merkle proof to L2OutputOracle
    l2StateProof: string[];   // Proof within L2 block
}
```

### Generating Proof

```typescript
async function getInclusionProof(txId: string, l2BlockNumber: bigint) {
    // Get L2 block
    const l2Block = await l2Provider.getBlock(l2BlockNumber, true);

    // Find transaction in block
    const txIndex = l2Block.transactions.findIndex(tx =>
        computeTxId(tx) === txId
    );

    // Get L1 output root
    const outputOracle = new Contract(L2_OUTPUT_ORACLE, L2OutputOracleABI, l1Provider);
    const outputIndex = await outputOracle.getL2OutputIndexAfter(l2BlockNumber);
    const output = await outputOracle.getL2Output(outputIndex);

    // Generate proofs
    const l1OutputProof = generateOutputProof(outputIndex, output);
    const l2StateProof = generateStateProof(l2Block, txIndex);

    return {
        l2BlockNumber,
        l2TransactionIndex: txIndex,
        l2BlockHash: l2Block.hash,
        l1OutputIndex: outputIndex,
        l1OutputProof,
        l2StateProof
    };
}
```

## Sequencer Obligations

### Monitoring Force Requests

Sequencers must monitor L1 for force requests:

```typescript
// Sequencer node logic
async function monitorForceRequests() {
    const forcedInclusion = new Contract(
        FORCED_INCLUSION_ADDRESS,
        ForcedInclusionABI,
        l1Provider
    );

    forcedInclusion.on("TransactionForced", async (txId, sender, target, data, gasLimit, deadline) => {
        console.log(`Force request received: ${txId}`);
        console.log(`Deadline: ${new Date(Number(deadline) * 1000)}`);

        // Queue for inclusion
        await sequencer.queueForcedTransaction({
            txId,
            sender,
            target,
            data,
            gasLimit,
            deadline,
            priority: "high"
        });
    });
}
```

### Inclusion Priority

Forced transactions get priority ordering:
1. Must be included before deadline
2. Higher priority than regular transactions
3. Cannot be censored without penalty

## Security Considerations

### Bond Protection

- Bond protects against spam
- Refunded if transaction included
- Sequencer penalized if censors

### Deadline Enforcement

- 24-hour deadline is enforced by L1 contract
- Based on L1 block timestamps
- Allows sufficient time for L1→L2 messaging

### Proof Verification

The L1 contract verifies:
1. Transaction was included on L2
2. Inclusion was in valid L2 block
3. L2 state is committed to L1

## Common Issues

### "Bond Too Low"

```typescript
// Always get current bond amount
const bondAmount = await forcedInclusion.getBondAmount();
await forcedInclusion.forceTransaction(target, data, gasLimit, {
    value: bondAmount
});
```

### "Gas Limit Too High"

```typescript
// Check max gas limit
const maxGas = await forcedInclusion.maxGasLimit();
if (gasLimit > maxGas) {
    throw new Error(`Gas limit exceeds maximum ${maxGas}`);
}
```

### "Already Claimed"

```typescript
// Check status before claiming
const status = await forcedInclusion.getStatus(txId);
if (status.state !== "expired") {
    throw new Error(`Cannot claim - status is ${status.state}`);
}
```

## Related

- [MEV Protection Overview](./overview.md)
- [Encrypted Mempool](./encrypted-mempool.md)
- [Trust Model](../architecture/trust-model.md)
- [MEV Contracts API](../contracts/mev-contracts.md)
