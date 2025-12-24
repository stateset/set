# Contract ABIs

JSON ABIs for Set Chain contracts.

## Usage

### From SDK

```typescript
import {
    SetRegistryABI,
    SetPaymasterABI,
    SetTimelockABI,
    ssUSDABI,
    wssUSDABI,
    TreasuryVaultABI,
    TokenRegistryABI,
    NAVOracleABI,
    EncryptedMempoolABI,
    ThresholdKeyRegistryABI
} from "@setchain/sdk";

import { Contract } from "ethers";

const registry = new Contract(REGISTRY_ADDRESS, SetRegistryABI, provider);
```

### From npm Package

```bash
npm install @setchain/contracts
```

```typescript
import { abi as SetRegistryABI } from "@setchain/contracts/artifacts/SetRegistry.json";
```

### Direct Download

ABIs are available at:
- `https://contracts.setchain.io/abis/SetRegistry.json`
- `https://contracts.setchain.io/abis/TreasuryVault.json`
- etc.

## Core Contracts

### SetRegistry ABI

```json
[
  {
    "type": "function",
    "name": "submitBatch",
    "inputs": [
      { "name": "tenantId", "type": "bytes32" },
      { "name": "storeId", "type": "bytes32" },
      { "name": "commitment", "type": "tuple", "components": [
        { "name": "merkleRoot", "type": "bytes32" },
        { "name": "stateRoot", "type": "bytes32" },
        { "name": "previousStateRoot", "type": "bytes32" },
        { "name": "eventCount", "type": "uint32" },
        { "name": "startSequence", "type": "uint64" },
        { "name": "endSequence", "type": "uint64" },
        { "name": "timestamp", "type": "uint64" },
        { "name": "metadata", "type": "bytes" }
      ]}
    ],
    "outputs": [{ "name": "batchId", "type": "uint256" }],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "verifyInclusion",
    "inputs": [
      { "name": "batchId", "type": "uint256" },
      { "name": "eventHash", "type": "bytes32" },
      { "name": "proof", "type": "bytes32[]" },
      { "name": "leafIndex", "type": "uint256" }
    ],
    "outputs": [{ "name": "", "type": "bool" }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getBatch",
    "inputs": [{ "name": "batchId", "type": "uint256" }],
    "outputs": [{ "name": "", "type": "tuple", "components": [
      { "name": "tenantId", "type": "bytes32" },
      { "name": "storeId", "type": "bytes32" },
      { "name": "merkleRoot", "type": "bytes32" },
      { "name": "stateRoot", "type": "bytes32" },
      { "name": "previousStateRoot", "type": "bytes32" },
      { "name": "eventCount", "type": "uint32" },
      { "name": "startSequence", "type": "uint64" },
      { "name": "endSequence", "type": "uint64" },
      { "name": "timestamp", "type": "uint64" },
      { "name": "submitter", "type": "address" },
      { "name": "blockNumber", "type": "uint256" }
    ]}],
    "stateMutability": "view"
  },
  {
    "type": "event",
    "name": "BatchSubmitted",
    "inputs": [
      { "name": "batchId", "type": "uint256", "indexed": true },
      { "name": "tenantId", "type": "bytes32", "indexed": true },
      { "name": "storeId", "type": "bytes32", "indexed": true },
      { "name": "merkleRoot", "type": "bytes32", "indexed": false },
      { "name": "eventCount", "type": "uint32", "indexed": false }
    ]
  }
]
```

### SetPaymaster ABI

```json
[
  {
    "type": "function",
    "name": "registerMerchant",
    "inputs": [],
    "outputs": [],
    "stateMutability": "payable"
  },
  {
    "type": "function",
    "name": "depositFunds",
    "inputs": [],
    "outputs": [],
    "stateMutability": "payable"
  },
  {
    "type": "function",
    "name": "withdrawFunds",
    "inputs": [{ "name": "amount", "type": "uint256" }],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setPolicy",
    "inputs": [{ "name": "policy", "type": "tuple", "components": [
      { "name": "maxGasPerTx", "type": "uint256" },
      { "name": "maxGasPerUser", "type": "uint256" },
      { "name": "maxTotalGas", "type": "uint256" },
      { "name": "allowedTargets", "type": "address[]" },
      { "name": "allowedSelectors", "type": "bytes4[]" },
      { "name": "requireWhitelist", "type": "bool" }
    ]}],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "willSponsor",
    "inputs": [
      { "name": "merchant", "type": "address" },
      { "name": "user", "type": "address" },
      { "name": "target", "type": "address" },
      { "name": "data", "type": "bytes" }
    ],
    "outputs": [{ "name": "", "type": "bool" }],
    "stateMutability": "view"
  },
  {
    "type": "event",
    "name": "GasSponsored",
    "inputs": [
      { "name": "merchant", "type": "address", "indexed": true },
      { "name": "user", "type": "address", "indexed": true },
      { "name": "gasUsed", "type": "uint256", "indexed": false },
      { "name": "gasCost", "type": "uint256", "indexed": false }
    ]
  }
]
```

## Stablecoin Contracts

### ssUSD ABI

```json
[
  {
    "type": "function",
    "name": "balanceOf",
    "inputs": [{ "name": "account", "type": "address" }],
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "sharesOf",
    "inputs": [{ "name": "account", "type": "address" }],
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "totalSupply",
    "inputs": [],
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "totalShares",
    "inputs": [],
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "nav",
    "inputs": [],
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "convertToShares",
    "inputs": [{ "name": "assets", "type": "uint256" }],
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "convertToAssets",
    "inputs": [{ "name": "shares", "type": "uint256" }],
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "transfer",
    "inputs": [
      { "name": "to", "type": "address" },
      { "name": "amount", "type": "uint256" }
    ],
    "outputs": [{ "name": "", "type": "bool" }],
    "stateMutability": "nonpayable"
  },
  {
    "type": "event",
    "name": "Rebase",
    "inputs": [
      { "name": "oldNav", "type": "uint256", "indexed": false },
      { "name": "newNav", "type": "uint256", "indexed": false },
      { "name": "totalSupply", "type": "uint256", "indexed": false }
    ]
  }
]
```

### TreasuryVault ABI

```json
[
  {
    "type": "function",
    "name": "deposit",
    "inputs": [
      { "name": "token", "type": "address" },
      { "name": "amount", "type": "uint256" },
      { "name": "minSsUSD", "type": "uint256" }
    ],
    "outputs": [{ "name": "ssUSDMinted", "type": "uint256" }],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "redeem",
    "inputs": [
      { "name": "token", "type": "address" },
      { "name": "ssUSDAmount", "type": "uint256" },
      { "name": "minTokens", "type": "uint256" }
    ],
    "outputs": [{ "name": "tokensRedeemed", "type": "uint256" }],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "previewDeposit",
    "inputs": [
      { "name": "token", "type": "address" },
      { "name": "amount", "type": "uint256" }
    ],
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "previewRedeem",
    "inputs": [
      { "name": "token", "type": "address" },
      { "name": "ssUSDAmount", "type": "uint256" }
    ],
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "depositsPaused",
    "inputs": [],
    "outputs": [{ "name": "", "type": "bool" }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "redemptionsPaused",
    "inputs": [],
    "outputs": [{ "name": "", "type": "bool" }],
    "stateMutability": "view"
  },
  {
    "type": "event",
    "name": "Deposit",
    "inputs": [
      { "name": "user", "type": "address", "indexed": true },
      { "name": "token", "type": "address", "indexed": true },
      { "name": "amount", "type": "uint256", "indexed": false },
      { "name": "ssUSDMinted", "type": "uint256", "indexed": false }
    ]
  },
  {
    "type": "event",
    "name": "Redemption",
    "inputs": [
      { "name": "user", "type": "address", "indexed": true },
      { "name": "token", "type": "address", "indexed": true },
      { "name": "ssUSDBurned", "type": "uint256", "indexed": false },
      { "name": "amountRedeemed", "type": "uint256", "indexed": false }
    ]
  }
]
```

### NAVOracle ABI

```json
[
  {
    "type": "function",
    "name": "currentNAV",
    "inputs": [],
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "lastUpdateTimestamp",
    "inputs": [],
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "isStale",
    "inputs": [],
    "outputs": [{ "name": "", "type": "bool" }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getLatestReport",
    "inputs": [],
    "outputs": [{ "name": "", "type": "tuple", "components": [
      { "name": "reportId", "type": "uint256" },
      { "name": "nav", "type": "uint256" },
      { "name": "totalAssets", "type": "uint256" },
      { "name": "totalShares", "type": "uint256" },
      { "name": "timestamp", "type": "uint256" },
      { "name": "proofHash", "type": "bytes32" }
    ]}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "updateNAV",
    "inputs": [
      { "name": "report", "type": "tuple", "components": [
        { "name": "reportId", "type": "uint256" },
        { "name": "nav", "type": "uint256" },
        { "name": "totalAssets", "type": "uint256" },
        { "name": "totalShares", "type": "uint256" },
        { "name": "timestamp", "type": "uint256" },
        { "name": "proofHash", "type": "bytes32" }
      ]},
      { "name": "signature", "type": "bytes" }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "event",
    "name": "NAVUpdated",
    "inputs": [
      { "name": "reportId", "type": "uint256", "indexed": true },
      { "name": "nav", "type": "uint256", "indexed": false },
      { "name": "totalAssets", "type": "uint256", "indexed": false },
      { "name": "totalShares", "type": "uint256", "indexed": false },
      { "name": "timestamp", "type": "uint256", "indexed": false }
    ]
  }
]
```

## TypeScript Types

### Type Generation

Generate TypeScript types from ABIs:

```bash
npx typechain --target ethers-v6 --out-dir types 'abis/*.json'
```

### Using Generated Types

```typescript
import { SetRegistry } from "./types/SetRegistry";
import { TreasuryVault } from "./types/TreasuryVault";

// Fully typed contract interactions
const registry: SetRegistry = SetRegistry__factory.connect(address, signer);

const batch = await registry.getBatch(batchId);
// batch is fully typed with all fields

const tx = await registry.submitBatch(tenantId, storeId, {
    merkleRoot,
    stateRoot,
    previousStateRoot,
    eventCount,
    startSequence,
    endSequence,
    timestamp,
    metadata
});
```

## Related

- [Contract Addresses](./addresses.md)
- [Events Reference](./events.md)
- [Error Codes](./error-codes.md)
