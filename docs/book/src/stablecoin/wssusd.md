# wssUSD (Wrapped ssUSD)

Deep dive into the wrapped, non-rebasing version of ssUSD.

## Overview

wssUSD is an ERC-4626 compliant wrapper for ssUSD that:
- Maintains a constant balance (no rebasing)
- Accumulates yield through share appreciation
- Compatible with DeFi protocols
- Redeemable for increasing amounts of ssUSD

## Why wssUSD?

### The Rebasing Problem

ssUSD balances change automatically with NAV updates:

```
Day 1: User has 1000 ssUSD
Day 2: NAV increases 0.0137%
Day 2: User now has 1000.137 ssUSD (same shares, more tokens)
```

This breaks many DeFi protocols:
- AMMs see phantom deposits
- Lending protocols miscalculate collateral
- Accounting systems get confused

### The wssUSD Solution

wssUSD solves this by wrapping ssUSD:

```
Day 1: User wraps 1000 ssUSD → receives ~1000 wssUSD
Day 2: User still has ~1000 wssUSD (constant balance)
Day 2: wssUSD now redeemable for 1000.137 ssUSD
```

## ERC-4626 Interface

wssUSD implements the full ERC-4626 tokenized vault standard:

```solidity
interface IERC4626 is IERC20 {
    // Asset (ssUSD)
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);

    // Convert between shares (wssUSD) and assets (ssUSD)
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);

    // Deposit ssUSD → receive wssUSD
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    // Withdraw wssUSD → receive ssUSD
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    // Preview operations
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewMint(uint256 shares) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);

    // Limits
    function maxDeposit(address) external view returns (uint256);
    function maxMint(address) external view returns (uint256);
    function maxWithdraw(address owner) external view returns (uint256);
    function maxRedeem(address owner) external view returns (uint256);
}
```

## Exchange Rate Mechanics

### Initial Rate

At launch, 1 ssUSD = 1 wssUSD (when NAV = $1.00)

### Rate Evolution

```
NAV = $1.00:  1 ssUSD = 1 wssUSD
NAV = $1.05:  1.05 ssUSD = 1 wssUSD  (wssUSD worth more)
NAV = $1.10:  1.10 ssUSD = 1 wssUSD
```

### Rate Calculation

```solidity
function convertToAssets(uint256 shares) public view returns (uint256) {
    // How much ssUSD for given wssUSD shares
    uint256 totalWssUSD = totalSupply();
    if (totalWssUSD == 0) return shares;

    uint256 totalSsUSD = ssUSD.balanceOf(address(this));
    return shares * totalSsUSD / totalWssUSD;
}

function convertToShares(uint256 assets) public view returns (uint256) {
    // How much wssUSD for given ssUSD
    uint256 totalWssUSD = totalSupply();
    if (totalWssUSD == 0) return assets;

    uint256 totalSsUSD = ssUSD.balanceOf(address(this));
    return assets * totalWssUSD / totalSsUSD;
}
```

## Wrapping (Deposit)

### deposit() - Deposit ssUSD by amount

```solidity
function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
    shares = previewDeposit(assets);
    require(shares > 0, "ZeroShares");

    ssUSD.transferFrom(msg.sender, address(this), assets);
    _mint(receiver, shares);

    emit Deposit(msg.sender, receiver, assets, shares);
}
```

### mint() - Mint exact wssUSD amount

```solidity
function mint(uint256 shares, address receiver) external returns (uint256 assets) {
    assets = previewMint(shares);
    require(assets > 0, "ZeroAssets");

    ssUSD.transferFrom(msg.sender, address(this), assets);
    _mint(receiver, shares);

    emit Deposit(msg.sender, receiver, assets, shares);
}
```

### Usage Example

```typescript
import { parseUnits, formatUnits } from "ethers";

// Wrap 100 ssUSD
const ssUSDAmount = parseUnits("100", 18);

// Approve
await ssUSD.approve(wssUSDAddress, ssUSDAmount);

// Deposit
const wssUSDReceived = await wssUSD.deposit(ssUSDAmount, userAddress);

console.log(`Deposited: ${formatUnits(ssUSDAmount, 18)} ssUSD`);
console.log(`Received: ${formatUnits(wssUSDReceived, 18)} wssUSD`);
```

## Unwrapping (Withdraw/Redeem)

### withdraw() - Withdraw exact ssUSD amount

```solidity
function withdraw(
    uint256 assets,
    address receiver,
    address owner
) external returns (uint256 shares) {
    shares = previewWithdraw(assets);

    if (msg.sender != owner) {
        _spendAllowance(owner, msg.sender, shares);
    }

    _burn(owner, shares);
    ssUSD.transfer(receiver, assets);

    emit Withdraw(msg.sender, receiver, owner, assets, shares);
}
```

### redeem() - Redeem exact wssUSD amount

```solidity
function redeem(
    uint256 shares,
    address receiver,
    address owner
) external returns (uint256 assets) {
    assets = previewRedeem(shares);

    if (msg.sender != owner) {
        _spendAllowance(owner, msg.sender, shares);
    }

    _burn(owner, shares);
    ssUSD.transfer(receiver, assets);

    emit Withdraw(msg.sender, receiver, owner, assets, shares);
}
```

### Usage Example

```typescript
// Unwrap all wssUSD
const wssUSDBalance = await wssUSD.balanceOf(userAddress);

// Preview how much ssUSD we'll get
const ssUSDExpected = await wssUSD.previewRedeem(wssUSDBalance);
console.log(`Expected: ${formatUnits(ssUSDExpected, 18)} ssUSD`);

// Redeem
const ssUSDReceived = await wssUSD.redeem(wssUSDBalance, userAddress, userAddress);

console.log(`Burned: ${formatUnits(wssUSDBalance, 18)} wssUSD`);
console.log(`Received: ${formatUnits(ssUSDReceived, 18)} ssUSD`);
```

## Yield Tracking

### Tracking Individual Yield

```typescript
// Track yield by comparing deposit to current value
interface WssUSDPosition {
    depositedSsUSD: bigint;
    wssUSDBalance: bigint;
    depositTimestamp: number;
}

async function calculateYield(position: WssUSDPosition) {
    // Current value in ssUSD
    const currentValue = await wssUSD.previewRedeem(position.wssUSDBalance);

    // Yield earned
    const yieldEarned = currentValue - position.depositedSsUSD;
    const yieldPercent = Number(yieldEarned * 10000n / position.depositedSsUSD) / 100;

    // Annualized
    const daysHeld = (Date.now() - position.depositTimestamp) / (1000 * 60 * 60 * 24);
    const apy = yieldPercent * 365 / daysHeld;

    return {
        depositedSsUSD: formatUnits(position.depositedSsUSD, 18),
        currentValue: formatUnits(currentValue, 18),
        yieldEarned: formatUnits(yieldEarned, 18),
        yieldPercent: yieldPercent.toFixed(4),
        daysHeld: daysHeld.toFixed(1),
        apy: apy.toFixed(2)
    };
}
```

### Exchange Rate Over Time

```typescript
async function getExchangeRateHistory(days: number) {
    const history = [];

    for (let i = 0; i < days; i++) {
        // Query past blocks or use indexed data
        const rate = await wssUSD.convertToAssets(parseUnits("1", 18));
        history.push({
            day: i,
            rate: formatUnits(rate, 18)
        });
    }

    return history;
}
```

## DeFi Integration

### AMM Liquidity

wssUSD can be used in AMM pools:

```typescript
// Add liquidity to wssUSD/USDC pool
await wssUSD.approve(routerAddress, wssUSDAmount);
await usdc.approve(routerAddress, usdcAmount);

await router.addLiquidity(
    wssUSDAddress,
    usdcAddress,
    wssUSDAmount,
    usdcAmount,
    minWssUSD,
    minUSDC,
    userAddress,
    deadline
);
```

### Lending Collateral

wssUSD as collateral in lending protocols:

```typescript
// Deposit wssUSD as collateral
await wssUSD.approve(lendingPoolAddress, wssUSDAmount);
await lendingPool.deposit(wssUSDAddress, wssUSDAmount, userAddress, 0);

// wssUSD value grows over time, increasing collateral value
```

### Yield Aggregators

wssUSD enables yield-on-yield strategies:

```
1. Deposit USDC → mint ssUSD (~5% APY from T-Bills)
2. Wrap ssUSD → wssUSD
3. Provide wssUSD/USDC liquidity → earn trading fees
4. Total yield = T-Bill yield + LP fees
```

## Comparison: ssUSD vs wssUSD

| Feature | ssUSD | wssUSD |
|---------|-------|--------|
| Balance | Changes daily | Constant |
| Yield | Balance increases | Redemption value increases |
| ERC-20 | Yes | Yes |
| ERC-4626 | No | Yes |
| DeFi Compatible | Limited | Full |
| Gas for yield | 0 | 0 |
| Wrapping cost | N/A | 1 tx |

## When to Use Each

### Use ssUSD when:
- Holding for yield
- Making payments
- Simple transfers
- Want to see balance grow

### Use wssUSD when:
- Using DeFi protocols
- Providing liquidity
- Using as collateral
- Need stable balances for accounting

## SDK Integration

```typescript
import { stablecoin } from "@setchain/sdk";

const client = stablecoin.createStablecoinClient(addresses, privateKey, rpcUrl);

// Wrap ssUSD
const wrapResult = await client.wrap(parseUnits("100", 18));
console.log(`Received: ${formatUnits(wrapResult.wssUSDReceived, 18)} wssUSD`);
console.log(`Exchange rate: ${formatUnits(wrapResult.exchangeRate, 18)}`);

// Check wssUSD balance and value
const balance = await client.getBalance(userAddress);
console.log(`wssUSD balance: ${formatUnits(balance.wssUSD, 18)}`);

// Calculate current ssUSD value
const ssUSDValue = await wssUSD.previewRedeem(balance.wssUSD);
console.log(`Current value: ${formatUnits(ssUSDValue, 18)} ssUSD`);

// Unwrap
const unwrapResult = await client.unwrap(balance.wssUSD);
console.log(`Received: ${formatUnits(unwrapResult.ssUSDReceived, 18)} ssUSD`);
```

## Related

- [ssUSD Overview](./overview.md)
- [Rebasing Mechanism](./rebasing.md)
- [Treasury Vault](./treasury-vault.md)
- [Stablecoin Contracts API](../contracts/stablecoin-contracts.md)
