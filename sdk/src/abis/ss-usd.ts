export const ssUsdAbi = [
  {
    type: "function",
    name: "name",
    inputs: [],
    outputs: [{ name: "", type: "string" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "symbol",
    inputs: [],
    outputs: [{ name: "", type: "string" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "decimals",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
    stateMutability: "pure"
  },
  {
    type: "function",
    name: "totalSupply",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "balanceOf",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "sharesOf",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "totalShares",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getNavPerShare",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getSharesByAmount",
    inputs: [{ name: "amount", type: "uint256" }],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getAmountByShares",
    inputs: [{ name: "shares", type: "uint256" }],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getTokenStatus",
    inputs: [],
    outputs: [
      { name: "totalSupply_", type: "uint256" },
      { name: "totalShares_", type: "uint256" },
      { name: "navPerShare_", type: "uint256" },
      { name: "isPaused_", type: "bool" },
      { name: "treasuryVault_", type: "address" },
      { name: "navOracle_", type: "address" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getAccountDetails",
    inputs: [{ name: "account", type: "address" }],
    outputs: [
      { name: "balance", type: "uint256" },
      { name: "shares", type: "uint256" },
      { name: "percentOfSupply", type: "uint256" }
    ],
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
    name: "batchSharesOf",
    inputs: [{ name: "accounts", type: "address[]" }],
    outputs: [{ name: "shares", type: "uint256[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "simulateBalanceAtNAV",
    inputs: [
      { name: "account", type: "address" },
      { name: "newNavPerShare", type: "uint256" }
    ],
    outputs: [{ name: "expectedBalance", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getAccruedYield",
    inputs: [
      { name: "account", type: "address" },
      { name: "baselineNAV", type: "uint256" }
    ],
    outputs: [
      { name: "yieldAccrued", type: "uint256" },
      { name: "yieldPercent", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "transfer",
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" }
    ],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "batchTransfer",
    inputs: [
      { name: "recipients", type: "address[]" },
      { name: "amounts", type: "uint256[]" }
    ],
    outputs: [{ name: "success", type: "bool" }],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "batchTransferShares",
    inputs: [
      { name: "recipients", type: "address[]" },
      { name: "sharesAmounts", type: "uint256[]" }
    ],
    outputs: [{ name: "success", type: "bool" }],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "batchGetSharesByAmount",
    inputs: [{ name: "amounts", type: "uint256[]" }],
    outputs: [{ name: "shares", type: "uint256[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "batchGetAmountByShares",
    inputs: [{ name: "sharesArray", type: "uint256[]" }],
    outputs: [{ name: "amounts", type: "uint256[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "paused",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view"
  }
] as const;
