# Stablecoin Client

Complete guide to using the StablecoinClient for ssUSD operations.

## Overview

The StablecoinClient provides a high-level API for interacting with the ssUSD stablecoin system:

- Deposit collateral and mint ssUSD
- Check balances and NAV
- Wrap/unwrap between ssUSD and wssUSD
- Redeem ssUSD for collateral

## Creating a Client

### With Private Key

```typescript
import { stablecoin } from "@setchain/sdk";

const addresses = {
    tokenRegistry: "0x...",
    navOracle: "0x...",
    ssUSD: "0x...",
    wssUSD: "0x...",
    treasury: "0x..."
};

const client = stablecoin.createStablecoinClient(
    addresses,
    process.env.PRIVATE_KEY,
    "https://rpc.testnet.setchain.io"
);
```

### With Signer (Browser)

```typescript
import { stablecoin } from "@setchain/sdk";
import { BrowserProvider } from "ethers";

const provider = new BrowserProvider(window.ethereum);
const signer = await provider.getSigner();

const client = new stablecoin.StablecoinClient(addresses, signer);
```

### With Provider (Read-Only)

```typescript
import { stablecoin } from "@setchain/sdk";
import { JsonRpcProvider } from "ethers";

const provider = new JsonRpcProvider("https://rpc.testnet.setchain.io");
const client = new stablecoin.StablecoinClient(addresses, provider);

// Can only call view methods
const balance = await client.getBalance(userAddress);
```

## Methods

### getBalance

Get user's complete balance information.

```typescript
async getBalance(address: string): Promise<UserBalance>

interface UserBalance {
    ssUSD: bigint;        // ssUSD balance (18 decimals)
    ssUSDShares: bigint;  // Underlying shares
    wssUSD: bigint;       // wssUSD balance (18 decimals)
}
```

**Example:**
```typescript
const balance = await client.getBalance(userAddress);

console.log(`ssUSD: ${formatUnits(balance.ssUSD, 18)}`);
console.log(`Shares: ${balance.ssUSDShares}`);
console.log(`wssUSD: ${formatUnits(balance.wssUSD, 18)}`);
```

### getStats

Get system-wide stablecoin statistics.

```typescript
async getStats(): Promise<StablecoinStats>

interface StablecoinStats {
    totalSupply: bigint;       // Total ssUSD supply
    totalShares: bigint;       // Total shares
    nav: bigint;               // Current NAV (18 decimals)
    totalAssets: bigint;       // Total backing assets
    lastNavUpdate: number;     // Timestamp of last NAV update
    isNavStale: boolean;       // Whether NAV is stale
    depositsPaused: boolean;   // Deposits paused?
    redemptionsPaused: boolean;// Redemptions paused?
}
```

**Example:**
```typescript
const stats = await client.getStats();

console.log(`Total Supply: ${formatUnits(stats.totalSupply, 18)} ssUSD`);
console.log(`NAV: $${formatUnits(stats.nav, 18)}`);
console.log(`APY: ${calculateAPY(stats.nav)}%`);

if (stats.isNavStale) {
    console.warn("NAV data is stale!");
}
```

### getNAVReport

Get the latest NAV attestation report.

```typescript
async getNAVReport(): Promise<NAVReport>

interface NAVReport {
    reportId: bigint;
    nav: bigint;
    totalAssets: bigint;
    totalShares: bigint;
    timestamp: number;
    proofHash: string;
}
```

**Example:**
```typescript
const report = await client.getNAVReport();

console.log(`Report #${report.reportId}`);
console.log(`NAV: $${formatUnits(report.nav, 18)}`);
console.log(`Total Assets: $${formatUnits(report.totalAssets, 18)}`);
console.log(`Updated: ${new Date(report.timestamp * 1000)}`);
```

### deposit

Deposit collateral to mint ssUSD.

```typescript
async deposit(
    token: string,
    amount: bigint,
    options?: DepositOptions
): Promise<DepositResult>

interface DepositOptions {
    minSsUSD?: bigint;      // Minimum ssUSD to receive
    recipient?: string;      // Recipient address (default: sender)
    gasLimit?: bigint;       // Override gas limit
}

interface DepositResult {
    txHash: string;
    ssUSDMinted: bigint;
    sharesReceived: bigint;
    effectiveNav: bigint;
    gasUsed: bigint;
}
```

**Example:**
```typescript
import { parseUnits } from "ethers";

// Deposit 1000 USDC
const USDC = "0x...";
const amount = parseUnits("1000", 6);

// Preview first
const preview = await client.previewDeposit(USDC, amount);
console.log(`Will receive: ~${formatUnits(preview, 18)} ssUSD`);

// Execute with 1% slippage protection
const minSsUSD = preview * 99n / 100n;
const result = await client.deposit(USDC, amount, { minSsUSD });

console.log(`Minted: ${formatUnits(result.ssUSDMinted, 18)} ssUSD`);
console.log(`Tx: ${result.txHash}`);
```

### previewDeposit

Preview expected ssUSD from deposit (no transaction).

```typescript
async previewDeposit(token: string, amount: bigint): Promise<bigint>
```

**Example:**
```typescript
const expectedSsUSD = await client.previewDeposit(USDC, parseUnits("500", 6));
console.log(`Expected: ${formatUnits(expectedSsUSD, 18)} ssUSD`);
```

### redeem

Redeem ssUSD for collateral.

```typescript
async redeem(
    token: string,
    ssUSDAmount: bigint,
    options?: RedeemOptions
): Promise<RedemptionResult>

interface RedeemOptions {
    minTokens?: bigint;     // Minimum tokens to receive
    recipient?: string;     // Recipient address
    gasLimit?: bigint;
}

interface RedemptionResult {
    txHash: string;
    ssUSDBurned: bigint;
    tokensReceived: bigint;
    feeAmount: bigint;
    gasUsed: bigint;
}
```

**Example:**
```typescript
// Redeem 500 ssUSD for USDC
const ssUSDAmount = parseUnits("500", 18);

// Preview
const preview = await client.previewRedeem(USDC, ssUSDAmount);
console.log(`Will receive: ~${formatUnits(preview, 6)} USDC`);

// Execute
const result = await client.redeem(USDC, ssUSDAmount, {
    minTokens: preview * 99n / 100n
});

console.log(`Received: ${formatUnits(result.tokensReceived, 6)} USDC`);
console.log(`Fee: ${formatUnits(result.feeAmount, 6)} USDC`);
```

### previewRedeem

Preview expected tokens from redemption.

```typescript
async previewRedeem(token: string, ssUSDAmount: bigint): Promise<bigint>
```

### wrap

Wrap ssUSD to wssUSD.

```typescript
async wrap(amount: bigint, options?: WrapOptions): Promise<WrapResult>

interface WrapOptions {
    recipient?: string;
    gasLimit?: bigint;
}

interface WrapResult {
    txHash: string;
    ssUSDDeposited: bigint;
    wssUSDReceived: bigint;
    exchangeRate: bigint;   // wssUSD per ssUSD
    gasUsed: bigint;
}
```

**Example:**
```typescript
// Wrap 100 ssUSD
const result = await client.wrap(parseUnits("100", 18));

console.log(`Wrapped: ${formatUnits(result.ssUSDDeposited, 18)} ssUSD`);
console.log(`Received: ${formatUnits(result.wssUSDReceived, 18)} wssUSD`);
console.log(`Rate: 1 ssUSD = ${formatUnits(result.exchangeRate, 18)} wssUSD`);
```

### unwrap

Unwrap wssUSD to ssUSD.

```typescript
async unwrap(shares: bigint, options?: UnwrapOptions): Promise<UnwrapResult>

interface UnwrapOptions {
    recipient?: string;
    gasLimit?: bigint;
}

interface UnwrapResult {
    txHash: string;
    wssUSDBurned: bigint;
    ssUSDReceived: bigint;
    exchangeRate: bigint;
    gasUsed: bigint;
}
```

**Example:**
```typescript
// Unwrap all wssUSD
const balance = await client.getBalance(userAddress);
const result = await client.unwrap(balance.wssUSD);

console.log(`Unwrapped: ${formatUnits(result.wssUSDBurned, 18)} wssUSD`);
console.log(`Received: ${formatUnits(result.ssUSDReceived, 18)} ssUSD`);
```

### getApprovedTokens

Get list of approved collateral tokens.

```typescript
async getApprovedTokens(): Promise<TokenInfo[]>

interface TokenInfo {
    address: string;
    symbol: string;
    decimals: number;
    depositCap: bigint;
    currentDeposits: bigint;
    depositEnabled: boolean;
    redemptionEnabled: boolean;
}
```

**Example:**
```typescript
const tokens = await client.getApprovedTokens();

for (const token of tokens) {
    const utilization = Number(token.currentDeposits * 100n / token.depositCap);
    console.log(`${token.symbol}: ${utilization}% utilized`);
    console.log(`  Deposits: ${token.depositEnabled ? "Enabled" : "Disabled"}`);
    console.log(`  Redemptions: ${token.redemptionEnabled ? "Enabled" : "Disabled"}`);
}
```

### approve

Approve token spending for deposits.

```typescript
async approve(token: string, amount: bigint): Promise<string>
```

**Example:**
```typescript
// Approve max for convenience
const MAX_UINT256 = 2n ** 256n - 1n;
const txHash = await client.approve(USDC, MAX_UINT256);
console.log(`Approved: ${txHash}`);
```

### getAllowance

Check current approval amount.

```typescript
async getAllowance(token: string, owner: string): Promise<bigint>
```

**Example:**
```typescript
const allowance = await client.getAllowance(USDC, userAddress);

if (allowance < depositAmount) {
    await client.approve(USDC, depositAmount);
}
```

## Events

### Listening to Events

```typescript
// Deposit events
client.on("Deposit", (user, token, amount, ssUSDMinted) => {
    console.log(`${user} deposited ${formatUnits(amount, 6)} ${token}`);
    console.log(`Received ${formatUnits(ssUSDMinted, 18)} ssUSD`);
});

// Redemption events
client.on("Redemption", (user, token, ssUSDBurned, amountReceived) => {
    console.log(`${user} redeemed ${formatUnits(ssUSDBurned, 18)} ssUSD`);
    console.log(`Received ${formatUnits(amountReceived, 6)} ${token}`);
});

// NAV update events
client.on("NAVUpdated", (reportId, nav, totalAssets, totalShares) => {
    console.log(`NAV updated to $${formatUnits(nav, 18)}`);
});
```

### Removing Listeners

```typescript
const handler = (user, token, amount, ssUSDMinted) => {
    // ...
};

client.on("Deposit", handler);
// Later...
client.off("Deposit", handler);
```

## Complete Example

```typescript
import { stablecoin, formatBalance } from "@setchain/sdk";
import { parseUnits, formatUnits } from "ethers";

async function main() {
    // Create client
    const client = stablecoin.createStablecoinClient(
        addresses,
        process.env.PRIVATE_KEY,
        "https://rpc.testnet.setchain.io"
    );

    // Check system status
    const stats = await client.getStats();
    console.log("=== System Status ===");
    console.log(`NAV: $${formatUnits(stats.nav, 18)}`);
    console.log(`Total Supply: ${formatUnits(stats.totalSupply, 18)} ssUSD`);
    console.log(`Deposits Paused: ${stats.depositsPaused}`);

    if (stats.isNavStale) {
        console.error("Cannot proceed - NAV is stale");
        return;
    }

    // Check available tokens
    const tokens = await client.getApprovedTokens();
    const usdc = tokens.find(t => t.symbol === "USDC");

    if (!usdc?.depositEnabled) {
        console.error("USDC deposits not enabled");
        return;
    }

    // Check initial balance
    const userAddress = await client.getSignerAddress();
    let balance = await client.getBalance(userAddress);
    console.log(`\n=== Initial Balance ===`);
    console.log(`ssUSD: ${formatUnits(balance.ssUSD, 18)}`);
    console.log(`wssUSD: ${formatUnits(balance.wssUSD, 18)}`);

    // Deposit 1000 USDC
    console.log(`\n=== Depositing 1000 USDC ===`);
    const depositAmount = parseUnits("1000", 6);

    // Approve if needed
    const allowance = await client.getAllowance(usdc.address, userAddress);
    if (allowance < depositAmount) {
        console.log("Approving USDC...");
        await client.approve(usdc.address, depositAmount);
    }

    // Preview and deposit
    const preview = await client.previewDeposit(usdc.address, depositAmount);
    console.log(`Expected: ${formatUnits(preview, 18)} ssUSD`);

    const depositResult = await client.deposit(usdc.address, depositAmount, {
        minSsUSD: preview * 99n / 100n
    });
    console.log(`Minted: ${formatUnits(depositResult.ssUSDMinted, 18)} ssUSD`);
    console.log(`Tx: ${depositResult.txHash}`);

    // Wrap half for DeFi
    console.log(`\n=== Wrapping 500 ssUSD ===`);
    const wrapResult = await client.wrap(parseUnits("500", 18));
    console.log(`Received: ${formatUnits(wrapResult.wssUSDReceived, 18)} wssUSD`);

    // Final balance
    balance = await client.getBalance(userAddress);
    console.log(`\n=== Final Balance ===`);
    console.log(`ssUSD: ${formatUnits(balance.ssUSD, 18)}`);
    console.log(`wssUSD: ${formatUnits(balance.wssUSD, 18)}`);
}

main().catch(console.error);
```

## Error Handling

```typescript
import {
    isSDKError,
    DepositsPausedError,
    NAVStaleError,
    InsufficientBalanceError
} from "@setchain/sdk";

try {
    await client.deposit(USDC, amount);
} catch (error) {
    if (isSDKError(error)) {
        if (error instanceof DepositsPausedError) {
            console.error("Deposits are currently paused");
        } else if (error instanceof NAVStaleError) {
            console.error("NAV data is stale - try again later");
        } else if (error instanceof InsufficientBalanceError) {
            console.error(`Insufficient balance: need ${error.required}, have ${error.available}`);
        } else {
            console.error(`SDK Error [${error.code}]: ${error.message}`);
        }
    } else {
        throw error;
    }
}
```

## Related

- [SDK Installation](./installation.md)
- [Error Handling](./errors.md)
- [Utilities](./utilities.md)
- [ssUSD Overview](../stablecoin/overview.md)
