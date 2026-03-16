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
  },
  {
    type: "function",
    name: "getBatchCommitment",
    inputs: [{ name: "_batchId", type: "bytes32" }],
    outputs: [
      {
        name: "commitment",
        type: "tuple",
        components: [
          { name: "eventsRoot", type: "bytes32" },
          { name: "prevStateRoot", type: "bytes32" },
          { name: "newStateRoot", type: "bytes32" },
          { name: "sequenceStart", type: "uint64" },
          { name: "sequenceEnd", type: "uint64" },
          { name: "eventCount", type: "uint32" },
          { name: "timestamp", type: "uint64" },
          { name: "submitter", type: "address" }
        ]
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "batchExists",
    inputs: [{ name: "_batchId", type: "bytes32" }],
    outputs: [{ name: "exists", type: "bool" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getLatestBatchId",
    inputs: [
      { name: "_tenantId", type: "bytes32" },
      { name: "_storeId", type: "bytes32" }
    ],
    outputs: [{ name: "batchId", type: "bytes32" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getRegistryStats",
    inputs: [],
    outputs: [
      { name: "commitmentCount", type: "uint256" },
      { name: "proofCount", type: "uint256" },
      { name: "isPaused", type: "bool" },
      { name: "isStrictMode", type: "bool" }
    ],
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
    name: "hasStarkProof",
    inputs: [{ name: "_batchId", type: "bytes32" }],
    outputs: [{ name: "hasProof", type: "bool" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getBatchCommitments",
    inputs: [{ name: "_batchIds", type: "bytes32[]" }],
    outputs: [{
      name: "commitmentList",
      type: "tuple[]",
      components: [
        { name: "eventsRoot", type: "bytes32" },
        { name: "prevStateRoot", type: "bytes32" },
        { name: "newStateRoot", type: "bytes32" },
        { name: "sequenceStart", type: "uint64" },
        { name: "sequenceEnd", type: "uint64" },
        { name: "eventCount", type: "uint32" },
        { name: "timestamp", type: "uint64" },
        { name: "submitter", type: "address" }
      ]
    }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getBatchProofStatuses",
    inputs: [{ name: "_batchIds", type: "bytes32[]" }],
    outputs: [
      { name: "hasProofs", type: "bool[]" },
      { name: "allCompliant", type: "bool[]" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getBatchLatestStateRoots",
    inputs: [
      { name: "_tenantIds", type: "bytes32[]" },
      { name: "_storeIds", type: "bytes32[]" }
    ],
    outputs: [{ name: "stateRoots", type: "bytes32[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getBatchHeadSequences",
    inputs: [
      { name: "_tenantIds", type: "bytes32[]" },
      { name: "_storeIds", type: "bytes32[]" }
    ],
    outputs: [{ name: "sequences", type: "uint64[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getExtendedRegistryStatus",
    inputs: [],
    outputs: [
      { name: "totalBatches", type: "uint256" },
      { name: "totalProofs", type: "uint256" },
      { name: "sequencerCount", type: "uint256" },
      { name: "isPaused", type: "bool" },
      { name: "isStrictMode", type: "bool" },
      { name: "proofCoverage", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getTenantStoreSummary",
    inputs: [
      { name: "_tenantId", type: "bytes32" },
      { name: "_storeId", type: "bytes32" }
    ],
    outputs: [
      { name: "latestBatchId", type: "bytes32" },
      { name: "currentStateRoot", type: "bytes32" },
      { name: "currentHeadSequence", type: "uint64" },
      { name: "hasLatestProof", type: "bool" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "areSequencersAuthorized",
    inputs: [{ name: "_addresses", type: "address[]" }],
    outputs: [{ name: "authorized", type: "bool[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "authorizedSequencerCount",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  }
] as const;
