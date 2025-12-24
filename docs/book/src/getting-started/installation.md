# Installation Guide

Detailed setup instructions for Set Chain development.

## System Requirements

- **Node.js**: 18.0.0 or higher
- **npm/yarn/pnpm**: Latest version
- **Foundry**: For smart contract development
- **Git**: For version control

## SDK Installation

### Using npm

```bash
npm install @setchain/sdk ethers
```

### Using yarn

```bash
yarn add @setchain/sdk ethers
```

### Using pnpm

```bash
pnpm add @setchain/sdk ethers
```

## Smart Contract Development

### Install Foundry

```bash
# Install foundryup
curl -L https://foundry.paradigm.xyz | bash

# Install Foundry tools
foundryup
```

### Clone Set Contracts

```bash
git clone https://github.com/setchain/contracts.git
cd contracts

# Install dependencies
forge install
```

### Build Contracts

```bash
forge build
```

### Run Tests

```bash
forge test
```

## Development Environment

### Environment Variables

Create a `.env` file:

```bash
# Network
SET_RPC_URL=https://rpc.testnet.setchain.io
SET_CHAIN_ID=84532001

# Wallet (use test keys only!)
PRIVATE_KEY=0x...

# Contract Addresses (testnet)
SET_REGISTRY_ADDRESS=0x...
SET_PAYMASTER_ADDRESS=0x...
TOKEN_REGISTRY_ADDRESS=0x...
NAV_ORACLE_ADDRESS=0x...
SSUSD_ADDRESS=0x...
WSSUSD_ADDRESS=0x...
TREASURY_ADDRESS=0x...
```

### TypeScript Project Setup

```bash
# Initialize project
mkdir my-set-app && cd my-set-app
npm init -y

# Install dependencies
npm install @setchain/sdk ethers dotenv typescript ts-node
npm install -D @types/node

# Initialize TypeScript
npx tsc --init
```

Recommended `tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "esModuleInterop": true,
    "strict": true,
    "skipLibCheck": true,
    "outDir": "./dist",
    "rootDir": "./src"
  },
  "include": ["src/**/*"]
}
```

### Basic Script

Create `src/index.ts`:

```typescript
import "dotenv/config";
import { stablecoin, formatBalance } from "@setchain/sdk";
import { JsonRpcProvider, formatUnits } from "ethers";

async function main() {
    // Setup provider
    const provider = new JsonRpcProvider(process.env.SET_RPC_URL);

    // Create stablecoin client
    const client = stablecoin.createStablecoinClient(
        {
            tokenRegistry: process.env.TOKEN_REGISTRY_ADDRESS!,
            navOracle: process.env.NAV_ORACLE_ADDRESS!,
            ssUSD: process.env.SSUSD_ADDRESS!,
            wssUSD: process.env.WSSUSD_ADDRESS!,
            treasury: process.env.TREASURY_ADDRESS!
        },
        process.env.PRIVATE_KEY!,
        process.env.SET_RPC_URL!
    );

    // Get system stats
    const stats = await client.getStats();
    console.log("Set Chain Stablecoin Stats:");
    console.log(`  NAV: $${formatUnits(stats.nav, 18)}`);
    console.log(`  Total Supply: ${formatUnits(stats.totalSupply, 18)} ssUSD`);
    console.log(`  Deposits Paused: ${stats.depositsPaused}`);
}

main().catch(console.error);
```

Run:

```bash
npx ts-node src/index.ts
```

## Wallet Setup

### MetaMask Configuration

Add Set Chain network to MetaMask:

| Setting | Testnet Value |
|---------|---------------|
| Network Name | Set Chain Testnet |
| RPC URL | https://rpc.testnet.setchain.io |
| Chain ID | 84532001 |
| Currency Symbol | ETH |
| Block Explorer | https://explorer.testnet.setchain.io |

### Programmatic Wallet

```typescript
import { Wallet, JsonRpcProvider } from "ethers";

// From private key
const provider = new JsonRpcProvider("https://rpc.testnet.setchain.io");
const wallet = new Wallet(PRIVATE_KEY, provider);

// Generate new wallet
const newWallet = Wallet.createRandom();
console.log("Address:", newWallet.address);
console.log("Private Key:", newWallet.privateKey);
console.log("Mnemonic:", newWallet.mnemonic.phrase);
```

## Get Test Tokens

### Bridge ETH from Sepolia

1. Get Sepolia ETH from a faucet
2. Go to [bridge.testnet.setchain.io](https://bridge.testnet.setchain.io)
3. Connect wallet
4. Bridge Sepolia ETH to Set Chain

### Get Test USDC/USDT

Test stablecoins are available from the testnet faucet:

```bash
# Via CLI
curl -X POST https://faucet.testnet.setchain.io/api/claim \
  -H "Content-Type: application/json" \
  -d '{"address": "0x...", "token": "USDC"}'
```

Or visit [faucet.testnet.setchain.io](https://faucet.testnet.setchain.io).

## IDE Setup

### VS Code Extensions

Recommended extensions for Set Chain development:

- **Solidity** - Solidity language support
- **Hardhat Solidity** - Hardhat integration
- **ESLint** - JavaScript/TypeScript linting
- **Prettier** - Code formatting

### VS Code Settings

```json
{
  "solidity.packageDefaultDependenciesContractsDirectory": "src",
  "solidity.packageDefaultDependenciesDirectory": "lib",
  "editor.formatOnSave": true,
  "[solidity]": {
    "editor.defaultFormatter": "JuanBlanco.solidity"
  }
}
```

## Verify Installation

Run this script to verify everything is set up correctly:

```typescript
import { JsonRpcProvider } from "ethers";

async function verify() {
    const checks: { name: string; status: boolean; error?: string }[] = [];

    // Check RPC connection
    try {
        const provider = new JsonRpcProvider("https://rpc.testnet.setchain.io");
        const network = await provider.getNetwork();
        checks.push({
            name: "RPC Connection",
            status: network.chainId === 84532001n
        });
    } catch (error) {
        checks.push({
            name: "RPC Connection",
            status: false,
            error: error.message
        });
    }

    // Check SDK import
    try {
        const { stablecoin } = await import("@setchain/sdk");
        checks.push({
            name: "SDK Import",
            status: typeof stablecoin.createStablecoinClient === "function"
        });
    } catch (error) {
        checks.push({
            name: "SDK Import",
            status: false,
            error: error.message
        });
    }

    // Print results
    console.log("\nInstallation Verification:");
    for (const check of checks) {
        const icon = check.status ? "✅" : "❌";
        console.log(`${icon} ${check.name}${check.error ? `: ${check.error}` : ""}`);
    }
}

verify();
```

## Troubleshooting

### Module Not Found

```bash
# Clear cache and reinstall
rm -rf node_modules package-lock.json
npm install
```

### TypeScript Errors

```bash
# Ensure correct TypeScript version
npm install typescript@^5.0.0 --save-dev
```

### RPC Connection Issues

```bash
# Test RPC endpoint
curl -X POST https://rpc.testnet.setchain.io \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
```

## Next Steps

- [Configuration](./configuration.md) - Configure SDK options
- [Quick Start](./quick-start.md) - Start building
- [Local Development](./local-development.md) - Run locally
