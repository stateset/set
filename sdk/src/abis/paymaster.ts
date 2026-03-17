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
  },
  {
    type: "function",
    name: "batchSponsorMerchants",
    inputs: [
      { name: "_merchants", type: "address[]" },
      { name: "_tierIds", type: "uint256[]" }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "batchRevokeMerchants",
    inputs: [{ name: "_merchants", type: "address[]" }],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "batchExecuteSponsorship",
    inputs: [
      { name: "_merchants", type: "address[]" },
      { name: "_amounts", type: "uint256[]" },
      { name: "_operationTypes", type: "uint8[]" }
    ],
    outputs: [
      { name: "succeeded", type: "uint256" },
      { name: "failed", type: "uint256" }
    ],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "batchRefundUnusedGas",
    inputs: [
      { name: "_merchants", type: "address[]" },
      { name: "_refundAmounts", type: "uint256[]" }
    ],
    outputs: [],
    stateMutability: "payable"
  },
  {
    type: "function",
    name: "batchGetMerchantStatus",
    inputs: [{ name: "_merchants", type: "address[]" }],
    outputs: [
      { name: "statuses", type: "bool[]" },
      { name: "tiers_", type: "uint256[]" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "batchCanSponsor",
    inputs: [
      { name: "_merchants", type: "address[]" },
      { name: "_amounts", type: "uint256[]" }
    ],
    outputs: [
      { name: "canSponsor_", type: "bool[]" },
      { name: "reasons", type: "string[]" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "batchGetRemainingDailyAllowance",
    inputs: [{ name: "_merchants", type: "address[]" }],
    outputs: [{ name: "allowances", type: "uint256[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "batchGetMerchantDetails",
    inputs: [{ name: "_merchants", type: "address[]" }],
    outputs: [
      { name: "active", type: "bool[]" },
      { name: "tierIds", type: "uint256[]" },
      { name: "spentToday", type: "uint256[]" },
      { name: "spentThisMonth", type: "uint256[]" },
      { name: "totalSponsored", type: "uint256[]" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "batchUpdateMerchantTier",
    inputs: [
      { name: "_merchants", type: "address[]" },
      { name: "_newTierId", type: "uint256" }
    ],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "getPaymasterStatus",
    inputs: [],
    outputs: [
      { name: "paymasterBalance", type: "uint256" },
      { name: "totalSponsored_", type: "uint256" },
      { name: "tierCount", type: "uint256" },
      { name: "treasuryAddr", type: "address" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getAllTiers",
    inputs: [],
    outputs: [
      { name: "tierIds", type: "uint256[]" },
      { name: "names", type: "string[]" },
      { name: "maxPerTx", type: "uint256[]" },
      { name: "maxPerDay_", type: "uint256[]" },
      { name: "maxPerMonth_", type: "uint256[]" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "canSponsor",
    inputs: [
      { name: "_merchant", type: "address" },
      { name: "_amount", type: "uint256" }
    ],
    outputs: [
      { name: "sponsorable", type: "bool" },
      { name: "reason", type: "string" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getRemainingDailyAllowance",
    inputs: [{ name: "_merchant", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "MAX_BATCH_SIZE",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  }
] as const;
