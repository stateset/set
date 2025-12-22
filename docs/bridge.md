# Bridge and Onramp Support

## OP Stack Standard Bridge
Set Chain inherits the OP Stack Standard Bridge contracts on L1/L2. The
addresses are configured in `config/sepolia.env` after L1 deployment.

Key addresses:
- L1_STANDARD_BRIDGE_ADDRESS
- L1_CROSS_DOMAIN_MESSENGER_ADDRESS
- L2_STANDARD_BRIDGE_ADDRESS
- L2_CROSS_DOMAIN_MESSENGER_ADDRESS

## Onramp Options
- ETH and ERC20 onramp via L1 bridge
- Third-party fiat onramp integrations (documented externally)

## Operational Notes
- Monitor bridge contract upgrades and security advisories.
- Track deposit/withdrawal throughput and latency.

## Evidence
Record bridge endpoints and supported assets in `docs/operations-history.md`.
