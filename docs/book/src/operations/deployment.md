# Deployment Guide

Deploy Set Chain contracts to testnet or mainnet.

## Prerequisites

- Node.js 18+
- Foundry (forge, cast, anvil)
- Private key with sufficient ETH
- RPC endpoints for L1 and L2

## Environment Setup

Create `.env` file:

```bash
# Deployer
PRIVATE_KEY=0x...
DEPLOYER_ADDRESS=0x...

# L1 (Ethereum)
L1_RPC_URL=https://eth-sepolia.example.com
L1_CHAIN_ID=11155111

# L2 (Set Chain)
L2_RPC_URL=https://rpc.testnet.setchain.io
L2_CHAIN_ID=84532001

# Etherscan (for verification)
ETHERSCAN_API_KEY=...
```

## Contract Deployment Order

```
1. Core Infrastructure
   ├── SetTimelock (governance)
   └── SetRegistry (VES anchoring)

2. Gas Sponsorship
   └── SetPaymaster

3. Stablecoin System
   ├── TokenRegistry
   ├── NAVOracle
   ├── ssUSD (proxy)
   ├── wssUSD (proxy)
   └── TreasuryVault (proxy)

4. MEV Protection
   ├── ThresholdKeyRegistry
   ├── EncryptedMempool
   ├── SequencerAttestation
   └── ForcedInclusion (L1)
```

## Deployment Scripts

### 1. Deploy Core Contracts

```bash
# Deploy SetTimelock
forge script scripts/Deploy.s.sol:DeployTimelock \
    --rpc-url $L2_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify
```

```solidity
// scripts/Deploy.s.sol
contract DeployTimelock is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy timelock with 48-hour upgrade delay
        SetTimelock timelock = new SetTimelock(
            48 hours,  // upgrade delay
            24 hours,  // parameter delay
            admin,     // initial admin
            guardians  // emergency guardians
        );

        console.log("SetTimelock:", address(timelock));

        vm.stopBroadcast();
    }
}
```

### 2. Deploy SetRegistry

```bash
forge script scripts/Deploy.s.sol:DeployRegistry \
    --rpc-url $L2_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify
```

```solidity
contract DeployRegistry is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy implementation
        SetRegistry impl = new SetRegistry();

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(SetRegistry.initialize, (
                admin,
                timelock,
                1000  // max batch size
            ))
        );

        console.log("SetRegistry proxy:", address(proxy));
        console.log("SetRegistry impl:", address(impl));

        vm.stopBroadcast();
    }
}
```

### 3. Deploy Stablecoin System

```bash
forge script scripts/DeployStablecoin.s.sol \
    --rpc-url $L2_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify
```

```solidity
contract DeployStablecoin is Script {
    function run() external {
        vm.startBroadcast();

        // 1. TokenRegistry
        TokenRegistry tokenRegistry = new TokenRegistry();
        tokenRegistry.initialize(admin, timelock);

        // 2. NAVOracle
        NAVOracle navOracle = new NAVOracle();
        navOracle.initialize(
            admin,
            attestor,      // NAV attestor address
            24 hours       // staleness threshold
        );

        // 3. ssUSD (proxy)
        ssUSD ssUSDImpl = new ssUSD();
        ERC1967Proxy ssUSDProxy = new ERC1967Proxy(
            address(ssUSDImpl),
            abi.encodeCall(ssUSD.initialize, (
                admin,
                address(navOracle),
                "Set Stablecoin USD",
                "ssUSD"
            ))
        );

        // 4. wssUSD (proxy)
        wssUSD wssUSDImpl = new wssUSD();
        ERC1967Proxy wssUSDProxy = new ERC1967Proxy(
            address(wssUSDImpl),
            abi.encodeCall(wssUSD.initialize, (
                address(ssUSDProxy),
                "Wrapped ssUSD",
                "wssUSD"
            ))
        );

        // 5. TreasuryVault (proxy)
        TreasuryVault treasuryImpl = new TreasuryVault();
        ERC1967Proxy treasuryProxy = new ERC1967Proxy(
            address(treasuryImpl),
            abi.encodeCall(TreasuryVault.initialize, (
                admin,
                address(tokenRegistry),
                address(navOracle),
                address(ssUSDProxy)
            ))
        );

        // 6. Configure ssUSD minter
        ssUSD(address(ssUSDProxy)).setTreasury(address(treasuryProxy));

        // Log addresses
        console.log("TokenRegistry:", address(tokenRegistry));
        console.log("NAVOracle:", address(navOracle));
        console.log("ssUSD:", address(ssUSDProxy));
        console.log("wssUSD:", address(wssUSDProxy));
        console.log("TreasuryVault:", address(treasuryProxy));

        vm.stopBroadcast();
    }
}
```

### 4. Configure Collateral Tokens

```bash
forge script scripts/ConfigureTokens.s.sol \
    --rpc-url $L2_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast
```

```solidity
contract ConfigureTokens is Script {
    function run() external {
        vm.startBroadcast();

        TokenRegistry registry = TokenRegistry(TOKEN_REGISTRY);

        // Register USDC
        registry.registerToken(
            USDC_ADDRESS,
            TokenInfo({
                symbol: "USDC",
                decimals: 6,
                depositCap: 10_000_000e6,  // $10M cap
                currentDeposits: 0,
                depositEnabled: true,
                redemptionEnabled: true
            })
        );

        // Register USDT
        registry.registerToken(
            USDT_ADDRESS,
            TokenInfo({
                symbol: "USDT",
                decimals: 6,
                depositCap: 10_000_000e6,
                currentDeposits: 0,
                depositEnabled: true,
                redemptionEnabled: true
            })
        );

        vm.stopBroadcast();
    }
}
```

## Verification

### Verify on Block Explorer

```bash
# Verify proxy implementation
forge verify-contract \
    --chain-id $L2_CHAIN_ID \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --compiler-version v0.8.20 \
    $IMPL_ADDRESS \
    src/SetRegistry.sol:SetRegistry

# Verify proxy
forge verify-contract \
    --chain-id $L2_CHAIN_ID \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --compiler-version v0.8.20 \
    --constructor-args $(cast abi-encode "constructor(address,bytes)" $IMPL_ADDRESS $INIT_DATA) \
    $PROXY_ADDRESS \
    lib/openzeppelin/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy
```

### Post-Deployment Checks

```typescript
import { Contract, JsonRpcProvider } from "ethers";

async function verifyDeployment() {
    const provider = new JsonRpcProvider(L2_RPC_URL);

    // Check SetRegistry
    const registry = new Contract(REGISTRY_ADDRESS, SetRegistryABI, provider);
    const admin = await registry.hasRole(await registry.DEFAULT_ADMIN_ROLE(), ADMIN_ADDRESS);
    console.log("Registry admin configured:", admin);

    // Check TreasuryVault
    const treasury = new Contract(TREASURY_ADDRESS, TreasuryVaultABI, provider);
    const tokenRegistry = await treasury.tokenRegistry();
    console.log("Treasury tokenRegistry:", tokenRegistry);

    // Check ssUSD
    const ssUSD = new Contract(SSUSD_ADDRESS, ssUSDABI, provider);
    const treasuryAddress = await ssUSD.treasury();
    console.log("ssUSD treasury:", treasuryAddress);

    // Check NAVOracle
    const navOracle = new Contract(NAV_ORACLE_ADDRESS, NAVOracleABI, provider);
    const attestor = await navOracle.attestor();
    console.log("NAVOracle attestor:", attestor);
}
```

## Upgrade Procedure

### 1. Deploy New Implementation

```bash
forge script scripts/UpgradeRegistry.s.sol:DeployNewImpl \
    --rpc-url $L2_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify
```

### 2. Schedule Upgrade via Timelock

```typescript
import { Contract, Wallet } from "ethers";

async function scheduleUpgrade() {
    const timelock = new Contract(TIMELOCK_ADDRESS, SetTimelockABI, wallet);

    // Prepare upgrade call
    const upgradeData = registry.interface.encodeFunctionData(
        "upgradeToAndCall",
        [newImplementation, "0x"]
    );

    // Schedule with 48-hour delay
    const tx = await timelock.schedule(
        REGISTRY_ADDRESS,
        0n,
        upgradeData,
        0  // OperationType.UPGRADE
    );

    const receipt = await tx.wait();
    console.log("Scheduled upgrade:", receipt.logs[0].args.operationId);
    console.log("Ready at:", new Date(Date.now() + 48 * 60 * 60 * 1000));
}
```

### 3. Execute After Delay

```typescript
async function executeUpgrade(operationId: string) {
    const timelock = new Contract(TIMELOCK_ADDRESS, SetTimelockABI, wallet);

    // Check if ready
    const isReady = await timelock.isOperationReady(operationId);
    if (!isReady) {
        throw new Error("Operation not ready yet");
    }

    // Execute
    const tx = await timelock.execute(operationId);
    await tx.wait();

    console.log("Upgrade executed");
}
```

## Local Development

### Start Local Devnet

```bash
# Start anvil (local Ethereum)
anvil --fork-url $L2_RPC_URL --port 8545

# Deploy to local
forge script scripts/DeployAll.s.sol \
    --rpc-url http://localhost:8545 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --broadcast
```

### Quick Start Script

```bash
#!/bin/bash
# scripts/dev.sh

# Start anvil in background
anvil --port 8545 &
ANVIL_PID=$!

# Wait for anvil to start
sleep 2

# Deploy contracts
forge script scripts/DeployAll.s.sol \
    --rpc-url http://localhost:8545 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --broadcast

# Keep anvil running
wait $ANVIL_PID
```

## Deployment Checklist

### Pre-Deployment

- [ ] Audit complete and issues resolved
- [ ] Test coverage > 90%
- [ ] Gas estimates within budget
- [ ] Admin addresses confirmed
- [ ] Timelock delays configured
- [ ] Emergency guardians set

### Deployment

- [ ] Deploy timelock first
- [ ] Deploy core contracts
- [ ] Deploy stablecoin system
- [ ] Configure token registry
- [ ] Set initial NAV attestation
- [ ] Verify all contracts on explorer

### Post-Deployment

- [ ] Transfer admin to multisig
- [ ] Test all main flows
- [ ] Monitor for 24 hours
- [ ] Update documentation
- [ ] Announce deployment

## Related

- [Security Operations](./security.md)
- [Monitoring](./monitoring.md)
- [Contract Addresses](../api/addresses.md)
