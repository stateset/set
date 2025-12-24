# Frequently Asked Questions

Common questions about Set Chain.

## General

### What is Set Chain?

Set Chain is an L2 blockchain built on the OP Stack, optimized for commerce applications. It features:
- VES (Validium-style Event Sourcing) for efficient off-chain data with on-chain proofs
- ssUSD, a yield-bearing stablecoin backed by T-Bills
- MEV protection through threshold encryption
- Gas sponsorship for merchants

### How is Set Chain different from other L2s?

Set Chain is purpose-built for commerce with:
1. **VES Anchoring**: Efficient Merkle-root commitments for high-volume event data
2. **Native Stablecoin**: ssUSD earns yield automatically through rebasing
3. **MEV Protection**: Encrypted mempool prevents frontrunning and sandwich attacks
4. **Gas Sponsorship**: Merchants can pay gas fees for their customers

### Is Set Chain compatible with Ethereum?

Yes. Set Chain is fully EVM-compatible. Any Ethereum smart contract can be deployed without modification.

## ssUSD Stablecoin

### What is ssUSD?

ssUSD (Set Stablecoin USD) is a rebasing stablecoin that automatically earns yield from U.S. Treasury Bills. Your balance increases daily without any action required.

### How does ssUSD earn yield?

ssUSD is backed by T-Bill reserves. Daily NAV updates from an attestor increase the NAV per share, which automatically increases your ssUSD balance through rebasing.

### What's the expected APY?

ssUSD targets approximately 5% APY based on current T-Bill yields. The actual rate varies with market conditions.

### What's the difference between ssUSD and wssUSD?

| Feature | ssUSD | wssUSD |
|---------|-------|--------|
| Rebasing | Yes, balance changes | No, fixed balance |
| Yield | Automatic balance increase | Redeemable for more ssUSD |
| DeFi Compatible | Limited | Yes (ERC-4626) |
| Use Case | Holding, payments | DeFi, lending, AMMs |

### How do I deposit collateral?

```typescript
import { stablecoin } from "@setchain/sdk";

const client = stablecoin.createStablecoinClient(addresses, privateKey, rpcUrl);

// Approve and deposit USDC
await client.approve(USDC_ADDRESS, amount);
const result = await client.deposit(USDC_ADDRESS, amount);
```

### How do I redeem ssUSD?

```typescript
const result = await client.redeem(USDC_ADDRESS, ssUSDAmount);
// Receive USDC (minus small redemption fee)
```

### What tokens can I use as collateral?

Currently supported:
- USDC (6 decimals)
- USDT (6 decimals)

Additional stablecoins may be added through governance.

### What happens if NAV data is stale?

If NAV hasn't been updated in 24+ hours:
- Deposits may be restricted
- Redemptions may be restricted
- System waits for fresh attestation

This protects users from transacting at outdated prices.

## VES Anchoring

### What is VES?

VES (Validium-style Event Sourcing) is Set Chain's data anchoring system. Commerce events are stored off-chain but their Merkle roots are committed on-chain, enabling trustless verification.

### How do I verify an event was anchored?

```typescript
const registry = new Contract(REGISTRY_ADDRESS, SetRegistryABI, provider);

const isValid = await registry.verifyInclusion(
    batchId,
    eventHash,
    merkleProof,
    leafIndex
);
```

### What's included in a batch commitment?

Each batch contains:
- Merkle root of events
- State root (optional)
- Sequence numbers
- Event count
- Timestamp
- Metadata

### How often are batches submitted?

Typically every few minutes or when event count thresholds are reached. The frequency depends on activity volume.

## MEV Protection

### What MEV attacks does Set Chain prevent?

| Attack | Protection |
|--------|------------|
| Frontrunning | Encrypted until ordering committed |
| Sandwich | Transactions hidden from attackers |
| Censorship | Forced inclusion via L1 |
| Reordering | Sequencer attestation proofs |

### How does transaction encryption work?

1. User encrypts transaction with threshold public key
2. Submits encrypted payload to EncryptedMempool
3. Sequencer commits ordering (without seeing contents)
4. Keypers release decryption shares
5. Transaction decrypted and executed

### What if the sequencer censors my transaction?

Use forced inclusion via L1:
1. Submit transaction to ForcedInclusion contract on Ethereum
2. Pay a small bond (0.01 ETH)
3. Sequencer MUST include within 24 hours
4. If not included, you get bond back + penalty

### Is MEV protection enabled by default?

Currently, Set Chain uses a private mempool (Phase 0). Full threshold encryption is available but optional. It will become default in future phases.

## Gas & Fees

### How much does it cost to use Set Chain?

Set Chain fees are significantly lower than Ethereum mainnet:
- Simple transfer: ~$0.001
- Deposit/Redeem: ~$0.01-0.05
- Complex operations: Varies

### Can merchants pay gas for customers?

Yes! Using SetPaymaster:

```typescript
// Merchant setup
await paymaster.registerMerchant({ value: parseEther("1.0") });
await paymaster.setPolicy({
    maxGasPerTx: 500000n,
    allowedTargets: [ssUSDAddress],
    // ...
});

// User transactions are sponsored automatically
```

### How do I get testnet ETH?

1. Get Sepolia ETH from a faucet
2. Bridge to Set Chain at bridge.testnet.setchain.io
3. Or request from our Discord faucet

## Development

### Which SDK should I use?

Use `@setchain/sdk` for TypeScript/JavaScript applications. It includes:
- StablecoinClient for ssUSD operations
- MEV protection client
- Utility functions
- Contract ABIs and types

### How do I run a local development environment?

```bash
git clone https://github.com/setchain/set.git
cd set
./scripts/dev.sh
```

This starts a local Anvil node with all contracts deployed.

### Where are the contract ABIs?

ABIs are available:
1. In the SDK: `import { SetRegistryABI } from "@setchain/sdk"`
2. Download: `https://contracts.setchain.io/abis/`
3. In repository: `contracts/out/*/abi.json`

### How do I report a bug or security issue?

- Bugs: [github.com/setchain/set/issues](https://github.com/setchain/set/issues)
- Security: security@setchain.io (do NOT create public issues)

## Security

### Has Set Chain been audited?

Yes. See our audit reports at [setchain.io/security](https://setchain.io/security).

### How are upgrades handled?

All contract upgrades go through SetTimelock with:
- 48-hour delay for upgrades
- 24-hour delay for parameter changes
- Public visibility of pending operations
- Emergency guardian override (multi-sig)

### What if there's an emergency?

The guardian committee (3-of-5 multi-sig) can:
1. Pause deposits/redemptions
2. Execute emergency upgrades
3. Respond to security incidents

All emergency actions are logged and publicly visible.

### Are my funds safe?

ssUSD is backed 1:1 by approved stablecoins. Key security measures:
- Time-locked upgrades
- Multi-sig admin controls
- Regular security audits
- On-chain proof verification

## Support

### Where can I get help?

- Documentation: docs.setchain.io
- Discord: discord.gg/setchain
- Twitter: @SetChain
- Email: support@setchain.io

### How do I stay updated?

- Follow [@SetChain](https://twitter.com/setchain) on Twitter
- Join our [Discord](https://discord.gg/setchain)
- Subscribe to our newsletter

## Related

- [Quick Start](../getting-started/quick-start.md)
- [Architecture Overview](../architecture/overview.md)
- [ssUSD Overview](../stablecoin/overview.md)
