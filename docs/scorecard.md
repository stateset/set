# Set Chain 10/10 Scorecard

This scorecard defines what 10/10 means for the Set Chain L2 and tracks
progress toward that bar. Evidence should be in-repo (docs, tests, configs,
CI).

## How scoring works
- Each dimension is scored 0-10.
- 10/10 overall means every dimension meets its 10/10 criteria.
- Evidence should link to concrete artifacts in this repository.

## Dimensions and criteria

### Security
A 10/10 security score requires:
- [x] Threat model and assumptions documented (`docs/threat-model.md`)
- [ ] Independent audit completed and published (`docs/audit-report.md`)
- [ ] Multisig + timelock for admin/upgrade keys (`docs/governance-evidence.md`)
- [x] Key management and rotation runbook (`docs/runbook.md`)
- [x] Contract invariants and fuzz tests (`contracts/test`)
- [x] Upgrade and rollback procedures documented (`docs/runbook.md`)

### Decentralization
A 10/10 decentralization score requires:
- [x] Sequencer decentralization plan with milestones (`docs/decentralization.md`)
- [x] Permissionless node guidance and incentives (`docs/node-operators.md`)
- [ ] Fault proof / dispute system configured and exercised (`docs/fault-proof-exercise.md`)
- [x] Transparent governance and upgrade policy (`docs/security.md`)

### Reliability and Operations
A 10/10 reliability score requires:
- [x] SLOs and alert thresholds defined (`docs/monitoring.md`)
- [x] Monitoring and alerting implemented (`docker/docker-compose.monitoring.yml`)
- [x] Backup/restore procedures for node data (`docs/runbook.md`)
- [x] Incident response and on-call runbooks (`docs/runbook.md`)
- [x] CI smoke coverage for contracts and anchor service (`.github/workflows`)

### Developer Experience
A 10/10 devx score requires:
- [x] One-command local devnet (`scripts/dev.sh`)
- [x] Documented testing and debugging (`docs/local_testing_guide.md`)
- [x] Reproducible builds and pinned tool versions (`docs/toolchain.md`)
- [x] CI for contracts, anchor, and devnet flows (`.github/workflows`)
- [x] Example integrations for merchants or apps (`docs/integration-example.md`)

### Ecosystem and Adoption
A 10/10 ecosystem score requires:
- [ ] Block explorer and indexing
- [ ] Bridge and token onramp support
- [x] Public docs and SDKs (`docs/`, `sdk/`)
- [ ] Testnet and mainnet operational history

## Current evidence in repo
- Local devnet scripts: `scripts/dev.sh`, `scripts/start-local-anvil.sh`
- Contract tests: `contracts/test`
- Anchor service and tests: `anchor/src`, `anchor/tests`
- OP Stack configs and tooling: `op-stack/`, `scripts/`
- Monitoring hooks: `anchor/src/health.rs`, `README.md` monitoring section
- SLOs and alert suggestions: `docs/monitoring.md`
- Governance and decentralization docs: `docs/security.md`, `docs/decentralization.md`
- Fault proof operations: `docs/fault-proofs.md`, `scripts/validate-ops-config.sh`
- Monitoring stack: `docker/docker-compose.monitoring.yml`, `docker/monitoring/`
- Node operator guidance: `docs/node-operators.md`
- Integration example: `docs/integration-example.md`
- Toolchain pinning: `rust-toolchain.toml`, `.foundry-version`, `docs/toolchain.md`
- Explorer and bridge guidance: `docs/explorer.md`, `docs/bridge.md`
- Operations history log: `docs/operations-history.md`
- Audit and governance evidence: `docs/audit-report.md`, `docs/governance-evidence.md`
- Fault proof exercise log: `docs/fault-proof-exercise.md`

## Next steps to 10/10
- Publish audit results and multisig/timelock deployment evidence.
- Exercise fault-proof operations against L1 disputes and record outcomes.
- Publish explorer and bridge deployment details in `docs/operations-history.md`.
- Record testnet and mainnet operational history in `docs/operations-history.md`.
