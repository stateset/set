# Security Operations

Security procedures and best practices for Set Chain operations.

## Access Control

### Role Hierarchy

```
ADMIN_ROLE
├── Can grant/revoke all roles
├── Can upgrade contracts (via timelock)
└── Should be multisig

OPERATOR_ROLE
├── Can pause/unpause operations
├── Can update parameters (via timelock)
└── Cannot upgrade contracts

ATTESTOR_ROLE
├── Can submit NAV attestations
└── Single key, hardware-secured

GUARDIAN_ROLE
├── Can execute emergency actions
├── Requires threshold (3-of-5)
└── Used for security incidents only
```

### Multisig Configuration

**Admin Multisig (Gnosis Safe):**
- Threshold: 3-of-5
- Signers: Core team members
- Hardware wallets required

**Guardian Multisig:**
- Threshold: 3-of-5
- Signers: Security-focused members
- 24/7 availability required

```typescript
// Example Gnosis Safe setup
import Safe from "@safe-global/protocol-kit";

const adminSafe = await Safe.create({
    ethAdapter,
    safeAddress: ADMIN_SAFE_ADDRESS
});

// Propose upgrade
const tx = await adminSafe.createTransaction({
    safeTransactionData: {
        to: TIMELOCK_ADDRESS,
        value: "0",
        data: timelock.interface.encodeFunctionData("schedule", [
            targetContract,
            0,
            upgradeCalldata,
            0  // UPGRADE type
        ])
    }
});

// Sign and execute (requires 3 signers)
await adminSafe.signTransaction(tx);
await adminSafe.executeTransaction(tx);
```

## Emergency Procedures

### Pause Protocol

When to pause:
- Active exploit detected
- Critical vulnerability discovered
- Abnormal market conditions
- Oracle manipulation detected

```typescript
async function emergencyPause() {
    const guardianSafe = await Safe.create({
        ethAdapter,
        safeAddress: GUARDIAN_SAFE_ADDRESS
    });

    // Prepare pause calls
    const pauseDeposits = treasury.interface.encodeFunctionData("pauseDeposits");
    const pauseRedemptions = treasury.interface.encodeFunctionData("pauseRedemptions");

    // Create batch transaction
    const tx = await guardianSafe.createTransaction({
        safeTransactionData: [
            { to: TREASURY_ADDRESS, value: "0", data: pauseDeposits },
            { to: TREASURY_ADDRESS, value: "0", data: pauseRedemptions }
        ]
    });

    // Execute immediately (emergency powers)
    await guardianSafe.executeTransaction(tx);

    console.log("Protocol paused");

    // Notify team
    await alerting.critical("EMERGENCY: Protocol Paused", {
        pausedBy: guardianSafe.getAddress(),
        timestamp: Date.now()
    });
}
```

### Emergency Upgrade

For critical vulnerabilities requiring immediate fix:

```typescript
async function emergencyUpgrade(
    newImplementation: string,
    guardianSignatures: string[]
) {
    const timelock = new Contract(TIMELOCK_ADDRESS, SetTimelockABI, wallet);

    // Prepare upgrade call
    const upgradeData = registry.interface.encodeFunctionData(
        "upgradeToAndCall",
        [newImplementation, "0x"]
    );

    // Emergency execute (bypasses delay with guardian signatures)
    await timelock.emergencyExecute(
        REGISTRY_ADDRESS,
        0,
        upgradeData,
        guardianSignatures
    );

    console.log("Emergency upgrade executed");

    // Post-upgrade verification
    const impl = await getImplementation(REGISTRY_ADDRESS);
    if (impl !== newImplementation) {
        throw new Error("Upgrade verification failed");
    }
}
```

### Emergency Withdrawal

In catastrophic scenarios, allow users to withdraw collateral:

```solidity
// In TreasuryVault.sol
function emergencyWithdraw(
    address token,
    address recipient
) external whenPaused onlyRole(GUARDIAN_ROLE) {
    uint256 shares = ssUSD.sharesOf(recipient);
    require(shares > 0, "No shares");

    // Calculate proportional collateral
    uint256 totalShares = ssUSD.totalShares();
    uint256 tokenBalance = IERC20(token).balanceOf(address(this));
    uint256 amount = tokenBalance * shares / totalShares;

    // Burn shares and transfer
    ssUSD.burn(recipient, shares);
    IERC20(token).safeTransfer(recipient, amount);

    emit EmergencyWithdrawal(recipient, token, amount);
}
```

## Security Monitoring

### Suspicious Activity Detection

```typescript
// Monitor for suspicious patterns
async function monitorSuspiciousActivity() {
    const provider = new JsonRpcProvider(L2_RPC_URL);

    // Large single transactions
    treasury.on("Deposit", async (user, token, amount, ssUSDMinted) => {
        const amountUSD = Number(formatUnits(amount, 6));

        if (amountUSD > 1_000_000) {  // $1M threshold
            alerting.warning("Large deposit detected", {
                user,
                amount: amountUSD,
                token
            });
        }
    });

    // Rapid withdrawal pattern
    const recentRedemptions = new Map<string, number[]>();

    treasury.on("Redemption", async (user, token, ssUSDBurned, amountRedeemed) => {
        const now = Date.now();
        const userHistory = recentRedemptions.get(user) || [];

        // Track last 10 minutes
        const recent = userHistory.filter(t => now - t < 600000);
        recent.push(now);
        recentRedemptions.set(user, recent);

        if (recent.length > 10) {  // More than 10 redemptions in 10 min
            alerting.warning("Rapid redemption pattern", {
                user,
                count: recent.length,
                period: "10 minutes"
            });
        }
    });

    // Flash loan detection (same block deposit + redemption)
    const blockDeposits = new Map<number, Set<string>>();

    treasury.on("Deposit", async (user, token, amount, ssUSDMinted, event) => {
        const block = event.blockNumber;
        const deposits = blockDeposits.get(block) || new Set();
        deposits.add(user);
        blockDeposits.set(block, deposits);
    });

    treasury.on("Redemption", async (user, token, ssUSDBurned, amountRedeemed, event) => {
        const block = event.blockNumber;
        const deposits = blockDeposits.get(block);

        if (deposits?.has(user)) {
            alerting.critical("Possible flash loan attack", {
                user,
                block,
                ssUSDBurned: formatUnits(ssUSDBurned, 18),
                amountRedeemed: formatUnits(amountRedeemed, 6)
            });
        }
    });
}
```

### Contract Monitoring

```typescript
// Monitor for unauthorized changes
async function monitorContractChanges() {
    // Implementation changes
    const proxyContracts = [
        { name: "SetRegistry", address: REGISTRY_ADDRESS },
        { name: "TreasuryVault", address: TREASURY_ADDRESS },
        { name: "ssUSD", address: SSUSD_ADDRESS }
    ];

    for (const contract of proxyContracts) {
        const impl = await getImplementation(contract.address);

        // Store and compare
        const previousImpl = await db.get(`impl:${contract.name}`);

        if (previousImpl && previousImpl !== impl) {
            alerting.critical("Contract implementation changed", {
                contract: contract.name,
                previousImpl,
                newImpl: impl
            });
        }

        await db.set(`impl:${contract.name}`, impl);
    }

    // Role changes
    const roleChanges = [
        { contract: "SetRegistry", roles: ["ADMIN_ROLE", "OPERATOR_ROLE"] },
        { contract: "TreasuryVault", roles: ["ADMIN_ROLE", "PAUSER_ROLE"] }
    ];

    // ... monitor role grants/revokes
}
```

## Key Management

### Hardware Security Modules

**Attestor Key:**
```
- Stored in HSM (AWS CloudHSM / Azure HSM)
- Never exported
- Signing happens in HSM
- Access logged and audited
```

**Guardian Keys:**
```
- Individual hardware wallets (Ledger/Trezor)
- Geographically distributed
- Regular key rotation (quarterly)
- Backup keys in secure locations
```

### Key Rotation

```typescript
async function rotateAttestor(newAttestor: string) {
    const timelock = new Contract(TIMELOCK_ADDRESS, SetTimelockABI, adminSafe);

    // Schedule attestor update
    const updateData = navOracle.interface.encodeFunctionData(
        "setAttestor",
        [newAttestor]
    );

    await timelock.schedule(
        NAV_ORACLE_ADDRESS,
        0,
        updateData,
        1  // PARAMETER type - 24h delay
    );

    console.log("Attestor rotation scheduled");
    console.log("New attestor will be active in 24 hours");
}
```

## Audit Trail

### Event Logging

All security-relevant events are logged:

```typescript
interface SecurityEvent {
    timestamp: number;
    type: "pause" | "unpause" | "upgrade" | "role_change" | "emergency";
    actor: string;
    target: string;
    details: Record<string, unknown>;
    txHash: string;
}

async function logSecurityEvent(event: SecurityEvent) {
    // Log to database
    await db.insert("security_events", event);

    // Log to blockchain (SetRegistry.logEvent)
    await registry.logEvent(
        keccak256(toUtf8Bytes(event.type)),
        encodeEventData(event)
    );

    // External audit log (immutable)
    await auditLog.append(event);
}
```

### Regular Audits

**Continuous:**
- Automated vulnerability scanning
- Dependency audits (npm/cargo audit)
- Static analysis (Slither)

**Quarterly:**
- Third-party security review
- Penetration testing
- Access control audit

**Annually:**
- Full smart contract audit
- Infrastructure audit
- Incident response drill

## Incident Response

### Severity Levels

| Level | Description | Response Time | Examples |
|-------|-------------|---------------|----------|
| P0 | Active exploit | Immediate | Funds at risk, protocol compromise |
| P1 | Critical vulnerability | < 1 hour | Unpatched vuln, severe bug |
| P2 | High severity | < 4 hours | Potential exploit, DoS |
| P3 | Medium severity | < 24 hours | Non-critical bug, edge case |
| P4 | Low severity | < 1 week | Minor issues, improvements |

### Response Procedure

```
1. DETECT
   └── Monitoring alert / Bug report / Community report

2. ASSESS (< 15 min)
   ├── Determine severity
   ├── Identify affected components
   └── Estimate impact

3. CONTAIN (P0/P1: immediate)
   ├── Pause affected operations
   ├── Notify response team
   └── Preserve evidence

4. ERADICATE
   ├── Develop fix
   ├── Review fix (2 reviewers min)
   └── Deploy via emergency or standard process

5. RECOVER
   ├── Unpause operations
   ├── Monitor for recurrence
   └── User communication

6. POST-MORTEM
   ├── Document incident
   ├── Identify improvements
   └── Update procedures
```

### Communication

```typescript
// Status page updates
async function updateStatus(incident: Incident) {
    await statusPage.createIncident({
        name: incident.title,
        status: incident.status,  // investigating | identified | monitoring | resolved
        body: incident.publicDescription,
        component_ids: incident.affectedComponents,
        notify: true
    });
}

// User notification
async function notifyUsers(message: string, severity: "info" | "warning" | "critical") {
    // In-app banner
    await notifications.broadcast({
        type: severity,
        message,
        dismissable: severity === "info"
    });

    // Twitter/Discord for critical
    if (severity === "critical") {
        await twitter.post(message);
        await discord.announce(message);
    }
}
```

## Related

- [Deployment Guide](./deployment.md)
- [Monitoring](./monitoring.md)
- [Runbook](./runbook.md)
