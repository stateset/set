# Stablecoin Contracts

Complete API reference for the ssUSD stablecoin system contracts.

## Contract Overview

| Contract | Purpose | Upgradeable |
|----------|---------|-------------|
| [TokenRegistry](#tokenregistry) | Approved collateral management | Yes |
| [NAVOracle](#navoracle) | Daily NAV attestation | Yes |
| [ssUSD](#ssusd) | Rebasing stablecoin token | Yes |
| [wssUSD](#wssusd) | Wrapped non-rebasing token | Yes |
| [TreasuryVault](#treasuryvault) | Collateral custody & minting | Yes |

---

## TokenRegistry

Maintains the whitelist of approved collateral tokens.

### Interface

```solidity
interface ITokenRegistry {
    // Events
    event TokenRegistered(address indexed token, TokenInfo info);
    event TokenUpdated(address indexed token, TokenInfo info);
    event TokenRemoved(address indexed token);

    // State
    function isApproved(address token) external view returns (bool);
    function getTokenInfo(address token) external view returns (TokenInfo memory);
    function getApprovedTokens() external view returns (address[] memory);
    function tokenCount() external view returns (uint256);

    // Admin
    function registerToken(address token, TokenInfo calldata info) external;
    function updateToken(address token, TokenInfo calldata info) external;
    function removeToken(address token) external;
}

struct TokenInfo {
    string symbol;
    uint8 decimals;
    uint256 depositCap;      // Maximum total deposits
    uint256 currentDeposits; // Current deposited amount
    bool depositEnabled;     // Accept deposits
    bool redemptionEnabled;  // Allow redemptions
}
```

### Key Functions

#### registerToken

```solidity
function registerToken(address token, TokenInfo calldata info) external;
```

Register a new collateral token.

**Requirements:**
- Caller must have ADMIN_ROLE
- Token must not already be registered
- Token must be valid ERC20

**Example:**
```typescript
await tokenRegistry.registerToken(USDC_ADDRESS, {
    symbol: "USDC",
    decimals: 6,
    depositCap: parseUnits("10000000", 6), // 10M cap
    currentDeposits: 0n,
    depositEnabled: true,
    redemptionEnabled: true
});
```

#### getTokenInfo

```solidity
function getTokenInfo(address token) external view returns (TokenInfo memory);
```

Get full information about a registered token.

**Example:**
```typescript
const info = await tokenRegistry.getTokenInfo(USDC_ADDRESS);
console.log(`Cap: ${formatUnits(info.depositCap, info.decimals)}`);
console.log(`Current: ${formatUnits(info.currentDeposits, info.decimals)}`);
console.log(`Utilization: ${Number(info.currentDeposits * 100n / info.depositCap)}%`);
```

---

## NAVOracle

Receives and stores daily NAV (Net Asset Value) attestations.

### Interface

```solidity
interface INAVOracle {
    // Events
    event NAVUpdated(
        uint256 indexed reportId,
        uint256 nav,
        uint256 totalAssets,
        uint256 totalShares,
        uint256 timestamp
    );
    event AttestorUpdated(address indexed oldAttestor, address indexed newAttestor);
    event StalenessThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    // State
    function currentNAV() external view returns (uint256);
    function lastUpdateTimestamp() external view returns (uint256);
    function isStale() external view returns (bool);
    function attestor() external view returns (address);
    function stalenessThreshold() external view returns (uint256);

    // History
    function getReport(uint256 reportId) external view returns (NAVReport memory);
    function getLatestReport() external view returns (NAVReport memory);
    function reportCount() external view returns (uint256);

    // Update
    function updateNAV(NAVReport calldata report, bytes calldata signature) external;

    // Admin
    function setAttestor(address newAttestor) external;
    function setStalenessThreshold(uint256 newThreshold) external;
}

struct NAVReport {
    uint256 reportId;
    uint256 nav;           // NAV per share (18 decimals)
    uint256 totalAssets;   // Total assets in USD (18 decimals)
    uint256 totalShares;   // Total shares outstanding
    uint256 timestamp;     // Report timestamp
    bytes32 proofHash;     // Hash of supporting documentation
}
```

### Key Functions

#### updateNAV

```solidity
function updateNAV(NAVReport calldata report, bytes calldata signature) external;
```

Submit a new NAV attestation.

**Requirements:**
- Signature must be from authorized attestor
- Report timestamp must be newer than last update
- Report ID must be sequential

**Example:**
```typescript
// Attestor submits daily report
const report = {
    reportId: 100n,
    nav: parseUnits("1.000137", 18), // $1.000137 per share
    totalAssets: parseUnits("50000000", 18), // $50M
    totalShares: parseUnits("49993150", 18),
    timestamp: BigInt(Math.floor(Date.now() / 1000)),
    proofHash: keccak256(toUtf8Bytes("audit-report-100"))
};

const signature = await attestor.signMessage(
    keccak256(abiEncode(report))
);

await navOracle.updateNAV(report, signature);
```

#### currentNAV

```solidity
function currentNAV() external view returns (uint256);
```

Get current NAV per share.

**Returns:** NAV with 18 decimals

**Example:**
```typescript
const nav = await navOracle.currentNAV();
console.log(`NAV: $${formatUnits(nav, 18)}`);
// NAV: $1.000137
```

#### isStale

```solidity
function isStale() external view returns (bool);
```

Check if NAV data is stale (>24 hours old).

**Returns:** `true` if stale

**Example:**
```typescript
if (await navOracle.isStale()) {
    console.warn("NAV data is stale - some operations may be restricted");
}
```

---

## ssUSD

The rebasing stablecoin token.

### Interface

```solidity
interface IssUSD is IERC20 {
    // Events
    event Rebase(uint256 oldNav, uint256 newNav, uint256 totalSupply);
    event Deposit(address indexed user, address indexed token, uint256 amount, uint256 shares);
    event Redemption(address indexed user, address indexed token, uint256 shares, uint256 amount);

    // ERC20 overrides
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);

    // Share accounting
    function sharesOf(address account) external view returns (uint256);
    function totalShares() external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);

    // NAV
    function nav() external view returns (uint256);
    function rebase() external;

    // Mint/Burn (only TreasuryVault)
    function mint(address to, uint256 shares) external;
    function burn(address from, uint256 shares) external;
}
```

### Key Functions

#### balanceOf

```solidity
function balanceOf(address account) external view returns (uint256);
```

Get user's ssUSD balance (in assets, not shares).

**Note:** This value changes with NAV updates without any transfers.

**Example:**
```typescript
const balance = await ssUSD.balanceOf(userAddress);
console.log(`Balance: ${formatUnits(balance, 18)} ssUSD`);
```

#### sharesOf

```solidity
function sharesOf(address account) external view returns (uint256);
```

Get user's underlying shares (constant unless transferred).

**Example:**
```typescript
const shares = await ssUSD.sharesOf(userAddress);
const balance = await ssUSD.balanceOf(userAddress);
const effectiveNav = balance * BigInt(1e18) / shares;
console.log(`Effective NAV: $${formatUnits(effectiveNav, 18)}`);
```

#### convertToShares / convertToAssets

```solidity
function convertToShares(uint256 assets) external view returns (uint256);
function convertToAssets(uint256 shares) external view returns (uint256);
```

Convert between assets (ssUSD) and shares.

**Example:**
```typescript
// How many shares for 100 ssUSD?
const shares = await ssUSD.convertToShares(parseUnits("100", 18));

// How much ssUSD for these shares?
const assets = await ssUSD.convertToAssets(shares);
```

#### rebase

```solidity
function rebase() external;
```

Trigger a rebase to sync with latest NAV.

**Note:** Usually called automatically by the system.

---

## wssUSD

Wrapped ssUSD implementing ERC-4626 vault standard.

### Interface

```solidity
interface IwssUSD is IERC4626 {
    // ERC-4626 Standard
    function asset() external view returns (address);  // Returns ssUSD
    function totalAssets() external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);

    // Deposit/Withdraw
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function mint(uint256 shares, address receiver) external returns (uint256 assets);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    // Preview
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

### Key Functions

#### deposit

```solidity
function deposit(uint256 assets, address receiver) external returns (uint256 shares);
```

Deposit ssUSD to receive wssUSD.

**Example:**
```typescript
// Approve ssUSD
await ssUSD.approve(wssUSDAddress, parseUnits("100", 18));

// Wrap 100 ssUSD
const shares = await wssUSD.deposit(parseUnits("100", 18), userAddress);
console.log(`Received ${formatUnits(shares, 18)} wssUSD`);
```

#### redeem

```solidity
function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
```

Redeem wssUSD for ssUSD.

**Example:**
```typescript
// Unwrap all wssUSD
const wssUSDBalance = await wssUSD.balanceOf(userAddress);
const ssUSDReceived = await wssUSD.redeem(
    wssUSDBalance,
    userAddress,
    userAddress
);
console.log(`Received ${formatUnits(ssUSDReceived, 18)} ssUSD`);
```

---

## TreasuryVault

Manages collateral deposits, ssUSD minting, and redemptions.

### Interface

```solidity
interface ITreasuryVault {
    // Events
    event Deposit(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 ssUSDMinted
    );
    event Redemption(
        address indexed user,
        address indexed token,
        uint256 ssUSDBurned,
        uint256 amountRedeemed
    );
    event DepositsPaused(address indexed by);
    event DepositsUnpaused(address indexed by);
    event RedemptionsPaused(address indexed by);
    event RedemptionsUnpaused(address indexed by);

    // Deposit
    function deposit(
        address token,
        uint256 amount,
        uint256 minSsUSD
    ) external returns (uint256 ssUSDMinted);

    function depositFor(
        address token,
        uint256 amount,
        uint256 minSsUSD,
        address recipient
    ) external returns (uint256 ssUSDMinted);

    // Redemption
    function redeem(
        address token,
        uint256 ssUSDAmount,
        uint256 minTokens
    ) external returns (uint256 tokensRedeemed);

    function redeemFor(
        address token,
        uint256 ssUSDAmount,
        uint256 minTokens,
        address recipient
    ) external returns (uint256 tokensRedeemed);

    // Preview
    function previewDeposit(address token, uint256 amount)
        external view returns (uint256 ssUSDAmount);
    function previewRedeem(address token, uint256 ssUSDAmount)
        external view returns (uint256 tokenAmount);

    // State
    function getCollateralBalance(address token) external view returns (uint256);
    function getTotalCollateralValue() external view returns (uint256);
    function depositsPaused() external view returns (bool);
    function redemptionsPaused() external view returns (bool);

    // Admin
    function pauseDeposits() external;
    function unpauseDeposits() external;
    function pauseRedemptions() external;
    function unpauseRedemptions() external;
    function setDepositFee(uint256 feeBps) external;
    function setRedemptionFee(uint256 feeBps) external;
}
```

### Key Functions

#### deposit

```solidity
function deposit(
    address token,
    uint256 amount,
    uint256 minSsUSD
) external returns (uint256 ssUSDMinted);
```

Deposit collateral to mint ssUSD.

**Parameters:**
- `token`: Collateral token address (USDC, USDT)
- `amount`: Amount to deposit (in token decimals)
- `minSsUSD`: Minimum ssUSD to receive (slippage protection)

**Requirements:**
- Token must be approved in TokenRegistry
- Deposits must not be paused
- NAV must not be stale
- Deposit cap not exceeded

**Example:**
```typescript
// Approve USDC
await usdc.approve(treasuryAddress, parseUnits("1000", 6));

// Deposit 1000 USDC, expect at least 999 ssUSD
const ssUSDMinted = await treasury.deposit(
    USDC_ADDRESS,
    parseUnits("1000", 6),
    parseUnits("999", 18)
);
console.log(`Minted: ${formatUnits(ssUSDMinted, 18)} ssUSD`);
```

#### redeem

```solidity
function redeem(
    address token,
    uint256 ssUSDAmount,
    uint256 minTokens
) external returns (uint256 tokensRedeemed);
```

Burn ssUSD to redeem collateral.

**Parameters:**
- `token`: Collateral token to receive
- `ssUSDAmount`: Amount of ssUSD to burn
- `minTokens`: Minimum tokens to receive (slippage protection)

**Requirements:**
- Token must have redemptions enabled
- Redemptions must not be paused
- Sufficient collateral available

**Example:**
```typescript
// Redeem 500 ssUSD for USDC
const usdcReceived = await treasury.redeem(
    USDC_ADDRESS,
    parseUnits("500", 18),
    parseUnits("499", 6)  // Min USDC with fee
);
console.log(`Received: ${formatUnits(usdcReceived, 6)} USDC`);
```

#### previewDeposit / previewRedeem

```solidity
function previewDeposit(address token, uint256 amount) external view returns (uint256);
function previewRedeem(address token, uint256 ssUSDAmount) external view returns (uint256);
```

Preview expected output amounts.

**Example:**
```typescript
// Check deposit output
const expectedSsUSD = await treasury.previewDeposit(
    USDC_ADDRESS,
    parseUnits("1000", 6)
);
console.log(`Expected: ${formatUnits(expectedSsUSD, 18)} ssUSD`);

// Check redemption output
const expectedUSDC = await treasury.previewRedeem(
    USDC_ADDRESS,
    parseUnits("1000", 18)
);
console.log(`Expected: ${formatUnits(expectedUSDC, 6)} USDC`);
```

---

## Fee Structure

| Operation | Default Fee | Range |
|-----------|-------------|-------|
| Deposit | 0 bps | 0-50 bps |
| Redemption | 10 bps | 0-100 bps |

Fees are configurable via governance with timelock.

---

## Error Codes

| Contract | Error | Description |
|----------|-------|-------------|
| TokenRegistry | `TokenNotRegistered()` | Token not in registry |
| TokenRegistry | `TokenAlreadyRegistered()` | Token already exists |
| TokenRegistry | `DepositCapExceeded()` | Would exceed deposit cap |
| NAVOracle | `StaleNAV()` | NAV data too old |
| NAVOracle | `InvalidSignature()` | Attestor signature invalid |
| NAVOracle | `InvalidReportId()` | Report ID not sequential |
| ssUSD | `OnlyTreasury()` | Only treasury can mint/burn |
| TreasuryVault | `DepositsPaused()` | Deposits currently paused |
| TreasuryVault | `RedemptionsPaused()` | Redemptions currently paused |
| TreasuryVault | `SlippageExceeded()` | Output below minimum |
| TreasuryVault | `InsufficientCollateral()` | Not enough tokens to redeem |

---

## Related

- [ssUSD Overview](../stablecoin/overview.md)
- [Rebasing Mechanism](../stablecoin/rebasing.md)
- [Collateral Management](../stablecoin/collateral.md)
