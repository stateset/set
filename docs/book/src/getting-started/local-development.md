# Local Development

Run Set Chain locally for development and testing.

## Quick Start

The fastest way to get started:

```bash
# Clone repository
git clone https://github.com/setchain/set.git
cd set

# Start local environment
./scripts/dev.sh
```

This starts:
- Anvil (local Ethereum node)
- Deploys all contracts
- Configures test tokens

## Manual Setup

### 1. Start Anvil

```bash
# Start with deterministic accounts
anvil --port 8545

# Or fork testnet
anvil --fork-url https://rpc.testnet.setchain.io --port 8545
```

### 2. Deploy Contracts

```bash
# Set environment
export RPC_URL=http://localhost:8545
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Deploy all contracts
forge script scripts/DeployLocal.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

### 3. Configure Environment

The deploy script outputs addresses. Add to `.env.local`:

```bash
# Local development
RPC_URL=http://localhost:8545
CHAIN_ID=31337

# Test account (Anvil default)
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Contract addresses (from deployment)
SET_REGISTRY_ADDRESS=0x5FbDB2315678afecb367f032d93F642f64180aa3
SET_PAYMASTER_ADDRESS=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
TOKEN_REGISTRY_ADDRESS=0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
NAV_ORACLE_ADDRESS=0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
SSUSD_ADDRESS=0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9
WSSUSD_ADDRESS=0x5FC8d32690cc91D4c39d9d3abcBD16989F875707
TREASURY_ADDRESS=0x0165878A594ca255338adfa4d48449f69242Eb8F

# Test tokens
USDC_ADDRESS=0xa513E6E4b8f2a923D98304ec87F64353C4D5C853
USDT_ADDRESS=0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6
```

## Test Accounts

Anvil provides funded test accounts:

| Account | Address | Private Key |
|---------|---------|-------------|
| Account 0 | 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 | 0xac0974... |
| Account 1 | 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 | 0x59c6995e... |
| Account 2 | 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC | 0x5de4111... |

Each account starts with 10,000 ETH.

## Local Workflows

### Mint Test Tokens

```typescript
import { Contract, Wallet, JsonRpcProvider, parseUnits } from "ethers";

const provider = new JsonRpcProvider("http://localhost:8545");
const wallet = new Wallet(PRIVATE_KEY, provider);

// MockERC20 ABI (includes mint)
const MockERC20ABI = [
    "function mint(address to, uint256 amount) external"
];

const usdc = new Contract(USDC_ADDRESS, MockERC20ABI, wallet);

// Mint 10,000 USDC
await usdc.mint(wallet.address, parseUnits("10000", 6));
```

### Submit NAV Attestation

```typescript
import { Contract, Wallet, parseUnits, keccak256, toUtf8Bytes } from "ethers";

const navOracle = new Contract(NAV_ORACLE_ADDRESS, NAVOracleABI, wallet);

// Create report
const report = {
    reportId: 1n,
    nav: parseUnits("1.0", 18),  // $1.00
    totalAssets: parseUnits("1000000", 18),
    totalShares: parseUnits("1000000", 18),
    timestamp: BigInt(Math.floor(Date.now() / 1000)),
    proofHash: keccak256(toUtf8Bytes("test-proof"))
};

// Sign and submit (local attestor)
const signature = await wallet.signMessage(/* ... */);
await navOracle.updateNAV(report, signature);
```

### Simulate NAV Increase (Yield)

```typescript
// Day 1: Initial NAV
await submitNAV(1n, parseUnits("1.0", 18));

// Day 2: 0.0137% daily yield (~5% APY)
await submitNAV(2n, parseUnits("1.000137", 18));

// Check user balance increased
const balance = await ssUSD.balanceOf(userAddress);
// Balance increased proportionally
```

### Test Deposits and Redemptions

```typescript
import { stablecoin } from "@setchain/sdk";
import { parseUnits, formatUnits } from "ethers";

const client = stablecoin.createStablecoinClient(
    addresses,
    PRIVATE_KEY,
    "http://localhost:8545"
);

// Approve USDC
await client.approve(USDC_ADDRESS, parseUnits("1000", 6));

// Deposit
const depositResult = await client.deposit(
    USDC_ADDRESS,
    parseUnits("1000", 6)
);
console.log(`Minted: ${formatUnits(depositResult.ssUSDMinted, 18)} ssUSD`);

// Check balance
const balance = await client.getBalance(wallet.address);
console.log(`ssUSD: ${formatUnits(balance.ssUSD, 18)}`);
console.log(`Shares: ${balance.ssUSDShares}`);

// Redeem half
const redeemResult = await client.redeem(
    USDC_ADDRESS,
    parseUnits("500", 18)
);
console.log(`Received: ${formatUnits(redeemResult.tokensReceived, 6)} USDC`);
```

## Development Scripts

### dev.sh

```bash
#!/bin/bash
# scripts/dev.sh

set -e

# Start anvil in background
anvil --port 8545 &
ANVIL_PID=$!

# Wait for anvil
sleep 2

# Deploy contracts
echo "Deploying contracts..."
forge script scripts/DeployLocal.s.sol \
    --rpc-url http://localhost:8545 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --broadcast

# Mint test tokens
echo "Minting test tokens..."
cast send $USDC_ADDRESS "mint(address,uint256)" \
    0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
    1000000000000 \
    --rpc-url http://localhost:8545 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Submit initial NAV
echo "Submitting initial NAV..."
# ... NAV submission

echo "Local environment ready!"
echo "RPC: http://localhost:8545"

# Keep anvil running
wait $ANVIL_PID
```

### test-integration.sh

```bash
#!/bin/bash
# scripts/test-integration.sh

# Run integration tests against local environment
npm run test:integration
```

## Debugging

### Trace Transactions

```bash
# Get detailed trace
cast run $TX_HASH --rpc-url http://localhost:8545

# Debug specific call
cast call $CONTRACT "function(args)" --trace --rpc-url http://localhost:8545
```

### Console Logging

```solidity
// In Solidity contracts
import "forge-std/console.sol";

function deposit(uint256 amount) external {
    console.log("Deposit amount:", amount);
    console.log("Sender:", msg.sender);
    // ...
}
```

### Event Monitoring

```typescript
// Listen to all events locally
const provider = new JsonRpcProvider("http://localhost:8545");

provider.on("block", async (blockNumber) => {
    const block = await provider.getBlock(blockNumber, true);
    console.log(`Block ${blockNumber}: ${block.transactions.length} txs`);
});

treasury.on("Deposit", (user, token, amount, ssUSDMinted) => {
    console.log(`Deposit: ${user} deposited ${amount}`);
});
```

## Testing

### Unit Tests (Forge)

```bash
# Run all tests
forge test

# Run specific test file
forge test --match-path test/TreasuryVault.t.sol

# Verbose output
forge test -vvvv

# Gas report
forge test --gas-report
```

### Integration Tests (TypeScript)

```typescript
// test/integration/deposit.test.ts
import { describe, it, expect, beforeAll } from "vitest";
import { stablecoin } from "@setchain/sdk";

describe("Deposit Flow", () => {
    let client: stablecoin.StablecoinClient;

    beforeAll(async () => {
        client = stablecoin.createStablecoinClient(
            addresses,
            TEST_PRIVATE_KEY,
            "http://localhost:8545"
        );
    });

    it("should deposit USDC and receive ssUSD", async () => {
        const amount = parseUnits("100", 6);
        const result = await client.deposit(USDC_ADDRESS, amount);

        expect(result.ssUSDMinted).toBeGreaterThan(0n);
    });
});
```

## Reset Environment

```bash
# Kill anvil
pkill anvil

# Restart fresh
./scripts/dev.sh
```

## Next Steps

- [Quick Start](./quick-start.md) - Build your first app
- [Configuration](./configuration.md) - Configure for production
- [Deployment Guide](../operations/deployment.md) - Deploy to testnet
