# Trust Model

Understanding the trust assumptions and security guarantees of Set Chain.

## Trust Overview

Set Chain inherits Ethereum's security while making explicit trade-offs for commerce use cases:

| Component | Trust Assumption | Mitigation |
|-----------|------------------|------------|
| Sequencer | Honest ordering | Forced inclusion, attestations |
| VES Data | Available off-chain | Merkle proofs on-chain |
| NAV Oracle | Accurate attestation | Single trusted attestor + audits |
| Keypers | Threshold honesty | 3-of-5 distributed keys |
| Bridge | L1 security | Optimism fault proofs |

## Sequencer Trust

### Current Model (Phase 0)

Set Chain currently runs a **centralized sequencer** operated by the Set Chain team.

**Trust Assumption:** The sequencer will:
- Order transactions fairly (no front-running)
- Include all valid transactions
- Not censor users

**Mitigations:**

1. **Forced Inclusion**: Users can force transactions via L1 if censored
2. **Ordering Attestations**: Sequencer commits to ordering before execution
3. **Monitoring**: Public dashboards track sequencer behavior

### Future Model (Decentralized)

Planned progression:
- Phase 1: Multiple sequencers with rotation
- Phase 2: Decentralized sequencer set
- Phase 3: Based sequencing (L1 proposers)

## VES Data Availability

### Trust Model

VES uses a **validium-style** model:
- Raw event data stored **off-chain**
- Merkle roots committed **on-chain**
- Proofs enable trustless verification

```
┌─────────────────────────────────────────────────────────────┐
│                    Trust Boundary                            │
├──────────────────────┬──────────────────────────────────────┤
│    Off-Chain         │           On-Chain                    │
│    (Trust operator)  │           (Trustless)                 │
├──────────────────────┼──────────────────────────────────────┤
│  • Raw event data    │  • Merkle root commitments           │
│  • Full event history│  • Batch metadata                    │
│  • Merkle proofs     │  • Verification logic                │
└──────────────────────┴──────────────────────────────────────┘
```

**Trust Assumption:** The VES operator (tenant) stores event data correctly and makes it available.

**Mitigations:**

1. **Merkle Proofs**: Any event can be verified against on-chain root
2. **State Roots**: Optional state roots enable reconstruction verification
3. **Multiple Operators**: Different tenants can run independent VES systems
4. **Data Escrow**: Critical data can be escrowed to multiple parties

### Verification Guarantees

What you CAN verify trustlessly:
- ✅ Event was included in a specific batch
- ✅ Event has correct content (matches hash)
- ✅ Batch was submitted at specific time
- ✅ Sequence numbers are continuous

What requires trust:
- ❌ All events are stored (data availability)
- ❌ No events were omitted
- ❌ Off-chain queries return complete data

## NAV Oracle Trust

### Current Model

The NAV Oracle uses a **single trusted attestor** model:

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  T-Bill      │────▶│   Attestor   │────▶│  NAVOracle   │
│  Custodian   │     │   (trusted)  │     │  (on-chain)  │
└──────────────┘     └──────────────┘     └──────────────┘
```

**Trust Assumption:** The attestor:
- Reports accurate NAV based on actual T-Bill holdings
- Submits updates daily
- Doesn't manipulate for profit

**Mitigations:**

1. **Staleness Checks**: Operations blocked if NAV >24h old
2. **Change Limits**: Large NAV changes require additional verification
3. **Audit Trail**: All reports stored with proof hashes
4. **External Audits**: Regular third-party audits of reserves

### Future Improvements

Planned enhancements:
- Multi-attestor consensus
- Chainlink integration for redundancy
- Real-time T-Bill price feeds
- On-chain reserve proofs

## MEV Protection Trust

### Keyper Network

MEV protection relies on **threshold cryptography**:

```
┌──────────────────────────────────────────────────────────┐
│                 Threshold Encryption                      │
│                                                           │
│   Encrypt: Anyone can encrypt with public key            │
│   Decrypt: Requires 3-of-5 keypers to release shares     │
│                                                           │
│   ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐              │
│   │ K1  │ │ K2  │ │ K3  │ │ K4  │ │ K5  │              │
│   └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘              │
│      │       │       │       │       │                   │
│      └───────┴───────┴───────┴───────┘                   │
│              Need any 3 to decrypt                       │
└──────────────────────────────────────────────────────────┘
```

**Trust Assumption:** At least 3 of 5 keypers are honest and available.

**Mitigations:**

1. **Distributed Operators**: Keypers run by different entities
2. **Geographic Distribution**: Keypers in different jurisdictions
3. **Key Rotation**: Regular DKG ceremonies for fresh keys
4. **Slashing**: Future economic penalties for misbehavior

### Sequencer Ordering

Even with encryption, the sequencer chooses transaction order.

**Trust Assumption:** Sequencer commits to ordering fairly.

**Mitigations:**

1. **Ordering Attestations**: Signed commitment before decryption
2. **Verifiable Ordering**: Anyone can verify order was honored
3. **Forced Inclusion**: Bypass sequencer entirely via L1

## Bridge Trust

### Optimism Bridge Security

Set Chain inherits OP Stack's bridge security:

```
Deposit (L1→L2):
  • Instant once L1 tx confirms
  • Trust: L1 finality only

Withdrawal (L2→L1):
  • 7-day challenge period
  • Fault proofs can challenge invalid withdrawals
  • Trust: At least one honest challenger exists
```

**Trust Assumption:** The fault proof system works correctly and challengers monitor for fraud.

### Challenge Period

The 7-day withdrawal delay exists because:
- Allows time for fraud proof submission
- Anyone can challenge invalid state roots
- After period, withdrawals are guaranteed

## Economic Security

### ssUSD Backing

| Trust Level | Verification |
|-------------|--------------|
| Full reserves exist | External audit reports |
| Correct NAV reported | Attestor signature + audits |
| Redemption honored | Smart contract guarantee |
| No fractional reserve | Periodic proof of reserves |

### Attack Scenarios

| Attack | Cost | Mitigation |
|--------|------|------------|
| Sequencer censorship | Reputation | Forced inclusion |
| NAV manipulation | Legal liability | Audits, monitoring |
| Keyper collusion (3+) | Coordination | Distribution, rotation |
| Bridge fraud | L1 value at risk | Fault proofs |

## Trust Minimization Roadmap

### Current State (Testnet)

- ❌ Centralized sequencer
- ❌ Single NAV attestor
- ✅ On-chain Merkle verification
- ✅ Threshold encryption available
- ✅ Forced inclusion implemented

### Phase 1 (Mainnet Launch)

- ⏳ Sequencer rotation
- ⏳ Multiple NAV attestors
- ✅ Full MEV protection
- ✅ Comprehensive monitoring

### Phase 2 (Decentralization)

- ⏳ Decentralized sequencer set
- ⏳ Chainlink NAV integration
- ⏳ Keyper staking/slashing
- ⏳ Data availability committee

### Phase 3 (Maximum Decentralization)

- ⏳ Based sequencing
- ⏳ Trustless NAV oracles
- ⏳ Fully permissionless keypers
- ⏳ On-chain reserve proofs

## Comparison with Alternatives

| Property | Set Chain | Pure Rollup | Validium | Sidechain |
|----------|-----------|-------------|----------|-----------|
| Data Availability | L1 + VES | L1 only | Off-chain | Off-chain |
| Sequencer | Centralized* | Centralized* | Centralized | Varies |
| Finality | 7 days | 7 days | Instant* | Instant |
| MEV Protection | Yes | No | Varies | Varies |
| L1 Security | Inherited | Inherited | Partial | None |

*With planned decentralization path

## Summary

Set Chain makes explicit trust trade-offs optimized for commerce:

1. **Sequencer**: Trusted but with forced inclusion escape hatch
2. **VES Data**: Trust operator for availability, verify on-chain
3. **NAV Oracle**: Trust attestor, verify with audits
4. **MEV Protection**: Trust threshold of keypers
5. **Bridge**: Inherit L1 security via OP Stack

Each trust assumption has mitigations and a path toward further decentralization.

## Related

- [Architecture Overview](./overview.md)
- [OP Stack Integration](./op-stack.md)
- [Security Operations](../operations/security.md)
