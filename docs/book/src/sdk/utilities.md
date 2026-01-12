# SDK Utilities

Helper functions for common operations.

## Validation

### validateAddress

Validate an Ethereum address.

```typescript
function validateAddress(address: string): void
```

Throws `InvalidAddressError` if invalid.

**Example:**
```typescript
import { validateAddress, InvalidAddressError } from "@setchain/sdk";

try {
    validateAddress("0x742d35Cc6634C0532925a3b844Bc9e7595f");
} catch (error) {
    if (error instanceof InvalidAddressError) {
        console.error("Invalid address:", error.message);
    }
}
```

### validateNonZeroAddress

Validate address is not zero address.

```typescript
function validateNonZeroAddress(address: string): void
```

**Example:**
```typescript
import { validateNonZeroAddress } from "@setchain/sdk";

// Throws if zero address
validateNonZeroAddress(recipient);
```

### isValidAddress

Check if address is valid (no throw).

```typescript
function isValidAddress(address: string): boolean
```

**Example:**
```typescript
import { isValidAddress } from "@setchain/sdk";

if (isValidAddress(userInput)) {
    // Proceed with address
} else {
    console.error("Please enter a valid address");
}
```

### validatePositiveAmount

Validate amount is positive.

```typescript
function validatePositiveAmount(amount: bigint, paramName?: string): void
```

**Example:**
```typescript
import { validatePositiveAmount } from "@setchain/sdk";

validatePositiveAmount(depositAmount, "depositAmount");
// Throws if amount <= 0
```

### validateBytes32

Validate a bytes32 hex string.

```typescript
function validateBytes32(value: string, paramName?: string): void
```

**Example:**
```typescript
import { validateBytes32 } from "@setchain/sdk";

validateBytes32(merkleRoot, "merkleRoot");
```

## Formatting

### formatBalance

Format a bigint balance for display.

```typescript
function formatBalance(
    value: bigint,
    decimals: number,
    displayDecimals?: number
): string
```

**Example:**
```typescript
import { formatBalance } from "@setchain/sdk";

const balance = 1234567890123456789n;  // 1.234... with 18 decimals

console.log(formatBalance(balance, 18));      // "1.234567890123456789"
console.log(formatBalance(balance, 18, 2));   // "1.23"
console.log(formatBalance(balance, 18, 4));   // "1.2345"
```

### parseBalance

Parse a string to bigint with decimals.

```typescript
function parseBalance(value: string, decimals: number): bigint
```

**Example:**
```typescript
import { parseBalance } from "@setchain/sdk";

const amount = parseBalance("100.5", 18);
// 100500000000000000000n

const usdc = parseBalance("1000", 6);
// 1000000000n
```

### formatUSD

Format a value as USD currency.

```typescript
function formatUSD(value: bigint, decimals?: number): string
```

**Example:**
```typescript
import { formatUSD } from "@setchain/sdk";

const nav = 1000137000000000000n;  // $1.000137 with 18 decimals
console.log(formatUSD(nav));       // "$1.00"
console.log(formatUSD(nav, 6));    // "$1.000137"

const total = 50000000000000000000000000n;  // $50M
console.log(formatUSD(total));     // "$50,000,000.00"
```

### formatPercentage

Format a value as percentage.

```typescript
function formatPercentage(
    value: bigint,
    decimals: number,
    displayDecimals?: number
): string
```

**Example:**
```typescript
import { formatPercentage } from "@setchain/sdk";

// 5% APY as basis points (500 = 5%)
const apyBps = 500n;
console.log(formatPercentage(apyBps, 2));  // "5.00%"

// NAV change
const navChange = 137000000000000n;  // 0.0137% with 18 decimals
console.log(formatPercentage(navChange, 18, 4));  // "0.0137%"
```

### shortenAddress

Shorten an address for display.

```typescript
function shortenAddress(address: string, chars?: number): string
```

**Example:**
```typescript
import { shortenAddress } from "@setchain/sdk";

const addr = "0x742d35Cc6634C0532925a3b844Bc454e4438f44e";

console.log(shortenAddress(addr));      // "0x742d...f44e"
console.log(shortenAddress(addr, 6));   // "0x742d35...4438f44e"
```

## Gas Utilities

### estimateGas

Estimate gas for a transaction.

```typescript
async function estimateGas(
    provider: Provider,
    tx: TransactionRequest
): Promise<GasEstimate>

interface GasEstimate {
    gasLimit: bigint;
    maxFeePerGas: bigint;
    maxPriorityFeePerGas: bigint;
    estimatedCost: bigint;
}
```

**Example:**
```typescript
import { estimateGas } from "@setchain/sdk";

const estimate = await estimateGas(provider, {
    to: treasuryAddress,
    data: treasury.interface.encodeFunctionData("deposit", [token, amount, minOut])
});

console.log(`Gas limit: ${estimate.gasLimit}`);
console.log(`Estimated cost: ${formatEther(estimate.estimatedCost)} ETH`);
```

### applyGasBuffer

Apply a safety buffer to gas estimate.

```typescript
function applyGasBuffer(gasLimit: bigint, bufferPercent?: number): bigint
```

**Example:**
```typescript
import { applyGasBuffer } from "@setchain/sdk";

const baseGas = 150000n;
const safeGas = applyGasBuffer(baseGas, 20);  // +20%
// 180000n
```

### DEFAULT_GAS_LIMITS

Preset gas limits for common operations.

```typescript
const DEFAULT_GAS_LIMITS = {
    deposit: 200000n,
    redeem: 180000n,
    wrap: 100000n,
    unwrap: 100000n,
    transfer: 65000n,
    approve: 50000n,
    submitBatch: 300000n,
    encryptedSubmit: 250000n
};
```

**Example:**
```typescript
import { DEFAULT_GAS_LIMITS } from "@setchain/sdk";

const tx = await treasury.deposit(token, amount, minOut, {
    gasLimit: DEFAULT_GAS_LIMITS.deposit
});
```

## Retry Utilities

### withRetry

Retry an async operation with exponential backoff.

```typescript
async function withRetry<T>(
    fn: () => Promise<T>,
    options?: RetryOptions
): Promise<T>

interface RetryOptions {
    maxRetries?: number;      // Default: 3
    initialDelay?: number;    // Default: 1000ms
    maxDelay?: number;        // Default: 10000ms
    backoffFactor?: number;   // Default: 2
    shouldRetry?: (error: Error) => boolean;
}
```

**Example:**
```typescript
import { withRetry } from "@setchain/sdk";

const balance = await withRetry(
    () => client.getBalance(address),
    {
        maxRetries: 5,
        initialDelay: 500,
        shouldRetry: (error) => {
            // Only retry on network errors
            return error.message.includes("network");
        }
    }
);
```

### withTimeout

Add timeout to an async operation.

```typescript
async function withTimeout<T>(
    fn: () => Promise<T>,
    timeoutMs: number,
    errorMessage?: string
): Promise<T>
```

**Example:**
```typescript
import { withTimeout } from "@setchain/sdk";

try {
    const result = await withTimeout(
        () => client.deposit(token, amount),
        30000,  // 30 seconds
        "Deposit timed out"
    );
} catch (error) {
    if (error.message === "Deposit timed out") {
        console.error("Transaction is taking too long");
    }
}
```

### pollUntil

Poll an async function until condition is met.

```typescript
async function pollUntil<T>(
    fn: () => Promise<T>,
    condition: (result: T) => boolean,
    options?: PollOptions
): Promise<T>

interface PollOptions {
    interval?: number;    // Default: 2000ms
    timeout?: number;     // Default: 60000ms
    onPoll?: (result: T) => void;
}
```

**Example:**
```typescript
import { pollUntil } from "@setchain/sdk";

// Wait for transaction to be confirmed
const receipt = await pollUntil(
    () => provider.getTransactionReceipt(txHash),
    (receipt) => receipt !== null && receipt.confirmations >= 1,
    {
        interval: 2000,
        timeout: 120000,
        onPoll: (receipt) => {
            if (receipt) {
                console.log(`${receipt.confirmations} confirmations...`);
            }
        }
    }
);
```

## Event Utilities

### findEvent

Find a specific event in transaction logs.

```typescript
function findEvent<T>(
    receipt: TransactionReceipt,
    contract: Contract,
    eventName: string
): T | null
```

**Example:**
```typescript
import { findEvent } from "@setchain/sdk";

const receipt = await tx.wait();
const depositEvent = findEvent(receipt, treasury, "Deposit");

if (depositEvent) {
    console.log(`Deposited: ${depositEvent.args.amount}`);
    console.log(`Minted: ${depositEvent.args.ssUSDMinted}`);
}
```

### extractEventArg

Extract a specific argument from an event.

```typescript
function extractEventArg<T>(
    receipt: TransactionReceipt,
    contract: Contract,
    eventName: string,
    argName: string
): T | null
```

**Example:**
```typescript
import { extractEventArg } from "@setchain/sdk";

const receipt = await tx.wait();
const ssUSDMinted = extractEventArg<bigint>(
    receipt,
    treasury,
    "Deposit",
    "ssUSDMinted"
);

console.log(`Minted: ${formatUnits(ssUSDMinted, 18)} ssUSD`);
```

## Complete Example

```typescript
import {
    validateAddress,
    validatePositiveAmount,
    formatBalance,
    formatUSD,
    shortenAddress,
    withRetry,
    withTimeout,
    pollUntil,
    findEvent,
    DEFAULT_GAS_LIMITS
} from "@setchain/sdk";

async function safeDeposit(
    client: StablecoinClient,
    token: string,
    amount: bigint,
    recipient: string
) {
    // Validate inputs
    validateAddress(token);
    validateAddress(recipient);
    validatePositiveAmount(amount, "amount");

    console.log(`Depositing ${formatBalance(amount, 6)} to ${shortenAddress(recipient)}`);

    // Preview with retry
    const preview = await withRetry(
        () => client.previewDeposit(token, amount),
        { maxRetries: 3 }
    );
    console.log(`Expected: ${formatUSD(preview)} ssUSD`);

    // Execute with timeout
    const result = await withTimeout(
        () => client.deposit(token, amount, {
            minSsUSD: preview * 99n / 100n,
            recipient,
            gasLimit: DEFAULT_GAS_LIMITS.deposit
        }),
        60000,
        "Deposit transaction timed out"
    );

    console.log(`Minted: ${formatBalance(result.ssUSDMinted, 18)} ssUSD`);
    console.log(`Tx: ${result.txHash}`);

    return result;
}
```

## Contract Helper Functions

The SDK provides helper functions for common contract interactions.

### TreasuryVault Helpers

```typescript
import {
  getTreasuryVault,
  fetchTreasuryVaultHealth,
  getCollateralBreakdown,
  getTreasuryUserSummary,
  getRedemptionStatus,
  getReadyRedemptions,
  batchGetCollateralBalances,
  batchGetRedemptionRequests
} from "@setchain/sdk";

const vault = getTreasuryVault(address, provider);

// Get vault health
const health = await fetchTreasuryVaultHealth(vault);
console.log(`Collateral Ratio: ${health.collateralizationRatio}%`);
console.log(`Pending Redemptions: ${health.pendingRedemptionsCount}`);

// Get collateral breakdown
const breakdown = await getCollateralBreakdown(vault);
for (let i = 0; i < breakdown.tokens.length; i++) {
  console.log(`${breakdown.tokens[i]}: ${breakdown.balances[i]}`);
}

// Get user summary
const summary = await getTreasuryUserSummary(vault, userAddress);
console.log(`Can Deposit: ${summary.canDeposit}`);
console.log(`Pending Redemptions: ${summary.pendingRedemptions}`);

// Check redemption status
const status = await getRedemptionStatus(vault, requestId);
if (status.canProcess) {
  console.log("Redemption is ready to process!");
}

// Batch operations for efficiency
const balances = await batchGetCollateralBalances(vault, tokenAddresses);
const requests = await batchGetRedemptionRequests(vault, requestIds);
```

### SetPaymaster Helpers

```typescript
import {
  getSetPaymaster,
  fetchPaymasterStatus,
  fetchAllTiers,
  fetchMerchantDetails,
  fetchBatchMerchantDetails,
  checkCanSponsor,
  batchCheckCanSponsor,
  fetchBatchRemainingAllowances,
  aggregateMerchantStats,
  getPaymasterHealthSummary,
  findSponsorableMerchants
} from "@setchain/sdk";

const paymaster = getSetPaymaster(address, provider);

// Get paymaster health
const health = await getPaymasterHealthSummary(paymaster);
console.log(`Balance: ${health.balance}`);
console.log(`Tiers: ${health.tiers.length}`);
console.log(`Healthy: ${health.isHealthy}`);

// Check if merchant can be sponsored
const { canSponsor, reason } = await checkCanSponsor(paymaster, merchant, amount);
if (!canSponsor) {
  console.log(`Cannot sponsor: ${reason}`);
}

// Aggregate stats for multiple merchants
const stats = await aggregateMerchantStats(paymaster, merchants);
console.log(`Active: ${stats.activeMerchants}/${stats.totalMerchants}`);
console.log(`Total Spent: ${stats.totalSpent}`);

// Find which merchants can be sponsored
const { sponsorable, nonSponsorable } = await findSponsorableMerchants(
  paymaster,
  merchants,
  amounts
);
```

### SetRegistry Helpers

```typescript
import {
  getSetRegistry,
  checkBatchExists,
  checkBatchHasProof,
  isRegistryPaused,
  fetchRegistryStats,
  fetchBatchHeadSequences
} from "@setchain/sdk";

const registry = getSetRegistry(address, provider);

// Check batch status
const exists = await checkBatchExists(registry, batchId);
const hasProof = await checkBatchHasProof(registry, batchId);

// Get registry stats
const stats = await fetchRegistryStats(registry);
console.log(`Commitments: ${stats.commitmentCount}`);
console.log(`Proofs: ${stats.proofCount}`);
console.log(`Strict Mode: ${stats.isStrictMode}`);

// Get sequences for multiple tenant/store pairs
const sequences = await fetchBatchHeadSequences(registry, tenantIds, storeIds);
```

## Related

- [SDK Installation](./installation.md)
- [Error Handling](./errors.md)
- [Stablecoin Client](./stablecoin-client.md)
