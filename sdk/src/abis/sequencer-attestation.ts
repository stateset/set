export const sequencerAttestationAbi = [
  {
    type: "function",
    name: "getStats",
    inputs: [],
    outputs: [
      {
        name: "stats_",
        type: "tuple",
        components: [
          { name: "totalCommitments", type: "uint256" },
          { name: "totalVerifications", type: "uint256" },
          { name: "failedVerifications", type: "uint256" },
          { name: "lastCommitmentTime", type: "uint64" }
        ]
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "commitments",
    inputs: [{ name: "_blockHash", type: "bytes32" }],
    outputs: [
      { name: "blockHash", type: "bytes32" },
      { name: "txOrderingRoot", type: "bytes32" },
      { name: "blockNumber", type: "uint64" },
      { name: "timestamp", type: "uint64" },
      { name: "txCount", type: "uint32" },
      { name: "sequencer", type: "address" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getCommitmentByBlockNumber",
    inputs: [{ name: "_blockNumber", type: "uint256" }],
    outputs: [
      {
        name: "commitment",
        type: "tuple",
        components: [
          { name: "blockHash", type: "bytes32" },
          { name: "txOrderingRoot", type: "bytes32" },
          { name: "blockNumber", type: "uint64" },
          { name: "timestamp", type: "uint64" },
          { name: "txCount", type: "uint32" },
          { name: "sequencer", type: "address" }
        ]
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "hasCommitment",
    inputs: [{ name: "_blockHash", type: "bytes32" }],
    outputs: [{ name: "exists", type: "bool" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "authorizedSequencers",
    inputs: [{ name: "_sequencer", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "verifyTxPositionView",
    inputs: [
      { name: "_blockHash", type: "bytes32" },
      { name: "_txHash", type: "bytes32" },
      { name: "_position", type: "uint256" },
      { name: "_proof", type: "bytes32[]" }
    ],
    outputs: [{ name: "valid", type: "bool" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "batchVerify",
    inputs: [
      { name: "_blockHash", type: "bytes32" },
      { name: "_txHashes", type: "bytes32[]" },
      { name: "_positions", type: "uint256[]" },
      { name: "_proofs", type: "bytes32[]" },
      { name: "_proofLength", type: "uint256" }
    ],
    outputs: [{ name: "results", type: "bool[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "blockNumberToHash",
    inputs: [{ name: "_blockNumber", type: "uint256" }],
    outputs: [{ name: "", type: "bytes32" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "domainSeparator",
    inputs: [],
    outputs: [{ name: "", type: "bytes32" }],
    stateMutability: "view"
  }
] as const;
