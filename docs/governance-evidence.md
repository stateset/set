# Governance Evidence

This document records the governance infrastructure for Set Chain, including
multisig configuration and timelock deployment.

## Overview

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Safe Multisig  │────►│   SetTimelock   │────►│  SetRegistry    │
│  (3/5 signers)  │     │  (24h delay)    │     │  SetPaymaster   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
       │                        │
       │                        │
       ▼                        ▼
   Propose               Execute after delay
```

## Multisig (Gnosis Safe)

| Property | Value |
|----------|-------|
| Network | Set Chain (84532001) |
| Address | `0x...` |
| Threshold | 3 of 5 |
| Deployment TX | `0x...` |

### Signers

| # | Role | Address | Verified |
|---|------|---------|----------|
| 1 | Lead Developer | `0x...` | [ ] |
| 2 | CTO | `0x...` | [ ] |
| 3 | Security Lead | `0x...` | [ ] |
| 4 | Operations | `0x...` | [ ] |
| 5 | Advisor | `0x...` | [ ] |

### Signing Policy

- All signers use hardware wallets (Ledger/Trezor)
- 24-hour review period for non-emergency changes
- 2 signers required for emergency response
- Monthly key rotation verification

## Timelock (SetTimelock)

| Property | Value |
|----------|-------|
| Contract | SetTimelock.sol |
| Address | `0x...` |
| Network | Set Chain (84532001) |
| Min Delay | 86400 seconds (24 hours) |
| Deployment TX | `0x...` |

### Roles

| Role | Holder | Purpose |
|------|--------|---------|
| Proposer | Multisig | Can schedule operations |
| Executor | Multisig | Can execute ready operations |
| Canceller | Multisig | Can cancel pending operations |
| Admin | Renounced | No admin (decentralized) |

### Delay Configuration

| Environment | Delay | Rationale |
|-------------|-------|-----------|
| Mainnet | 24 hours | Security review window |
| Testnet | 1 hour | Faster iteration |
| Devnet | 5 minutes | Development speed |

## Controlled Contracts

| Contract | Owner | Upgrade Path |
|----------|-------|--------------|
| SetRegistry (Proxy) | Timelock | UUPS via timelock |
| SetPaymaster (Proxy) | Timelock | UUPS via timelock |

## Ownership Transfer Evidence

### SetRegistry

```
# Transfer command
cast send $SET_REGISTRY_ADDRESS \
  "transferOwnership(address)" $TIMELOCK_ADDRESS \
  --private-key $DEPLOYER_KEY \
  --rpc-url $L2_RPC_URL

# Verification
cast call $SET_REGISTRY_ADDRESS "owner()" --rpc-url $L2_RPC_URL
# Returns: $TIMELOCK_ADDRESS
```

- Transfer TX: `0x...`
- Block: ...
- Timestamp: ...

### SetPaymaster

```
# Transfer command
cast send $SET_PAYMASTER_ADDRESS \
  "transferOwnership(address)" $TIMELOCK_ADDRESS \
  --private-key $DEPLOYER_KEY \
  --rpc-url $L2_RPC_URL

# Verification
cast call $SET_PAYMASTER_ADDRESS "owner()" --rpc-url $L2_RPC_URL
# Returns: $TIMELOCK_ADDRESS
```

- Transfer TX: `0x...`
- Block: ...
- Timestamp: ...

## Admin Renouncement

The timelock admin role should be renounced after setup to prevent centralized control.

```
# Renounce admin
cast send $TIMELOCK_ADDRESS \
  "renounceRole(bytes32,address)" \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  $DEPLOYER_ADDRESS \
  --private-key $DEPLOYER_KEY \
  --rpc-url $L2_RPC_URL

# Verify admin is renounced
cast call $TIMELOCK_ADDRESS "isAdminRenounced()" --rpc-url $L2_RPC_URL
# Returns: true
```

- Renouncement TX: `0x...`
- Verified: [ ]

## Governance Process

### Standard Upgrade Flow

1. **Propose** (Multisig creates transaction)
   - Submit proposal via Safe UI
   - Include description and rationale
   - Collect 3/5 signatures

2. **Schedule** (Timelock queues operation)
   - Multisig calls `timelock.schedule()`
   - 24-hour delay begins
   - Anyone can verify pending operation

3. **Review** (Community verification)
   - Code review of proposed changes
   - Security analysis
   - Community feedback period

4. **Execute** (Timelock executes operation)
   - After delay, multisig calls `timelock.execute()`
   - Changes take effect immediately
   - Events emitted for transparency

### Emergency Response

For critical security issues:

1. Multisig can call `timelock.cancel()` to stop pending malicious operations
2. Document incident in `docs/operations-history.md`
3. Post-mortem within 48 hours

## Verification Checklist

- [ ] Multisig deployed and signers verified
- [ ] Timelock deployed with correct delay
- [ ] All contracts transferred to timelock
- [ ] Admin role renounced on timelock
- [ ] Test proposal/execution flow works
- [ ] Safe UI configured correctly
- [ ] All signers have tested signing
- [ ] Emergency procedures documented

## Deployment Script

Use the governance deployment script:

```bash
# Deploy governance
MULTISIG_ADDRESS=0x... \
SET_REGISTRY_ADDRESS=0x... \
SET_PAYMASTER_ADDRESS=0x... \
TIMELOCK_DELAY=86400 \
forge script script/DeployGovernance.s.sol \
  --rpc-url $L2_RPC_URL \
  --broadcast
```

See `contracts/script/DeployGovernance.s.sol` for implementation details.

## References

- [SetTimelock Contract](../contracts/governance/SetTimelock.sol)
- [Gnosis Safe](https://safe.global/)
- [OpenZeppelin TimelockController](https://docs.openzeppelin.com/contracts/4.x/api/governance#TimelockController)
- [Security Policy](./security.md)
