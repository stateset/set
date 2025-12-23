# Operations History

This document records all significant operational milestones for Set Chain.
Update as deployments and upgrades occur to maintain an auditable history.

## Deployment Checklist

Before recording a deployment, ensure:

- [ ] All contracts deployed and verified
- [ ] Governance (multisig + timelock) configured
- [ ] Explorer running and indexed
- [ ] Bridge functional
- [ ] Monitoring and alerting configured
- [ ] Runbook tested

---

## Sepolia Testnet

### Deployment

| Item | Value |
|------|-------|
| Launch Date | YYYY-MM-DD |
| Chain ID | 84532001 |
| L1 Settlement | Sepolia (11155111) |
| Block Time | 2 seconds |

### Endpoints

| Service | URL |
|---------|-----|
| L2 RPC | https://rpc.sepolia.setchain.io |
| L2 WebSocket | wss://ws.sepolia.setchain.io |
| Explorer | https://explorer.sepolia.setchain.io |
| Bridge | https://bridge.sepolia.setchain.io |

### Contract Addresses

| Contract | Proxy | Implementation |
|----------|-------|----------------|
| SetRegistry | 0x... | 0x... |
| SetPaymaster | 0x... | 0x... |
| SetTimelock | 0x... | N/A |

### L1 Contracts (Sepolia)

| Contract | Address |
|----------|---------|
| OptimismPortal | 0x... |
| L2OutputOracle | 0x... |
| SystemConfig | 0x... |
| L1StandardBridge | 0x... |
| DisputeGameFactory | 0x... |

### Deployment Log

```
# Record deployment transactions here
Date: YYYY-MM-DD

1. L1 contracts deployed
   - Tx: 0x...
   - Block: ...

2. L2 genesis generated
   - Genesis hash: 0x...

3. L2 contracts deployed
   - SetRegistry: 0x...
   - SetPaymaster: 0x...

4. Governance deployed
   - Timelock: 0x...
   - Ownership transferred
```

---

## Mainnet

### Deployment

| Item | Value |
|------|-------|
| Launch Date | TBD |
| Chain ID | 84532001 |
| L1 Settlement | Ethereum Mainnet (1) |
| Block Time | 2 seconds |

### Endpoints

| Service | URL |
|---------|-----|
| L2 RPC | https://rpc.setchain.io |
| L2 WebSocket | wss://ws.setchain.io |
| Explorer | https://explorer.setchain.io |
| Bridge | https://bridge.setchain.io |

### Contract Addresses

_To be filled after mainnet deployment_

---

## Upgrade History

### [Date] - Upgrade Name

**Summary:** Brief description of the upgrade

**Changes:**
- Change 1
- Change 2

**Governance:**
- Proposal TX: 0x...
- Execution TX: 0x...
- Timelock delay: 24 hours

**Verification:**
- [ ] Contracts verified on explorer
- [ ] Functionality tested
- [ ] No user funds at risk

---

## Incident History

### [Date] - Incident Name

**Severity:** Low / Medium / High / Critical

**Summary:** What happened

**Impact:** Users affected, funds at risk, downtime

**Timeline:**
- HH:MM UTC - Issue detected
- HH:MM UTC - Mitigation started
- HH:MM UTC - Resolved

**Root Cause:** Why it happened

**Resolution:** How it was fixed

**Action Items:**
- [ ] Prevent recurrence
- [ ] Update monitoring
- [ ] Update runbook

---

## Audit History

| Audit | Firm | Date | Scope | Report |
|-------|------|------|-------|--------|
| Pre-launch | TBD | TBD | SetRegistry, SetPaymaster | `docs/audit-report.md` |

---

## References

- Governance: `docs/governance-evidence.md`
- Audit Details: `docs/audit-report.md`
- Fault Proofs: `docs/fault-proof-exercise.md`
- Runbook: `docs/runbook.md`
