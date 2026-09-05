# Changelog

All notable changes to Set will be documented in this file.

## [Unreleased]

## [0.3.11] - 2026-09-05

Agent spending policy safety and external signer support.

Compatibility: the SDK requires the updated V2 policy getter and revocation API;
existing policy deployments must be upgraded or replaced before using it. Policy
limits must fit uint128; callers using uint256.max must migrate to uint128.max.
This release does not deploy or upgrade contracts. Sepolia remains on hold.

### Fixed

- V2 agent policy rejects packed-accounting overflow for limits, spending and
  commitments; computes the combined collateral floor at full uint256 width
- SDK policy getter ABI matches Solidity's packed field order
- AgentClient snapshots deployment addresses so later caller mutations cannot
  redirect approval targets

### Added

- Explicit agent policy revocation that preserves daily usage and outstanding
  commitments while allowing authorized refund/settlement commitment release
- Provider-connected external signer support for AgentClient, with revocation-aware
  status/preflight and documentation of the unrestricted-transfer enforcement boundary
- Agent policy boundary/fuzz regressions and critical contract smoke-suite coverage

## [0.3.10] - 2026-09-05

Local launch/reset safety and fail-closed release validation. Reset now requires
the node to be stopped explicitly and archives artifacts instead of deleting them.
Full rollup lifecycle assurance remains incomplete; Sepolia deployment stays on hold.

### Fixed

- Anvil reset no longer kills port/name-matched processes or removes containers;
  reserves the idle local RPC port and archives scoped artifacts with a recovery
  journal instead of recursive deletion, preserving other chains' broadcast records
- Local Anvil launch binds RPC to loopback and no longer stops existing Docker
  nodes or removes containers to resolve conflicts; executes the validated host binary
- Standalone local execution Compose isolates project resources, removes host
  Engine RPC exposure and unsafe application APIs, and fails on genesis init errors
- Release checks fail closed on missing tools, scanner errors and malformed or
  empty dependency locks; reject semver/branch action references, not just major tags
- Executable regressions cover launch and certification failures

## [0.3.9] - 2026-09-05

Transaction-flow event integrity patch. Rollup settlement, recovery and independent
audit remain unverified; Sepolia deployment stays on hold.

### Fixed

- Redemption, encrypted-transaction and forced-inclusion flows only extract identifiers
  from logs emitted by the resolved target contract; removed logs are ignored and
  emitter resolution completes before submitting a transaction
- Added transaction-flow regressions for spoofed events, approval handling, failed
  transactions, exceptions and accumulated successful-transaction costs

## [0.3.8] - 2026-09-05

Commerce verification and local operations hardening release. Full rollup settlement,
recovery and independent audit remain unverified; Sepolia deployment stays on hold.

### Added

- Whole-operation deadlines and cancellation for SDK finality/payment verification,
  with typed interruption errors and no automatic finality downgrade
- Local RPC-to-ledger commerce regressions covering one-time order credit,
  underpayment rejection and idempotent fulfillment retries across process restarts
- Durable SQLite merchant-ledger reference with atomic payment consumption, immutable
  checkout expectations and a leased fulfillment outbox; tested against concurrent
  credits, rollback and worker restart scenarios
- ERC-20 payment verification combining canonical finality with exact token, payer,
  recipient, amount and event checks across multiple RPC sources; provides a stable
  receipt key for application-level atomic payment consumption
- Transaction finality observations in the SDK with canonical receipt checks,
  safe/finalized head validation, reorg detection, and conservative agreement
  across independently configured RPC sources
- Read-only loopback diagnostic for transaction finality and JSON evidence output
- Offline L2 readiness regressions for settlement validation, generated configuration,
  governance policy, RPC exposure, and fault-proof walkthrough behavior

### Fixed

- Local readiness RPC parsing rejects duplicate JSON fields and non-finite numbers;
  real loopback HTTP regressions cover redirects, proxy bypass and stalled responses
- Local startup replaces fixed sleeps with bounded RPC chain/genesis, rollup
  configuration and canonical-head checks before starting transaction submitters
- Local start/stop operations use a shared lifecycle lock; startup failures attempt
  identity-checked rollback and process status no longer trusts bare PID liveness
- Local OP Stack shutdown verifies recorded process ownership and uses Linux pidfds
  instead of signaling bare PIDs; stale or untrusted records fail closed
- Legacy devnet startup no longer loads Sepolia configuration; local chain/origin
  preflight, loopback RPC binding and stale-PID refusal protect local-only runs
- Merchant ledger validates evidence structure and permits expired matching retries
  without rewriting evidence or re-enqueueing completed fulfillment
- Verification evidence retains the whole-operation start time through slow sources
  and finality rechecks; payment terms and deadline options are snapshotted at entry
- Payment verification validates the entire receipt-log sequence before assigning
  a consumption key, rejecting index gaps, reordering, duplicates and stale metadata
- Settlement validation rejects wrong-chain, malformed, failed and empty RPC results
- Shared-network configuration aligns generated artifact/data paths and restricts RPC exposure
- Production validation requires governance and fault-proof configuration
- Fault-proof walkthroughs no longer report successful execution of unperformed disputes

## [0.3.7] - 2026-09-04

### Fixed

- Increased exhaustive invariant certification headroom after standard hosted runners reached the
  previous job ceiling without reporting an assertion failure

## [0.3.6] - 2026-09-04

### Fixed

- Made the upgradeable OpenZeppelin dependency a pinned first-class submodule and stopped CI
  from recursively compiling dependency-owned tests and formal-verification harnesses
- Preserved annotated tag objects during release checkout so certification verifies tag type
  instead of an Actions-generated lightweight checkout reference
- Made fallback Foundry dependency installation shallow and independent of repository metadata
- Pinned the deployment helper's fallback dependencies to the release-audited revisions
- Added release checks that prove each Foundry lock revision matches an initialized direct submodule
- Corrected Slither option types and made SARIF upload conditional on successful report creation
- Enabled coverage's minimal IR pipeline for contracts that require via-IR compilation
- Migrated SARIF upload to the immutable CodeQL v4 action before the v3 retirement window
- Added an on-demand devnet smoke entry point for pre-tag release-candidate certification
- Upgraded GitHub-owned workflow actions to their current Node 24-based major releases
- Replaced monolithic Solidity coverage with compiler-safe critical-contract shards, enforced
  per-contract line thresholds, and retained LCOV reports as CI artifacts
- Removed a redundant full-suite compilation from devnet smoke so local deployment checks stay
  within deterministic CI time bounds while release and security workflows retain full coverage
- Removed duplicate smoke compilation from the comprehensive Forge job and sized its timeout for
  the release-equivalent via-IR build on standard hosted runners
- Added a production-equivalent sparse profile for local deployment scripts, avoiding compilation
  of test-only sources during devnet smoke checks

## [0.3.5] - 2026-09-04

### Added

- Release certification with full contract/invariant, Rust/Anvil, and SDK quality gates
- SPDX SBOMs, SHA-256 checksums, and build-provenance attestations for tagged releases
- Automated dependency update configuration and a public vulnerability disclosure policy
- A strict CI failure policy for new RustSec advisories classified as unsound, with documented
  time-bound exceptions for the pinned Alloy provider line

### Fixed

- Replaced the stale anchor integration bytecode placeholder with an auditable Solidity fixture
- Restored execution of all four Anvil-dependent anchor integration tests
- Corrected a NatSpec mismatch that prevented compilation of the complete Solidity suite
- Removed the unsound `scc` test dependency and refreshed compatible Rust dependencies
- Replaced the obsolete Foundry nightly and incorrect default-branch CI trigger with pinned,
  supported release settings

## [0.3.4] - 2026-09-04

### Added

- Commerce order escrow and full-precision FX oracle contracts with dedicated tests
- Proof-of-reserves v2 contracts, breaker coverage, and hardened reserve attestor service
- Kubernetes deployment templates with secret-safe examples
- Reproducible SDK and Rust lockfiles, pinned toolchains, linting, and critical smoke suites

### Fixed

- Restored SetRegistry batch and STARK-proof accounting counters
- Enforced escrow confirmation windows and fee-on-transfer solvency checks
- Added checked proof-of-reserves configuration bounds and attestor readiness validation
- Hardened SDK health, encryption, event, retry, and gas-flow behavior

## [0.2.1] - 2026-02-27

### Fixed

**Contracts**
- Hardened MEV queue handling and forced-inclusion refund/liveness flows
- Added backward-compatible ssUSD/wssUSD aliases while standardizing SSDC naming
- Fixed NAV oracle and treasury naming drift plus attestor batch accounting
- Fixed ERC20 false-return handling in payment batching

**Anchor**
- Added transaction confirmation timeout with reverted-receipt checks
- Improved health marking logic and fail-fast numeric config parsing
- Prevented uptime underflow edge case

**SDK**
- Fixed ESM export paths and ABI/event parsing mismatches
- Added safer bigint gas math and stricter redemption/allowance checks
- Disabled insecure threshold-encryption fallback by default
- Added Node-runtime-aware Vitest launcher for stable test execution

## [0.2.0] - 2026-01-11

### Added

**Contracts**
- SetPaymaster for gas-sponsored commerce transactions
- SetTimelock for governance with configurable delay
- MEV protection suite:
  - EncryptedMempool for transaction privacy
  - ForcedInclusion for censorship resistance
  - ThresholdKeyRegistry for key management
- Stablecoin infrastructure:
  - NAVOracle for net asset value calculations
  - TreasuryVault for collateral management
  - ssUSD stablecoin implementation
  - wssUSD wrapped stablecoin with yield
- Comprehensive test coverage for all new contracts

**SDK**
- Full TypeScript SDK for SetRegistry and SetPaymaster
- Stablecoin ABIs and utilities
- Enhanced configuration options

**Anchor**
- Health check endpoints
- Improved type definitions
- Error handling module

**Documentation**
- API reference documentation
- Architecture guides (data flow, OP Stack, trust model)
- MEV protection documentation
- Stablecoin system documentation
- SDK configuration and utilities guides
- Operations runbook

### Changed
- Expanded SetRegistry with additional functionality
- Enhanced SDK with stablecoin support

## [0.1.0] - Initial Release

- Initial SetRegistry contract
- Basic SDK implementation
- Anchor service foundation
