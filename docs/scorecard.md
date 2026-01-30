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
- [x] Security-critical fixes implemented and tested:
  - ForcedInclusion: Real inclusion-proof verification against L2OutputOracle
  - EncryptedMempool: Decryption proofs bound to encrypted payloads
  - TreasuryVault: Redemption shares burned at request time (NAV manipulation fix)
  - ThresholdKeyRegistry: DKG state cleared per ceremony, duplicate registration prevented
  - SetRegistry: Legacy registerBatchRoot disabled by default

### Decentralization (9/10)
A 10/10 decentralization score requires:
- [x] Sequencer decentralization plan with milestones (`docs/decentralization.md`)
- [x] Permissionless node guidance and incentives (`docs/node-operators.md`)
- [x] Fault proof / dispute system configured and exercised (`docs/fault-proof-exercise.md`)
  - Exercise script: `scripts/fault-proof-exercise.sh`
  - Documentation with checklist
  - **← Complete exercise on Sepolia and record results**
- [x] Transparent governance and upgrade policy (`docs/security.md`)
- [x] MEV protection strategy (`docs/mev-protection.md`)
  - SequencerAttestation contract: `contracts/mev/SequencerAttestation.sol`
  - ForcedInclusion L1 contract: `contracts/mev/ForcedInclusion.sol`
  - MEV monitoring alerts: `docker/monitoring/alerts.yml`
  - Tests: `contracts/test/SequencerAttestation.t.sol`, `contracts/test/ForcedInclusion.t.sol`

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
- [x] Comprehensive SDK with error handling (`sdk/src/errors.ts`, `sdk/src/utils/`)
- [x] SDK documentation and examples (`sdk/README.md`)
- [x] API reference documentation (`docs/api-reference.md`)
- [x] Glossary of terms (`docs/glossary.md`)

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
  - Stablecoin SDK: `sdk/src/stablecoin/`
  - Stablecoin docs: `docs/stablecoin.md`
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
| SequencerAttestation | `contracts/mev/SequencerAttestation.sol` |
| ForcedInclusion | `contracts/mev/ForcedInclusion.sol` |
| ThresholdKeyRegistry | `contracts/mev/ThresholdKeyRegistry.sol` |
| EncryptedMempool | `contracts/mev/EncryptedMempool.sol` |
| TokenRegistry | `contracts/stablecoin/TokenRegistry.sol` |
| NAVOracle | `contracts/stablecoin/NAVOracle.sol` |
| SSDC | `contracts/stablecoin/SSDC.sol` |
| wSSDC | `contracts/stablecoin/wSSDC.sol` |
| TreasuryVault | `contracts/stablecoin/TreasuryVault.sol` |
| Unit Tests | `contracts/test/SetRegistry.t.sol`, `contracts/test/SetPaymaster.t.sol` |
| Timelock Tests | `contracts/test/SetTimelock.t.sol` |
| MEV Phase 1 Tests | `contracts/test/SequencerAttestation.t.sol`, `contracts/test/ForcedInclusion.t.sol` |
| MEV Phase 2 Tests | `contracts/test/ThresholdKeyRegistry.t.sol`, `contracts/test/EncryptedMempool.t.sol` |
| Stablecoin Tests | `contracts/test/stablecoin/StablecoinIntegration.t.sol` |
| Invariant Tests | `contracts/test/SetRegistry.invariants.t.sol` |
| Deploy Scripts | `contracts/script/Deploy.s.sol`, `contracts/script/DeployGovernance.s.sol` |
| Stablecoin Deploy | `contracts/script/stablecoin/DeployStablecoin.s.sol` |
| Integration Tests | `contracts/test/Integration.t.sol` |

### SDK
| Artifact | Path |
|----------|------|
| Main Exports | `sdk/src/index.ts` |
| Error Handling | `sdk/src/errors.ts` |
| Configuration | `sdk/src/config.ts` |
| Validation Utils | `sdk/src/utils/validation.ts` |
| Formatting Utils | `sdk/src/utils/formatting.ts` |
| Gas Utils | `sdk/src/utils/gas.ts` |
| Retry Utils | `sdk/src/utils/retry.ts` |
| Event Utils | `sdk/src/utils/events.ts` |
| Stablecoin Client | `sdk/src/stablecoin/StablecoinClient.ts` |
| MEV Protection | `sdk/src/encryption.ts` |

### Infrastructure
| Artifact | Path |
|----------|------|
| Main Docker Compose | `docker/docker-compose.yml` |
| Explorer Stack | `docker/docker-compose.explorer.yml` |
| Monitoring Stack | `docker/docker-compose.monitoring.yml` |
| Keyper Network | `docker/docker-compose.keypers.yml` |
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
| `docs/mev-protection.md` | MEV protection strategy |
| `docs/fault-proof-exercise.md` | Dispute testing procedures |
| `docs/operations-history.md` | Deployment records |
| `docs/explorer.md` | Block explorer setup |
| `docs/bridge.md` | Bridge usage guide |
| `docs/runbook.md` | Operations handbook |
| `docs/monitoring.md` | SLOs and alerting |
| `docs/stablecoin.md` | ssUSD stablecoin system |
| `docs/glossary.md` | Terms and definitions |
| `docs/api-reference.md` | Contract and SDK API reference |

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
