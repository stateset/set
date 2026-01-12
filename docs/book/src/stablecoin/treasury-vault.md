# Treasury Vault

Deep dive into the TreasuryVault contract that manages collateral and minting.

## Overview

TreasuryVault is the core contract handling:
- Collateral custody (USDC, USDT)
- ssUSD minting on deposit
- ssUSD burning on redemption
- Fee collection

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     TreasuryVault                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │   Deposit    │    │   Redeem     │    │    Admin     │  │
│  │   Logic      │    │   Logic      │    │   Controls   │  │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘  │
│         │                   │                   │           │
│         ▼                   ▼                   ▼           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                   State Variables                    │   │
│  │  • collateralBalances[token]                        │   │
│  │  • depositsPaused                                   │   │
│  │  • redemptionsPaused                                │   │
│  │  • depositFee / redemptionFee                       │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│  External Dependencies                                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │TokenRegistry │  │  NAVOracle   │  │    ssUSD     │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

## Deposit Flow

### Step-by-Step Process

```solidity
function deposit(
    address token,
    uint256 amount,
    uint256 minSsUSD
) external returns (uint256 ssUSDMinted) {
    // 1. Validate token is approved
    require(tokenRegistry.isApproved(token), "TokenNotRegistered");

    // 2. Check deposits enabled
    require(!depositsPaused, "DepositsPaused");

    // 3. Check NAV is fresh
    require(!navOracle.isStale(), "StaleNAV");

    // 4. Check deposit cap
    TokenInfo memory info = tokenRegistry.getTokenInfo(token);
    require(
        info.currentDeposits + amount <= info.depositCap,
        "DepositCapExceeded"
    );

    // 5. Calculate ssUSD to mint
    uint256 nav = navOracle.currentNAV();
    uint256 normalizedAmount = _normalizeDecimals(token, amount);
    uint256 shares = normalizedAmount * 1e18 / nav;

    // 6. Apply deposit fee (if any)
    if (depositFee > 0) {
        uint256 fee = shares * depositFee / 10000;
        shares -= fee;
        // Fee shares go to protocol treasury
    }

    // 7. Slippage check
    ssUSDMinted = shares * nav / 1e18;
    require(ssUSDMinted >= minSsUSD, "SlippageExceeded");

    // 8. Transfer collateral
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

    // 9. Mint ssUSD
    ssUSD.mint(msg.sender, shares);

    // 10. Update registry
    tokenRegistry.incrementDeposits(token, amount);

    emit Deposit(msg.sender, token, amount, ssUSDMinted);
}
```

### Decimal Normalization

Different tokens have different decimals:

```solidity
function _normalizeDecimals(
    address token,
    uint256 amount
) internal view returns (uint256) {
    uint8 decimals = tokenRegistry.getTokenInfo(token).decimals;

    if (decimals == 18) {
        return amount;
    } else if (decimals < 18) {
        return amount * (10 ** (18 - decimals));
    } else {
        return amount / (10 ** (decimals - 18));
    }
}

// Example:
// 1000 USDC (6 decimals) = 1000 * 10^12 = 1000 * 1e12 (18 decimals)
```

## Redemption Flow

### Step-by-Step Process

```solidity
function redeem(
    address token,
    uint256 ssUSDAmount,
    uint256 minTokens
) external returns (uint256 tokensRedeemed) {
    // 1. Validate token
    TokenInfo memory info = tokenRegistry.getTokenInfo(token);
    require(info.redemptionEnabled, "RedemptionsDisabled");

    // 2. Check redemptions enabled
    require(!redemptionsPaused, "RedemptionsPaused");

    // 3. Convert ssUSD to shares
    uint256 shares = ssUSD.convertToShares(ssUSDAmount);

    // 4. Calculate tokens to return
    uint256 nav = navOracle.currentNAV();
    uint256 normalizedValue = shares * nav / 1e18;
    tokensRedeemed = _denormalizeDecimals(token, normalizedValue);

    // 5. Apply redemption fee
    if (redemptionFee > 0) {
        uint256 fee = tokensRedeemed * redemptionFee / 10000;
        tokensRedeemed -= fee;
        // Fee stays in vault
    }

    // 6. Slippage check
    require(tokensRedeemed >= minTokens, "SlippageExceeded");

    // 7. Check sufficient collateral
    require(
        collateralBalances[token] >= tokensRedeemed,
        "InsufficientCollateral"
    );

    // 8. Burn ssUSD
    ssUSD.burn(msg.sender, shares);

    // 9. Transfer tokens
    IERC20(token).safeTransfer(msg.sender, tokensRedeemed);

    // 10. Update balances
    collateralBalances[token] -= tokensRedeemed;
    tokenRegistry.decrementDeposits(token, tokensRedeemed);

    emit Redemption(msg.sender, token, ssUSDAmount, tokensRedeemed);
}
```

## Fee Structure

### Fee Parameters

```solidity
uint256 public depositFee;      // In basis points (e.g., 0 = 0%)
uint256 public redemptionFee;   // In basis points (e.g., 10 = 0.1%)

uint256 public constant MAX_FEE = 100; // 1% maximum
```

### Fee Calculation

```typescript
// Deposit fee (usually 0)
const depositFeePercent = 0;  // 0 bps
const grossShares = amount * 1e18 / nav;
const netShares = grossShares * (10000 - depositFeePercent) / 10000;

// Redemption fee (usually 10 bps = 0.1%)
const redemptionFeePercent = 10;  // 10 bps
const grossTokens = shares * nav / 1e18;
const netTokens = grossTokens * (10000 - redemptionFeePercent) / 10000;
```

### Fee Destination

- Deposit fees: Protocol treasury (shares minted to treasury)
- Redemption fees: Remain in vault (benefit all holders)

## Admin Functions

### Pause Controls

```solidity
// Pause deposits (emergency or maintenance)
function pauseDeposits() external onlyRole(PAUSER_ROLE) {
    depositsPaused = true;
    emit DepositsPaused(msg.sender);
}

function unpauseDeposits() external onlyRole(PAUSER_ROLE) {
    depositsPaused = false;
    emit DepositsUnpaused(msg.sender);
}

// Pause redemptions (emergency only)
function pauseRedemptions() external onlyRole(PAUSER_ROLE) {
    redemptionsPaused = true;
    emit RedemptionsPaused(msg.sender);
}

function unpauseRedemptions() external onlyRole(PAUSER_ROLE) {
    redemptionsPaused = false;
    emit RedemptionsUnpaused(msg.sender);
}
```

### Fee Management

```solidity
// Set fees (via timelock)
function setDepositFee(uint256 newFee) external onlyRole(ADMIN_ROLE) {
    require(newFee <= MAX_FEE, "FeeTooHigh");
    uint256 oldFee = depositFee;
    depositFee = newFee;
    emit DepositFeeUpdated(oldFee, newFee);
}

function setRedemptionFee(uint256 newFee) external onlyRole(ADMIN_ROLE) {
    require(newFee <= MAX_FEE, "FeeTooHigh");
    uint256 oldFee = redemptionFee;
    redemptionFee = newFee;
    emit RedemptionFeeUpdated(oldFee, newFee);
}
```

## Preview Functions

### Preview Deposit

```solidity
function previewDeposit(
    address token,
    uint256 amount
) external view returns (uint256 ssUSDAmount) {
    require(tokenRegistry.isApproved(token), "TokenNotRegistered");

    uint256 nav = navOracle.currentNAV();
    uint256 normalizedAmount = _normalizeDecimals(token, amount);
    uint256 shares = normalizedAmount * 1e18 / nav;

    // Apply fee
    if (depositFee > 0) {
        shares = shares * (10000 - depositFee) / 10000;
    }

    ssUSDAmount = shares * nav / 1e18;
}
```

### Preview Redeem

```solidity
function previewRedeem(
    address token,
    uint256 ssUSDAmount
) external view returns (uint256 tokenAmount) {
    TokenInfo memory info = tokenRegistry.getTokenInfo(token);
    require(info.redemptionEnabled, "RedemptionsDisabled");

    uint256 shares = ssUSD.convertToShares(ssUSDAmount);
    uint256 nav = navOracle.currentNAV();
    uint256 normalizedValue = shares * nav / 1e18;
    tokenAmount = _denormalizeDecimals(token, normalizedValue);

    // Apply fee
    if (redemptionFee > 0) {
        tokenAmount = tokenAmount * (10000 - redemptionFee) / 10000;
    }
}
```

## Collateral Management

### View Functions

```solidity
// Get collateral balance for specific token
function getCollateralBalance(address token) external view returns (uint256) {
    return IERC20(token).balanceOf(address(this));
}

// Get total collateral value in USD (18 decimals)
function getTotalCollateralValue() external view returns (uint256 total) {
    address[] memory tokens = tokenRegistry.getApprovedTokens();

    for (uint256 i = 0; i < tokens.length; i++) {
        uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
        uint256 normalized = _normalizeDecimals(tokens[i], balance);
        total += normalized;  // All stablecoins assumed $1
    }
}
```

### Health Checks

```typescript
async function checkVaultHealth() {
    const treasury = new Contract(TREASURY_ADDRESS, TreasuryVaultABI, provider);
    const ssUSD = new Contract(SSUSD_ADDRESS, ssUSDABI, provider);

    const totalCollateral = await treasury.getTotalCollateralValue();
    const totalSupply = await ssUSD.totalSupply();

    const backingRatio = totalCollateral * 100n / totalSupply;

    return {
        totalCollateral: formatUnits(totalCollateral, 18),
        totalSupply: formatUnits(totalSupply, 18),
        backingRatio: Number(backingRatio),
        isFullyBacked: backingRatio >= 100n
    };
}
```

## Security Considerations

### Reentrancy Protection

```solidity
// All external calls use ReentrancyGuard
modifier nonReentrant() {
    require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
    _status = _ENTERED;
    _;
    _status = _NOT_ENTERED;
}

function deposit(...) external nonReentrant { ... }
function redeem(...) external nonReentrant { ... }
```

### Access Control

```solidity
// Role-based access
bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

// Admin actions require timelock
modifier onlyTimelockAdmin() {
    require(
        hasRole(ADMIN_ROLE, msg.sender) ||
        msg.sender == address(timelock),
        "Unauthorized"
    );
    _;
}
```

### Invariants

The vault maintains these invariants:
1. `totalCollateral >= totalSupply` (full backing)
2. `depositFee <= MAX_FEE` (fee caps)
3. `redemptionFee <= MAX_FEE`
4. Only approved tokens accepted

## Integration Example

```typescript
import { Contract, parseUnits, formatUnits } from "ethers";

async function depositUSDC(amount: string) {
    const treasury = new Contract(TREASURY_ADDRESS, TreasuryVaultABI, signer);
    const usdc = new Contract(USDC_ADDRESS, ERC20ABI, signer);

    // Parse amount
    const depositAmount = parseUnits(amount, 6);  // USDC has 6 decimals

    // Preview
    const expectedSsUSD = await treasury.previewDeposit(USDC_ADDRESS, depositAmount);
    console.log(`Expected: ${formatUnits(expectedSsUSD, 18)} ssUSD`);

    // Approve
    await usdc.approve(TREASURY_ADDRESS, depositAmount);

    // Deposit with 1% slippage
    const minSsUSD = expectedSsUSD * 99n / 100n;
    const tx = await treasury.deposit(USDC_ADDRESS, depositAmount, minSsUSD);
    const receipt = await tx.wait();

    // Parse event
    const event = receipt.logs.find(l => l.topics[0] === treasury.interface.getEventTopic("Deposit"));
    const decoded = treasury.interface.decodeEventLog("Deposit", event.data, event.topics);

    console.log(`Deposited: ${formatUnits(decoded.amount, 6)} USDC`);
    console.log(`Minted: ${formatUnits(decoded.ssUSDMinted, 18)} ssUSD`);
}
```

## Related

- [ssUSD Overview](./overview.md)
- [NAV Oracle](./nav-oracle.md)
- [Collateral Management](./collateral.md)
- [Stablecoin Contracts API](../contracts/stablecoin-contracts.md)
