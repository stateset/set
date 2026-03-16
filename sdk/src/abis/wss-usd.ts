export const wssUsdAbi = [
  {
    type: "function",
    name: "getVaultStatus",
    inputs: [],
    outputs: [
      { name: "assets", type: "uint256" },
      { name: "supply", type: "uint256" },
      { name: "sharePrice", type: "uint256" },
      { name: "cap", type: "uint256" },
      { name: "deposited", type: "uint256" },
      { name: "remainingCap", type: "uint256" },
      { name: "isPaused", type: "bool" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getAccountDetails",
    inputs: [{ name: "account", type: "address" }],
    outputs: [
      { name: "wssUSDBalance", type: "uint256" },
      { name: "ssUSDValue", type: "uint256" },
      { name: "percentOfVault", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getAccruedYield",
    inputs: [],
    outputs: [{ name: "yieldBps", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getSharePrice",
    inputs: [],
    outputs: [{ name: "price", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "wrap",
    inputs: [{ name: "ssUSDAmount", type: "uint256" }],
    outputs: [{ name: "wssUSDAmount", type: "uint256" }],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "unwrap",
    inputs: [{ name: "wssUSDAmount", type: "uint256" }],
    outputs: [{ name: "ssUSDAmount", type: "uint256" }],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "maxDeposit",
    inputs: [{ name: "receiver", type: "address" }],
    outputs: [{ name: "maxAssets", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "depositCap",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "paused",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view"
  },
  // New batch operations
  {
    type: "function",
    name: "batchWrap",
    inputs: [
      { name: "recipients", type: "address[]" },
      { name: "amounts", type: "uint256[]" }
    ],
    outputs: [
      { name: "totalSsUSD", type: "uint256" },
      { name: "totalWssUSD", type: "uint256" }
    ],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "batchUnwrap",
    inputs: [{ name: "amounts", type: "uint256[]" }],
    outputs: [
      { name: "totalWssUSD", type: "uint256" },
      { name: "totalSsUSD", type: "uint256" }
    ],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "batchGetSsUSDValues",
    inputs: [{ name: "accounts", type: "address[]" }],
    outputs: [{ name: "values", type: "uint256[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "batchBalanceOf",
    inputs: [{ name: "accounts", type: "address[]" }],
    outputs: [{ name: "balances", type: "uint256[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "previewBatchWrap",
    inputs: [{ name: "amounts", type: "uint256[]" }],
    outputs: [{ name: "shares", type: "uint256[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "previewBatchUnwrap",
    inputs: [{ name: "shareAmounts", type: "uint256[]" }],
    outputs: [{ name: "assets", type: "uint256[]" }],
    stateMutability: "view"
  },
  // Rate limiting
  {
    type: "function",
    name: "getRateLimitStatus",
    inputs: [{ name: "account", type: "address" }],
    outputs: [
      { name: "remainingDaily", type: "uint256" },
      { name: "cooldownRemaining", type: "uint256" },
      { name: "canWrap", type: "bool" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "canAccountWrap",
    inputs: [
      { name: "account", type: "address" },
      { name: "amount", type: "uint256" }
    ],
    outputs: [
      { name: "canWrap", type: "bool" },
      { name: "reason", type: "uint8" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "dailyWrapLimit",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "wrapCooldown",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  // Analytics
  {
    type: "function",
    name: "getSnapshotCount",
    inputs: [],
    outputs: [{ name: "count", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getSharePriceHistoryRange",
    inputs: [
      { name: "startIndex", type: "uint256" },
      { name: "count", type: "uint256" }
    ],
    outputs: [
      { name: "prices", type: "uint256[]" },
      { name: "timestamps", type: "uint256[]" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getLatestSnapshots",
    inputs: [{ name: "count", type: "uint256" }],
    outputs: [
      { name: "prices", type: "uint256[]" },
      { name: "timestamps", type: "uint256[]" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getYieldOverPeriod",
    inputs: [{ name: "periodSeconds", type: "uint256" }],
    outputs: [
      { name: "yieldBps", type: "uint256" },
      { name: "annualizedBps", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getVaultStatistics",
    inputs: [],
    outputs: [
      { name: "assets", type: "uint256" },
      { name: "supply", type: "uint256" },
      { name: "sharePrice", type: "uint256" },
      { name: "yieldBps", type: "uint256" },
      { name: "snapshotCount", type: "uint256" },
      { name: "dailyLimit", type: "uint256" },
      { name: "cooldown", type: "uint256" }
    ],
    stateMutability: "view"
  }
] as const;
