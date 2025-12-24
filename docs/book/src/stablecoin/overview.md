# ssUSD Stablecoin Overview

Set Chain's native stablecoin system provides a **yield-bearing stablecoin** backed by U.S. Treasury Bills, offering approximately 5% APY to holders.

## Two Token System

| Token | Type | Yield Mechanism | Best For |
|-------|------|-----------------|----------|
| **ssUSD** | Rebasing | Balance increases automatically | Holding, payments, transfers |
| **wssUSD** | Non-rebasing (ERC-4626) | Share price increases | DeFi, AMMs, lending protocols |

Both tokens represent the same underlying value and can be freely converted.

## How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                      User Journey                                │
│                                                                  │
│  1. DEPOSIT                                                      │
│     User deposits USDC/USDT → TreasuryVault → Receives ssUSD    │
│                                                                  │
│  2. HOLD & EARN                                                  │
│     ssUSD balance automatically increases as yield accrues      │
│     (NAV updated daily by attestor)                             │
│                                                                  │
│  3. USE                                                          │
│     • Transfer ssUSD for payments                               │
│     • Wrap to wssUSD for DeFi (AMMs, lending)                   │
│     • Unwrap wssUSD back to ssUSD                               │
│                                                                  │
│  4. REDEEM                                                       │
│     Request redemption → Wait 24h → Receive USDC/USDT           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Yield Example

### ssUSD (Rebasing)

```
Day 0:   Deposit 1,000 USDC → Receive 1,000.00 ssUSD
Day 30:  Balance automatically becomes 1,004.11 ssUSD
Day 365: Balance automatically becomes 1,051.27 ssUSD
         (at 5% APY)
```

Your share count stays the same, but NAV per share increases:
- Shares: 1,000 (constant)
- NAV Day 0: $1.00 → Balance: 1,000 ssUSD
- NAV Day 365: $1.05127 → Balance: 1,051.27 ssUSD

### wssUSD (Non-Rebasing)

```
Day 0:   Wrap 1,000 ssUSD → Receive 1,000.00 wssUSD
Day 30:  wssUSD balance: 1,000.00 (unchanged)
         wssUSD value: 1,004.11 ssUSD (share price increased)
Day 365: Unwrap 1,000 wssUSD → Receive 1,051.27 ssUSD
```

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    Stablecoin System                              │
│                                                                   │
│  ┌─────────────────┐                                             │
│  │  TokenRegistry  │  Whitelist of approved collateral tokens    │
│  └────────┬────────┘                                             │
│           │                                                       │
│           ▼                                                       │
│  ┌─────────────────┐     ┌─────────────────┐                     │
│  │  TreasuryVault  │◄───►│    NAVOracle    │                     │
│  │                 │     │                 │                     │
│  │  • Deposits     │     │  • Daily NAV    │                     │
│  │  • Redemptions  │     │  • Attestor     │                     │
│  │  • Collateral   │     │  • History      │                     │
│  └────────┬────────┘     └─────────────────┘                     │
│           │                       │                               │
│           │ mints/burns           │ NAV updates                   │
│           ▼                       ▼                               │
│  ┌─────────────────┐     ┌─────────────────┐                     │
│  │     ssUSD       │◄───►│    wssUSD       │                     │
│  │                 │     │   (ERC-4626)    │                     │
│  │  • Rebasing     │     │                 │                     │
│  │  • Shares-based │     │  • Wrap/Unwrap  │                     │
│  │  • 18 decimals  │     │  • DeFi-ready   │                     │
│  └─────────────────┘     └─────────────────┘                     │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

## Contract Addresses

| Contract | Description | Address |
|----------|-------------|---------|
| TokenRegistry | Collateral whitelist | TBD |
| NAVOracle | NAV attestation | TBD |
| ssUSD | Rebasing stablecoin | TBD |
| wssUSD | ERC-4626 wrapper | TBD |
| TreasuryVault | Deposits & redemptions | TBD |

## Quick Start

### Installation

```bash
npm install @setchain/sdk ethers
```

### Basic Usage

```typescript
import { stablecoin } from "@setchain/sdk";
import { parseUnits, formatUnits } from "ethers";

// Create client
const client = stablecoin.createStablecoinClient(
  {
    tokenRegistry: "0x...",
    navOracle: "0x...",
    ssUSD: "0x...",
    wssUSD: "0x...",
    treasury: "0x..."
  },
  PRIVATE_KEY,
  RPC_URL
);

// Deposit USDC → ssUSD
const depositResult = await client.deposit(
  USDC_ADDRESS,
  parseUnits("1000", 6)  // 1000 USDC
);
console.log(`Minted: ${formatUnits(depositResult.ssUSDMinted, 18)} ssUSD`);

// Check balance
const balance = await client.getBalance(myAddress);
console.log(`ssUSD: ${formatUnits(balance.ssUSD, 18)}`);
console.log(`Shares: ${balance.ssUSDShares}`);

// Get current yield
const stats = await client.getStats();
console.log(`APY: ${stats.apy.toFixed(2)}%`);
```

## Collateral

### Accepted Tokens

| Token | Symbol | Decimals | Type |
|-------|--------|----------|------|
| USD Coin | USDC | 6 | Bridged |
| Tether USD | USDT | 6 | Bridged |

### Minting Rate

Collateral is converted 1:1 to ssUSD (normalized to 18 decimals):

```
100 USDC (6 decimals) = 100000000
                      ↓
100 ssUSD (18 decimals) = 100000000000000000000
```

## Fees

| Operation | Default Fee | Max Fee |
|-----------|-------------|---------|
| Mint (deposit) | 0% | 1% |
| Redeem | 0.1% | 1% |

Fees are configurable by governance.

## Security Features

### NAV Staleness Protection

- NAV must be updated within 24 hours
- Operations may be restricted if NAV becomes stale
- Check `isNAVFresh()` before large operations

### Redemption Delay

- 24-hour delay between request and processing
- Protects against bank-run scenarios
- Users can cancel pending redemptions

### Pause Mechanisms

- Deposits can be paused: `depositsPaused()`
- Redemptions can be paused: `redemptionsPaused()`
- Emergency controls for security incidents

## Next Steps

- [Rebasing Mechanism](./rebasing.md) - How ssUSD balance increases
- [Treasury Vault](./treasury-vault.md) - Deposit and redemption details
- [NAV Oracle](./nav-oracle.md) - Daily NAV attestation
- [wssUSD](./wssusd.md) - ERC-4626 wrapper for DeFi
