export const thresholdKeyRegistryAbi = [
  {
    type: "function",
    name: "getRegistryStatus",
    inputs: [],
    outputs: [
      { name: "totalKeypers", type: "uint256" },
      { name: "activeCount", type: "uint256" },
      { name: "currentThreshold", type: "uint256" },
      { name: "epoch", type: "uint256" },
      { name: "dkgPhase", type: "uint256" },
      { name: "isPaused", type: "bool" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getKeyperDetails",
    inputs: [{ name: "_keyper", type: "address" }],
    outputs: [
      {
        name: "keyperData",
        type: "tuple",
        components: [
          { name: "addr", type: "address" },
          { name: "publicKey", type: "bytes" },
          { name: "endpoint", type: "string" },
          { name: "registeredAt", type: "uint256" },
          { name: "active", type: "bool" },
          { name: "slashCount", type: "uint256" }
        ]
      },
      { name: "stakedAmount", type: "uint256" },
      { name: "isActive", type: "bool" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getCurrentKeyStatus",
    inputs: [],
    outputs: [
      { name: "valid", type: "bool" },
      { name: "blocksRemaining", type: "uint256" },
      { name: "keyperCount", type: "uint256" },
      { name: "epochThreshold", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getDKGStatus",
    inputs: [],
    outputs: [
      { name: "epoch", type: "uint256" },
      { name: "phase", type: "uint256" },
      { name: "deadline", type: "uint256" },
      { name: "participantCount", type: "uint256" },
      { name: "dealingsCount", type: "uint256" },
      { name: "blocksUntilDeadline", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getCurrentPublicKey",
    inputs: [],
    outputs: [{ name: "pubKey", type: "bytes" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "isKeyperActive",
    inputs: [{ name: "keyper", type: "address" }],
    outputs: [{ name: "active", type: "bool" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getActiveKeypers",
    inputs: [],
    outputs: [{ name: "activeKeypers", type: "address[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getTotalStaked",
    inputs: [],
    outputs: [{ name: "totalStaked", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "paused",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view"
  },
  // Batch query functions
  {
    type: "function",
    name: "batchIsKeyperActive",
    inputs: [{ name: "_keypers", type: "address[]" }],
    outputs: [{ name: "active", type: "bool[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "batchGetStakes",
    inputs: [{ name: "_keypers", type: "address[]" }],
    outputs: [{ name: "stakedAmounts", type: "uint256[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "batchIsRegisteredForDKG",
    inputs: [{ name: "_keypers", type: "address[]" }],
    outputs: [{ name: "registered", type: "bool[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "batchIsEpochKeyValid",
    inputs: [{ name: "_epochs", type: "uint256[]" }],
    outputs: [{ name: "valid", type: "bool[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "batchGetKeyperSummary",
    inputs: [{ name: "_keypers", type: "address[]" }],
    outputs: [
      { name: "active_", type: "bool[]" },
      { name: "stakes_", type: "uint256[]" },
      { name: "slashCounts", type: "uint256[]" },
      { name: "registeredForDKG", type: "bool[]" }
    ],
    stateMutability: "view"
  },
  // Extended monitoring
  {
    type: "function",
    name: "getNetworkHealth",
    inputs: [],
    outputs: [
      { name: "totalKeypers_", type: "uint256" },
      { name: "activeCount_", type: "uint256" },
      { name: "avgStake", type: "uint256" },
      { name: "totalSlashed", type: "uint256" },
      { name: "networkSecure", type: "bool" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getEpochHistory",
    inputs: [
      { name: "_epochStart", type: "uint256" },
      { name: "_epochEnd", type: "uint256" }
    ],
    outputs: [
      { name: "epochs_", type: "uint256[]" },
      { name: "valid", type: "bool[]" },
      { name: "revoked", type: "bool[]" },
      { name: "thresholds_", type: "uint256[]" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getKeyExpirationInfo",
    inputs: [],
    outputs: [
      { name: "blocksRemaining", type: "uint256" },
      { name: "secondsRemaining", type: "uint256" },
      { name: "percentRemaining", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getTopKeypersByStake",
    inputs: [{ name: "_limit", type: "uint256" }],
    outputs: [
      { name: "topKeypers", type: "address[]" },
      { name: "topStakes", type: "uint256[]" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getAllKeypers",
    inputs: [],
    outputs: [{ name: "allKeypers", type: "address[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "isRegisteredForDKG",
    inputs: [{ name: "_keyper", type: "address" }],
    outputs: [{ name: "registered", type: "bool" }],
    stateMutability: "view"
  }
] as const;
