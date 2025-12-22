# Set Chain Threat Model

## Scope
This document covers the Set Chain L2, its smart contracts, OP Stack
components, and the anchor service that bridges the sequencer API to
on-chain commitments.

## Assets
- L2 state and user balances
- Commitment history and state roots stored in SetRegistry
- Sequencer private key used to submit commitments
- Admin/upgrade keys for contracts
- Paymaster funds and sponsorship limits

## Actors
- External attacker (network or smart contract exploitation)
- Malicious or compromised sequencer operator
- Insider with access to admin keys
- L1 network disruption or reorgs

## Trust Assumptions
- Ethereum L1 finality and OP Stack correctness
- Contract upgrades are governed by trusted operators
- Sequencer API is trusted to serve correct commitments

## Primary Threats and Mitigations

### Unauthorized commitments
- Threat: A non-authorized address calls `commitBatch`.
- Mitigations: `authorizedSequencers` allowlist, strict mode enforcement.

### Sequencer key compromise
- Threat: Attacker submits malicious commitments.
- Mitigations: key rotation, least-privileged hot keys, multisig governance
  for authorization updates, monitoring for anomalous activity.

### Malicious or incorrect commitments
- Threat: Sequencer provides inconsistent roots or sequence ranges.
- Mitigations: strict mode checks, verification in SetRegistry, operational
  monitoring of state root continuity.

### Anchor service downtime
- Threat: Commitments are not anchored, causing lag.
- Mitigations: retries, health checks, alerting, manual runbook steps.

### L1 reorgs and settlement issues
- Threat: L2 outputs are reorged or delayed, impacting finality.
- Mitigations: monitor safe head lag, delay critical operations until L1
  finality thresholds are reached.

### Admin key misuse
- Threat: Malicious upgrades or configuration changes.
- Mitigations: multisig + timelock, upgrade policy, change management logs.

## Out of Scope
- L1 consensus attacks
- User-side wallet security
- External application-level logic beyond Set Chain contracts

## Security Controls Backlog
- Independent contract audit and published results
- Formal key management policy and HSM support
- Formal incident response and on-call escalation procedures
