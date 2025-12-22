# Block Explorer and Indexing

## Recommended Options
- Blockscout (self-hosted)
- Third-party explorers compatible with OP Stack chains

## Blockscout (Self-Hosted)
Blockscout provides an open-source explorer and indexing stack. Use their
installation guide and configure it with your L2 RPC endpoints.

Key inputs:
- L2 RPC URL
- L2 chain ID (`84532001` by default)
- Block time (2 seconds)

## Operational Notes
- Run the explorer on separate hardware from sequencer components.
- Monitor indexer lag and database health.
- Back up explorer databases for recovery.

## Evidence
Record explorer URLs and deployment details in `docs/operations-history.md`.
