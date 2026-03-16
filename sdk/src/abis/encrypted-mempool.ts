export const encryptedMempoolAbi = [
  {
    type: "function",
    name: "getMempoolStatus",
    inputs: [],
    outputs: [
      { name: "pendingCount", type: "uint256" },
      { name: "queueCapacity", type: "uint256" },
      { name: "submitted", type: "uint256" },
      { name: "executed", type: "uint256" },
      { name: "failed", type: "uint256" },
      { name: "expired", type: "uint256" },
      { name: "isPaused", type: "bool" },
      { name: "currentMaxQueueSize", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getStats",
    inputs: [],
    outputs: [
      { name: "submitted", type: "uint256" },
      { name: "executed", type: "uint256" },
      { name: "failed", type: "uint256" },
      { name: "expired", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getTxStatus",
    inputs: [{ name: "_txId", type: "bytes32" }],
    outputs: [
      { name: "status", type: "uint8" },
      { name: "statusName", type: "string" },
      { name: "blocksUntilExpiry", type: "uint256" },
      { name: "canExecute", type: "bool" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getBatchTxStatuses",
    inputs: [{ name: "_txIds", type: "bytes32[]" }],
    outputs: [{ name: "statuses", type: "uint8[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "canUserSubmit",
    inputs: [{ name: "_user", type: "address" }],
    outputs: [
      { name: "canSubmit", type: "bool" },
      { name: "remainingSubmissions", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getUserPendingTxs",
    inputs: [{ name: "_user", type: "address" }],
    outputs: [{ name: "txIds", type: "bytes32[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getBatchUserPendingCounts",
    inputs: [{ name: "_users", type: "address[]" }],
    outputs: [{ name: "counts", type: "uint256[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getSuccessRate",
    inputs: [],
    outputs: [{ name: "rate", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getPendingQueueLength",
    inputs: [],
    outputs: [{ name: "length", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getEncryptedTx",
    inputs: [{ name: "_txId", type: "bytes32" }],
    outputs: [
      {
        name: "etx",
        type: "tuple",
        components: [
          { name: "id", type: "bytes32" },
          { name: "sender", type: "address" },
          { name: "encryptedPayload", type: "bytes" },
          { name: "payloadHash", type: "bytes32" },
          { name: "epoch", type: "uint256" },
          { name: "gasLimit", type: "uint256" },
          { name: "maxFeePerGas", type: "uint256" },
          { name: "valueDeposit", type: "uint256" },
          { name: "submittedAt", type: "uint256" },
          { name: "orderPosition", type: "uint256" },
          { name: "status", type: "uint8" }
        ]
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getDecryptedTx",
    inputs: [{ name: "_txId", type: "bytes32" }],
    outputs: [
      {
        name: "dtx",
        type: "tuple",
        components: [
          { name: "encryptedId", type: "bytes32" },
          { name: "to", type: "address" },
          { name: "data", type: "bytes" },
          { name: "value", type: "uint256" },
          { name: "decryptedAt", type: "uint256" },
          { name: "executed", type: "bool" },
          { name: "success", type: "bool" }
        ]
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "sequencer",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "paused",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "MAX_PAYLOAD_SIZE",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "DECRYPTION_TIMEOUT",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  }
] as const;
