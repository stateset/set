# Changelog

All notable changes to Set will be documented in this file.

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
