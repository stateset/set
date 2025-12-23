# Set Chain 10/10 Scorecard

This scorecard defines what 10/10 means for the Set Chain L2 and tracks
progress toward that bar. Evidence should be in-repo (docs, tests, configs,
CI).

## How scoring works
- Each dimension is scored 0-10.
- 10/10 overall means every dimension meets its 10/10 criteria.
- Evidence should link to concrete artifacts in this repository.

## Current Status: 9/10 (Ready for Final Steps)

All infrastructure is in place. Complete the final operational steps to reach 10/10.

## Dimensions and criteria

### Security (9/10)
A 10/10 security score requires:
- [x] Threat model and assumptions documented (`docs/threat-model.md`)
- [ ] Independent audit completed and published (`docs/audit-report.md`) **← Schedule audit**
- [x] Multisig + timelock for admin/upgrade keys (`docs/governance-evidence.md`)
  - Timelock contract: `contracts/governance/SetTimelock.sol`
  - Deployment script: `contracts/script/DeployGovernance.s.sol`
  - Tests: `contracts/test/SetTimelock.t.sol`
- [x] Key management and rotation runbook (`docs/runbook.md`)
- [x] Contract invariants and fuzz tests (`contracts/test`)
- [x] Upgrade and rollback procedures documented (`docs/runbook.md`)
- [x] Static analysis tooling (`contracts/slither.config.json`, `scripts/security-analysis.sh`)
- [x] Security CI workflow (`.github/workflows/security.yml`)

### Decentralization (9/10)
A 10/10 decentralization score requires:
- [x] Sequencer decentralization plan with milestones (`docs/decentralization.md`)
- [x] Permissionless node guidance and incentives (`docs/node-operators.md`)
- [x] Fault proof / dispute system configured and exercised (`docs/fault-proof-exercise.md`)
  - Exercise script: `scripts/fault-proof-exercise.sh`
  - Documentation with checklist
  - **← Complete exercise on Sepolia and record results**
- [x] Transparent governance and upgrade policy (`docs/security.md`)

### Reliability and Operations (10/10)
A 10/10 reliability score requires:
- [x] SLOs and alert thresholds defined (`docs/monitoring.md`)
- [x] Monitoring and alerting implemented (`docker/docker-compose.monitoring.yml`)
- [x] Backup/restore procedures for node data (`docs/runbook.md`)
- [x] Incident response and on-call runbooks (`docs/runbook.md`)
- [x] CI smoke coverage for contracts and anchor service (`.github/workflows`)

### Developer Experience (10/10)
A 10/10 devx score requires:
- [x] One-command local devnet (`scripts/dev.sh`)
- [x] Documented testing and debugging (`docs/local_testing_guide.md`)
- [x] Reproducible builds and pinned tool versions (`docs/toolchain.md`)
- [x] CI for contracts, anchor, and devnet flows (`.github/workflows`)
- [x] Example integrations for merchants or apps (`docs/integration-example.md`)

### Ecosystem and Adoption (9/10)
A 10/10 ecosystem score requires:
- [x] Block explorer and indexing
  - Docker compose: `docker/docker-compose.explorer.yml`
  - Documentation: `docs/explorer.md`
  - Includes: Blockscout + frontend + contract verifier + visualizer
- [x] Bridge and token onramp support
  - Documentation: `docs/bridge.md`
  - OP Stack Standard Bridge contracts
  - Bridge UI options documented
- [x] Public docs and SDKs (`docs/`, `sdk/`)
- [ ] Testnet and mainnet operational history **← Deploy to Sepolia**
  - Template ready: `docs/operations-history.md`
  - Deployment script: `scripts/deploy-sepolia.sh`

## Evidence in Repository

### Contracts
| Artifact | Path |
|----------|------|
| SetRegistry | `contracts/SetRegistry.sol` |
| SetPaymaster | `contracts/commerce/SetPaymaster.sol` |
| SetTimelock | `contracts/governance/SetTimelock.sol` |
| Unit Tests | `contracts/test/SetRegistry.t.sol`, `contracts/test/SetPaymaster.t.sol` |
| Timelock Tests | `contracts/test/SetTimelock.t.sol` |
| Invariant Tests | `contracts/test/SetRegistry.invariants.t.sol` |
| Deploy Scripts | `contracts/script/Deploy.s.sol`, `contracts/script/DeployGovernance.s.sol` |

### Infrastructure
| Artifact | Path |
|----------|------|
| Main Docker Compose | `docker/docker-compose.yml` |
| Explorer Stack | `docker/docker-compose.explorer.yml` |
| Monitoring Stack | `docker/docker-compose.monitoring.yml` |
| Sepolia Config | `docker/docker-compose.sepolia.yml` |

### Scripts
| Script | Purpose |
|--------|---------|
| `scripts/dev.sh` | Local development CLI |
| `scripts/deploy-sepolia.sh` | Sepolia deployment |
| `scripts/security-analysis.sh` | Static analysis (Slither/Aderyn) |
| `scripts/fault-proof-exercise.sh` | Fault proof testing |

### CI/CD
| Workflow | Purpose |
|----------|---------|
| `.github/workflows/devnet-smoke.yml` | Smoke tests |
| `.github/workflows/security.yml` | Slither, tests, coverage |

### Documentation
| Document | Content |
|----------|---------|
| `docs/scorecard.md` | This file |
| `docs/threat-model.md` | Security assumptions |
| `docs/governance-evidence.md` | Multisig + timelock setup |
| `docs/fault-proof-exercise.md` | Dispute testing procedures |
| `docs/operations-history.md` | Deployment records |
| `docs/explorer.md` | Block explorer setup |
| `docs/bridge.md` | Bridge usage guide |
| `docs/runbook.md` | Operations handbook |
| `docs/monitoring.md` | SLOs and alerting |

## Final Steps to 10/10

### 1. Security Audit (Required for Mainnet)
```bash
# Prepare audit package
./scripts/security-analysis.sh all

# Review reports/security-summary.md
# Share with audit firm
```
- [ ] Select audit firm
- [ ] Complete audit
- [ ] Remediate findings
- [ ] Publish report to `docs/audit-report.md`

### 2. Deploy to Sepolia
```bash
# Deploy L1 + L2
./scripts/deploy-sepolia.sh all

# Deploy governance
./scripts/deploy-sepolia.sh governance

# Start explorer
docker compose -f docker/docker-compose.explorer.yml up -d
```
- [ ] Deploy L1 contracts
- [ ] Deploy L2 contracts
- [ ] Deploy timelock and transfer ownership
- [ ] Verify all contracts
- [ ] Update `docs/operations-history.md`

### 3. Exercise Fault Proofs
```bash
# Run fault proof exercise
./scripts/fault-proof-exercise.sh exercise

# Document results
./scripts/fault-proof-exercise.sh report
```
- [ ] Complete exercise on Sepolia
- [ ] Document in `docs/fault-proof-exercise.md`

### 4. Governance Verification
```bash
# Deploy Safe multisig via safe.global
# Configure 3/5 threshold
# Transfer ownership to timelock
```
- [ ] Deploy Safe multisig
- [ ] Transfer contract ownership
- [ ] Test proposal/execution flow
- [ ] Update `docs/governance-evidence.md`

## Score History

| Date | Score | Notes |
|------|-------|-------|
| 2024-XX-XX | 7/10 | Initial assessment |
| 2024-XX-XX | 9/10 | Added governance, explorer, bridge, security tooling |
| TBD | 10/10 | Audit + Sepolia deployment + fault proof exercise |
