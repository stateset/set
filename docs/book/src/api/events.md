# Events Reference

Complete reference of events emitted by Set Chain contracts.

## Event Indexing

All indexed parameters can be used for filtering:

```typescript
// Filter by indexed parameter
const filter = treasury.filters.Deposit(userAddress);
const events = await treasury.queryFilter(filter, fromBlock, toBlock);
```

## Core Events

### SetRegistry Events

#### BatchSubmitted

Emitted when a new batch commitment is submitted.

```solidity
event BatchSubmitted(
    uint256 indexed batchId,
    bytes32 indexed tenantId,
    bytes32 indexed storeId,
    bytes32 merkleRoot,
    uint32 eventCount
);
```

**Parameters:**
- `batchId`: Unique batch identifier
- `tenantId`: Tenant that owns the batch
- `storeId`: Store within the tenant
- `merkleRoot`: Merkle root of committed events
- `eventCount`: Number of events in batch

**Listening:**
```typescript
registry.on("BatchSubmitted", (batchId, tenantId, storeId, merkleRoot, eventCount) => {
    console.log(`Batch ${batchId} submitted`);
    console.log(`Events: ${eventCount}`);
    console.log(`Root: ${merkleRoot}`);
});
```

#### TenantRegistered

Emitted when a new tenant is registered.

```solidity
event TenantRegistered(
    bytes32 indexed tenantId,
    address indexed owner,
    string name
);
```

#### StoreCreated

Emitted when a new store is created.

```solidity
event StoreCreated(
    bytes32 indexed tenantId,
    bytes32 indexed storeId,
    string name
);
```

#### SubmitterAuthorized / SubmitterRevoked

```solidity
event SubmitterAuthorized(bytes32 indexed tenantId, address indexed submitter);
event SubmitterRevoked(bytes32 indexed tenantId, address indexed submitter);
```

### SetPaymaster Events

#### MerchantRegistered

```solidity
event MerchantRegistered(address indexed merchant, uint256 deposit);
```

#### GasSponsored

Emitted when gas is sponsored for a user.

```solidity
event GasSponsored(
    address indexed merchant,
    address indexed user,
    uint256 gasUsed,
    uint256 gasCost
);
```

**Listening:**
```typescript
paymaster.on("GasSponsored", (merchant, user, gasUsed, gasCost) => {
    console.log(`${merchant} sponsored ${gasUsed} gas for ${user}`);
    console.log(`Cost: ${formatEther(gasCost)} ETH`);
});
```

#### PolicyUpdated

```solidity
event PolicyUpdated(address indexed merchant, bytes32 policyHash);
```

### SetTimelock Events

#### OperationScheduled

Emitted when an operation is scheduled.

```solidity
event OperationScheduled(
    bytes32 indexed operationId,
    address indexed target,
    uint256 value,
    bytes data,
    uint256 delay,
    uint256 readyTimestamp
);
```

**Listening:**
```typescript
timelock.on("OperationScheduled", (opId, target, value, data, delay, readyAt) => {
    console.log(`Operation ${opId} scheduled`);
    console.log(`Target: ${target}`);
    console.log(`Ready at: ${new Date(Number(readyAt) * 1000)}`);

    // Decode the call
    const iface = new Interface(targetABI);
    const decoded = iface.parseTransaction({ data });
    console.log(`Function: ${decoded.name}(${decoded.args})`);
});
```

#### OperationExecuted

```solidity
event OperationExecuted(bytes32 indexed operationId);
```

#### OperationCancelled

```solidity
event OperationCancelled(bytes32 indexed operationId);
```

## Stablecoin Events

### ssUSD Events

#### Rebase

Emitted when NAV changes and balances rebase.

```solidity
event Rebase(
    uint256 oldNav,
    uint256 newNav,
    uint256 totalSupply
);
```

**Listening:**
```typescript
ssUSD.on("Rebase", (oldNav, newNav, totalSupply) => {
    const changePercent = Number((newNav - oldNav) * 10000n / oldNav) / 100;
    console.log(`Rebase: ${formatUnits(oldNav, 18)} → ${formatUnits(newNav, 18)}`);
    console.log(`Change: ${changePercent.toFixed(4)}%`);
    console.log(`New supply: ${formatUnits(totalSupply, 18)}`);
});
```

#### Transfer (ERC20)

Standard ERC20 transfer event.

```solidity
event Transfer(address indexed from, address indexed to, uint256 value);
```

**Note:** For ssUSD, `value` is in assets (USD), not shares.

### TreasuryVault Events

#### Deposit

Emitted when collateral is deposited.

```solidity
event Deposit(
    address indexed user,
    address indexed token,
    uint256 amount,
    uint256 ssUSDMinted
);
```

**Listening:**
```typescript
treasury.on("Deposit", (user, token, amount, ssUSDMinted) => {
    // Get token info for proper formatting
    const decimals = token === USDC ? 6 : 6;  // Both USDC/USDT are 6

    console.log(`Deposit by ${user}`);
    console.log(`Token: ${token}`);
    console.log(`Amount: ${formatUnits(amount, decimals)}`);
    console.log(`ssUSD Minted: ${formatUnits(ssUSDMinted, 18)}`);
});
```

#### Redemption

Emitted when ssUSD is redeemed for collateral.

```solidity
event Redemption(
    address indexed user,
    address indexed token,
    uint256 ssUSDBurned,
    uint256 amountRedeemed
);
```

#### DepositsPaused / DepositsUnpaused

```solidity
event DepositsPaused(address indexed by);
event DepositsUnpaused(address indexed by);
```

#### RedemptionsPaused / RedemptionsUnpaused

```solidity
event RedemptionsPaused(address indexed by);
event RedemptionsUnpaused(address indexed by);
```

### NAVOracle Events

#### NAVUpdated

Emitted when a new NAV attestation is submitted.

```solidity
event NAVUpdated(
    uint256 indexed reportId,
    uint256 nav,
    uint256 totalAssets,
    uint256 totalShares,
    uint256 timestamp
);
```

**Listening:**
```typescript
navOracle.on("NAVUpdated", (reportId, nav, totalAssets, totalShares, timestamp) => {
    console.log(`NAV Report #${reportId}`);
    console.log(`NAV: $${formatUnits(nav, 18)}`);
    console.log(`Total Assets: $${formatUnits(totalAssets, 18)}`);
    console.log(`Updated: ${new Date(Number(timestamp) * 1000)}`);

    // Calculate implied APY
    // ...
});
```

#### AttestorUpdated

```solidity
event AttestorUpdated(address indexed oldAttestor, address indexed newAttestor);
```

### TokenRegistry Events

#### TokenRegistered

```solidity
event TokenRegistered(address indexed token, TokenInfo info);
```

#### TokenUpdated

```solidity
event TokenUpdated(address indexed token, TokenInfo info);
```

#### TokenRemoved

```solidity
event TokenRemoved(address indexed token);
```

### wssUSD Events

Standard ERC-4626 events:

```solidity
event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
```

## MEV Protection Events

### EncryptedMempool Events

#### TransactionSubmitted

```solidity
event TransactionSubmitted(
    bytes32 indexed txId,
    address indexed sender,
    bytes encryptedPayload,
    uint256 gasLimit,
    uint256 submitBlock
);
```

#### TransactionDecrypted

```solidity
event TransactionDecrypted(
    bytes32 indexed txId,
    address target,
    bytes data,
    uint256 value
);
```

#### TransactionExecuted

```solidity
event TransactionExecuted(
    bytes32 indexed txId,
    bool success,
    bytes returnData
);
```

### SequencerAttestation Events

#### OrderingCommitted

```solidity
event OrderingCommitted(
    uint256 indexed blockNumber,
    bytes32 txOrderingRoot,
    uint32 txCount,
    bytes signature
);
```

### ForcedInclusion Events

#### TransactionForced

```solidity
event TransactionForced(
    bytes32 indexed txId,
    address indexed sender,
    address target,
    bytes data,
    uint256 gasLimit,
    uint256 deadline
);
```

#### TransactionIncluded

```solidity
event TransactionIncluded(bytes32 indexed txId, uint256 l2BlockNumber);
```

#### TransactionExpired

```solidity
event TransactionExpired(bytes32 indexed txId);
```

#### BondClaimed

```solidity
event BondClaimed(bytes32 indexed txId, address indexed claimer, uint256 amount);
```

## Event Querying

### Historical Queries

```typescript
// Query past events
const fromBlock = 1000000;
const toBlock = "latest";

// All deposits
const deposits = await treasury.queryFilter(
    treasury.filters.Deposit(),
    fromBlock,
    toBlock
);

// Deposits by specific user
const userDeposits = await treasury.queryFilter(
    treasury.filters.Deposit(userAddress),
    fromBlock,
    toBlock
);

// Process events
for (const event of deposits) {
    console.log(`Block ${event.blockNumber}: ${event.args.user} deposited ${event.args.amount}`);
}
```

### Pagination

```typescript
async function getDepositsWithPagination(fromBlock: number, pageSize = 10000) {
    const latestBlock = await provider.getBlockNumber();
    const allDeposits = [];

    for (let start = fromBlock; start < latestBlock; start += pageSize) {
        const end = Math.min(start + pageSize - 1, latestBlock);
        const deposits = await treasury.queryFilter(
            treasury.filters.Deposit(),
            start,
            end
        );
        allDeposits.push(...deposits);
    }

    return allDeposits;
}
```

### Event Subscription

```typescript
// Use WebSocket provider for subscriptions
const wsProvider = new WebSocketProvider("wss://ws.testnet.setchain.io");
const treasury = new Contract(TREASURY_ADDRESS, TreasuryVaultABI, wsProvider);

// Subscribe to all events
treasury.on("*", (event) => {
    console.log(`Event: ${event.eventName}`);
    console.log(`Args:`, event.args);
});

// Cleanup
process.on("SIGINT", () => {
    treasury.removeAllListeners();
    wsProvider.destroy();
});
```

## Related

- [Contract ABIs](./abis.md)
- [Error Codes](./error-codes.md)
- [Monitoring Guide](../operations/monitoring.md)
