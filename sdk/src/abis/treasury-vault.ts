export const treasuryVaultAbi = [
  {
    type: "function",
    name: "getVaultHealth",
    inputs: [],
    outputs: [
      { name: "collateralValue", type: "uint256" },
      { name: "ssUSDSupply", type: "uint256" },
      { name: "collateralizationRatio", type: "uint256" },
      { name: "isDepositsEnabled", type: "bool" },
      { name: "isRedemptionsEnabled", type: "bool" },
      { name: "pendingRedemptionsCount", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getCollateralRatio",
    inputs: [],
    outputs: [{ name: "ratio", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getCollateralBalance",
    inputs: [{ name: "token", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getTotalCollateralValue",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getExcessCollateral",
    inputs: [],
    outputs: [{ name: "excess", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "checkUndercollateralization",
    inputs: [],
    outputs: [
      { name: "isUnder", type: "bool" },
      { name: "shortfall", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getRedemptionRequest",
    inputs: [{ name: "requestId", type: "uint256" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "id", type: "uint256" },
          { name: "requester", type: "address" },
          { name: "ssUSDAmount", type: "uint256" },
          { name: "collateralToken", type: "address" },
          { name: "requestedAt", type: "uint256" },
          { name: "processedAt", type: "uint256" },
          { name: "status", type: "uint8" }
        ]
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getUserRedemptions",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "", type: "uint256[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getUserPendingRedemptionCount",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "count", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getTotalPendingRedemptionValue",
    inputs: [],
    outputs: [{ name: "totalValue", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "pendingRedemptionCount",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "mintFee",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "redeemFee",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "redemptionDelay",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "depositsPaused",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "redemptionsPaused",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view"
  },
  // Batch queries
  {
    type: "function",
    name: "batchGetCollateralBalances",
    inputs: [{ name: "tokens", type: "address[]" }],
    outputs: [{ name: "balances", type: "uint256[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "batchGetRedemptionRequests",
    inputs: [{ name: "requestIds", type: "uint256[]" }],
    outputs: [
      {
        name: "requests",
        type: "tuple[]",
        components: [
          { name: "id", type: "uint256" },
          { name: "requester", type: "address" },
          { name: "ssUSDAmount", type: "uint256" },
          { name: "collateralToken", type: "address" },
          { name: "requestedAt", type: "uint256" },
          { name: "processedAt", type: "uint256" },
          { name: "status", type: "uint8" }
        ]
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getReadyRedemptions",
    inputs: [{ name: "maxCount", type: "uint256" }],
    outputs: [{ name: "readyIds", type: "uint256[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getCollateralBreakdown",
    inputs: [],
    outputs: [
      { name: "tokens", type: "address[]" },
      { name: "balances", type: "uint256[]" },
      { name: "values", type: "uint256[]" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getUserSummary",
    inputs: [{ name: "user", type: "address" }],
    outputs: [
      { name: "ssUSDBalance", type: "uint256" },
      { name: "pendingRedemptions", type: "uint256" },
      { name: "totalPendingValue", type: "uint256" },
      { name: "canDeposit", type: "bool" },
      { name: "canRedeem", type: "bool" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getRedemptionStatus",
    inputs: [{ name: "requestId", type: "uint256" }],
    outputs: [
      { name: "status", type: "uint8" },
      { name: "timeRemaining", type: "uint256" },
      { name: "isReady", type: "bool" },
      { name: "ssUSDValue", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "batchIsOperator",
    inputs: [{ name: "addresses", type: "address[]" }],
    outputs: [{ name: "authorized", type: "bool[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "operators",
    inputs: [{ name: "operator", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view"
  }
] as const;
