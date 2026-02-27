# Changelog

All notable changes to Set will be documented in this file.

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
