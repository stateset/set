import { Contract, JsonRpcProvider, Wallet } from "ethers";

// Re-export errors
export * from "./errors";

// Re-export configuration
export * from "./config";

// Re-export utilities
export * from "./utils";

// Re-export encryption module
export * from "./encryption";

// Re-export stablecoin module
export * as stablecoin from "./stablecoin";

export const setRegistryAbi = [
  {
    type: "function",
    name: "commitBatch",
    inputs: [
      { name: "_batchId", type: "bytes32" },
      { name: "_tenantId", type: "bytes32" },
      { name: "_storeId", type: "bytes32" },
      { name: "_eventsRoot", type: "bytes32" },
      { name: "_prevStateRoot", type: "bytes32" },
      { name: "_newStateRoot", type: "bytes32" },
      { name: "_sequenceStart", type: "uint64" },
      { name: "_sequenceEnd", type: "uint64" },
      { name: "_eventCount", type: "uint32" }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "verifyInclusion",
    inputs: [
      { name: "_batchId", type: "bytes32" },
      { name: "_leaf", type: "bytes32" },
      { name: "_proof", type: "bytes32[]" },
      { name: "_index", type: "uint256" }
    ],
    outputs: [{ name: "valid", type: "bool" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "verifyMultipleInclusions",
    inputs: [
      { name: "_batchId", type: "bytes32" },
      { name: "_leaves", type: "bytes32[]" },
      { name: "_proofs", type: "bytes32[][]" },
      { name: "_indices", type: "uint256[]" }
    ],
    outputs: [{ name: "allValid", type: "bool" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getLatestStateRoot",
    inputs: [
      { name: "_tenantId", type: "bytes32" },
      { name: "_storeId", type: "bytes32" }
    ],
    outputs: [{ name: "stateRoot", type: "bytes32" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getHeadSequence",
    inputs: [
      { name: "_tenantId", type: "bytes32" },
      { name: "_storeId", type: "bytes32" }
    ],
    outputs: [{ name: "sequence", type: "uint64" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "authorizedSequencers",
    inputs: [{ name: "", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view"
  }
] as const;

export const setPaymasterAbi = [
  {
    type: "function",
    name: "sponsorMerchant",
    inputs: [
      { name: "_merchant", type: "address" },
      { name: "_tierId", type: "uint256" }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "executeSponsorship",
    inputs: [
      { name: "_merchant", type: "address" },
      { name: "_amount", type: "uint256" },
      { name: "_operationType", type: "uint8" }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "getMerchantDetails",
    inputs: [{ name: "_merchant", type: "address" }],
    outputs: [
      { name: "active", type: "bool" },
      { name: "tierId", type: "uint256" },
      { name: "spentToday", type: "uint256" },
      { name: "spentThisMonth", type: "uint256" },
      { name: "totalSponsored", type: "uint256" }
    ],
    stateMutability: "view"
  }
] as const;

export function createProvider(rpcUrl: string): JsonRpcProvider {
  return new JsonRpcProvider(rpcUrl);
}

export function createWallet(privateKey: string, rpcUrl: string): Wallet {
  return new Wallet(privateKey, createProvider(rpcUrl));
}

export function getSetRegistry(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, setRegistryAbi, runner);
}

export function getSetPaymaster(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, setPaymasterAbi, runner);
}
