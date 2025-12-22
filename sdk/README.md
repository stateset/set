# Set Chain SDK

A lightweight SDK for interacting with SetRegistry and SetPaymaster using
ethers v6.

## Install

```bash
npm install @setchain/sdk
```

## Usage

```ts
import { createProvider, getSetRegistry } from "@setchain/sdk";

const provider = createProvider("http://localhost:8545");
const registry = getSetRegistry("0xYourSetRegistry", provider);

const stateRoot = await registry.getLatestStateRoot(tenantId, storeId);
```

## Notes
- This SDK exposes minimal ABIs for core flows.
- For advanced usage, import and extend the ABI arrays.
