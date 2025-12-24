# Set Chain Documentation

<div class="warning">

**Set Chain is currently in testnet.** Contract addresses and APIs may change before mainnet launch.

</div>

## What is Set Chain?

**Set Chain** is a commerce-optimized Layer 2 blockchain built on the [OP Stack](https://docs.optimism.io/). It provides:

- **Validium-style Event Sourcing (VES)** - Cryptographic anchoring of off-chain commerce events
- **ssUSD Stablecoin** - Yield-bearing stablecoin backed by U.S. Treasury Bills (~5% APY)
- **MEV Protection** - Threshold-encrypted mempool to prevent frontrunning and sandwich attacks
- **Gas Sponsorship** - Merchants can sponsor customer transactions
- **Sub-second Finality** - Fast confirmation times for commerce workloads

## Key Features

| Feature | Description |
|---------|-------------|
| **VES Anchoring** | Merkle root commitments of commerce events anchored on-chain |
| **ssUSD** | Rebasing stablecoin with automatic yield distribution |
| **wssUSD** | Non-rebasing wrapper for DeFi compatibility (ERC-4626) |
| **Encrypted Mempool** | Transaction privacy until ordering is committed |
| **Forced Inclusion** | Censorship resistance via L1 submission |
| **STARK Proofs** | Compliance verification for regulatory requirements |

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Set Chain L2                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ SetRegistry  │  │ SetPaymaster │  │  Stablecoin System   │  │
│  │              │  │              │  │  ┌────────────────┐  │  │
│  │ • Batch      │  │ • Gas        │  │  │ ssUSD  wssUSD  │  │  │
│  │   commits    │  │   sponsorship│  │  │ Treasury NAV   │  │  │
│  │ • Merkle     │  │ • Merchant   │  │  │ TokenRegistry  │  │  │
│  │   proofs     │  │   tiers      │  │  └────────────────┘  │  │
│  │ • STARK      │  │              │  │                      │  │
│  │   proofs     │  │              │  │                      │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                   MEV Protection Layer                     │  │
│  │  EncryptedMempool │ ThresholdKeyRegistry │ ForcedInclusion │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│                      OP Stack Components                         │
│         op-geth │ op-node │ op-batcher │ op-proposer            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Ethereum L1 (Sepolia/Mainnet)               │
│              OptimismPortal │ L2OutputOracle │ SystemConfig      │
└─────────────────────────────────────────────────────────────────┘
```

## Network Information

| Property | Value |
|----------|-------|
| **Chain ID** | `84532001` (Testnet) |
| **Native Token** | ETH |
| **Block Time** | 2 seconds |
| **Finality** | ~12 minutes (L1 finality) |
| **RPC URL** | `https://rpc.setchain.io` |
| **Explorer** | `https://explorer.setchain.io` |
| **Bridge** | `https://bridge.setchain.io` |

## Quick Links

- [Quick Start Guide](./getting-started/quick-start.md)
- [Architecture Overview](./architecture/overview.md)
- [ssUSD Stablecoin](./stablecoin/overview.md)
- [SDK Reference](./sdk/installation.md)
- [Contract Addresses](./api/addresses.md)

## Use Cases

### Commerce Event Anchoring

Anchor order, payment, and inventory events with cryptographic proofs:

```typescript
// Off-chain: stateset-sequencer batches events
// On-chain: Anchor service commits to SetRegistry

const commitment = await registry.getCommitment(batchId);
const isValid = await registry.verifyInclusion(
  batchId,
  eventHash,
  merkleProof,
  index
);
```

### Yield-Bearing Stablecoin

Deposit USDC/USDT and receive ssUSD with automatic yield:

```typescript
import { stablecoin } from "@setchain/sdk";

const client = stablecoin.createStablecoinClient(addresses, signer);

// Deposit 1000 USDC → receive ~1000 ssUSD
await client.deposit(USDC_ADDRESS, parseUnits("1000", 6));

// Balance automatically increases as yield accrues
const balance = await client.getBalance(myAddress);
console.log(`ssUSD: ${formatUnits(balance.ssUSD, 18)}`);
```

### MEV-Protected Transactions

Submit transactions that are hidden until ordering is committed:

```typescript
import { createMEVProtectionClient } from "@setchain/sdk";

const mev = createMEVProtectionClient(addresses, signer);

// Submit encrypted transaction
const { txId } = await mev.submit(
  targetContract,
  calldata,
  parseEther("0.1")
);

// Transaction is decrypted and executed after ordering committed
const status = await mev.getTransactionStatus(txId);
```

## Getting Help

- **GitHub Issues**: [github.com/stateset/set-chain/issues](https://github.com/stateset/set-chain/issues)
- **Discord**: [discord.gg/setchain](https://discord.gg/setchain)
- **Documentation**: You're here!

---

*Set Chain is built by [Stateset](https://stateset.io) and is open source under the MIT license.*
