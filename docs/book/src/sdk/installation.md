# SDK Installation

Install and configure the Set Chain SDK for your project.

## Requirements

- Node.js 18.0.0 or higher
- TypeScript 5.0+ (recommended)
- ethers.js 6.x

## Installation

### npm

```bash
npm install @setchain/sdk ethers
```

### yarn

```bash
yarn add @setchain/sdk ethers
```

### pnpm

```bash
pnpm add @setchain/sdk ethers
```

## Basic Setup

### TypeScript

```typescript
import {
    stablecoin,
    createMEVProtectionClient,
    validateAddress,
    formatBalance
} from "@setchain/sdk";
import { JsonRpcProvider, Wallet, parseUnits } from "ethers";

// Setup provider and wallet
const provider = new JsonRpcProvider("https://rpc.testnet.setchain.io");
const wallet = new Wallet(process.env.PRIVATE_KEY!, provider);

// Create stablecoin client
const ssUSDClient = stablecoin.createStablecoinClient(
    {
        tokenRegistry: "0x...",
        navOracle: "0x...",
        ssUSD: "0x...",
        wssUSD: "0x...",
        treasury: "0x..."
    },
    process.env.PRIVATE_KEY!,
    "https://rpc.testnet.setchain.io"
);

// Use the client
const balance = await ssUSDClient.getBalance(wallet.address);
console.log("ssUSD:", formatBalance(balance.ssUSD, 18));
```

### JavaScript (ESM)

```javascript
import { stablecoin, formatBalance } from "@setchain/sdk";
import { JsonRpcProvider, Wallet } from "ethers";

const provider = new JsonRpcProvider("https://rpc.testnet.setchain.io");
const wallet = new Wallet(process.env.PRIVATE_KEY, provider);

const client = stablecoin.createStablecoinClient(addresses, privateKey, rpcUrl);
```

### JavaScript (CommonJS)

```javascript
const { stablecoin, formatBalance } = require("@setchain/sdk");
const { JsonRpcProvider, Wallet } = require("ethers");

// Same usage as ESM
```

## TypeScript Configuration

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
    "resolveJsonModule": true
  }
}
```

## Exports

The SDK exports the following modules:

### Main Exports

```typescript
// Stablecoin client
import { stablecoin } from "@setchain/sdk";
const { createStablecoinClient, StablecoinClient } = stablecoin;

// MEV protection
import { createMEVProtectionClient } from "@setchain/sdk";

// Configuration
import { setConfig, getConfig, NETWORK_PRESETS } from "@setchain/sdk";

// Contract ABIs
import {
    SetRegistryABI,
    SetPaymasterABI,
    ssUSDABI,
    wssUSDABI,
    TreasuryVaultABI
} from "@setchain/sdk";
```

### Utilities

```typescript
import {
    // Validation
    validateAddress,
    validateNonZeroAddress,
    isValidAddress,
    validatePositiveAmount,
    validateBytes32,

    // Formatting
    formatBalance,
    parseBalance,
    formatUSD,
    formatPercentage,
    shortenAddress,

    // Gas
    estimateGas,
    applyGasBuffer,
    DEFAULT_GAS_LIMITS,

    // Retry
    withRetry,
    withTimeout,
    pollUntil,

    // Events
    findEvent,
    extractEventArg
} from "@setchain/sdk";
```

### Error Types

```typescript
import {
    SDKError,
    SDKErrorCode,
    InvalidAddressError,
    InvalidAmountError,
    InsufficientBalanceError,
    TransactionFailedError,
    NAVStaleError,
    DepositsPausedError,
    isSDKError,
    hasErrorCode,
    wrapError
} from "@setchain/sdk";
```

### Types

```typescript
import type {
    StablecoinAddresses,
    StablecoinStats,
    UserBalance,
    NAVReport,
    RedemptionRequest,
    TokenInfo,
    DepositResult,
    RedemptionResult,
    WrapResult,
    GasEstimate,
    SDKConfig
} from "@setchain/sdk";
```

## Environment Variables

Recommended environment setup:

```bash
# .env
PRIVATE_KEY=0x...
SET_RPC_URL=https://rpc.testnet.setchain.io

# Contract addresses
SET_REGISTRY_ADDRESS=0x...
SET_PAYMASTER_ADDRESS=0x...
SSUSD_ADDRESS=0x...
WSSUSD_ADDRESS=0x...
TREASURY_ADDRESS=0x...
TOKEN_REGISTRY_ADDRESS=0x...
NAV_ORACLE_ADDRESS=0x...
```

Load with dotenv:

```typescript
import "dotenv/config";

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
```

## Bundle Size

The SDK is tree-shakeable. Import only what you need:

```typescript
// Good - only imports stablecoin module
import { stablecoin } from "@setchain/sdk";

// Good - specific utilities
import { validateAddress, formatBalance } from "@setchain/sdk";

// Avoid - imports everything
import * as SetChain from "@setchain/sdk";
```

## Browser Usage

The SDK works in browsers with a bundler:

```typescript
// React example
import { stablecoin, formatBalance } from "@setchain/sdk";
import { BrowserProvider } from "ethers";

function useSetChain() {
    const [client, setClient] = useState(null);

    useEffect(() => {
        async function init() {
            const provider = new BrowserProvider(window.ethereum);
            const signer = await provider.getSigner();

            const client = new stablecoin.StablecoinClient(
                addresses,
                signer
            );
            setClient(client);
        }
        init();
    }, []);

    return client;
}
```

## Troubleshooting

### Module Resolution Errors

If you see `Cannot find module '@setchain/sdk'`:

```bash
# Clear node_modules and reinstall
rm -rf node_modules package-lock.json
npm install
```

### TypeScript Errors

Ensure you have compatible TypeScript version:

```bash
npm install typescript@^5.0.0 --save-dev
```

### BigInt Support

The SDK uses native BigInt. Ensure your environment supports it:

```typescript
// Node.js 10.4+ supports BigInt
// Modern browsers support BigInt

// For older environments, use BigInt polyfill
import "core-js/features/bigint";
```

## Next Steps

- [Configuration](./configuration.md) - SDK configuration options
- [Stablecoin Client](./stablecoin-client.md) - ssUSD operations
- [Error Handling](./errors.md) - Handle SDK errors
