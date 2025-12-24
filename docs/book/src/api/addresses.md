# Contract Addresses

Official contract addresses for Set Chain networks.

## Testnet (Sepolia-based)

**Chain ID:** `84532001`
**RPC URL:** `https://rpc.testnet.setchain.io`
**Explorer:** `https://explorer.testnet.setchain.io`

### Core Contracts

| Contract | Address | Verified |
|----------|---------|----------|
| SetRegistry | `TBD` | - |
| SetPaymaster | `TBD` | - |
| SetTimelock | `TBD` | - |

### Stablecoin System

| Contract | Address | Verified |
|----------|---------|----------|
| TokenRegistry | `TBD` | - |
| NAVOracle | `TBD` | - |
| ssUSD | `TBD` | - |
| wssUSD | `TBD` | - |
| TreasuryVault | `TBD` | - |

### MEV Protection

| Contract | Address | Verified |
|----------|---------|----------|
| EncryptedMempool | `TBD` | - |
| ThresholdKeyRegistry | `TBD` | - |
| SequencerAttestation | `TBD` | - |
| ForcedInclusion | `TBD` | - |

### Tokens

| Token | Address | Decimals |
|-------|---------|----------|
| USDC (Bridged) | `TBD` | 6 |
| USDT (Bridged) | `TBD` | 6 |

## Mainnet

**Chain ID:** `TBD`
**RPC URL:** `TBD`
**Explorer:** `TBD`

> Mainnet addresses will be published after launch.

## Local Devnet

When running locally with `scripts/dev.sh`:

**Chain ID:** `31337`
**RPC URL:** `http://localhost:8545`

Addresses are deterministic based on deployer nonce:

```typescript
// Example local addresses (may vary)
const LOCAL_ADDRESSES = {
    setRegistry: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
    setPaymaster: "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512",
    // ... deployed by scripts/dev.sh deploy
};
```

## L1 Contracts (Ethereum)

### Sepolia L1

| Contract | Address | Purpose |
|----------|---------|---------|
| OptimismPortal | `TBD` | Bridge deposits/withdrawals |
| L2OutputOracle | `TBD` | L2 state root publishing |
| SystemConfig | `TBD` | Chain configuration |
| AddressManager | `TBD` | Contract registry |

### Mainnet L1

> L1 mainnet addresses will be published after launch.

## Address Configuration

### Environment Variables

```bash
# .env
SET_REGISTRY_ADDRESS=0x...
SET_PAYMASTER_ADDRESS=0x...
SET_TIMELOCK_ADDRESS=0x...

TOKEN_REGISTRY_ADDRESS=0x...
NAV_ORACLE_ADDRESS=0x...
SSUSD_ADDRESS=0x...
WSSUSD_ADDRESS=0x...
TREASURY_ADDRESS=0x...

ENCRYPTED_MEMPOOL_ADDRESS=0x...
THRESHOLD_KEY_REGISTRY_ADDRESS=0x...
```

### TypeScript Configuration

```typescript
import type { StablecoinAddresses } from "@setchain/sdk";

const TESTNET_ADDRESSES: StablecoinAddresses = {
    tokenRegistry: "0x...",
    navOracle: "0x...",
    ssUSD: "0x...",
    wssUSD: "0x...",
    treasury: "0x..."
};

const MAINNET_ADDRESSES: StablecoinAddresses = {
    tokenRegistry: "0x...",
    navOracle: "0x...",
    ssUSD: "0x...",
    wssUSD: "0x...",
    treasury: "0x..."
};

// Use based on environment
const addresses = process.env.NETWORK === "mainnet"
    ? MAINNET_ADDRESSES
    : TESTNET_ADDRESSES;
```

### Hardcoded Presets

```typescript
import { NETWORK_PRESETS } from "@setchain/sdk";

// Use testnet preset
const addresses = NETWORK_PRESETS.testnet.addresses;

// Use mainnet preset (when available)
const addresses = NETWORK_PRESETS.mainnet.addresses;
```

## Verification

All production contracts are verified on the block explorer.

### Verify on Explorer

1. Go to explorer: `https://explorer.testnet.setchain.io`
2. Search for contract address
3. Click "Contract" tab
4. View verified source code

### Verify Programmatically

```typescript
import { Contract, JsonRpcProvider } from "ethers";
import { SetRegistryABI } from "@setchain/sdk";

const provider = new JsonRpcProvider(RPC_URL);
const registry = new Contract(REGISTRY_ADDRESS, SetRegistryABI, provider);

// Check contract code exists
const code = await provider.getCode(REGISTRY_ADDRESS);
if (code === "0x") {
    throw new Error("Contract not deployed at this address");
}

// Call a view function to verify ABI
const totalBatches = await registry.totalBatches();
console.log("Contract verified, total batches:", totalBatches);
```

## Proxy Addresses

All upgradeable contracts use UUPS proxies:

| Contract | Proxy Address | Implementation |
|----------|---------------|----------------|
| SetRegistry | `0x...` (use this) | `0x...` (internal) |
| TreasuryVault | `0x...` (use this) | `0x...` (internal) |

**Always use the proxy address** - implementations may change during upgrades.

## Address Changes

Contract addresses will NOT change after mainnet launch, except:

1. **Upgrades**: Implementation changes (same proxy address)
2. **New contracts**: Additional functionality (new addresses)
3. **Emergency**: Migration to new contracts (announced with migration period)

Subscribe to announcements:
- Twitter: [@SetChain](https://twitter.com/setchain)
- Discord: [discord.gg/setchain](https://discord.gg/setchain)

## Related

- [Deployment Guide](../operations/deployment.md)
- [Contract ABIs](./abis.md)
- [Network Configuration](../getting-started/configuration.md)
