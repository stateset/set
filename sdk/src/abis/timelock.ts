export const setTimelockAbi = [
  {
    type: "function",
    name: "getTimelockStatus",
    inputs: [],
    outputs: [
      { name: "delay", type: "uint256" },
      { name: "maxDelay", type: "uint256" },
      { name: "isMainnetDelay", type: "bool" },
      { name: "isTestnetDelay", type: "bool" },
      { name: "isDevnetDelay", type: "bool" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getOperationStatus",
    inputs: [{ name: "id", type: "bytes32" }],
    outputs: [
      { name: "isPending", type: "bool" },
      { name: "isReady", type: "bool" },
      { name: "isDone", type: "bool" },
      { name: "timestamp", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getTimeRemaining",
    inputs: [{ name: "id", type: "bytes32" }],
    outputs: [{ name: "remaining", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getRoles",
    inputs: [{ name: "account", type: "address" }],
    outputs: [
      { name: "isProposer", type: "bool" },
      { name: "isExecutor", type: "bool" },
      { name: "isCanceller", type: "bool" },
      { name: "isAdmin", type: "bool" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "computeOperationId",
    inputs: [
      { name: "target", type: "address" },
      { name: "value", type: "uint256" },
      { name: "data", type: "bytes" },
      { name: "predecessor", type: "bytes32" },
      { name: "salt", type: "bytes32" }
    ],
    outputs: [{ name: "id", type: "bytes32" }],
    stateMutability: "pure"
  },
  {
    type: "function",
    name: "getMinDelay",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "canPropose",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "canExecute",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view"
  },
  // Batch query functions
  {
    type: "function",
    name: "batchGetRoles",
    inputs: [{ name: "accounts", type: "address[]" }],
    outputs: [
      { name: "isProposer_", type: "bool[]" },
      { name: "isExecutor_", type: "bool[]" },
      { name: "isCanceller_", type: "bool[]" },
      { name: "isAdmin_", type: "bool[]" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "batchGetOperationStatus",
    inputs: [{ name: "ids", type: "bytes32[]" }],
    outputs: [
      { name: "isPending_", type: "bool[]" },
      { name: "isReady_", type: "bool[]" },
      { name: "isDone_", type: "bool[]" },
      { name: "timestamps_", type: "uint256[]" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "batchGetTimeRemaining",
    inputs: [{ name: "ids", type: "bytes32[]" }],
    outputs: [{ name: "remaining", type: "uint256[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "batchCanPropose",
    inputs: [{ name: "accounts", type: "address[]" }],
    outputs: [{ name: "canPropose_", type: "bool[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "batchCanExecute",
    inputs: [{ name: "accounts", type: "address[]" }],
    outputs: [{ name: "canExecute_", type: "bool[]" }],
    stateMutability: "view"
  },
  // Extended monitoring
  {
    type: "function",
    name: "getExtendedConfig",
    inputs: [],
    outputs: [
      { name: "minDelay_", type: "uint256" },
      { name: "maxDelay_", type: "uint256" },
      { name: "mainnetDelay_", type: "uint256" },
      { name: "testnetDelay_", type: "uint256" },
      { name: "devnetDelay_", type: "uint256" },
      { name: "currentEnvironment_", type: "uint8" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getOperationActionability",
    inputs: [{ name: "id", type: "bytes32" }],
    outputs: [
      { name: "exists", type: "bool" },
      { name: "actionable", type: "bool" },
      { name: "secondsToActionable", type: "uint256" },
      { name: "executed", type: "bool" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "verifyRolesForOperation",
    inputs: [
      { name: "proposer", type: "address" },
      { name: "executor", type: "address" }
    ],
    outputs: [
      { name: "canSchedule", type: "bool" },
      { name: "canRun", type: "bool" },
      { name: "delay", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getExecutionTimeline",
    inputs: [],
    outputs: [
      { name: "executeableAt", type: "uint256" },
      { name: "currentTime", type: "uint256" },
      { name: "delaySeconds", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getRecommendedDelay",
    inputs: [{ name: "environment", type: "uint8" }],
    outputs: [{ name: "recommendedDelay", type: "uint256" }],
    stateMutability: "pure"
  }
] as const;
