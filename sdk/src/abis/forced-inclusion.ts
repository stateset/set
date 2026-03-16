export const forcedInclusionAbi = [
  {
    type: "function",
    name: "getSystemStatus",
    inputs: [],
    outputs: [
      { name: "pendingCount", type: "uint256" },
      { name: "totalForced", type: "uint256" },
      { name: "totalIncluded", type: "uint256" },
      { name: "totalExpired", type: "uint256" },
      { name: "bondsLocked", type: "uint256" },
      { name: "isPaused", type: "bool" },
      { name: "circuitBreakerCapacity", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getStats",
    inputs: [],
    outputs: [
      {
        name: "stats_",
        type: "tuple",
        components: [
          { name: "totalForced", type: "uint256" },
          { name: "totalIncluded", type: "uint256" },
          { name: "totalExpired", type: "uint256" },
          { name: "totalBondsLocked", type: "uint256" }
        ]
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getTxDetails",
    inputs: [{ name: "_txId", type: "bytes32" }],
    outputs: [
      { name: "sender", type: "address" },
      { name: "target", type: "address" },
      { name: "bond", type: "uint256" },
      { name: "deadline", type: "uint256" },
      { name: "isResolved", type: "bool" },
      { name: "isExpiredNow", type: "bool" },
      { name: "timeRemaining", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getBatchTxStatuses",
    inputs: [{ name: "_txIds", type: "bytes32[]" }],
    outputs: [
      { name: "resolved", type: "bool[]" },
      { name: "expired", type: "bool[]" }
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
    name: "getUserSummary",
    inputs: [{ name: "_user", type: "address" }],
    outputs: [
      { name: "totalSubmitted", type: "uint256" },
      { name: "pendingCount", type: "uint256" },
      { name: "currentRateUsed", type: "uint256" },
      { name: "canSubmitNow", type: "bool" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "isRateLimited",
    inputs: [{ name: "_user", type: "address" }],
    outputs: [
      { name: "limited", type: "bool" },
      { name: "remaining", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "isPending",
    inputs: [{ name: "_txId", type: "bytes32" }],
    outputs: [{ name: "pending", type: "bool" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "isExpired",
    inputs: [{ name: "_txId", type: "bytes32" }],
    outputs: [{ name: "expired", type: "bool" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getPendingCount",
    inputs: [],
    outputs: [{ name: "pendingCount", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getInclusionRate",
    inputs: [],
    outputs: [{ name: "rate", type: "uint256" }],
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
    name: "MIN_BOND",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "MAX_GAS_LIMIT",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "INCLUSION_DEADLINE",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  }
] as const;
