# SetPaymaster

The gas sponsorship contract enabling merchants to pay transaction fees on behalf of customers.

## Overview

SetPaymaster implements ERC-4337 compatible gas sponsorship, allowing merchants to:

- Sponsor gas for customer transactions
- Set spending limits and policies
- Whitelist specific contract interactions
- Track gas usage per customer

## Contract Interface

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISetPaymaster {
    // Events
    event MerchantRegistered(address indexed merchant, uint256 deposit);
    event MerchantDeposit(address indexed merchant, uint256 amount);
    event MerchantWithdrawal(address indexed merchant, uint256 amount);
    event GasSponsored(
        address indexed merchant,
        address indexed user,
        uint256 gasUsed,
        uint256 gasCost
    );
    event PolicyUpdated(address indexed merchant, bytes32 policyHash);

    // Merchant Management
    function registerMerchant() external payable;
    function depositFunds() external payable;
    function withdrawFunds(uint256 amount) external;
    function getMerchantBalance(address merchant) external view returns (uint256);

    // Policy Management
    function setPolicy(SponsorshipPolicy calldata policy) external;
    function getPolicy(address merchant) external view returns (SponsorshipPolicy memory);

    // Sponsorship
    function willSponsor(
        address merchant,
        address user,
        address target,
        bytes calldata data
    ) external view returns (bool);

    function recordSponsorship(
        address merchant,
        address user,
        uint256 gasUsed
    ) external;

    // Queries
    function getUsage(address merchant, address user) external view returns (UserUsage memory);
    function getTotalSponsored(address merchant) external view returns (uint256);
}

struct SponsorshipPolicy {
    uint256 maxGasPerTx;        // Maximum gas per transaction
    uint256 maxGasPerUser;      // Maximum gas per user (daily)
    uint256 maxTotalGas;        // Maximum total gas (daily)
    address[] allowedTargets;   // Whitelisted contracts
    bytes4[] allowedSelectors;  // Whitelisted function selectors
    bool requireWhitelist;      // If true, only allowed targets/selectors
}

struct UserUsage {
    uint256 totalGasUsed;
    uint256 transactionCount;
    uint256 lastResetTimestamp;
}
```

## Functions

### registerMerchant

Register as a merchant with initial deposit.

```solidity
function registerMerchant() external payable;
```

**Requirements:**
- `msg.value >= MIN_DEPOSIT` (0.1 ETH)
- Caller not already registered

**Example:**
```typescript
const tx = await paymaster.registerMerchant({
    value: parseEther("1.0")
});
await tx.wait();
```

### depositFunds

Add funds to merchant balance.

```solidity
function depositFunds() external payable;
```

**Requirements:**
- Caller must be registered merchant
- `msg.value > 0`

**Example:**
```typescript
const tx = await paymaster.depositFunds({
    value: parseEther("0.5")
});
```

### withdrawFunds

Withdraw funds from merchant balance.

```solidity
function withdrawFunds(uint256 amount) external;
```

**Parameters:**
- `amount`: Amount to withdraw in wei

**Requirements:**
- Caller must be registered merchant
- `amount <= merchantBalance`

**Example:**
```typescript
const tx = await paymaster.withdrawFunds(parseEther("0.25"));
```

### setPolicy

Configure sponsorship policy.

```solidity
function setPolicy(SponsorshipPolicy calldata policy) external;
```

**Parameters:**
- `policy`: Sponsorship policy struct

**Requirements:**
- Caller must be registered merchant

**Example:**
```typescript
const policy = {
    maxGasPerTx: 500000n,
    maxGasPerUser: 2000000n,  // Daily limit per user
    maxTotalGas: 100000000n,   // Daily total limit
    allowedTargets: [ssUSDAddress, wssUSDAddress],
    allowedSelectors: [
        "0xa9059cbb", // transfer
        "0x095ea7b3", // approve
        "0x23b872dd"  // transferFrom
    ],
    requireWhitelist: true
};

const tx = await paymaster.setPolicy(policy);
```

### willSponsor

Check if merchant will sponsor a transaction.

```solidity
function willSponsor(
    address merchant,
    address user,
    address target,
    bytes calldata data
) external view returns (bool);
```

**Parameters:**
- `merchant`: Merchant address
- `user`: User address
- `target`: Target contract
- `data`: Transaction calldata

**Returns:** `true` if transaction will be sponsored

**Example:**
```typescript
const willSponsor = await paymaster.willSponsor(
    merchantAddress,
    userAddress,
    ssUSDAddress,
    transferCalldata
);

if (willSponsor) {
    // Submit as sponsored transaction
}
```

### getMerchantBalance

Get merchant's available balance.

```solidity
function getMerchantBalance(address merchant) external view returns (uint256);
```

**Returns:** Balance in wei

### getUsage

Get user's gas usage under a merchant.

```solidity
function getUsage(address merchant, address user) external view returns (UserUsage memory);
```

**Returns:** UserUsage struct with gas statistics

## Events

### GasSponsored

Emitted when gas is sponsored for a user transaction.

```solidity
event GasSponsored(
    address indexed merchant,
    address indexed user,
    uint256 gasUsed,
    uint256 gasCost
);
```

**Example listener:**
```typescript
paymaster.on("GasSponsored", (merchant, user, gasUsed, gasCost, event) => {
    console.log(`Merchant ${merchant} sponsored ${gasUsed} gas for ${user}`);
    console.log(`Cost: ${formatEther(gasCost)} ETH`);
});
```

## Integration Guide

### Setting Up Gas Sponsorship

```typescript
import { Contract, Wallet, parseEther } from "ethers";
import { SetPaymasterABI } from "@setchain/sdk";

// Connect as merchant
const merchant = new Wallet(MERCHANT_KEY, provider);
const paymaster = new Contract(PAYMASTER_ADDRESS, SetPaymasterABI, merchant);

// 1. Register merchant
await paymaster.registerMerchant({ value: parseEther("1.0") });

// 2. Set sponsorship policy
await paymaster.setPolicy({
    maxGasPerTx: 500000n,
    maxGasPerUser: 5000000n,
    maxTotalGas: 500000000n,
    allowedTargets: [SSUSD_ADDRESS],
    allowedSelectors: ["0xa9059cbb"], // transfer only
    requireWhitelist: true
});

console.log("Gas sponsorship configured");
```

### User Transaction Flow

```typescript
// User wants to transfer ssUSD
const userTx = {
    to: ssUSDAddress,
    data: ssUSD.interface.encodeFunctionData("transfer", [
        recipientAddress,
        parseUnits("100", 18)
    ])
};

// Check if merchant will sponsor
const willSponsor = await paymaster.willSponsor(
    merchantAddress,
    userAddress,
    userTx.to,
    userTx.data
);

if (willSponsor) {
    // Submit via ERC-4337 bundler with paymaster
    const userOp = await buildUserOperation(userTx, {
        paymaster: PAYMASTER_ADDRESS,
        paymasterData: encodeMerchantData(merchantAddress)
    });

    await bundler.sendUserOperation(userOp);
} else {
    // User pays own gas
    await user.sendTransaction(userTx);
}
```

### Monitoring Usage

```typescript
// Get merchant stats
const balance = await paymaster.getMerchantBalance(merchantAddress);
const totalSponsored = await paymaster.getTotalSponsored(merchantAddress);

console.log(`Balance: ${formatEther(balance)} ETH`);
console.log(`Total sponsored: ${totalSponsored} gas units`);

// Get user usage
const usage = await paymaster.getUsage(merchantAddress, userAddress);
console.log(`User gas used today: ${usage.totalGasUsed}`);
console.log(`Transactions: ${usage.transactionCount}`);
```

## Policy Configuration

### Conservative Policy

```typescript
const conservativePolicy = {
    maxGasPerTx: 100000n,      // Low per-tx limit
    maxGasPerUser: 500000n,    // Low daily user limit
    maxTotalGas: 10000000n,    // Low daily total
    allowedTargets: [ssUSDAddress],
    allowedSelectors: ["0xa9059cbb"], // Only transfers
    requireWhitelist: true
};
```

### Generous Policy

```typescript
const generousPolicy = {
    maxGasPerTx: 1000000n,     // High per-tx limit
    maxGasPerUser: 10000000n,  // High daily user limit
    maxTotalGas: 1000000000n,  // High daily total
    allowedTargets: [],
    allowedSelectors: [],
    requireWhitelist: false    // Any transaction
};
```

### Selective Policy

```typescript
const selectivePolicy = {
    maxGasPerTx: 500000n,
    maxGasPerUser: 2000000n,
    maxTotalGas: 100000000n,
    allowedTargets: [ssUSDAddress, wssUSDAddress, treasuryAddress],
    allowedSelectors: [
        "0xa9059cbb", // transfer
        "0x095ea7b3", // approve
        "0xb6b55f25", // deposit
        "0x2e1a7d4d"  // withdraw
    ],
    requireWhitelist: true
};
```

## Security Considerations

### Rate Limiting

The daily limits (`maxGasPerUser`, `maxTotalGas`) reset at midnight UTC:

```solidity
function _shouldReset(UserUsage storage usage) internal view returns (bool) {
    return block.timestamp >= usage.lastResetTimestamp + 1 days;
}
```

### Fund Protection

- Merchants can only withdraw their own deposited funds
- Minimum deposit requirement prevents spam registrations
- Automatic balance checks before sponsorship

### Policy Validation

- Empty `allowedTargets` with `requireWhitelist = true` blocks all transactions
- Selector validation uses first 4 bytes of calldata
- Policy changes take effect immediately

## Batch Operations

SetPaymaster supports efficient batch operations for managing multiple merchants:

### Batch Sponsor Merchants

```typescript
// Sponsor multiple merchants at once
const merchants = [merchant1, merchant2, merchant3];
const tierIds = [0n, 1n, 2n];  // Different tiers

await paymaster.batchSponsorMerchants(merchants, tierIds);
```

### Batch Execute Sponsorship

```typescript
// Execute sponsorship for multiple merchants
const { succeeded, failed } = await paymaster.batchExecuteSponsorship(
    [merchant1, merchant2, merchant3],
    [amount1, amount2, amount3],
    [OperationType.ORDER_CREATE, OperationType.PAYMENT_PROCESS, OperationType.INVENTORY_UPDATE]
);

console.log(`${succeeded} succeeded, ${failed} failed`);
```

### Batch Query Functions

```typescript
// Check status for multiple merchants
const { statuses, tiers } = await paymaster.batchGetMerchantStatus(merchants);

// Check if multiple merchants can be sponsored
const { canSponsor, reasons } = await paymaster.batchCanSponsor(merchants, amounts);

// Get remaining allowances for multiple merchants
const allowances = await paymaster.batchGetRemainingDailyAllowance(merchants);

// Get comprehensive details
const { active, tierIds, spentToday, spentThisMonth, totalSponsored } =
    await paymaster.batchGetMerchantDetails(merchants);
```

### Batch Update Tier

```typescript
// Update tier for multiple merchants
await paymaster.batchUpdateMerchantTier(merchants, newTierId);
```

### Batch Limits

| Parameter | Value | Description |
|-----------|-------|-------------|
| MAX_BATCH_SIZE | 100 | Maximum merchants per batch |

## Monitoring

### Paymaster Status

```typescript
const {
    balance,
    totalSponsored,
    tierCount,
    treasury
} = await paymaster.getPaymasterStatus();

console.log(`Balance: ${formatEther(balance)} ETH`);
console.log(`Total sponsored: ${totalSponsored} gas units`);
```

### Get All Tiers

```typescript
const tiers = await paymaster.getAllTiers();

for (const tier of tiers) {
    console.log(`Tier ${tier.tierId}: ${tier.name}`);
    console.log(`  Max/tx: ${formatEther(tier.maxPerTx)} ETH`);
    console.log(`  Max/day: ${formatEther(tier.maxPerDay)} ETH`);
    console.log(`  Max/month: ${formatEther(tier.maxPerMonth)} ETH`);
}
```

## Error Codes

| Error | Description |
|-------|-------------|
| `NotRegistered()` | Caller is not a registered merchant |
| `AlreadyRegistered()` | Merchant already registered |
| `InsufficientDeposit()` | Deposit below minimum |
| `InsufficientBalance()` | Not enough balance for withdrawal |
| `PolicyViolation()` | Transaction violates sponsorship policy |
| `DailyLimitExceeded()` | User or total daily limit exceeded |
| `InvalidTarget()` | Target contract not whitelisted |
| `InvalidSelector()` | Function selector not whitelisted |
| `InvalidAddress()` | Zero address provided |
| `ArrayLengthMismatch()` | Batch arrays have different lengths |
| `BatchTooLarge()` | Batch exceeds MAX_BATCH_SIZE |
| `EmptyArray()` | Empty array provided to batch function |

## Related

- [SetRegistry](./set-registry.md) - Core registry contract
- [SetTimelock](./set-timelock.md) - Governance timelock
- [Gas Sponsorship Guide](../operations/gas-sponsorship.md) - Operational guide
