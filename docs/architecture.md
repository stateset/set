# Set Chain Architecture

## Overview
Set Chain (SSC) is an OP Stack L2 focused on commerce workloads. The standard
OP Stack components provide execution, derivation, batch submission, and state
root publication. On top of that, Set Chain adds on-chain commitment storage
(SetRegistry), gas sponsorship (SetPaymaster), and a Rust anchor service that
bridges an off-chain sequencer API to on-chain commitments.

## Core Components
- OP Stack: op-geth, op-node, op-batcher, op-proposer, op-challenger
- SetRegistry (Solidity): commitment storage and verification
- SetPaymaster (Solidity): gas sponsorship for user/merchant flows
- Anchor service (Rust): polls sequencer API and submits commitments
- stateset-sequencer (off-chain): builds commitment batches for anchoring

## Data Flow
1. stateset-sequencer batches off-chain commerce events into commitments.
2. Anchor service polls `/v1/commitments/pending` and submits `commitBatch` to
   SetRegistry using the authorized sequencer key.
3. SetRegistry stores roots and sequence metadata for inclusion proofs.
4. OP Stack batches L2 transactions to L1 and posts L2 outputs to L1 contracts.

## Trust Boundaries
- Sequencer key: hot key used for `commitBatch` transactions.
- Admin/upgrade keys: should be multisig for production.
- L1 settlement: relies on Ethereum L1 finality and OP Stack correctness.

## Config and Entry Points
- `config/chain-config.toml`: chain parameters
- `op-stack/`: OP Stack intent and rollup configuration
- `scripts/`: deployment and devnet helpers
- `contracts/src/`: SetRegistry and SetPaymaster contracts
- `anchor/src/`: anchor service

## Reference Diagram

```
Off-chain sequencer
        |
        | pending commitments (HTTP API)
        v
Anchor service  --->  SetRegistry (L2)  --->  OP Stack L2 blocks
        |                                      |
        |                                      v
        +----------------------------->  L1 settlement contracts
```
