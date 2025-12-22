# Set Chain Security and Governance

## Upgrade Policy
SetRegistry and SetPaymaster use UUPS upgrades, so the contract owner controls
upgrades. For production, the owner should be a timelock that is controlled by
an M-of-N multisig. Avoid EOAs for upgrade authority.

## Governance Process
- Proposals are submitted by the multisig to the timelock contract.
- Timelock delay provides a review window before execution.
- Emergency actions should be limited to a pause guardian with clear scope.
- Record multisig/timelock deployment evidence in `docs/governance-evidence.md`.

## Multisig and Timelock Setup (Recommended)
1. Create a Safe (M-of-N) for upgrade governance.
2. Deploy a TimelockController with a minimum delay (e.g., 48 hours).
3. Set the TimelockController as the owner of SetRegistry and SetPaymaster.
4. Configure the Safe as proposer/executor on the timelock.
5. Use the timelock for upgrades and admin actions.

## Key Roles
- Admin/upgrade: multisig and timelock addresses.
- Sequencer: hot key used to submit commitments.
- Batcher/proposer/challenger: service keys for OP Stack components.
- Treasury: recipient of paymaster withdrawals.

## Key Rotation (Sequencer)
1. Generate a new sequencer key and fund it.
2. Authorize it in SetRegistry via the timelock.
3. Update anchor service config to use the new key.
4. Revoke the old key and rotate secrets.

## Config Guidance (config/sepolia.env)
Set the following values for production deployments:
- ADMIN_ADDRESS should point to the timelock contract.
- UPGRADE_MULTISIG_ADDRESS should point to the Safe.
- UPGRADE_TIMELOCK_ADDRESS should point to the timelock contract.
- UPGRADE_TIMELOCK_DELAY_SECS should match your governance delay.
- PAUSE_GUARDIAN_ADDRESS should be a distinct key for emergency actions.

These values are used for operational validation and governance runbooks even
when not enforced directly by contracts.

## Emergency Actions
- Revoke sequencer authorization to halt commitments.
- Disable strict mode only if necessary to recover from gaps.
- Revoke operator roles and withdraw paymaster funds if compromised.

## Audit Evidence
- Record audit scope and results in `docs/audit-report.md`.
