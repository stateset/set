# Collateral Management

Understanding how collateral backing ssUSD is managed.

## Overview

ssUSD is fully backed by approved stablecoin collateral:
- USDC (USD Coin)
- USDT (Tether USD)
- Future: Additional approved tokens

## Collateral Requirements

### 1:1 Backing

Every ssUSD is backed by equivalent stablecoin collateral:

```
Invariant: Total Collateral Value ≥ Total ssUSD Supply
```

This is enforced at the smart contract level.

### Approved Tokens

Only tokens in the TokenRegistry can be used as collateral:

```solidity
struct TokenInfo {
    string symbol;           // e.g., "USDC"
    uint8 decimals;          // e.g., 6
    uint256 depositCap;      // Maximum deposits allowed
    uint256 currentDeposits; // Current deposited amount
    bool depositEnabled;     // Accept new deposits
    bool redemptionEnabled;  // Allow redemptions
}
```

## TokenRegistry

### Registration Process

New collateral tokens must be approved through governance:

```solidity
function registerToken(
    address token,
    TokenInfo calldata info
) external onlyRole(ADMIN_ROLE) {
    require(!isApproved(token), "TokenAlreadyRegistered");
    require(token != address(0), "ZeroAddress");

    // Verify it's a valid ERC20
    require(IERC20(token).totalSupply() > 0, "InvalidToken");

    tokens[token] = info;
    approvedTokens.push(token);

    emit TokenRegistered(token, info);
}
```

### Token Requirements

Approved collateral tokens must:
1. Be ERC-20 compliant
2. Have stable $1.00 peg
3. Have sufficient liquidity
4. Pass security review
5. Be approved by governance

### Current Approved Tokens

| Token | Symbol | Decimals | Deposit Cap |
|-------|--------|----------|-------------|
| USDC | USDC | 6 | $10M |
| USDT | USDT | 6 | $10M |

## Deposit Caps

### Purpose

Deposit caps:
- Limit concentration risk
- Prevent any single token from dominating
- Allow gradual scaling
- Protect against depegging events

### Cap Management

```solidity
function updateDepositCap(
    address token,
    uint256 newCap
) external onlyRole(ADMIN_ROLE) {
    require(isApproved(token), "TokenNotRegistered");

    TokenInfo storage info = tokens[token];
    uint256 oldCap = info.depositCap;
    info.depositCap = newCap;

    emit DepositCapUpdated(token, oldCap, newCap);
}
```

### Monitoring Utilization

```typescript
async function getCollateralUtilization() {
    const registry = new Contract(TOKEN_REGISTRY, TokenRegistryABI, provider);
    const tokens = await registry.getApprovedTokens();

    const utilization = [];

    for (const token of tokens) {
        const info = await registry.getTokenInfo(token);
        const usedPercent = Number(info.currentDeposits * 100n / info.depositCap);

        utilization.push({
            token: info.symbol,
            current: formatUnits(info.currentDeposits, info.decimals),
            cap: formatUnits(info.depositCap, info.decimals),
            utilization: usedPercent.toFixed(2) + "%"
        });
    }

    return utilization;
}

// Example output:
// [
//   { token: "USDC", current: "5000000", cap: "10000000", utilization: "50.00%" },
//   { token: "USDT", current: "3000000", cap: "10000000", utilization: "30.00%" }
// ]
```

## Collateral Custody

### On-Chain Custody

All collateral is held in the TreasuryVault contract:

```
User deposits 1000 USDC
  │
  ▼
TreasuryVault receives 1000 USDC
  │
  ▼
TreasuryVault mints ssUSD to user
  │
  ▼
USDC remains in TreasuryVault until redemption
```

### No External Custody

Unlike some stablecoins:
- No off-chain custody required for collateral
- All collateral verifiable on-chain
- No counterparty risk for collateral custody

### Yield Generation

The T-Bill yield comes from:
1. Collateral stablecoins are backed by T-Bills (USDC, USDT backing)
2. Set Chain attestor reports aggregate yield
3. NAV increases reflect this yield

```
Collateral (USDC/USDT)
    │
    ├── Issuers hold T-Bills (Circle, Tether)
    │
    ▼
T-Bill yield flows to stablecoin holders
    │
    ▼
NAV Oracle reports aggregate yield
    │
    ▼
ssUSD holders benefit via rebasing
```

## Redemption Mechanics

### Token Selection

Users choose which collateral token to redeem:

```typescript
// User has 1000 ssUSD and wants USDC
const ssUSDAmount = parseUnits("1000", 18);

// Check available USDC
const usdcBalance = await treasury.getCollateralBalance(USDC_ADDRESS);
console.log(`Available USDC: ${formatUnits(usdcBalance, 6)}`);

// Redeem for USDC
const usdcReceived = await treasury.redeem(
    USDC_ADDRESS,
    ssUSDAmount,
    minUSDC
);
```

### Pro-Rata Redemption

If specific token is low, users can redeem proportionally:

```typescript
// Get all collateral balances
const tokens = await registry.getApprovedTokens();
const balances = await Promise.all(
    tokens.map(t => treasury.getCollateralBalance(t))
);

// Calculate proportional redemption
const totalValue = balances.reduce((sum, b) => sum + b, 0n);
const ssUSDToRedeem = parseUnits("1000", 18);

for (let i = 0; i < tokens.length; i++) {
    const proportion = balances[i] * ssUSDToRedeem / totalValue;
    console.log(`${tokens[i]}: ${formatUnits(proportion, 6)}`);
}
```

## Reserve Verification

### On-Chain Verification

Anyone can verify reserves:

```typescript
async function verifyReserves() {
    const treasury = new Contract(TREASURY_ADDRESS, TreasuryVaultABI, provider);
    const ssUSD = new Contract(SSUSD_ADDRESS, ssUSDABI, provider);

    // Get total collateral
    const totalCollateral = await treasury.getTotalCollateralValue();

    // Get total ssUSD supply
    const totalSupply = await ssUSD.totalSupply();

    // Calculate backing ratio
    const backingRatio = totalCollateral * 10000n / totalSupply;

    return {
        totalCollateral: formatUnits(totalCollateral, 18),
        totalSupply: formatUnits(totalSupply, 18),
        backingRatio: (Number(backingRatio) / 100).toFixed(2) + "%",
        isFullyBacked: backingRatio >= 10000n
    };
}

// Example output:
// {
//   totalCollateral: "8000000.00",
//   totalSupply: "8000000.00",
//   backingRatio: "100.00%",
//   isFullyBacked: true
// }
```

### Real-Time Monitoring

```typescript
// Monitor reserve changes
treasury.on("Deposit", async () => {
    const status = await verifyReserves();
    console.log(`Reserves after deposit: ${status.backingRatio}`);

    if (!status.isFullyBacked) {
        alerting.critical("Underbacking detected!", status);
    }
});

treasury.on("Redemption", async () => {
    const status = await verifyReserves();
    console.log(`Reserves after redemption: ${status.backingRatio}`);
});
```

## Risk Management

### Depeg Risk

If a collateral token depegs:

```
Scenario: USDT depegs to $0.95

Impact:
- USDT collateral worth less
- Total collateral value drops
- ssUSD backing ratio drops

Mitigation:
1. Deposit caps limit exposure
2. Multiple collateral types diversify risk
3. Redemptions can be paused if severe
4. NAV oracle can adjust for depeg
```

### Concentration Risk

Managed through deposit caps:

```
Target allocation:
- No single token > 50% of collateral
- Caps adjusted based on risk assessment
```

### Protocol Risk

Collateral token protocol risks (Circle, Tether):
- Regulatory risk
- Smart contract risk
- Centralization risk

Mitigations:
- Multiple approved tokens
- Regular review of issuers
- Governance can delist tokens

## Governance

### Adding New Collateral

Process for adding new collateral:

1. **Proposal**: Submit governance proposal with:
   - Token address
   - Justification
   - Risk assessment
   - Proposed cap

2. **Review Period**: 7-day community review

3. **Vote**: Token holder vote

4. **Timelock**: 48-hour delay before activation

5. **Activation**: Token added to registry

### Removing Collateral

Process for removing collateral:

1. **Proposal**: Justification for removal

2. **Vote**: Token holder vote

3. **Grace Period**: Redemptions only (deposits disabled)

4. **Removal**: Token removed from registry

```solidity
function disableDeposits(address token) external onlyRole(ADMIN_ROLE) {
    tokens[token].depositEnabled = false;
    emit DepositsDisabled(token);
}

function removeToken(address token) external onlyRole(ADMIN_ROLE) {
    require(tokens[token].currentDeposits == 0, "NonZeroDeposits");
    delete tokens[token];
    // Remove from approvedTokens array...
    emit TokenRemoved(token);
}
```

## Collateral Dashboard

```typescript
async function getCollateralDashboard() {
    const registry = new Contract(TOKEN_REGISTRY, TokenRegistryABI, provider);
    const treasury = new Contract(TREASURY_ADDRESS, TreasuryVaultABI, provider);
    const ssUSD = new Contract(SSUSD_ADDRESS, ssUSDABI, provider);

    const tokens = await registry.getApprovedTokens();
    const totalSupply = await ssUSD.totalSupply();

    let totalCollateralValue = 0n;
    const breakdown = [];

    for (const tokenAddr of tokens) {
        const info = await registry.getTokenInfo(tokenAddr);
        const balance = await treasury.getCollateralBalance(tokenAddr);
        const normalized = balance * BigInt(10 ** (18 - info.decimals));

        totalCollateralValue += normalized;

        breakdown.push({
            symbol: info.symbol,
            balance: formatUnits(balance, info.decimals),
            cap: formatUnits(info.depositCap, info.decimals),
            utilization: Number(balance * 100n / info.depositCap).toFixed(1) + "%",
            depositsEnabled: info.depositEnabled,
            redemptionsEnabled: info.redemptionEnabled
        });
    }

    return {
        totalCollateral: formatUnits(totalCollateralValue, 18),
        totalSupply: formatUnits(totalSupply, 18),
        backingRatio: (Number(totalCollateralValue * 10000n / totalSupply) / 100).toFixed(2) + "%",
        tokens: breakdown
    };
}
```

## Related

- [ssUSD Overview](./overview.md)
- [Treasury Vault](./treasury-vault.md)
- [Stablecoin Contracts API](../contracts/stablecoin-contracts.md)
- [Security Operations](../operations/security.md)
