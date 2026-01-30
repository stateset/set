# SSDC Stablecoin System

Set Chain's native stablecoin system provides a yield-bearing stablecoin backed by company-held U.S. Treasury Bills.

## Overview

The SSDC stablecoin system consists of:

| Token | Type | Yield | Use Case |
|-------|------|-------|----------|
| **SSDC** | Rebasing | ~5% APY | Holding, payments |
| **wSSDC** | Non-rebasing | Accrues in share price | DeFi, AMMs, lending |

Both tokens represent the same underlying value. Users can wrap/unwrap between them freely.

## Architecture

```
User deposits USDC/USDT → TreasuryVault → Mints ssUSD shares
                              ↓
                         NAVOracle (daily T-Bill NAV attestation)
                              ↓
                    ssUSD balance = shares × NAV (auto-rebasing)
                              ↓
                    wssUSD wraps ssUSD (ERC4626, DeFi-friendly)
```

### Contracts

| Contract | Description |
|----------|-------------|
| `TokenRegistry` | Verified token list and collateral whitelist |
| `NAVOracle` | Daily NAV attestation from company attestors |
| `ssUSD` | Rebasing stablecoin (shares-based accounting) |
| `wssUSD` | ERC4626 wrapper for DeFi compatibility |
| `TreasuryVault` | Collateral management and minting |

## How Yield Works

### ssUSD (Rebasing)
- Your balance automatically increases as yield accrues
- No action required to receive yield
- Best for: holding, payments, simple transfers

```
Day 0: Balance = 1000 ssUSD
Day 30: Balance = 1004.11 ssUSD (≈5% APY)
```

### wssUSD (Non-Rebasing)
- Your balance stays constant, but share price increases
- Better for DeFi protocols (AMMs, lending, vaults)
- Wrap ssUSD → wssUSD to use in DeFi

```
Day 0: 1000 ssUSD → 1000 wssUSD (1:1 rate)
Day 30: 1000 wssUSD = 1004.11 ssUSD (share price increased)
```

## Collateral

Accepted collateral tokens:
- **USDC** (USD Coin) - 6 decimals, bridged
- **USDT** (Tether USD) - 6 decimals, bridged

Minting is 1:1 minus any applicable fees:
- 100 USDC → ~100 ssUSD (decimal normalized from 6→18)

## SDK Usage

### Installation

```typescript
import { stablecoin } from "@set-chain/sdk";
import { parseUnits, formatUnits } from "ethers";
```

### Create Client

```typescript
const addresses: stablecoin.StablecoinAddresses = {
  tokenRegistry: "0x...",
  navOracle: "0x...",
  ssUSD: "0x...",
  wssUSD: "0x...",
  treasury: "0x..."
};

const client = stablecoin.createStablecoinClient(
  addresses,
  PRIVATE_KEY,
  RPC_URL
);
```

### Deposit USDC/USDT → ssUSD

```typescript
const USDC = "0x..."; // USDC address on Set Chain
const amount = parseUnits("1000", 6); // 1000 USDC (6 decimals)

const result = await client.deposit(USDC, amount);
console.log("ssUSD minted:", formatUnits(result.ssUSDMinted, 18));
console.log("Tx hash:", result.txHash);
```

### Check Balances

```typescript
const balance = await client.getBalance(address);
console.log("ssUSD:", formatUnits(balance.ssUSD, 18));
console.log("ssUSD shares:", balance.ssUSDShares.toString());
console.log("wssUSD:", formatUnits(balance.wssUSD, 18));
console.log("wssUSD value:", formatUnits(balance.wssUSDValue, 18));
```

### Wrap for DeFi

```typescript
const ssUSDAmount = parseUnits("500", 18);
const wrapResult = await client.wrap(ssUSDAmount);
console.log("wssUSD received:", formatUnits(wrapResult.wssUSDReceived, 18));
```

### Unwrap to ssUSD

```typescript
const wssUSDAmount = parseUnits("500", 18);
const unwrapResult = await client.unwrap(wssUSDAmount);
console.log("ssUSD received:", formatUnits(unwrapResult.ssUSDReceived, 18));
```

### Request Redemption

```typescript
const ssUSDToRedeem = parseUnits("100", 18);
const result = await client.requestRedemption(ssUSDToRedeem, USDC);
console.log("Request ID:", result.requestId.toString());

// Check redemption status
const request = await client.getRedemptionRequest(result.requestId);
console.log("Status:", request.status);
```

### Get System Stats

```typescript
const stats = await client.getStats();
console.log("Total Supply:", formatUnits(stats.totalSupply, 18));
console.log("NAV per Share:", formatUnits(stats.navPerShare, 18));
console.log("Collateral Ratio:", formatUnits(stats.collateralRatio, 16) + "%");
console.log("APY:", stats.apy.toFixed(2) + "%");
```

### Check NAV Freshness

```typescript
const nav = await client.getCurrentNAV();
console.log("NAV per share:", formatUnits(nav.navPerShare, 18));
console.log("Last report:", new Date(Number(nav.timestamp) * 1000));
console.log("Attestor:", nav.attestor);

const isFresh = await client.isNAVFresh();
console.log("NAV is fresh:", isFresh);
```

## Contract Interfaces

### Deposit Flow

```solidity
// 1. User approves collateral
IERC20(usdc).approve(treasury, amount);

// 2. User deposits collateral
ITreasuryVault(treasury).deposit(usdc, amount, recipient);
// → Mints ssUSD shares to recipient
```

### Redemption Flow

```solidity
// 1. User approves ssUSD
IssUSD(ssUSD).approve(treasury, amount);

// 2. User requests redemption
uint256 requestId = ITreasuryVault(treasury).requestRedemption(amount, preferredCollateral);

// 3. Wait for redemption delay (T+1)

// 4. Operator processes redemption
ITreasuryVault(treasury).processRedemption(requestId);
// → Collateral sent to user
```

### NAV Attestation

```solidity
// Company attestor submits daily NAV
INAVOracle(navOracle).attestNAV(
  totalAssets,  // Total T-Bill value in USD (18 decimals)
  reportDate,   // YYYYMMDD format
  proofHash     // Hash of off-chain attestation proof
);
```

## Security Considerations

### NAV Staleness
- NAV must be updated within 24 hours
- Operations may be restricted if NAV is stale
- Check `isNAVFresh()` before critical operations

### Redemption Delays
- Redemptions have a configurable delay (default: 24 hours)
- Users can cancel pending redemptions
- Protects against bank-run scenarios

### Access Control
- `ssUSD` minting/burning: only TreasuryVault
- NAV attestation: only authorized attestors
- Collateral management: requires OPERATOR_ROLE
- Upgrades/configuration: requires owner (timelock)

### Emergency Controls
- Deposits can be paused: `depositsPaused()`
- Redemptions can be paused: `redemptionsPaused()`
- Check status before operations

## Deployment

### Deploy Stablecoin System

```bash
cd contracts

# Set environment
export OWNER=0x...       # Admin address
export NAV_ATTESTOR=0x... # NAV attestor address
export USDC_ADDRESS=0x...  # Bridged USDC
export USDT_ADDRESS=0x...  # Bridged USDT

# Deploy
forge script script/stablecoin/DeployStablecoin.s.sol:DeployStablecoin \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvvv
```

### Post-Deployment Configuration

```bash
# Configure operator and transfer to timelock
export TOKEN_REGISTRY=0x...
export TREASURY_VAULT=0x...
export TIMELOCK=0x...
export OPERATOR=0x...

forge script script/stablecoin/DeployStablecoin.s.sol:ConfigureStablecoin \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### Initial NAV Attestation

After deployment, the NAV attestor must submit the initial NAV:

```solidity
navOracle.attestNAV(
  1e18,       // Initial NAV = $1.00 per share
  20241201,   // Report date
  bytes32(0)  // Initial proof hash
);
```

## Contract Addresses

| Network | Contract | Address |
|---------|----------|---------|
| Set Chain Mainnet | TokenRegistry | TBD |
| Set Chain Mainnet | NAVOracle | TBD |
| Set Chain Mainnet | ssUSD | TBD |
| Set Chain Mainnet | wssUSD | TBD |
| Set Chain Mainnet | TreasuryVault | TBD |

## FAQ

### Why two tokens (ssUSD and wssUSD)?

**ssUSD** rebases automatically - your balance increases. This is intuitive for users but problematic for DeFi protocols that expect constant balances.

**wssUSD** has a constant balance - yield accrues in the share price. This is compatible with AMMs, lending protocols, and vaults.

### How is the yield generated?

The company holds U.S. Treasury Bills off-chain. The yield from these T-Bills is reflected in the daily NAV attestation, which causes ssUSD balances to increase.

### Is this fully collateralized?

Yes. Every ssUSD is backed 1:1 by either:
- On-chain USDC/USDT collateral
- Off-chain T-Bill holdings (attested via NAVOracle)

### What happens if NAV becomes stale?

If NAV is not updated within 24 hours:
- New deposits may be restricted
- Redemptions continue to function
- Users should verify `isNAVFresh()` before large operations

### Can I use ssUSD in DeFi?

For best compatibility, wrap ssUSD to wssUSD first:
```typescript
await client.wrap(ssUSDAmount);
// Now use wssUSD in AMMs, lending, etc.
```

### What are the fees?

Fees are configurable by governance:
- Mint fee: Default 0%
- Redeem fee: Default 0%

Check current fees:
```typescript
const mintFee = await treasury.mintFee();
const redeemFee = await treasury.redeemFee();
```
