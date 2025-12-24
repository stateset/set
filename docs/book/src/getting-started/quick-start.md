# Quick Start

Get started with Set Chain in under 5 minutes.

## Prerequisites

- Node.js 18+
- A wallet with Sepolia ETH (for testnet)

## 1. Install SDK

```bash
npm install @setchain/sdk ethers
```

## 2. Connect to Set Chain

```typescript
import { JsonRpcProvider, Wallet } from "ethers";

// Testnet RPC
const provider = new JsonRpcProvider("https://rpc.testnet.setchain.io");

// Create wallet
const wallet = new Wallet(PRIVATE_KEY, provider);

// Check connection
const chainId = await provider.getNetwork().then(n => n.chainId);
console.log("Connected to chain:", chainId); // 84532001
```

## 3. Get Test ETH

Bridge ETH from Sepolia to Set Chain:

1. Get Sepolia ETH from a [faucet](https://sepoliafaucet.com/)
2. Go to [bridge.setchain.io](https://bridge.setchain.io)
3. Bridge Sepolia ETH → Set Chain ETH

## 4. Use ssUSD Stablecoin

### Deposit USDC → ssUSD

```typescript
import { stablecoin } from "@setchain/sdk";
import { parseUnits, formatUnits } from "ethers";

// Contract addresses (testnet)
const addresses = {
    tokenRegistry: "0x...",
    navOracle: "0x...",
    ssUSD: "0x...",
    wssUSD: "0x...",
    treasury: "0x..."
};

// Create client
const client = stablecoin.createStablecoinClient(
    addresses,
    PRIVATE_KEY,
    "https://rpc.testnet.setchain.io"
);

// Deposit 100 USDC
const USDC = "0x..."; // USDC on Set Chain
const result = await client.deposit(USDC, parseUnits("100", 6));

console.log("ssUSD minted:", formatUnits(result.ssUSDMinted, 18));
```

### Check Balance

```typescript
const balance = await client.getBalance(wallet.address);

console.log("ssUSD:", formatUnits(balance.ssUSD, 18));
console.log("Shares:", balance.ssUSDShares.toString());
```

### Wrap for DeFi

```typescript
// Wrap ssUSD → wssUSD for DeFi compatibility
const wrapResult = await client.wrap(parseUnits("50", 18));
console.log("wssUSD received:", formatUnits(wrapResult.wssUSDReceived, 18));
```

## 5. Verify Commerce Events

### Check Event Inclusion

```typescript
import { Contract } from "ethers";
import { SetRegistryABI } from "@setchain/sdk";

const registry = new Contract(REGISTRY_ADDRESS, SetRegistryABI, provider);

// Verify an event was anchored
const isValid = await registry.verifyInclusion(
    batchId,
    eventHash,
    merkleProof,
    leafIndex
);

console.log("Event verified:", isValid);
```

### Query Latest State

```typescript
const tenantId = "0x..."; // Your tenant ID
const storeId = "0x...";  // Your store ID

const stateRoot = await registry.getLatestStateRoot(tenantId, storeId);
const sequence = await registry.getHeadSequence(tenantId, storeId);

console.log("State root:", stateRoot);
console.log("Head sequence:", sequence);
```

## 6. MEV-Protected Transactions

```typescript
import { createMEVProtectionClient } from "@setchain/sdk";

const mev = createMEVProtectionClient(
    {
        encryptedMempool: "0x...",
        thresholdKeyRegistry: "0x..."
    },
    wallet
);

// Check if encryption is available
if (await mev.isAvailable()) {
    // Submit encrypted transaction
    const { txId } = await mev.submit(
        targetContract,
        calldata,
        parseEther("0")
    );

    // Wait for execution
    const result = await mev.waitForExecution(txId);
    console.log("Executed:", result.success);
}
```

## Network Details

| Property | Testnet | Mainnet |
|----------|---------|---------|
| Chain ID | `84532001` | TBD |
| RPC URL | `https://rpc.testnet.setchain.io` | TBD |
| Explorer | `https://explorer.testnet.setchain.io` | TBD |
| Bridge | `https://bridge.testnet.setchain.io` | TBD |

## Contract Addresses (Testnet)

| Contract | Address |
|----------|---------|
| SetRegistry | `TBD after deployment` |
| SetPaymaster | `TBD after deployment` |
| ssUSD | `TBD after deployment` |
| wssUSD | `TBD after deployment` |
| TreasuryVault | `TBD after deployment` |

## What's Next?

- [Installation Guide](./installation.md) - Detailed setup instructions
- [Configuration](./configuration.md) - SDK configuration options
- [ssUSD Overview](../stablecoin/overview.md) - Learn about the stablecoin
- [VES Anchoring](../architecture/ves-anchoring.md) - Understand event anchoring
