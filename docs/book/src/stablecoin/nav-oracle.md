# NAV Oracle

Deep dive into the NAVOracle contract that provides daily yield attestations.

## Overview

The NAVOracle is responsible for:
- Receiving daily NAV (Net Asset Value) attestations
- Storing NAV history for auditing
- Providing current NAV for deposit/redemption calculations
- Detecting stale data conditions

## How NAV Works

### NAV Calculation

NAV represents the value of each ssUSD share:

```
NAV = Total Assets / Total Shares

Where:
- Total Assets = Value of all T-Bill holdings + accrued yield
- Total Shares = Total ssUSD shares outstanding
```

### Daily Updates

```
Day 1: NAV = $1.000000 (initial)
Day 2: NAV = $1.000137 (+0.0137%, ~5% APY)
Day 3: NAV = $1.000274 (+0.0137%)
...
Day 365: NAV ≈ $1.050000 (~5% total yield)
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      NAVOracle                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────┐     ┌────────────────┐                  │
│  │  updateNAV()   │────▶│  NAV Reports   │                  │
│  │  (attestor)    │     │  (history)     │                  │
│  └────────────────┘     └────────────────┘                  │
│                               │                              │
│                               ▼                              │
│  ┌────────────────┐     ┌────────────────┐                  │
│  │  currentNAV()  │◀────│  Latest NAV    │                  │
│  │  (public)      │     │                │                  │
│  └────────────────┘     └────────────────┘                  │
│                                                              │
│  ┌────────────────┐     ┌────────────────┐                  │
│  │  isStale()     │────▶│  Staleness     │                  │
│  │  (check)       │     │  Threshold     │                  │
│  └────────────────┘     └────────────────┘                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## NAV Report Structure

```solidity
struct NAVReport {
    uint256 reportId;       // Sequential report number
    uint256 nav;            // NAV per share (18 decimals)
    uint256 totalAssets;    // Total asset value in USD (18 decimals)
    uint256 totalShares;    // Total shares outstanding
    uint256 timestamp;      // Report generation timestamp
    bytes32 proofHash;      // Hash of supporting documentation
}
```

### Example Report

```typescript
const report = {
    reportId: 100n,
    nav: parseUnits("1.000137", 18),           // $1.000137 per share
    totalAssets: parseUnits("50000000", 18),   // $50M total
    totalShares: parseUnits("49993150", 18),   // ~50M shares
    timestamp: BigInt(Date.now() / 1000),
    proofHash: keccak256(toUtf8Bytes("audit-hash-100"))
};
```

## Update Process

### Attestor Submission

```solidity
function updateNAV(
    NAVReport calldata report,
    bytes calldata signature
) external {
    // 1. Verify signature from authorized attestor
    bytes32 messageHash = keccak256(abi.encode(report));
    address recovered = ECDSA.recover(
        MessageHashUtils.toEthSignedMessageHash(messageHash),
        signature
    );
    require(recovered == attestor, "InvalidSignature");

    // 2. Verify report ID is sequential
    require(report.reportId == reportCount + 1, "InvalidReportId");

    // 3. Verify timestamp is newer
    require(report.timestamp > lastUpdateTimestamp, "ReportTooOld");

    // 4. Verify NAV change within limits
    if (reportCount > 0) {
        uint256 change = _calculateChange(currentNAV, report.nav);
        require(change <= maxNavChange, "NAVChangeTooLarge");
    }

    // 5. Store report
    reports[report.reportId] = report;
    currentNAV = report.nav;
    lastUpdateTimestamp = report.timestamp;
    reportCount++;

    emit NAVUpdated(
        report.reportId,
        report.nav,
        report.totalAssets,
        report.totalShares,
        report.timestamp
    );
}
```

### Change Limits

NAV changes are capped to prevent manipulation:

```solidity
uint256 public maxNavChange = 100; // 1% maximum daily change

function _calculateChange(uint256 oldNav, uint256 newNav) internal pure returns (uint256) {
    if (newNav >= oldNav) {
        return (newNav - oldNav) * 10000 / oldNav;
    } else {
        return (oldNav - newNav) * 10000 / oldNav;
    }
}
```

Typical daily change: ~1.37 bps (0.0137%)
Maximum allowed: 100 bps (1%)

## Staleness Detection

### Staleness Threshold

```solidity
uint256 public stalenessThreshold = 24 hours;

function isStale() public view returns (bool) {
    return block.timestamp > lastUpdateTimestamp + stalenessThreshold;
}
```

### Impact of Stale NAV

When NAV is stale, TreasuryVault:
- Blocks deposits (protect users from outdated pricing)
- May block redemptions (configurable)

```solidity
// In TreasuryVault
function deposit(...) external {
    require(!navOracle.isStale(), "StaleNAV");
    // ...
}
```

## Attestor Management

### Single Attestor Model

```solidity
address public attestor;

function setAttestor(address newAttestor) external onlyRole(ADMIN_ROLE) {
    require(newAttestor != address(0), "ZeroAddress");
    address oldAttestor = attestor;
    attestor = newAttestor;
    emit AttestorUpdated(oldAttestor, newAttestor);
}
```

### Attestor Responsibilities

The attestor must:
1. Calculate accurate NAV from T-Bill holdings
2. Submit daily updates (before staleness threshold)
3. Sign reports with authorized key
4. Maintain proof documentation

### Attestor Setup

```typescript
import { Wallet, keccak256, toUtf8Bytes } from "ethers";

// Attestor signs NAV report
async function signNAVReport(report: NAVReport, attestorWallet: Wallet) {
    const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
        ["uint256", "uint256", "uint256", "uint256", "uint256", "bytes32"],
        [
            report.reportId,
            report.nav,
            report.totalAssets,
            report.totalShares,
            report.timestamp,
            report.proofHash
        ]
    );

    const messageHash = keccak256(encoded);
    const signature = await attestorWallet.signMessage(ethers.getBytes(messageHash));

    return signature;
}
```

## Historical Data

### Query History

```solidity
function getReport(uint256 reportId) external view returns (NAVReport memory) {
    require(reportId <= reportCount, "ReportNotFound");
    return reports[reportId];
}

function getLatestReport() external view returns (NAVReport memory) {
    return reports[reportCount];
}

function reportCount() external view returns (uint256);
```

### Calculate Historical APY

```typescript
async function calculateAPY(days: number = 30) {
    const currentReport = await navOracle.getLatestReport();
    const pastReportId = currentReport.reportId - BigInt(days);
    const pastReport = await navOracle.getReport(pastReportId);

    const navChange = currentReport.nav - pastReport.nav;
    const dailyReturn = navChange / pastReport.nav / BigInt(days);
    const apy = dailyReturn * 365n * 10000n; // In basis points

    return Number(apy) / 100; // Convert to percentage
}
```

## Integration Examples

### Check NAV Status

```typescript
async function getNAVStatus() {
    const navOracle = new Contract(NAV_ORACLE_ADDRESS, NAVOracleABI, provider);

    const nav = await navOracle.currentNAV();
    const lastUpdate = await navOracle.lastUpdateTimestamp();
    const isStale = await navOracle.isStale();
    const report = await navOracle.getLatestReport();

    return {
        currentNAV: formatUnits(nav, 18),
        lastUpdate: new Date(Number(lastUpdate) * 1000),
        isStale,
        reportId: report.reportId.toString(),
        totalAssets: formatUnits(report.totalAssets, 18),
        totalShares: formatUnits(report.totalShares, 18)
    };
}
```

### Monitor NAV Updates

```typescript
const navOracle = new Contract(NAV_ORACLE_ADDRESS, NAVOracleABI, wsProvider);

navOracle.on("NAVUpdated", (reportId, nav, totalAssets, totalShares, timestamp) => {
    console.log(`NAV Report #${reportId}`);
    console.log(`  NAV: $${formatUnits(nav, 18)}`);
    console.log(`  Total Assets: $${formatUnits(totalAssets, 18)}`);
    console.log(`  Timestamp: ${new Date(Number(timestamp) * 1000)}`);

    // Calculate daily change
    // ...
});
```

### Staleness Alert

```typescript
async function checkStaleness() {
    const navOracle = new Contract(NAV_ORACLE_ADDRESS, NAVOracleABI, provider);

    const isStale = await navOracle.isStale();
    const lastUpdate = await navOracle.lastUpdateTimestamp();
    const threshold = await navOracle.stalenessThreshold();

    const hoursSinceUpdate = (Date.now() / 1000 - Number(lastUpdate)) / 3600;

    if (isStale) {
        console.error(`NAV is STALE! Last update: ${hoursSinceUpdate.toFixed(1)} hours ago`);
        // Alert operations team
    } else if (hoursSinceUpdate > Number(threshold) / 3600 * 0.8) {
        console.warn(`NAV update due soon. ${hoursSinceUpdate.toFixed(1)} hours since last update`);
    }
}
```

## Security Considerations

### Attestor Key Security

- Store attestor private key in HSM
- Use hardware wallet for signing
- Rotate keys periodically
- Monitor for unauthorized access

### Report Validation

The oracle validates:
1. **Signature**: Must be from authorized attestor
2. **Sequence**: Report ID must be sequential
3. **Timestamp**: Must be newer than previous
4. **Change Limit**: NAV change within bounds

### Emergency Procedures

If attestor is compromised:
1. Pause deposits/redemptions
2. Rotate attestor key via timelock
3. Investigate and remediate
4. Resume operations

```solidity
// Emergency attestor rotation (requires guardian signatures)
function emergencySetAttestor(
    address newAttestor,
    bytes[] calldata guardianSignatures
) external {
    // Verify guardian threshold
    require(
        _verifyGuardianSignatures(
            keccak256(abi.encode(newAttestor)),
            guardianSignatures
        ),
        "InvalidSignatures"
    );

    attestor = newAttestor;
    emit EmergencyAttestorChange(newAttestor);
}
```

## Configuration

### Parameters

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| stalenessThreshold | 24 hours | 12-48 hours | Time before NAV is stale |
| maxNavChange | 100 bps | 50-200 bps | Maximum daily NAV change |

### Updating Parameters

```solidity
function setStalenessThreshold(uint256 newThreshold) external onlyRole(ADMIN_ROLE) {
    require(newThreshold >= 12 hours && newThreshold <= 48 hours, "InvalidThreshold");
    uint256 oldThreshold = stalenessThreshold;
    stalenessThreshold = newThreshold;
    emit StalenessThresholdUpdated(oldThreshold, newThreshold);
}
```

## Related

- [ssUSD Overview](./overview.md)
- [Rebasing Mechanism](./rebasing.md)
- [Treasury Vault](./treasury-vault.md)
- [Stablecoin Contracts API](../contracts/stablecoin-contracts.md)
