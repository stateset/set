# Changelog

All notable changes to Set will be documented in this file.

## [Unreleased]

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
