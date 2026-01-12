# SDK Configuration

Configure the Set Chain SDK for your application.

## Basic Configuration

### Minimal Setup

```typescript
import { stablecoin, mev } from "@setchain/sdk";

// Stablecoin client
const stablecoinClient = stablecoin.createStablecoinClient(
    {
        tokenRegistry: "0x...",
        navOracle: "0x...",
        ssUSD: "0x...",
        wssUSD: "0x...",
        treasury: "0x..."
    },
    privateKey,
    rpcUrl
);

// MEV client
const mevClient = mev.createMEVProtectionClient(
    {
        encryptedMempool: "0x...",
        thresholdKeyRegistry: "0x..."
    },
    wallet
);
```

### Full Configuration

```typescript
import { SDKConfig, createSDK } from "@setchain/sdk";

const config: SDKConfig = {
    // Network
    network: {
        chainId: 84532001,
        rpcUrl: "https://rpc.testnet.setchain.io",
        wsUrl: "wss://ws.testnet.setchain.io"
    },

    // Contract addresses
    contracts: {
        // Core
        setRegistry: "0x...",
        setPaymaster: "0x...",
        setTimelock: "0x...",

        // Stablecoin
        tokenRegistry: "0x...",
        navOracle: "0x...",
        ssUSD: "0x...",
        wssUSD: "0x...",
        treasury: "0x...",

        // MEV
        encryptedMempool: "0x...",
        thresholdKeyRegistry: "0x...",
        sequencerAttestation: "0x...",

        // L1 (for forced inclusion)
        forcedInclusion: "0x..."  // On Ethereum
    },

    // Options
    options: {
        // Transaction defaults
        gasLimitBuffer: 1.2,  // 20% buffer
        maxGasPrice: parseUnits("100", "gwei"),
        maxPriorityFee: parseUnits("2", "gwei"),

        // Retry settings
        maxRetries: 3,
        retryDelay: 1000,
        retryBackoff: 2,

        // Timeouts
        transactionTimeout: 60000,
        confirmationTimeout: 120000,

        // Polling
        pollInterval: 2000,
        confirmations: 1
    }
};

const sdk = createSDK(config);
```

## Environment Variables

### Recommended .env Setup

```bash
# Network
SET_CHAIN_ID=84532001
SET_RPC_URL=https://rpc.testnet.setchain.io
SET_WS_URL=wss://ws.testnet.setchain.io

# Private key (NEVER commit this!)
PRIVATE_KEY=0x...

# Core contracts
SET_REGISTRY_ADDRESS=0x...
SET_PAYMASTER_ADDRESS=0x...
SET_TIMELOCK_ADDRESS=0x...

# Stablecoin contracts
TOKEN_REGISTRY_ADDRESS=0x...
NAV_ORACLE_ADDRESS=0x...
SSUSD_ADDRESS=0x...
WSSUSD_ADDRESS=0x...
TREASURY_ADDRESS=0x...

# MEV contracts
ENCRYPTED_MEMPOOL_ADDRESS=0x...
THRESHOLD_KEY_REGISTRY_ADDRESS=0x...

# L1 (Ethereum/Sepolia)
L1_RPC_URL=https://eth-sepolia.example.com
FORCED_INCLUSION_ADDRESS=0x...
```

### Loading Configuration

```typescript
import "dotenv/config";
import { SDKConfig } from "@setchain/sdk";

const config: SDKConfig = {
    network: {
        chainId: parseInt(process.env.SET_CHAIN_ID!),
        rpcUrl: process.env.SET_RPC_URL!,
        wsUrl: process.env.SET_WS_URL
    },
    contracts: {
        setRegistry: process.env.SET_REGISTRY_ADDRESS!,
        setPaymaster: process.env.SET_PAYMASTER_ADDRESS!,
        tokenRegistry: process.env.TOKEN_REGISTRY_ADDRESS!,
        navOracle: process.env.NAV_ORACLE_ADDRESS!,
        ssUSD: process.env.SSUSD_ADDRESS!,
        wssUSD: process.env.WSSUSD_ADDRESS!,
        treasury: process.env.TREASURY_ADDRESS!,
        encryptedMempool: process.env.ENCRYPTED_MEMPOOL_ADDRESS!,
        thresholdKeyRegistry: process.env.THRESHOLD_KEY_REGISTRY_ADDRESS!
    }
};
```

## Network Presets

### Testnet

```typescript
import { getTestnetConfig } from "@setchain/sdk";

const config = getTestnetConfig();
// Pre-configured with testnet addresses and RPC
```

### Mainnet

```typescript
import { getMainnetConfig } from "@setchain/sdk";

const config = getMainnetConfig();
// Pre-configured with mainnet addresses and RPC
```

### Local Development

```typescript
import { getLocalConfig } from "@setchain/sdk";

const config = getLocalConfig();
// Configured for localhost:8545
```

## Provider Configuration

### JSON-RPC Provider

```typescript
import { JsonRpcProvider } from "ethers";

const provider = new JsonRpcProvider(rpcUrl, {
    chainId: 84532001,
    name: "set-testnet"
});
```

### WebSocket Provider

```typescript
import { WebSocketProvider } from "ethers";

const wsProvider = new WebSocketProvider(wsUrl, {
    chainId: 84532001,
    name: "set-testnet"
});

// Handle reconnection
wsProvider.on("error", (error) => {
    console.error("WebSocket error:", error);
    // Implement reconnection logic
});
```

### Fallback Provider

```typescript
import { FallbackProvider, JsonRpcProvider } from "ethers";

const provider = new FallbackProvider([
    { provider: new JsonRpcProvider(primaryRpc), priority: 1, weight: 2 },
    { provider: new JsonRpcProvider(backupRpc), priority: 2, weight: 1 }
]);
```

## Wallet Configuration

### From Private Key

```typescript
import { Wallet } from "ethers";

const wallet = new Wallet(privateKey, provider);
```

### From Mnemonic

```typescript
import { Wallet, HDNodeWallet } from "ethers";

const hdWallet = HDNodeWallet.fromPhrase(mnemonic);
const wallet = hdWallet.connect(provider);

// Derive multiple accounts
const account0 = hdWallet.deriveChild(0).connect(provider);
const account1 = hdWallet.deriveChild(1).connect(provider);
```

### Browser Wallet (MetaMask)

```typescript
import { BrowserProvider } from "ethers";

const provider = new BrowserProvider(window.ethereum);
const signer = await provider.getSigner();
```

### Hardware Wallet (Ledger)

```typescript
import { LedgerSigner } from "@ethersproject/hardware-wallets";

const signer = new LedgerSigner(provider, "hid", "m/44'/60'/0'/0/0");
```

## Gas Configuration

### Default Gas Settings

```typescript
const options = {
    // Gas limit buffer (multiply estimated gas)
    gasLimitBuffer: 1.2,  // 20% buffer

    // Maximum gas price willing to pay
    maxGasPrice: parseUnits("100", "gwei"),

    // Priority fee (tip to sequencer)
    maxPriorityFee: parseUnits("2", "gwei"),

    // Override gas estimation
    defaultGasLimit: {
        deposit: 200000n,
        redeem: 180000n,
        wrap: 100000n,
        unwrap: 100000n,
        transfer: 65000n
    }
};
```

### Dynamic Gas Pricing

```typescript
async function getOptimalGasPrice() {
    const feeData = await provider.getFeeData();

    return {
        maxFeePerGas: feeData.maxFeePerGas! * 120n / 100n,  // 20% buffer
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas! * 110n / 100n
    };
}

// Use in transactions
const tx = await client.deposit(token, amount, {
    ...(await getOptimalGasPrice())
});
```

## Retry Configuration

### Automatic Retry

```typescript
const options = {
    maxRetries: 3,
    retryDelay: 1000,      // Initial delay in ms
    retryBackoff: 2,       // Exponential backoff multiplier

    // Custom retry condition
    shouldRetry: (error: Error, attempt: number) => {
        // Retry on network errors
        if (error.message.includes("network")) return true;
        // Retry on timeout
        if (error.message.includes("timeout")) return true;
        // Don't retry on user rejection
        if (error.message.includes("user rejected")) return false;
        // Default: retry
        return attempt < 3;
    }
};
```

### Manual Retry

```typescript
import { withRetry } from "@setchain/sdk";

const result = await withRetry(
    () => client.deposit(token, amount),
    {
        maxRetries: 5,
        initialDelay: 2000,
        shouldRetry: (error) => error.code === "NETWORK_ERROR"
    }
);
```

## Timeout Configuration

```typescript
const options = {
    // Transaction submission timeout
    transactionTimeout: 60000,  // 60 seconds

    // Confirmation timeout
    confirmationTimeout: 120000,  // 2 minutes

    // RPC call timeout
    rpcTimeout: 30000,  // 30 seconds

    // Polling interval for confirmations
    pollInterval: 2000  // 2 seconds
};
```

## Event Configuration

### Event Subscription

```typescript
const eventConfig = {
    // How far back to look for events
    fromBlock: "latest",

    // Maximum blocks per query (for historical)
    maxBlockRange: 10000,

    // Polling interval for new events
    pollInterval: 5000,

    // Auto-reconnect WebSocket
    autoReconnect: true,
    reconnectDelay: 5000
};
```

### Event Handlers

```typescript
const handlers = {
    onDeposit: (user, token, amount, ssUSDMinted) => {
        console.log(`Deposit: ${user} deposited ${amount}`);
    },
    onRedemption: (user, token, ssUSDBurned, amountRedeemed) => {
        console.log(`Redemption: ${user} redeemed ${ssUSDBurned}`);
    },
    onError: (error) => {
        console.error("Event error:", error);
    }
};

sdk.events.subscribe(handlers);
```

## Logging Configuration

### Log Levels

```typescript
const logConfig = {
    level: "info",  // "debug" | "info" | "warn" | "error"

    // Include transaction details
    logTransactions: true,

    // Include gas estimates
    logGas: true,

    // Custom logger
    logger: {
        debug: (msg, data) => console.debug(msg, data),
        info: (msg, data) => console.info(msg, data),
        warn: (msg, data) => console.warn(msg, data),
        error: (msg, data) => console.error(msg, data)
    }
};
```

### External Logging

```typescript
import pino from "pino";

const logger = pino({ level: "info" });

const logConfig = {
    logger: {
        debug: (msg, data) => logger.debug(data, msg),
        info: (msg, data) => logger.info(data, msg),
        warn: (msg, data) => logger.warn(data, msg),
        error: (msg, data) => logger.error(data, msg)
    }
};
```

## Complete Example

```typescript
import { createSDK, SDKConfig } from "@setchain/sdk";
import { Wallet, JsonRpcProvider, parseUnits } from "ethers";
import "dotenv/config";

// Load configuration
const config: SDKConfig = {
    network: {
        chainId: parseInt(process.env.SET_CHAIN_ID!),
        rpcUrl: process.env.SET_RPC_URL!,
        wsUrl: process.env.SET_WS_URL
    },
    contracts: {
        tokenRegistry: process.env.TOKEN_REGISTRY_ADDRESS!,
        navOracle: process.env.NAV_ORACLE_ADDRESS!,
        ssUSD: process.env.SSUSD_ADDRESS!,
        wssUSD: process.env.WSSUSD_ADDRESS!,
        treasury: process.env.TREASURY_ADDRESS!,
        encryptedMempool: process.env.ENCRYPTED_MEMPOOL_ADDRESS!,
        thresholdKeyRegistry: process.env.THRESHOLD_KEY_REGISTRY_ADDRESS!
    },
    options: {
        gasLimitBuffer: 1.2,
        maxRetries: 3,
        retryDelay: 1000,
        transactionTimeout: 60000,
        confirmations: 1,
        logLevel: "info"
    }
};

// Create provider and wallet
const provider = new JsonRpcProvider(config.network.rpcUrl);
const wallet = new Wallet(process.env.PRIVATE_KEY!, provider);

// Create SDK instance
const sdk = createSDK(config, wallet);

// Use SDK
async function main() {
    // Check system status
    const stats = await sdk.stablecoin.getStats();
    console.log(`NAV: $${formatUnits(stats.nav, 18)}`);

    // Deposit
    const result = await sdk.stablecoin.deposit(
        process.env.USDC_ADDRESS!,
        parseUnits("100", 6)
    );
    console.log(`Minted: ${formatUnits(result.ssUSDMinted, 18)} ssUSD`);
}

main().catch(console.error);
```

## Related

- [SDK Installation](./installation.md)
- [Stablecoin Client](./stablecoin-client.md)
- [MEV Client](./mev-client.md)
- [Error Handling](./errors.md)
