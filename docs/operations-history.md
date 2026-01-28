# Operations History

This document records all significant operational milestones for Set Chain.
Update as deployments and upgrades occur to maintain an auditable history.

## How to update this document
- Use UTC dates in YYYY-MM-DD.
- Include exact transaction hashes and block numbers.
- Record the git commit hash and tag for each deployment.
- Keep placeholders until actual data is available; do not delete sections.

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
| Commit hash | |
| Release tag | |
| Genesis hash | |
| Batch inbox | |
| Sequencer address | |
| Proposer address | |

### Endpoints

| Service | URL |
|---------|-----|
| L2 RPC | https://rpc.sepolia.setchain.io |
| L2 WebSocket | wss://ws.sepolia.setchain.io |
| Explorer | https://explorer.sepolia.setchain.io |
| Bridge | https://bridge.sepolia.setchain.io |
| Monitoring | |

### Contract Addresses

| Contract | Proxy | Implementation |
|----------|-------|----------------|
| SetRegistry | 0x... | 0x... |
| SetPaymaster | 0x... | 0x... |
| SetTimelock | 0x... | N/A |
| SequencerAttestation | 0x... | 0x... |
| ForcedInclusion | 0x... | 0x... |
| ThresholdKeyRegistry | 0x... | 0x... |
| EncryptedMempool | 0x... | 0x... |
| TokenRegistry | 0x... | 0x... |
| NAVOracle | 0x... | 0x... |
| ssUSD | 0x... | 0x... |
| wssUSD | 0x... | 0x... |
| TreasuryVault | 0x... | 0x... |

### L1 Contracts (Sepolia)

| Contract | Address |
|----------|---------|
| OptimismPortal | 0x... |
| L2OutputOracle | 0x... |
| SystemConfig | 0x... |
| L1StandardBridge | 0x... |
| DisputeGameFactory | 0x... |
| AnchorStateRegistry | 0x... |
| MIPS | 0x... |

### Deployment Log

```
# Record deployment transactions here
Date: YYYY-MM-DD
Commit: <git sha>
Tag: <release tag>

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

5. Explorer and bridge verified
   - Explorer indexed at: <block height>
   - Bridge deposit/withdraw test tx:

6. Monitoring and alerting
   - Alerts tested:
```

### Post-deploy Verification Checklist
- [ ] L2 RPC responds to `eth_chainId`
- [ ] L2 block production stable for 24h
- [ ] L1 batch submission observed
- [ ] L2 output submissions observed
- [ ] Explorer indexing verified
- [ ] Bridge deposit/withdraw works end-to-end
- [ ] Fault proof tooling deployed and reachable

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
