# Set Chain API Reference

Complete reference for Set Chain smart contracts and SDK.

## Smart Contracts

### SetRegistry

Core contract for anchoring batch commitments from the stateset-sequencer.

**Address:** Deployed per network (see [Contract Addresses](#contract-addresses))

#### Functions

##### `commitBatch`
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
) external
```
Commit a batch of commerce events.

| Parameter | Type | Description |
|-----------|------|-------------|
| `_batchId` | bytes32 | Unique batch identifier |
| `_tenantId` | bytes32 | Tenant identifier |
| `_storeId` | bytes32 | Store identifier |
| `_eventsRoot` | bytes32 | Merkle root of events |
| `_prevStateRoot` | bytes32 | Previous state root |
| `_newStateRoot` | bytes32 | New state root after batch |
| `_sequenceStart` | uint64 | First sequence number in batch |
| `_sequenceEnd` | uint64 | Last sequence number in batch |
| `_eventCount` | uint32 | Number of events in batch |

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

**Requirements:**
- Caller must be authorized sequencer
- If strict mode: `_prevStateRoot` must match current state root

---

##### `verifyInclusion`
```solidity
function verifyInclusion(
    bytes32 _batchId,
    bytes32 _leaf,
    bytes32[] calldata _proof,
    uint256 _index
) external view returns (bool valid)
```
Verify a leaf is included in a committed batch.

| Parameter | Type | Description |
|-----------|------|-------------|
| `_batchId` | bytes32 | Batch to verify against |
| `_leaf` | bytes32 | Leaf hash to verify |
| `_proof` | bytes32[] | Merkle proof |
| `_index` | uint256 | Leaf index in tree |

**Returns:** `true` if proof is valid

---

##### `verifyMultipleInclusions`
```solidity
function verifyMultipleInclusions(
    bytes32 _batchId,
    bytes32[] calldata _leaves,
    bytes32[][] calldata _proofs,
    uint256[] calldata _indices
) external view returns (bool allValid)
```
Verify multiple leaves in a single call.

---

##### `getLatestStateRoot`
```solidity
function getLatestStateRoot(
    bytes32 _tenantId,
    bytes32 _storeId
) external view returns (bytes32 stateRoot)
```
Get current state root for a tenant/store.

---

##### `getHeadSequence`
```solidity
function getHeadSequence(
    bytes32 _tenantId,
    bytes32 _storeId
) external view returns (uint64 sequence)
```
Get latest sequence number for a tenant/store.

---

##### `setSequencerAuthorization`
```solidity
function setSequencerAuthorization(
    address _sequencer,
    bool _authorized
) external onlyOwner
```
Authorize or revoke a sequencer.

---

##### `setStrictMode`
```solidity
function setStrictMode(bool _enabled) external onlyOwner
```
Enable/disable state chain continuity verification.

---

### SetPaymaster

Gas sponsorship contract for merchants.

#### Functions

##### `sponsorMerchant`
```solidity
function sponsorMerchant(
    address _merchant,
    uint256 _tierId
) external onlyOperator
```
Register a merchant for sponsorship.

| Parameter | Type | Description |
|-----------|------|-------------|
| `_merchant` | address | Merchant address |
| `_tierId` | uint256 | Sponsorship tier ID |

---

##### `executeSponsorship`
```solidity
function executeSponsorship(
    address _merchant,
    uint256 _amount,
    uint8 _operationType
) external onlyOperator
```
Execute a sponsored operation.

| Parameter | Type | Description |
|-----------|------|-------------|
| `_merchant` | address | Merchant address |
| `_amount` | uint256 | Gas amount in wei |
| `_operationType` | uint8 | Operation type enum |

**Operation Types:**
```solidity
enum OperationType {
    ORDER_CREATE,      // 0
    ORDER_UPDATE,      // 1
    PAYMENT_PROCESS,   // 2
    INVENTORY_UPDATE,  // 3
    RETURN_PROCESS,    // 4
    COMMITMENT_ANCHOR, // 5
    OTHER              // 6
}
```

---

##### `getMerchantDetails`
```solidity
function getMerchantDetails(
    address _merchant
) external view returns (
    bool active,
    uint256 tierId,
    uint256 spentToday,
    uint256 spentThisMonth,
    uint256 totalSponsored
)
```
Get merchant sponsorship details.

---

##### `createTier`
```solidity
function createTier(
    string calldata _name,
    uint256 _maxPerTx,
    uint256 _maxPerDay,
    uint256 _maxPerMonth
) external onlyOwner returns (uint256 tierId)
```
Create a new sponsorship tier.

---

### SetTimelock

Governance timelock controller.

#### Constants

| Name | Value | Description |
|------|-------|-------------|
| `MIN_DELAY_MAINNET` | 24 hours | Mainnet minimum delay |
| `MIN_DELAY_TESTNET` | 1 hour | Testnet minimum delay |
| `MIN_DELAY_DEVNET` | 5 minutes | Devnet minimum delay |

#### Functions

Standard OpenZeppelin TimelockController functions plus:

##### `scheduleWithDescription`
```solidity
function scheduleWithDescription(
    address target,
    uint256 value,
    bytes calldata data,
    bytes32 predecessor,
    bytes32 salt,
    uint256 delay,
    string calldata description
) external onlyRole(PROPOSER_ROLE)
```
Schedule operation with human-readable description.

---

### Stablecoin Contracts

#### ssUSD

Rebasing stablecoin token.

##### `balanceOf`
```solidity
function balanceOf(address account) external view returns (uint256)
```
Returns current balance including rebased yield.

##### `sharesOf`
```solidity
function sharesOf(address account) external view returns (uint256)
```
Returns internal share balance.

##### `getNavPerShare`
```solidity
function getNavPerShare() external view returns (uint256)
```
Returns current NAV per share (18 decimals).

---

#### wssUSD (ERC4626)

Non-rebasing wrapped ssUSD.

##### `wrap`
```solidity
function wrap(uint256 ssUSDAmount) external returns (uint256 wssUSDAmount)
```
Wrap ssUSD to wssUSD.

##### `unwrap`
```solidity
function unwrap(uint256 wssUSDAmount) external returns (uint256 ssUSDAmount)
```
Unwrap wssUSD to ssUSD.

##### `getSharePrice`
```solidity
function getSharePrice() external view returns (uint256)
```
Returns ssUSD per wssUSD share.

---

#### TreasuryVault

##### `deposit`
```solidity
function deposit(
    address collateralToken,
    uint256 amount,
    address recipient
) external returns (uint256 ssUSDMinted)
```
Deposit collateral and receive ssUSD.

**Events:**
```solidity
event Deposited(
    address indexed depositor,
    address indexed collateralToken,
    uint256 collateralAmount,
    uint256 ssUSDMinted
);
```

##### `requestRedemption`
```solidity
function requestRedemption(
    uint256 ssUSDAmount,
    address preferredCollateral
) external returns (uint256 requestId)
```
Request redemption of ssUSD.

**Events:**
```solidity
event RedemptionRequested(
    uint256 indexed requestId,
    address indexed requester,
    uint256 ssUSDAmount,
    address preferredCollateral
);
```

---

### MEV Protection Contracts

#### EncryptedMempool

##### `submitEncryptedTx`
```solidity
function submitEncryptedTx(
    bytes calldata encryptedPayload,
    uint256 epoch,
    uint256 gasLimit,
    uint256 maxFeePerGas
) external payable returns (bytes32 txId)
```
Submit an encrypted transaction.

| Parameter | Type | Description |
|-----------|------|-------------|
| `encryptedPayload` | bytes | Threshold-encrypted transaction |
| `epoch` | uint256 | Encryption epoch |
| `gasLimit` | uint256 | Gas limit (21000-10000000) |
| `maxFeePerGas` | uint256 | Max fee per gas |

**Requirements:**
- `msg.value >= gasLimit * maxFeePerGas`
- Any excess `msg.value` is reserved as `valueDeposit` to cover decrypted call value
- Valid epoch key must exist

##### `getEncryptedTx`
```solidity
function getEncryptedTx(bytes32 txId) external view returns (EncryptedTx memory)
```
Note: `EncryptedTx` includes a `valueDeposit` field reserved for the decrypted call value.

##### `getDecryptedTx`
```solidity
function getDecryptedTx(bytes32 txId) external view returns (DecryptedTx memory)
```

---

#### ThresholdKeyRegistry

##### `registerKeyper`
```solidity
function registerKeyper(
    bytes calldata pubKey,
    string calldata endpoint
) external payable
```
Register as a keyper with stake.

**Requirements:**
- `msg.value >= minStake`
- `pubKey` must be 48 bytes (BLS)
- Not already registered

##### `getCurrentPublicKey`
```solidity
function getCurrentPublicKey() external view returns (bytes memory)
```
Get current epoch's threshold public key.

##### `isEpochKeyValid`
```solidity
function isEpochKeyValid(uint256 epoch) external view returns (bool)
```
Check if an epoch key is valid for encryption.

---

#### SequencerAttestation

##### `commitOrdering`
```solidity
function commitOrdering(
    bytes32 blockHash,
    uint64 blockNumber,
    bytes32 txOrderingRoot,
    uint32 txCount,
    bytes calldata signature
) external
```
Commit to transaction ordering.

##### `verifyTxPosition`
```solidity
function verifyTxPosition(
    bytes32 blockHash,
    bytes32 txHash,
    uint256 position,
    bytes32[] calldata proof
) external returns (bool valid)
```
Verify a transaction's position in committed ordering.

---

#### ForcedInclusion

##### `forceTransaction`
```solidity
function forceTransaction(
    address target,
    bytes calldata data,
    uint256 gasLimit
) external payable returns (bytes32 txId)
```
Force transaction inclusion on L2.

| Parameter | Type | Description |
|-----------|------|-------------|
| `target` | address | Target contract |
| `data` | bytes | Call data |
| `gasLimit` | uint256 | Gas limit |

**Requirements:**
- `msg.value >= MIN_BOND` (0.01 ETH)
- `gasLimit <= MAX_GAS_LIMIT` (10M)

##### `confirmInclusion`
```solidity
function confirmInclusion(
    bytes32 txId,
    uint256 l2BlockNumber,
    bytes calldata proof
) external
```
Confirm transaction was included, return bond.

Note: `confirmInclusion` requires a tx root oracle to be configured via
`setTxRootOracle(address)` by the owner.

##### `claimExpired`
```solidity
function claimExpired(bytes32 txId) external
```
Claim bond for expired forced transaction (censorship detected).

---

## SDK Reference

### Installation

```bash
npm install @setchain/sdk ethers
```

### Configuration

```typescript
import { setConfig, NETWORK_PRESETS } from "@setchain/sdk";

// Use preset
setConfig(NETWORK_PRESETS.sepolia);

// Or custom
setConfig({
  gasBuffer: 1.3,
  transactionTimeout: 180000,
  maxRetries: 5,
  debug: true
});
```

### Core Functions

#### `createProvider`
```typescript
function createProvider(rpcUrl: string): JsonRpcProvider
```

#### `createWallet`
```typescript
function createWallet(privateKey: string, rpcUrl: string): Wallet
```

#### `getSetRegistry`
```typescript
function getSetRegistry(address: string, runner: Provider | Wallet): Contract
```

#### `getSetPaymaster`
```typescript
function getSetPaymaster(address: string, runner: Provider | Wallet): Contract
```

### Stablecoin Client

```typescript
import { stablecoin } from "@setchain/sdk";

const client = stablecoin.createStablecoinClient(addresses, privateKey, rpcUrl);

// Methods
await client.deposit(collateralToken, amount, recipient?);
await client.requestRedemption(ssUSDAmount, preferredCollateral);
await client.wrap(ssUSDAmount);
await client.unwrap(wssUSDAmount);
await client.getBalance(address);
await client.getFormattedBalance(address);
await client.getStats();
await client.getCurrentNAV();
```

### MEV Protection Client

```typescript
import { createMEVProtectionClient } from "@setchain/sdk";

const client = createMEVProtectionClient(
  mempoolAddress,
  keyRegistryAddress,
  privateKey,
  rpcUrl
);

// Methods
await client.isAvailable();
await client.getStatus();
await client.submit(to, data, value, options?);
await client.cancel(txId);
await client.getTransactionStatus(txId);
```

### Utilities

#### Validation
```typescript
validateAddress(address, name?): string        // throws on invalid
validateNonZeroAddress(address, name?): string
isValidAddress(address): boolean               // returns false on invalid
validatePositiveAmount(amount, name?): void
validateBytes32(value, name?): string
```

#### Formatting
```typescript
formatBalance(amount, decimals, options?): string
parseAmount(amount, decimals): bigint
formatETH(wei, options?): string
formatGas(gas): string
shortenAddress(address, chars?): string
formatDuration(seconds): string
```

#### Gas
```typescript
estimateGas(contract, functionName, args, options?): Promise<GasEstimate>
applyGasBuffer(gasLimit, buffer?): bigint
DEFAULT_GAS_LIMITS: { TRANSFER: 65000n, ... }
```

#### Retry
```typescript
withRetry(fn, options?): Promise<T>
withTimeout(fn, timeoutMs, operation?): Promise<T>
pollUntil(fn, options?): Promise<void>
```

#### Events
```typescript
findEvent(receipt, contract, eventName): ParsedEvent | null
findEventOrThrow(receipt, contract, eventName): ParsedEvent
extractEventArg(receipt, contract, eventName, argName): T | null
```

### Contract Helper Functions

#### TreasuryVault Helpers

```typescript
import { getTreasuryVault, fetchTreasuryVaultHealth, getCollateralBreakdown } from "@setchain/sdk";

// Create contract instance
const vault = getTreasuryVault(address, provider);

// Fetch vault health status
const health = await fetchTreasuryVaultHealth(vault);
// Returns: { collateralValue, ssUSDSupply, collateralizationRatio, isDepositsEnabled, isRedemptionsEnabled, pendingRedemptionsCount }

// Get collateral breakdown
const breakdown = await getCollateralBreakdown(vault);
// Returns: { tokens: string[], balances: bigint[], values: bigint[] }

// Get user summary
const summary = await getTreasuryUserSummary(vault, userAddress);
// Returns: { ssUSDBalance, pendingRedemptions, totalPendingValue, canDeposit, canRedeem }

// Check redemption status
const status = await getRedemptionStatus(vault, requestId);
// Returns: { isPending, isReady, isProcessed, canProcess, timeUntilReady }

// Get ready redemptions
const readyIds = await getReadyRedemptions(vault, 100);

// Batch operations
const balances = await batchGetCollateralBalances(vault, tokenAddresses);
const requests = await batchGetRedemptionRequests(vault, requestIds);
```

#### SetPaymaster Helpers

```typescript
import {
  getSetPaymaster,
  fetchPaymasterStatus,
  fetchBatchMerchantDetails,
  getPaymasterHealthSummary
} from "@setchain/sdk";

const paymaster = getSetPaymaster(address, provider);

// Get paymaster status
const status = await fetchPaymasterStatus(paymaster);
// Returns: { balance, totalSponsored, tierCount, treasury }

// Fetch all tiers
const tiers = await fetchAllTiers(paymaster);
// Returns: SponsorshipTier[]

// Get merchant details
const details = await fetchMerchantDetails(paymaster, merchant);
// Returns: { active, tierId, spentToday, spentThisMonth, totalSponsored }

// Batch merchant details
const batchDetails = await fetchBatchMerchantDetails(paymaster, merchants);

// Check sponsorability
const { canSponsor, reason } = await checkCanSponsor(paymaster, merchant, amount);

// Batch check sponsorability
const results = await batchCheckCanSponsor(paymaster, merchants, amounts);
// Returns: { canSponsor: boolean[], reasons: string[] }

// Get remaining allowances
const allowances = await fetchBatchRemainingAllowances(paymaster, merchants);

// Aggregate stats across merchants
const stats = await aggregateMerchantStats(paymaster, merchants);
// Returns: { totalMerchants, activeMerchants, totalSpent, avgSpentPerMerchant }

// Get total capacity
const capacity = await getTotalRemainingCapacity(paymaster, merchants);

// Find sponsorable merchants
const { sponsorable, nonSponsorable } = await findSponsorableMerchants(paymaster, merchants, amounts);

// Health summary
const health = await getPaymasterHealthSummary(paymaster);
// Returns: { ...status, tiers, isHealthy }

// Get merchant tier limits
const limits = await getMerchantTierLimits(paymaster, merchant);
// Returns: { maxPerTx, maxPerDay, maxPerMonth, tierName }
```

#### SetRegistry Helpers

```typescript
import {
  getSetRegistry,
  checkBatchExists,
  fetchRegistryStats,
  fetchBatchHeadSequences
} from "@setchain/sdk";

const registry = getSetRegistry(address, provider);

// Check if batch exists
const exists = await checkBatchExists(registry, batchId);

// Check if batch has proof
const hasProof = await checkBatchHasProof(registry, batchId);

// Check if registry is paused
const paused = await isRegistryPaused(registry);

// Get registry stats
const stats = await fetchRegistryStats(registry);
// Returns: { commitmentCount, proofCount, isPaused, isStrictMode }

// Get head sequences for tenant/store pairs
const sequences = await fetchBatchHeadSequences(registry, tenantIds, storeIds);
```

#### MEV Protection Helpers

```typescript
import {
  getEncryptedMempool,
  getForcedInclusion,
  getSequencerAttestation,
  fetchMempoolStatus,
  getMempoolHealthSummary,
  fetchForcedInclusionStatus,
  getForcedInclusionHealthSummary,
  fetchAttestationStats,
  getAttestationHealthSummary,
  verifyTxPosition
} from "@setchain/sdk";

// Encrypted Mempool
const mempool = getEncryptedMempool(address, provider);
const status = await fetchMempoolStatus(mempool);
// Returns: { pendingCount, queueCapacity, submitted, executed, failed, expired, isPaused, currentMaxQueueSize }

const mempoolHealth = await getMempoolHealthSummary(mempool);
// Returns: { isPaused, pendingCount, queueCapacity, successRate, isHealthy }

// Forced Inclusion (L1 censorship resistance)
const forcedInclusion = getForcedInclusion(address, provider);
const fiStatus = await fetchForcedInclusionStatus(forcedInclusion);
// Returns: { pendingCount, totalForced, totalIncluded, totalExpired, bondsLocked, isPaused, circuitBreakerCapacity }

const fiHealth = await getForcedInclusionHealthSummary(forcedInclusion);
// Returns: { isPaused, pendingCount, circuitBreakerCapacity, inclusionRate, bondsLocked, isHealthy }

// Sequencer Attestation (FCFS ordering verification)
const attestation = getSequencerAttestation(address, provider);
const attStats = await fetchAttestationStats(attestation);
// Returns: { totalCommitments, totalVerifications, failedVerifications, lastCommitmentTime }

// Verify transaction ordering
const isValid = await verifyTxPosition(attestation, blockHash, txHash, position, merkleProof);
```

#### System Health Check

```typescript
import {
  performSystemHealthCheck,
  formatHealthStatus,
  getSetRegistry,
  getSetPaymaster,
  getTreasuryVault,
  getNAVOracle,
  getEncryptedMempool,
  getForcedInclusion,
  getSequencerAttestation,
  getSetTimelock,
  getThresholdKeyRegistry
} from "@setchain/sdk";

// Create contract instances
const contracts = {
  registry: getSetRegistry(registryAddr, provider),
  paymaster: getSetPaymaster(paymasterAddr, provider),
  treasuryVault: getTreasuryVault(vaultAddr, provider),
  navOracle: getNAVOracle(oracleAddr, provider),
  mempool: getEncryptedMempool(mempoolAddr, provider),
  forcedInclusion: getForcedInclusion(fiAddr, provider),
  attestation: getSequencerAttestation(attAddr, provider),
  timelock: getSetTimelock(timelockAddr, provider),
  thresholdRegistry: getThresholdKeyRegistry(keyRegAddr, provider)
};

// Perform comprehensive health check
const health = await performSystemHealthCheck(contracts);
console.log(`Overall healthy: ${health.overallHealthy}`);
console.log(`Errors: ${health.errors.length}`);

// Get formatted status
const statusText = formatHealthStatus(health);
console.log(statusText);
// Output:
// System Health Check - 2024-01-15T10:30:00.000Z
// Overall: HEALTHY
//
// registry: OK
// paymaster: OK
// treasuryVault: OK
// ...
```

### Error Handling

```typescript
import { SDKError, SDKErrorCode, isSDKError, hasErrorCode } from "@setchain/sdk";

try {
  await client.deposit(token, amount);
} catch (error) {
  if (hasErrorCode(error, SDKErrorCode.INSUFFICIENT_BALANCE)) {
    console.log(error.suggestion); // "Need X more tokens"
  }
}
```

**Error Codes:**
| Code | Name | Description |
|------|------|-------------|
| SDK_1001 | INVALID_ADDRESS | Invalid Ethereum address |
| SDK_1002 | INVALID_AMOUNT | Invalid amount |
| SDK_2001 | INSUFFICIENT_BALANCE | Not enough tokens |
| SDK_2002 | INSUFFICIENT_ALLOWANCE | Need approval |
| SDK_3001 | NETWORK_ERROR | Network/RPC issue |
| SDK_3003 | TIMEOUT | Operation timeout |
| SDK_4001 | TRANSACTION_FAILED | TX failed |
| SDK_5002 | GAS_ESTIMATION_FAILED | Gas estimate failed |
| SDK_6001 | MEV_UNAVAILABLE | MEV protection unavailable |
| SDK_7002 | DEPOSITS_PAUSED | Deposits paused |
| SDK_7003 | REDEMPTIONS_PAUSED | Redemptions paused |

---

### Transaction Builder

High-level transaction builders with retry, simulation, and gas estimation.

#### TransactionBuilder Class

```typescript
import { TransactionBuilder, TxStatus, TxBuilderOptions } from "@setchain/sdk";

// Create builder with options
const builder = new TransactionBuilder(wallet, {
  maxRetries: 3,
  baseDelayMs: 1000,
  gasPriceMultiplier: 1.1,
  gasLimitMultiplier: 1.2,
  confirmations: 1,
  simulate: true,
  onStatusChange: (status, details) => console.log(status, details)
});

// Estimate gas
const { gasLimit, gasPrice, totalCost } = await builder.estimateGas(
  contract, 'methodName', [arg1, arg2], value
);

// Simulate (dry-run)
const { success, returnData, error } = await builder.simulate(
  contract, 'methodName', [arg1, arg2], value
);

// Execute with retry
const result = await builder.execute(contract, 'methodName', [arg1, arg2], value);
// Returns: { status, hash, receipt, gasUsed, gasPrice, totalCost, blockNumber }
```

**Transaction Statuses:**
| Status | Description |
|--------|-------------|
| `pending` | Transaction created, not yet sent |
| `simulating` | Running simulation |
| `estimating_gas` | Estimating gas costs |
| `sending` | Broadcasting transaction |
| `confirming` | Waiting for confirmations |
| `confirmed` | Transaction confirmed |
| `failed` | Transaction failed |
| `reverted` | Transaction reverted on-chain |

#### Flow Builders

Pre-built transaction sequences for common operations:

```typescript
import {
  executeDepositFlow,
  executeWrapFlow,
  executeUnwrapFlow,
  executeRedemptionRequestFlow,
  executeBatchSponsorFlow,
  executeCommitBatchFlow,
  executeEncryptedTxFlow,
  executeForcedInclusionFlow
} from "@setchain/sdk";

// Deposit collateral and mint ssUSD
const depositResult = await executeDepositFlow(
  wallet, treasuryVault, collateralToken, amount
);
// Returns: { success, steps[], totalGasUsed, totalCost }

// Wrap ssUSD to wssUSD
const wrapResult = await executeWrapFlow(wallet, wssUSD, ssUSD, amount);

// Unwrap wssUSD to ssUSD
const unwrapResult = await executeUnwrapFlow(wallet, wssUSD, shares);

// Request redemption
const redemptionResult = await executeRedemptionRequestFlow(
  wallet, treasuryVault, ssUSD, amount
);
// Returns: { success, steps[], requestId }

// Submit encrypted transaction
const encryptedResult = await executeEncryptedTxFlow(
  wallet, mempool, encryptedPayload, epoch, gasLimit, maxFeePerGas, valueDeposit
);
// Returns: { success, steps[], txId }

// Force transaction inclusion (L1)
const forcedResult = await executeForcedInclusionFlow(
  wallet, forcedInclusion, target, data, gasLimit, bond
);
// Returns: { success, steps[], txId, deadline }
```

#### Transaction Tracking

```typescript
import {
  TransactionTracker,
  createTransactionTracker,
  watchTransaction,
  speedUpTransaction,
  cancelTransaction,
  getNextNonce
} from "@setchain/sdk";

// Create tracker
const tracker = createTransactionTracker(provider, 2000); // 2s polling

// Track a transaction
const tracked = await tracker.track(txHash, { metadata: 'deposit' });

// Subscribe to events
const unsubscribe = tracker.on(txHash, (event) => {
  console.log(event.type, event.confirmations);
});

// Wait for confirmation
const confirmed = await tracker.waitForConfirmation(txHash, 2); // 2 confirmations

// Get pending transactions
const pending = tracker.getPending();

// Simple one-off watch
const receipt = await watchTransaction(provider, txHash, 1, 120000);

// Speed up stuck transaction
const newTxHash = await speedUpTransaction(wallet, originalTxHash, 1.5);

// Cancel pending transaction
const cancelHash = await cancelTransaction(wallet, originalTxHash, 1.5);

// Get next nonce (including pending)
const nonce = await getNextNonce(provider, address);
```

**Tracker Event Types:**
| Event | Description |
|-------|-------------|
| `submitted` | Transaction submitted for tracking |
| `confirmed` | First confirmation received |
| `confirmation` | Additional confirmation received |
| `failed` | Transaction failed |
| `dropped` | Transaction dropped from mempool |
| `replaced` | Transaction replaced (speedup/cancel) |

#### Gas Estimation Helpers

```typescript
import { estimateContractGas, simulateContractCall } from "@setchain/sdk";

// Detailed gas estimate
const estimate = await estimateContractGas(
  contract, 'methodName', [arg1], value, 1.2
);
// Returns: { gasLimit, gasPrice, maxFeePerGas, maxPriorityFeePerGas, totalCost, totalCostEth }

// Simulate with result
const sim = await simulateContractCall<ReturnType>(
  contract, 'methodName', [arg1], value
);
// Returns: { success, result, error, gasEstimate }
```

#### Event Parsing Helpers

```typescript
import { findEvent, findAllEvents, formatBalance } from "@setchain/sdk";

// Find single event
const event = findEvent(receipt, contract, 'Transfer');
// Returns: { name, args: { from, to, value }, log }

// Find all matching events
const events = findAllEvents(receipt, contract, 'Transfer');

// Format bigint balance
const formatted = formatBalance(BigInt('1000000000000000000'), 18);
// Returns: "1"
```

---

## Contract Addresses

### Sepolia Testnet (Chain ID: 84532001)

| Contract | Address |
|----------|---------|
| SetRegistry | `TBD after deployment` |
| SetPaymaster | `TBD after deployment` |
| SetTimelock | `TBD after deployment` |
| ssUSD | `TBD after deployment` |
| wssUSD | `TBD after deployment` |
| TreasuryVault | `TBD after deployment` |

### Local Devnet (Chain ID: 31337)

| Contract | Address |
|----------|---------|
| SetRegistry | Deployed by `scripts/dev.sh deploy` |
| SetPaymaster | Deployed by `scripts/dev.sh deploy` |

---

## Events Reference

### SetRegistry Events

```solidity
event BatchCommitted(bytes32 indexed batchId, bytes32 indexed tenantId, bytes32 indexed storeId, ...);
event StarkProofCommitted(bytes32 indexed batchId, bytes32 starkProofHash);
event SequencerAuthorizationChanged(address indexed sequencer, bool authorized);
event StrictModeChanged(bool enabled);
```

### SetPaymaster Events

```solidity
event MerchantSponsored(address indexed merchant, uint256 tierId);
event SponsorshipExecuted(address indexed merchant, uint256 amount, uint8 operationType);
event MerchantDeactivated(address indexed merchant);
event TierCreated(uint256 indexed tierId, string name);
event RefundIssued(address indexed merchant, uint256 amount);
```

### Stablecoin Events

```solidity
event Deposited(address indexed depositor, address indexed collateralToken, uint256 amount, uint256 ssUSDMinted);
event RedemptionRequested(uint256 indexed requestId, address indexed requester, uint256 ssUSDAmount, address preferredCollateral);
event RedemptionProcessed(uint256 indexed requestId, uint256 collateralAmount);
event Wrapped(address indexed user, uint256 ssUSDAmount, uint256 wssUSDAmount);
event Unwrapped(address indexed user, uint256 wssUSDAmount, uint256 ssUSDAmount);
event NAVUpdated(uint256 navPerShare, uint256 timestamp);
```

### MEV Events

```solidity
event EncryptedTxSubmitted(bytes32 indexed txId, address indexed sender, bytes32 payloadHash, uint256 epoch, uint256 gasLimit);
event OrderingCommitted(bytes32 indexed batchId, bytes32 orderingRoot, uint256 txCount);
event TxDecrypted(bytes32 indexed txId, address to, uint256 value);
event TxExecuted(bytes32 indexed txId, bool success);
event KeyperRegistered(address indexed keyper, bytes pubKey);
event DKGCompleted(uint256 indexed epoch, bytes aggregatedPubKey);
```
