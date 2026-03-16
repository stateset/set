export const navOracleAbi = [
  {
    type: "function",
    name: "getCurrentNAVPerShare",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getTotalAssets",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getLastReportDate",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "isNAVFresh",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getHistoryCount",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "authorizedAttestors",
    inputs: [{ name: "attestor", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "maxStalenessSeconds",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "maxNavChangeBps",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  // Status and monitoring
  {
    type: "function",
    name: "getOracleStatus",
    inputs: [],
    outputs: [
      { name: "navPerShare", type: "uint256" },
      { name: "lastUpdate", type: "uint256" },
      { name: "isFresh", type: "bool" },
      { name: "reportDate", type: "uint256" },
      { name: "totalAssets", type: "uint256" },
      { name: "configuredMaxChange", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getOracleHealth",
    inputs: [],
    outputs: [
      { name: "isFresh", type: "bool" },
      { name: "hasHistory", type: "bool" },
      { name: "hasAttestor", type: "bool" },
      { name: "ssUSDLinked", type: "bool" },
      { name: "healthScore", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "secondsSinceLastAttestation",
    inputs: [],
    outputs: [{ name: "seconds_", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "isAttestationOverdue",
    inputs: [],
    outputs: [{ name: "overdue", type: "bool" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getMaxAllowedNavChange",
    inputs: [],
    outputs: [{ name: "maxNav", type: "uint256" }],
    stateMutability: "view"
  },
  // Analytics
  {
    type: "function",
    name: "getNAVStatistics",
    inputs: [],
    outputs: [
      { name: "avgNav", type: "uint256" },
      { name: "minNav", type: "uint256" },
      { name: "maxNav", type: "uint256" },
      { name: "volatility", type: "uint256" },
      { name: "historyCount", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getNAVTrend",
    inputs: [],
    outputs: [
      { name: "currentNav", type: "uint256" },
      { name: "previousNav", type: "uint256" },
      { name: "changeBps", type: "uint256" },
      { name: "isPositive", type: "bool" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getAnnualizedYield",
    inputs: [],
    outputs: [
      { name: "annualizedBps", type: "uint256" },
      { name: "periodDays", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getCumulativeYield",
    inputs: [{ name: "baselineNav", type: "uint256" }],
    outputs: [
      { name: "yieldBps", type: "uint256" },
      { name: "yieldAmount", type: "uint256" }
    ],
    stateMutability: "view"
  },
  // Batch operations
  {
    type: "function",
    name: "batchIsAuthorized",
    inputs: [{ name: "addresses", type: "address[]" }],
    outputs: [{ name: "authorized", type: "bool[]" }],
    stateMutability: "view"
  }
] as const;
