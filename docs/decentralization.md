# Set Chain Decentralization Roadmap

## Phases

### Phase 0: Single Sequencer (today)
- Centralized sequencer with explicit authorization.
- `sequencer.p2p_enabled = false` and `sequencer.l1_confs = 0` in
  `config/chain-config.toml` for devnet.

### Phase 1: Backup Sequencer
- Add a secondary sequencer key.
- Use `setSequencerAuthorization` to allow multiple sequencers.
- Monitor for failover and publish operational runbooks.

### Phase 2: Shared Sequencer Set
- Enable P2P (`sequencer.p2p_enabled = true`).
- Require L1 confirmations for safety (`sequencer.l1_confs >= 1`).
- Publish node operation guidance and hardware requirements.

### Phase 3: Permissionless Participation
- Publish sequencer admission rules and on-chain governance.
- Move upgrades and authorization to timelock governance.
- Formalize incentives and dispute resolution.

## Operational Checks
- Ensure multiple sequencers are authorized.
- Track L1 confirmation depth and safe head lag.
- Validate P2P settings before production cutover.

## Related Docs
- `docs/fault-proofs.md`
- `docs/security.md`
- `docs/runbook.md`
- `docs/node-operators.md`
