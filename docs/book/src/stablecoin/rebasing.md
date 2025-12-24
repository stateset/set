# Rebasing Mechanism

ssUSD is a **rebasing token** - your balance automatically increases as yield accrues, without any action required.

## How Rebasing Works

### Shares vs Balance

ssUSD uses a **shares-based** accounting system:

```
Balance = Shares × NAV per Share
```

| Component | Description | Changes |
|-----------|-------------|---------|
| **Shares** | Your ownership stake | Only on deposit/withdrawal |
| **NAV per Share** | Net Asset Value | Daily (yield accrual) |
| **Balance** | What you see | Automatically increases |

### Example

```
Day 0: Deposit 1,000 USDC
├── Shares received: 1,000
├── NAV per share: $1.00
└── Balance: 1,000 × $1.00 = 1,000 ssUSD

Day 30: (5% APY accruing)
├── Shares: 1,000 (unchanged)
├── NAV per share: $1.00411
└── Balance: 1,000 × $1.00411 = 1,004.11 ssUSD

Day 365:
├── Shares: 1,000 (unchanged)
├── NAV per share: $1.05127
└── Balance: 1,000 × $1.05127 = 1,051.27 ssUSD
```

## Implementation Details

### Share Calculation

When depositing:

```solidity
function _mintShares(address to, uint256 amount) internal {
    // At 1:1 NAV, shares = amount
    // If NAV > 1, you get fewer shares for same USD value
    uint256 sharesToMint = (amount * 1e18) / getNavPerShare();
    _shares[to] += sharesToMint;
    _totalShares += sharesToMint;
}
```

### Balance Calculation

```solidity
function balanceOf(address account) public view returns (uint256) {
    return (_shares[account] * getNavPerShare()) / 1e18;
}

function getNavPerShare() public view returns (uint256) {
    uint256 totalAssets = navOracle.getTotalAssets();
    uint256 totalShares = _totalShares;

    if (totalShares == 0) {
        return 1e18; // Initial NAV = $1.00
    }

    return (totalAssets * 1e18) / totalShares;
}
```

## NAV Updates

### Daily Attestation

The NAV is updated daily by an authorized attestor:

```solidity
// Called by attestor (company representative)
navOracle.attestNAV(
    1050000000000000000000,  // Total assets: $1,050 (18 decimals)
    20240115,                 // Report date: Jan 15, 2024
    bytes32(proofHash)        // Off-chain proof hash
);
```

### NAV Change Limits

To prevent manipulation, NAV changes are limited:

| Direction | Max Change | Rationale |
|-----------|------------|-----------|
| Increase | +5% per day | Prevents artificial inflation |
| Decrease | -1% per day | Protects against errors |

```solidity
function _validateNAVChange(uint256 oldNav, uint256 newNav) internal pure {
    uint256 maxIncrease = (oldNav * 105) / 100; // +5%
    uint256 maxDecrease = (oldNav * 99) / 100;  // -1%

    require(newNav <= maxIncrease, "NAV increase too large");
    require(newNav >= maxDecrease, "NAV decrease too large");
}
```

## Transfer Behavior

When transferring ssUSD, shares are transferred (not balances):

```solidity
function transfer(address to, uint256 amount) public returns (bool) {
    // Convert amount to shares
    uint256 sharesToTransfer = (amount * 1e18) / getNavPerShare();

    // Transfer shares
    _shares[msg.sender] -= sharesToTransfer;
    _shares[to] += sharesToTransfer;

    // Emit with balance amount (what user expects)
    emit Transfer(msg.sender, to, amount);
    return true;
}
```

### Precision Considerations

Due to rounding, transferred amounts may differ slightly:

```typescript
// Sending exactly 100 ssUSD
const amount = parseUnits("100", 18);
await ssUSD.transfer(recipient, amount);

// Recipient may receive 99.999999... or 100.000001...
// due to share → balance → share conversion
```

## Querying Balances

### Get Balance (includes yield)

```typescript
const balance = await ssUSD.balanceOf(address);
// Returns current balance including all accrued yield
```

### Get Shares (underlying)

```typescript
const shares = await ssUSD.sharesOf(address);
// Returns share count (doesn't change with yield)
```

### Get NAV per Share

```typescript
const navPerShare = await ssUSD.getNavPerShare();
// Returns current NAV (e.g., 1.05e18 = $1.05)
```

### Calculate Expected Balance

```typescript
const shares = await ssUSD.sharesOf(address);
const navPerShare = await ssUSD.getNavPerShare();
const expectedBalance = (shares * navPerShare) / BigInt(1e18);
```

## Events

### NAV Updated

```solidity
event NAVUpdated(
    uint256 indexed reportDate,
    uint256 totalAssets,
    uint256 totalShares,
    uint256 navPerShare,
    address attestor
);
```

### Transfer (with shares)

```solidity
event Transfer(address indexed from, address indexed to, uint256 value);
event SharesTransferred(address indexed from, address indexed to, uint256 shares);
```

## Comparison: ssUSD vs wssUSD

| Aspect | ssUSD | wssUSD |
|--------|-------|--------|
| Balance changes | Yes (rebases) | No |
| Yield received | Auto in balance | In share price |
| DeFi compatible | Limited | Yes (ERC-4626) |
| Tax events | Each rebase | Only on unwrap |
| Best for | Holding, payments | AMMs, lending |

## Edge Cases

### First Depositor

The first depositor sets the initial NAV:

```solidity
if (_totalShares == 0) {
    // First deposit: 1 share = $1.00
    sharesToMint = amount;
} else {
    sharesToMint = (amount * _totalShares) / totalAssets;
}
```

### Zero Shares

If someone holds 0 shares, their balance is always 0:

```solidity
balanceOf(zeroShareHolder) = 0 × navPerShare = 0
```

### Maximum Supply

Total supply is bounded by:
- `totalSupply = totalShares × navPerShare / 1e18`
- As NAV increases, total supply increases proportionally

## Best Practices

### For Holders

1. **Check shares, not just balance**: Shares represent your true ownership
2. **Monitor NAV updates**: Large changes may indicate issues
3. **Account for precision**: Small rounding errors are normal

### For Integrators

1. **Use `sharesOf()` for accounting**: More stable than `balanceOf()`
2. **Handle rebasing in UI**: Update displayed balances after NAV changes
3. **Consider wssUSD for DeFi**: Simpler integration without rebasing

## Next Steps

- [NAV Oracle](./nav-oracle.md) - How NAV is attested
- [wssUSD](./wssusd.md) - Non-rebasing alternative
- [Treasury Vault](./treasury-vault.md) - Deposit/redemption mechanics
