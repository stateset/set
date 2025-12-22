# Fault Proofs and Challenger Operations

## Overview
Set Chain inherits OP Stack fault proof mechanisms. The op-challenger monitors
L2 outputs and can dispute invalid state via the DisputeGameFactory on L1.

## Required Configuration
Ensure these values are set in `config/sepolia.env`:
- DISPUTE_GAME_FACTORY_ADDRESS
- CHALLENGER_ADDRESS
- CHALLENGER_PRIVATE_KEY
- L1_RPC_URL and L1_BEACON_URL

## Operations
- Run op-challenger with the configured keys and L1 RPC endpoints.
- Monitor challenger logs for dispute participation and resolution.
- Verify that dispute games are created and finalized on L1.

## Exercise Checklist
- Confirm L1 contracts are deployed and reachable.
- Start op-challenger and capture logs for a test window.
- Record dispute game IDs and outcomes for postmortem review.

Log evidence in `docs/fault-proof-exercise.md`.

## Validation
Use the config validator for readiness checks:

```
./scripts/validate-ops-config.sh --mode testnet --require-fault-proofs
```

Verify L1 settlement contracts are deployed:

```
./scripts/check-l1-settlement.sh --env-file config/sepolia.env --mode testnet --require-addresses
```

## Runbook References
See `docs/runbook.md` for incident response and escalation procedures.
