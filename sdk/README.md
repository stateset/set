# Set Chain SDK

A comprehensive TypeScript SDK for interacting with Set Chain, a commerce-optimized Ethereum Layer 2.

## Features

- **SetRegistry** - Batch commitment anchoring and Merkle proof verification
- **SetPaymaster** - Gas sponsorship for merchants
- **Stablecoin** - ssUSD/wssUSD operations (deposit, redemption, wrap/unwrap)
- **MEV Protection** - Encrypted transaction submission with threshold encryption
- **Utilities** - Address validation, formatting, gas estimation, retry logic

## Installation

```bash
npm install @setchain/sdk ethers
```

## Quick Start

```typescript
import { createProvider, createWallet, getSetRegistry } from "@setchain/sdk";

// Create provider and wallet
const provider = createProvider("https://rpc.sepolia.setchain.io");
const wallet = createWallet(process.env.PRIVATE_KEY!, "https://rpc.sepolia.setchain.io");

// Get SetRegistry contract
const registry = getSetRegistry("0x...", wallet);

// Query state root
const stateRoot = await registry.getLatestStateRoot(tenantId, storeId);
```

## Core Modules

### SetRegistry

Anchor batch commitments and verify Merkle proofs:

```typescript
import { getSetRegistry } from "@setchain/sdk";

const registry = getSetRegistry(registryAddress, wallet);

// Commit a batch
await registry.commitBatch(
  batchId,
  tenantId,
  storeId,
  eventsRoot,
  prevStateRoot,
  newStateRoot,
  sequenceStart,
  sequenceEnd,
  eventCount
);

// Verify inclusion
const isValid = await registry.verifyInclusion(batchId, leaf, proof, index);

// Get latest state root
const stateRoot = await registry.getLatestStateRoot(tenantId, storeId);
```

### SetPaymaster

Gas sponsorship for commerce transactions:

```typescript
import { getSetPaymaster } from "@setchain/sdk";

const paymaster = getSetPaymaster(paymasterAddress, wallet);

// Sponsor a merchant
await paymaster.sponsorMerchant(merchantAddress, tierId);

// Execute sponsorship
await paymaster.executeSponsorship(merchantAddress, amount, operationType);

// Get merchant details
const details = await paymaster.getMerchantDetails(merchantAddress);
```

### Stablecoin Client

Full ssUSD stablecoin operations:

```typescript
import { stablecoin } from "@setchain/sdk";

const client = stablecoin.createStablecoinClient(
  {
    tokenRegistry: "0x...",
    navOracle: "0x...",
    ssUSD: "0x...",
    wssUSD: "0x...",
    treasury: "0x..."
  },
  privateKey,
  rpcUrl
);

// Deposit USDC for ssUSD
const result = await client.deposit(usdcAddress, 1000000n); // 1 USDC
console.log(`Minted: ${result.ssUSDMinted}`);

// Get formatted balance
const balance = await client.getFormattedBalance(userAddress);
console.log(balance.formatted.ssUSD); // "100.5000 ssUSD"

// Wrap ssUSD to wssUSD for DeFi
const wrapResult = await client.wrap(parseAmount("100", 18));

// Request redemption
const redemption = await client.requestRedemption(amount, preferredCollateral);
```

### MEV Protection

Submit encrypted transactions for front-running protection:

```typescript
import { createMEVProtectionClient, EncryptedTxStatus } from "@setchain/sdk";

const mevClient = createMEVProtectionClient(
  mempoolAddress,
  keyRegistryAddress,
  privateKey,
  rpcUrl
);

// Check availability
const available = await mevClient.isAvailable();

// Submit MEV-protected transaction
const { txId, waitForExecution } = await mevClient.submit(
  targetAddress,
  calldata,
  value
);

// Wait for execution
const result = await waitForExecution();
console.log(`Success: ${result.success}`);
```

## Utilities

### Validation

```typescript
import { validateAddress, validatePositiveAmount, isValidAddress } from "@setchain/sdk";

// Validate and normalize address
const checksummed = validateAddress("0x..."); // throws on invalid

// Check without throwing
if (isValidAddress(input)) {
  // safe to use
}

// Validate amounts
validatePositiveAmount(amount); // throws if <= 0
```

### Formatting

```typescript
import {
  formatBalance,
  parseAmount,
  formatETH,
  formatGas,
  shortenAddress,
  formatDuration
} from "@setchain/sdk";

// Format balance with options
formatBalance(1000000000000000000n, 18); // "1"
formatBalance(1234567890000000000n, 18, { maxDecimals: 2, suffix: " ETH" }); // "1.23 ETH"

// Parse human-readable amounts
parseAmount("1.5", 18); // 1500000000000000000n

// Convenience formatters
formatETH(wei); // "0.5 ETH"
formatGas(150000n); // "150K gas"
shortenAddress("0x1234...5678"); // "0x1234...5678"
formatDuration(86400); // "1d"
```

### Gas Estimation

```typescript
import { estimateGas, DEFAULT_GAS_LIMITS, applyGasBuffer } from "@setchain/sdk";

// Estimate gas for contract call
const estimate = await estimateGas(contract, "transfer", [to, amount]);
console.log(`Gas: ${estimate.gasLimit}, Cost: ${estimate.estimatedCost}`);

// Use default limits
const gasLimit = DEFAULT_GAS_LIMITS.TRANSFER; // 65000n

// Apply buffer
const bufferedGas = applyGasBuffer(gasLimit, 1.2); // 20% buffer
```

### Retry Logic

```typescript
import { withRetry, withTimeout, pollUntil } from "@setchain/sdk";

// Retry with exponential backoff
const result = await withRetry(
  () => fetchData(),
  { maxAttempts: 3, initialDelayMs: 1000 }
);

// Add timeout
const data = await withTimeout(
  () => slowOperation(),
  30000,
  "Slow operation"
);

// Poll until condition
await pollUntil(
  () => checkStatus(),
  { intervalMs: 2000, timeoutMs: 60000 }
);
```

### Event Parsing

```typescript
import { findEvent, extractEventArg, EVENT_SIGNATURES } from "@setchain/sdk";

// Find event in receipt
const event = findEvent(receipt, contract, "Transfer");
if (event) {
  console.log(`From: ${event.args.from}, To: ${event.args.to}`);
}

// Extract single argument
const amount = extractEventArg<bigint>(receipt, contract, "Transfer", "value");
```

## Error Handling

The SDK provides typed errors with codes and suggestions:

```typescript
import {
  SDKError,
  SDKErrorCode,
  InsufficientBalanceError,
  isSDKError,
  hasErrorCode
} from "@setchain/sdk";

try {
  await client.deposit(token, amount);
} catch (error) {
  if (isSDKError(error)) {
    console.log(`Error [${error.code}]: ${error.message}`);

    if (error.suggestion) {
      console.log(`Suggestion: ${error.suggestion}`);
    }

    // Handle specific errors
    if (hasErrorCode(error, SDKErrorCode.INSUFFICIENT_BALANCE)) {
      const details = error.details as { shortfall: string };
      console.log(`Need ${details.shortfall} more tokens`);
    }
  }
}
```

### Error Types

| Error | Code | Description |
|-------|------|-------------|
| `InvalidAddressError` | SDK_1001 | Invalid Ethereum address |
| `InvalidAmountError` | SDK_1002 | Invalid amount (negative, zero) |
| `InsufficientBalanceError` | SDK_2001 | Not enough tokens |
| `InsufficientAllowanceError` | SDK_2002 | Need to approve more |
| `NetworkError` | SDK_3001 | Network/RPC issues |
| `TimeoutError` | SDK_3003 | Operation timed out |
| `TransactionFailedError` | SDK_4001 | Transaction reverted |
| `GasEstimationError` | SDK_5002 | Gas estimation failed |
| `MEVUnavailableError` | SDK_6001 | MEV protection unavailable |
| `DepositsPausedError` | SDK_7002 | Deposits are paused |
| `RedemptionsPausedError` | SDK_7003 | Redemptions are paused |

## Configuration

Configure SDK behavior globally or per-operation:

```typescript
import { setConfig, getConfig, NETWORK_PRESETS } from "@setchain/sdk";

// Use network preset
setConfig(NETWORK_PRESETS.sepolia);

// Custom configuration
setConfig({
  gasBuffer: 1.3,           // 30% gas buffer
  transactionTimeout: 180000, // 3 minute timeout
  maxRetries: 5,            // More retries
  debug: true               // Enable debug logging
});

// Get current config
const config = getConfig();
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `gasBuffer` | 1.2 | Gas limit multiplier |
| `transactionTimeout` | 120000 | TX confirmation timeout (ms) |
| `blockConfirmations` | 1 | Confirmations to wait |
| `maxRetries` | 3 | Max retry attempts |
| `initialRetryDelay` | 1000 | Initial retry delay (ms) |
| `mevTimeout` | 180000 | MEV transaction timeout (ms) |
| `debug` | false | Enable debug logging |

## Networks

```typescript
import { NETWORKS, getContractAddresses } from "@setchain/sdk";

// Get network config
const sepolia = NETWORKS.sepolia;
console.log(sepolia.chainId); // 84532001
console.log(sepolia.rpcUrl);  // "https://rpc.sepolia.setchain.io"

// Get contract addresses (when available)
const addresses = getContractAddresses("sepolia");
```

## TypeScript Types

All types are exported for use in your application:

```typescript
import type {
  // Stablecoin
  StablecoinAddresses,
  UserBalance,
  DepositResult,
  RedemptionResult,
  NAVReport,

  // MEV
  ThresholdKey,
  EncryptedTransaction,
  EncryptedTxStatus,

  // Config
  SDKConfig,
  NetworkConfig,

  // Utils
  GasEstimate,
  RetryOptions,
  ParsedEvent
} from "@setchain/sdk";
```

## Examples

### Complete Deposit Flow

```typescript
import { stablecoin, setConfig, formatBalance, SDKErrorCode, isSDKError } from "@setchain/sdk";

// Configure for testnet
setConfig({ debug: true, gasBuffer: 1.3 });

const client = stablecoin.createStablecoinClient(addresses, privateKey, rpcUrl);

async function depositUSDC(amount: string) {
  try {
    // Check if deposits are active
    if (await client.areDepositsPaused()) {
      throw new Error("Deposits are currently paused");
    }

    // Parse amount (USDC has 6 decimals)
    const amountWei = parseAmount(amount, 6);

    // Execute deposit
    const result = await client.deposit(USDC_ADDRESS, amountWei);

    console.log(`Deposited ${amount} USDC`);
    console.log(`Received ${formatBalance(result.ssUSDMinted, 18)} ssUSD`);
    console.log(`TX: ${result.txHash}`);

    return result;
  } catch (error) {
    if (isSDKError(error)) {
      if (error.code === SDKErrorCode.INSUFFICIENT_BALANCE) {
        console.error("Not enough USDC in wallet");
      } else if (error.code === SDKErrorCode.INVALID_COLLATERAL) {
        console.error("USDC is not an approved collateral token");
      }
    }
    throw error;
  }
}
```

### MEV-Protected Swap

```typescript
import { createMEVProtectionClient, EncryptedTxStatus } from "@setchain/sdk";

const mev = createMEVProtectionClient(mempool, keyRegistry, privateKey, rpcUrl);

async function protectedSwap(swapData: string) {
  // Check MEV protection status
  const status = await mev.getStatus();
  if (!status.available) {
    throw new Error("MEV protection not available");
  }

  console.log(`Using epoch ${status.epoch}, threshold ${status.threshold}/${status.keyperCount}`);

  // Submit encrypted transaction
  const { txId, waitForExecution } = await mev.submit(
    ROUTER_ADDRESS,
    swapData,
    0n,
    { gasLimit: 500000n }
  );

  console.log(`Submitted encrypted TX: ${txId}`);

  // Wait for execution
  const result = await waitForExecution();

  if (result.success) {
    console.log("Swap executed successfully!");
  } else {
    console.log("Swap failed");
  }

  return result;
}
```

## API Reference

See the [API Reference](../docs/api-reference.md) for complete documentation of all exports.

## License

MIT
