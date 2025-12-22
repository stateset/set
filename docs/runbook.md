# Set Chain Operations Runbook

## Preflight Checklist
- Confirm L1 RPC and beacon endpoints are reachable.
- Verify JWT secret for engine API authentication.
- Ensure sequencer, batcher, proposer, and challenger keys are funded.
- Confirm admin and upgrade keys are secured (multisig for production).
- Validate config with `scripts/validate-ops-config.sh` for testnet/production.
- Verify L1 settlement contracts with `scripts/check-l1-settlement.sh`.

## Start Sequence (Production)
1. Deploy L1 OP Stack contracts (`scripts/deploy-l1.sh`).
2. Generate L2 genesis and rollup config (`scripts/generate-genesis.sh`).
3. Start op-geth and op-node.
4. Start op-batcher and op-proposer.
5. Start op-challenger (fault proof / disputes).
6. Deploy SetRegistry and SetPaymaster to L2 (`scripts/deploy-set-contracts.sh`).
7. Start anchor service (`scripts/anchor-devnet.sh start --no-mock`).

## Health Checks
- L2 RPC responding: `eth_chainId`, `eth_blockNumber`.
- op-node sync: `optimism_syncStatus`.
- Anchor service readiness: `/health` and `/ready`.
- Commitment growth: `SetRegistry.totalCommitments()`.

## Incident Playbooks

### L2 blocks stopped
- Check op-geth and op-node logs.
- Verify L1 RPC connectivity.
- Restart op-node and op-geth if needed.
- Validate rollup config matches expected chain config.

### Anchoring lag or backlog
- Check anchor service logs and health endpoints.
- Verify sequencer API is reachable.
- Confirm sequencer authorization on SetRegistry.
- Manually submit a test commitment to validate the path.

### Suspicious commitments
- Pause new commitments by removing sequencer authorization.
- Enable strict mode if disabled.
- Investigate sequencer API output and on-chain events.
- Rotate sequencer key if compromise is suspected.

### L1 instability or reorgs
- Pause sensitive operations dependent on L1 finality.
- Increase confirmation depth or wait for safe head.
- Monitor L1 output submission lag and resume once stable.

## Key Rotation
- Generate new sequencer key.
- Update `authorizedSequencers` on SetRegistry via multisig.
- Update anchor service environment variables.
- Decommission old key after confirmation.

## Governance and Upgrade Policy
- Ensure `ADMIN_ADDRESS` points to the timelock contract.
- Use the multisig as proposer/executor for timelock operations.
- Schedule upgrades through the timelock delay window.
- Record upgrade metadata for rollback readiness.

## Upgrade and Rollback
- Use staged upgrades with a timelock.
- Validate new implementations on a staging devnet.
- Keep previous implementation address for rollback.

## Backup and Restore
- Back up op-geth data directory and rollup config.
- Restore by stopping services, replacing data directories, and restarting.

## On-Call and Escalation
- Define primary and secondary on-call rotations for L2 and anchoring.
- Page on critical alerts (block gaps, anchor failures, L1 outages).
- Escalate to governance multisig for emergency actions.

## References
- `README.md` deployment checklist and monitoring section
- `docs/local_testing_guide.md`
- `docs/security.md`
- `docs/operations-history.md`
