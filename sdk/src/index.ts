import { Contract, JsonRpcProvider, Wallet, TransactionReceipt, Log, Interface } from "ethers";

// Re-export errors
export * from "./errors";

// Re-export configuration
export * from "./config";

// Re-export utilities
export * from "./utils";

// Re-export encryption module
export * from "./encryption";

// Re-export stablecoin module
export * as stablecoin from "./stablecoin";

// =========================================================================
// TypeScript Interfaces for Set Chain Contracts
// =========================================================================

/**
 * Batch commitment structure from SetRegistry
 */
export interface BatchCommitment {
  eventsRoot: string;
  prevStateRoot: string;
  newStateRoot: string;
  sequenceStart: bigint;
  sequenceEnd: bigint;
  eventCount: number;
  timestamp: bigint;
  submitter: string;
}

/**
 * STARK proof commitment structure
 */
export interface StarkProofCommitment {
  proofHash: string;
  policyHash: string;
  policyLimit: bigint;
  allCompliant: boolean;
  proofSize: bigint;
  provingTimeMs: bigint;
  timestamp: bigint;
  submitter: string;
}

/**
 * Registry statistics
 */
export interface RegistryStats {
  commitmentCount: bigint;
  proofCount: bigint;
  isPaused: boolean;
  isStrictMode: boolean;
}

/**
 * Merchant sponsorship details
 */
export interface MerchantDetails {
  active: boolean;
  tierId: bigint;
  spentToday: bigint;
  spentThisMonth: bigint;
  totalSponsored: bigint;
}

/**
 * Threshold key registry status
 */
export interface ThresholdRegistryStatus {
  totalKeypers: bigint;
  activeCount: bigint;
  currentThreshold: bigint;
  epoch: bigint;
  dkgPhase: bigint;
  isPaused: boolean;
}

/**
 * Keyper information
 */
export interface Keyper {
  addr: string;
  publicKey: string;
  endpoint: string;
  registeredAt: bigint;
  active: boolean;
  slashCount: bigint;
}

/**
 * Threshold key for an epoch
 */
export interface ThresholdKey {
  epoch: bigint;
  aggregatedPubKey: string;
  keyCommitment: string;
  threshold: bigint;
  keyperCount: bigint;
  activatedAt: bigint;
  expiresAt: bigint;
  revoked: boolean;
}

/**
 * DKG ceremony status
 */
export interface DKGStatus {
  epoch: bigint;
  phase: bigint;
  deadline: bigint;
  participantCount: bigint;
  dealingsCount: bigint;
  blocksUntilDeadline: bigint;
}

/**
 * Network health metrics
 */
export interface NetworkHealth {
  totalKeypers: bigint;
  activeCount: bigint;
  avgStake: bigint;
  totalSlashed: bigint;
  networkSecure: boolean;
}

/**
 * Key expiration info
 */
export interface KeyExpirationInfo {
  blocksRemaining: bigint;
  secondsRemaining: bigint;
  percentRemaining: bigint;
}

/**
 * Keyper summary
 */
export interface KeyperSummary {
  active: boolean;
  stake: bigint;
  slashCount: bigint;
  registeredForDKG: boolean;
}

/**
 * Epoch history entry
 */
export interface EpochHistoryEntry {
  epoch: bigint;
  valid: boolean;
  revoked: boolean;
  threshold: bigint;
}

/**
 * NAV Oracle status
 */
export interface NAVOracleStatus {
  navPerShare: bigint;
  lastUpdate: bigint;
  isFresh: boolean;
  reportDate: bigint;
  totalAssets: bigint;
  configuredMaxChange: bigint;
}

/**
 * NAV Oracle health
 */
export interface NAVOracleHealth {
  isFresh: boolean;
  hasHistory: boolean;
  hasAttestor: boolean;
  ssUSDLinked: boolean;
  healthScore: bigint;
}

/**
 * NAV statistics
 */
export interface NAVStatistics {
  avgNav: bigint;
  minNav: bigint;
  maxNav: bigint;
  volatility: bigint;
  historyCount: bigint;
}

/**
 * NAV trend data
 */
export interface NAVTrend {
  currentNav: bigint;
  previousNav: bigint;
  changeBps: bigint;
  isPositive: boolean;
}

/**
 * Annualized yield data
 */
export interface AnnualizedYield {
  annualizedBps: bigint;
  periodDays: bigint;
}

/**
 * Cumulative yield data
 */
export interface CumulativeYield {
  yieldBps: bigint;
  yieldAmount: bigint;
}

/**
 * TreasuryVault health status
 */
export interface TreasuryVaultHealth {
  collateralValue: bigint;
  ssUSDSupply: bigint;
  collateralizationRatio: bigint;
  isDepositsEnabled: boolean;
  isRedemptionsEnabled: boolean;
  pendingRedemptionsCount: bigint;
}

/**
 * Collateral breakdown
 */
export interface CollateralBreakdown {
  tokens: string[];
  balances: bigint[];
  values: bigint[];
}

/**
 * User vault summary
 */
export interface UserVaultSummary {
  ssUSDBalance: bigint;
  pendingRedemptions: bigint;
  totalPendingValue: bigint;
  canDeposit: boolean;
  canRedeem: boolean;
}

/**
 * Redemption request status
 */
export interface RedemptionRequestStatus {
  status: number;
  timeRemaining: bigint;
  isReady: boolean;
  ssUSDValue: bigint;
}

/**
 * Redemption request details
 */
export interface RedemptionRequest {
  id: bigint;
  requester: string;
  ssUSDAmount: bigint;
  collateralToken: string;
  requestedAt: bigint;
  processedAt: bigint;
  status: number;
}

/**
 * Timelock operation status
 */
export interface OperationStatus {
  isPending: boolean;
  isReady: boolean;
  isDone: boolean;
  timestamp: bigint;
}

/**
 * wssUSD vault status
 */
export interface WssUSDVaultStatus {
  assets: bigint;
  supply: bigint;
  sharePrice: bigint;
  cap: bigint;
  deposited: bigint;
  remainingCap: bigint;
  isPaused: boolean;
}

/**
 * Account details for wssUSD
 */
export interface WssUSDAccountDetails {
  wssUSDBalance: bigint;
  ssUSDValue: bigint;
  percentOfVault: bigint;
}

/**
 * wssUSD rate limit status
 */
export interface WssUSDRateLimitStatus {
  remainingDaily: bigint;
  cooldownRemaining: bigint;
  canWrap: boolean;
}

/**
 * wssUSD vault statistics
 */
export interface WssUSDVaultStatistics {
  assets: bigint;
  supply: bigint;
  sharePrice: bigint;
  yieldBps: bigint;
  snapshotCount: bigint;
  dailyLimit: bigint;
  cooldown: bigint;
}

/**
 * Share price snapshot
 */
export interface SharePriceSnapshot {
  price: bigint;
  timestamp: bigint;
}

/**
 * Yield over period result
 */
export interface YieldOverPeriod {
  yieldBps: bigint;
  annualizedBps: bigint;
}

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
    stateMutability: "nonpayable"
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

export const thresholdKeyRegistryAbi = [
  {
    type: "function",
    name: "getRegistryStatus",
    inputs: [],
    outputs: [
      { name: "totalKeypers", type: "uint256" },
      { name: "activeCount", type: "uint256" },
      { name: "currentThreshold", type: "uint256" },
      { name: "epoch", type: "uint256" },
      { name: "dkgPhase", type: "uint256" },
      { name: "isPaused", type: "bool" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getKeyperDetails",
    inputs: [{ name: "_keyper", type: "address" }],
    outputs: [
      {
        name: "keyperData",
        type: "tuple",
        components: [
          { name: "addr", type: "address" },
          { name: "publicKey", type: "bytes" },
          { name: "endpoint", type: "string" },
          { name: "registeredAt", type: "uint256" },
          { name: "active", type: "bool" },
          { name: "slashCount", type: "uint256" }
        ]
      },
      { name: "stakedAmount", type: "uint256" },
      { name: "isActive", type: "bool" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getCurrentKeyStatus",
    inputs: [],
    outputs: [
      { name: "valid", type: "bool" },
      { name: "blocksRemaining", type: "uint256" },
      { name: "keyperCount", type: "uint256" },
      { name: "epochThreshold", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getDKGStatus",
    inputs: [],
    outputs: [
      { name: "epoch", type: "uint256" },
      { name: "phase", type: "uint256" },
      { name: "deadline", type: "uint256" },
      { name: "participantCount", type: "uint256" },
      { name: "dealingsCount", type: "uint256" },
      { name: "blocksUntilDeadline", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getCurrentPublicKey",
    inputs: [],
    outputs: [{ name: "pubKey", type: "bytes" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "isKeyperActive",
    inputs: [{ name: "keyper", type: "address" }],
    outputs: [{ name: "active", type: "bool" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getActiveKeypers",
    inputs: [],
    outputs: [{ name: "activeKeypers", type: "address[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getTotalStaked",
    inputs: [],
    outputs: [{ name: "totalStaked", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "paused",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view"
  },
  // Batch query functions
  {
    type: "function",
    name: "batchIsKeyperActive",
    inputs: [{ name: "_keypers", type: "address[]" }],
    outputs: [{ name: "active", type: "bool[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "batchGetStakes",
    inputs: [{ name: "_keypers", type: "address[]" }],
    outputs: [{ name: "stakedAmounts", type: "uint256[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "batchIsRegisteredForDKG",
    inputs: [{ name: "_keypers", type: "address[]" }],
    outputs: [{ name: "registered", type: "bool[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "batchIsEpochKeyValid",
    inputs: [{ name: "_epochs", type: "uint256[]" }],
    outputs: [{ name: "valid", type: "bool[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "batchGetKeyperSummary",
    inputs: [{ name: "_keypers", type: "address[]" }],
    outputs: [
      { name: "active_", type: "bool[]" },
      { name: "stakes_", type: "uint256[]" },
      { name: "slashCounts", type: "uint256[]" },
      { name: "registeredForDKG", type: "bool[]" }
    ],
    stateMutability: "view"
  },
  // Extended monitoring
  {
    type: "function",
    name: "getNetworkHealth",
    inputs: [],
    outputs: [
      { name: "totalKeypers_", type: "uint256" },
      { name: "activeCount_", type: "uint256" },
      { name: "avgStake", type: "uint256" },
      { name: "totalSlashed", type: "uint256" },
      { name: "networkSecure", type: "bool" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getEpochHistory",
    inputs: [
      { name: "_epochStart", type: "uint256" },
      { name: "_epochEnd", type: "uint256" }
    ],
    outputs: [
      { name: "epochs_", type: "uint256[]" },
      { name: "valid", type: "bool[]" },
      { name: "revoked", type: "bool[]" },
      { name: "thresholds_", type: "uint256[]" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getKeyExpirationInfo",
    inputs: [],
    outputs: [
      { name: "blocksRemaining", type: "uint256" },
      { name: "secondsRemaining", type: "uint256" },
      { name: "percentRemaining", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getTopKeypersByStake",
    inputs: [{ name: "_limit", type: "uint256" }],
    outputs: [
      { name: "topKeypers", type: "address[]" },
      { name: "topStakes", type: "uint256[]" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getAllKeypers",
    inputs: [],
    outputs: [{ name: "allKeypers", type: "address[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "isRegisteredForDKG",
    inputs: [{ name: "_keyper", type: "address" }],
    outputs: [{ name: "registered", type: "bool" }],
    stateMutability: "view"
  }
] as const;

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

export function createProvider(rpcUrl: string): JsonRpcProvider {
  return new JsonRpcProvider(rpcUrl);
}

export function createWallet(privateKey: string, rpcUrl: string): Wallet {
  return new Wallet(privateKey, createProvider(rpcUrl));
}

export function getSetRegistry(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, setRegistryAbi, runner);
}

export function getSetPaymaster(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, setPaymasterAbi, runner);
}

export function getThresholdKeyRegistry(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, thresholdKeyRegistryAbi, runner);
}

export function getSetTimelock(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, setTimelockAbi, runner);
}

export function getWssUSD(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, wssUsdAbi, runner);
}

export function getNAVOracle(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, navOracleAbi, runner);
}

export function getTreasuryVault(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, treasuryVaultAbi, runner);
}

export function getEncryptedMempool(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, encryptedMempoolAbi, runner);
}

export function getForcedInclusion(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, forcedInclusionAbi, runner);
}

export function getSequencerAttestation(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, sequencerAttestationAbi, runner);
}

// =========================================================================
// Higher-Level Helper Functions
// =========================================================================

/**
 * Compute a tenant/store key for SetRegistry lookups
 * @param tenantId Tenant identifier (bytes32)
 * @param storeId Store identifier (bytes32)
 * @returns The keccak256 hash of the packed tenant and store IDs
 */
export function computeTenantStoreKey(tenantId: string, storeId: string): string {
  const { keccak256, solidityPacked } = require("ethers");
  return keccak256(solidityPacked(["bytes32", "bytes32"], [tenantId, storeId]));
}

/**
 * Generate a unique batch ID
 * @param tenantId Tenant identifier
 * @param storeId Store identifier
 * @param sequenceStart Start sequence number
 * @param sequenceEnd End sequence number
 * @param timestamp Timestamp in seconds
 * @returns A unique batch ID
 */
export function generateBatchId(
  tenantId: string,
  storeId: string,
  sequenceStart: bigint,
  sequenceEnd: bigint,
  timestamp: bigint
): string {
  const { keccak256, solidityPacked } = require("ethers");
  return keccak256(
    solidityPacked(
      ["bytes32", "bytes32", "uint64", "uint64", "uint64"],
      [tenantId, storeId, sequenceStart, sequenceEnd, timestamp]
    )
  );
}

/**
 * Compute event leaf hash for Merkle verification
 * @param eventType Type of commerce event
 * @param payload Event payload data (hex string)
 * @param metadata Event metadata (hex string)
 * @returns Leaf hash for Merkle tree
 */
export function computeEventLeaf(
  eventType: string,
  payload: string,
  metadata: string
): string {
  const { keccak256, solidityPacked } = require("ethers");
  return keccak256(solidityPacked(["string", "bytes", "bytes"], [eventType, payload, metadata]));
}

/**
 * Verify a Merkle proof against an events root
 * @param leaf The leaf hash to verify
 * @param proof Array of sibling hashes
 * @param index Index of the leaf in the tree
 * @param expectedRoot Expected root hash
 * @returns True if proof is valid
 */
export function verifyMerkleProof(
  leaf: string,
  proof: string[],
  index: number,
  expectedRoot: string
): boolean {
  const { keccak256, solidityPacked } = require("ethers");
  let computedHash = leaf;

  for (let i = 0; i < proof.length; i++) {
    const proofElement = proof[i];
    if (index % 2 === 0) {
      computedHash = keccak256(solidityPacked(["bytes32", "bytes32"], [computedHash, proofElement]));
    } else {
      computedHash = keccak256(solidityPacked(["bytes32", "bytes32"], [proofElement, computedHash]));
    }
    index = Math.floor(index / 2);
  }

  return computedHash.toLowerCase() === expectedRoot.toLowerCase();
}

/**
 * Fetch batch commitment with parsed data
 * @param registry SetRegistry contract instance
 * @param batchId Batch identifier
 * @returns Parsed batch commitment or null if not found
 */
export async function fetchBatchCommitment(
  registry: Contract,
  batchId: string
): Promise<BatchCommitment | null> {
  const commitment = await registry.getBatchCommitment(batchId);
  if (commitment.timestamp === 0n) {
    return null;
  }
  return {
    eventsRoot: commitment.eventsRoot,
    prevStateRoot: commitment.prevStateRoot,
    newStateRoot: commitment.newStateRoot,
    sequenceStart: commitment.sequenceStart,
    sequenceEnd: commitment.sequenceEnd,
    eventCount: Number(commitment.eventCount),
    timestamp: commitment.timestamp,
    submitter: commitment.submitter
  };
}

/**
 * Fetch registry statistics
 * @param registry SetRegistry contract instance
 * @returns Registry statistics
 */
export async function fetchRegistryStats(registry: Contract): Promise<RegistryStats> {
  const [commitmentCount, proofCount, isPaused, isStrictMode] = await registry.getRegistryStats();
  return {
    commitmentCount,
    proofCount,
    isPaused,
    isStrictMode
  };
}

/**
 * Check if the registry is operational (not paused)
 * @param registry SetRegistry contract instance
 * @returns True if registry is accepting new commitments
 */
export async function isRegistryOperational(registry: Contract): Promise<boolean> {
  return !(await registry.paused());
}

/**
 * Extended registry status
 */
export interface ExtendedRegistryStatus {
  totalBatches: bigint;
  totalProofs: bigint;
  sequencerCount: bigint;
  isPaused: boolean;
  isStrictMode: boolean;
  proofCoverage: bigint;
}

/**
 * Tenant/store summary
 */
export interface TenantStoreSummary {
  latestBatchId: string;
  currentStateRoot: string;
  currentHeadSequence: bigint;
  hasLatestProof: boolean;
}

/**
 * Fetch extended registry status with proof coverage
 * @param registry SetRegistry contract instance
 * @returns Extended registry status
 */
export async function fetchExtendedRegistryStatus(
  registry: Contract
): Promise<ExtendedRegistryStatus> {
  const [totalBatches, totalProofs, sequencerCount, isPaused, isStrictMode, proofCoverage] =
    await registry.getExtendedRegistryStatus();
  return {
    totalBatches,
    totalProofs,
    sequencerCount,
    isPaused,
    isStrictMode,
    proofCoverage
  };
}

/**
 * Fetch tenant/store summary
 * @param registry SetRegistry contract instance
 * @param tenantId Tenant identifier
 * @param storeId Store identifier
 * @returns Summary for the tenant/store
 */
export async function fetchTenantStoreSummary(
  registry: Contract,
  tenantId: string,
  storeId: string
): Promise<TenantStoreSummary> {
  const [latestBatchId, currentStateRoot, currentHeadSequence, hasLatestProof] =
    await registry.getTenantStoreSummary(tenantId, storeId);
  return {
    latestBatchId,
    currentStateRoot,
    currentHeadSequence,
    hasLatestProof
  };
}

/**
 * Fetch multiple batch commitments
 * @param registry SetRegistry contract instance
 * @param batchIds Array of batch identifiers
 * @returns Array of batch commitments
 */
export async function fetchBatchCommitments(
  registry: Contract,
  batchIds: string[]
): Promise<BatchCommitment[]> {
  const commitments = await registry.getBatchCommitments(batchIds);
  return commitments.map((c: any) => ({
    eventsRoot: c.eventsRoot,
    prevStateRoot: c.prevStateRoot,
    newStateRoot: c.newStateRoot,
    sequenceStart: c.sequenceStart,
    sequenceEnd: c.sequenceEnd,
    eventCount: Number(c.eventCount),
    timestamp: c.timestamp,
    submitter: c.submitter
  }));
}

/**
 * Fetch proof statuses for multiple batches
 * @param registry SetRegistry contract instance
 * @param batchIds Array of batch identifiers
 * @returns Arrays of proof existence and compliance flags
 */
export async function fetchBatchProofStatuses(
  registry: Contract,
  batchIds: string[]
): Promise<{ hasProofs: boolean[]; allCompliant: boolean[] }> {
  const [hasProofs, allCompliant] = await registry.getBatchProofStatuses(batchIds);
  return { hasProofs, allCompliant };
}

/**
 * Fetch latest state roots for multiple tenant/store pairs
 * @param registry SetRegistry contract instance
 * @param tenantIds Array of tenant identifiers
 * @param storeIds Array of store identifiers
 * @returns Array of state roots
 */
export async function fetchBatchLatestStateRoots(
  registry: Contract,
  tenantIds: string[],
  storeIds: string[]
): Promise<string[]> {
  return await registry.getBatchLatestStateRoots(tenantIds, storeIds);
}

/**
 * Check if multiple addresses are authorized sequencers
 * @param registry SetRegistry contract instance
 * @param addresses Array of addresses to check
 * @returns Array of authorization flags
 */
export async function checkSequencerAuthorization(
  registry: Contract,
  addresses: string[]
): Promise<boolean[]> {
  return await registry.areSequencersAuthorized(addresses);
}

/**
 * Get the count of authorized sequencers
 * @param registry SetRegistry contract instance
 * @returns Number of authorized sequencers
 */
export async function getAuthorizedSequencerCount(registry: Contract): Promise<bigint> {
  return await registry.authorizedSequencerCount();
}

/**
 * Calculate proof coverage percentage
 * @param registry SetRegistry contract instance
 * @returns Proof coverage as a percentage (0-100)
 */
export async function getProofCoveragePercent(registry: Contract): Promise<number> {
  const status = await fetchExtendedRegistryStatus(registry);
  return Number(status.proofCoverage) / 100;
}

/**
 * Check if a batch exists
 * @param registry SetRegistry contract instance
 * @param batchId Batch identifier
 * @returns True if batch exists
 */
export async function checkBatchExists(registry: Contract, batchId: string): Promise<boolean> {
  return await registry.batchExists(batchId);
}

/**
 * Fetch head sequences for multiple tenant/store pairs
 * @param registry SetRegistry contract instance
 * @param tenantIds Array of tenant identifiers
 * @param storeIds Array of store identifiers
 * @returns Array of head sequences
 */
export async function fetchBatchHeadSequences(
  registry: Contract,
  tenantIds: string[],
  storeIds: string[]
): Promise<bigint[]> {
  return await registry.getBatchHeadSequences(tenantIds, storeIds);
}

/**
 * Check if registry is paused
 * @param registry SetRegistry contract instance
 * @returns True if paused
 */
export async function isRegistryPaused(registry: Contract): Promise<boolean> {
  return await registry.paused();
}

/**
 * Check if a batch has a STARK proof
 * @param registry SetRegistry contract instance
 * @param batchId Batch identifier
 * @returns True if batch has proof
 */
export async function checkBatchHasProof(registry: Contract, batchId: string): Promise<boolean> {
  return await registry.hasStarkProof(batchId);
}

// =========================================================================
// ThresholdKeyRegistry Helper Functions
// =========================================================================

/**
 * Fetch threshold key registry status
 * @param registry ThresholdKeyRegistry contract instance
 * @returns Registry status
 */
export async function fetchThresholdRegistryStatus(
  registry: Contract
): Promise<ThresholdRegistryStatus> {
  const [totalKeypers, activeCount, currentThreshold, epoch, dkgPhase, isPaused] =
    await registry.getRegistryStatus();
  return {
    totalKeypers,
    activeCount,
    currentThreshold,
    epoch,
    dkgPhase,
    isPaused
  };
}

/**
 * Fetch DKG ceremony status
 * @param registry ThresholdKeyRegistry contract instance
 * @returns DKG status
 */
export async function fetchDKGStatus(registry: Contract): Promise<DKGStatus> {
  const [epoch, phase, deadline, participantCount, dealingsCount, blocksUntilDeadline] =
    await registry.getDKGStatus();
  return {
    epoch,
    phase,
    deadline,
    participantCount,
    dealingsCount,
    blocksUntilDeadline
  };
}

/**
 * Check if threshold encryption is available
 * @param registry ThresholdKeyRegistry contract instance
 * @returns True if there is a valid current key for encryption
 */
export async function isThresholdEncryptionAvailable(registry: Contract): Promise<boolean> {
  try {
    const [valid] = await registry.getCurrentKeyStatus();
    return valid;
  } catch {
    return false;
  }
}

/**
 * Get total staked value in the key registry
 * @param registry ThresholdKeyRegistry contract instance
 * @returns Total staked in wei
 */
export async function getTotalKeyperStake(registry: Contract): Promise<bigint> {
  return await registry.getTotalStaked();
}

/**
 * Get network health metrics
 * @param registry ThresholdKeyRegistry contract instance
 * @returns Network health metrics
 */
export async function getNetworkHealth(registry: Contract): Promise<NetworkHealth> {
  const [totalKeypers, activeCount, avgStake, totalSlashed, networkSecure] =
    await registry.getNetworkHealth();
  return { totalKeypers, activeCount, avgStake, totalSlashed, networkSecure };
}

/**
 * Get key expiration info for current epoch
 * @param registry ThresholdKeyRegistry contract instance
 * @returns Expiration info
 */
export async function getKeyExpirationInfo(registry: Contract): Promise<KeyExpirationInfo> {
  const [blocksRemaining, secondsRemaining, percentRemaining] =
    await registry.getKeyExpirationInfo();
  return { blocksRemaining, secondsRemaining, percentRemaining };
}

/**
 * Get top keypers by stake
 * @param registry ThresholdKeyRegistry contract instance
 * @param limit Maximum number of keypers to return
 * @returns Arrays of keyper addresses and stakes
 */
export async function getTopKeypersByStake(
  registry: Contract,
  limit: number
): Promise<{ keypers: string[]; stakes: bigint[] }> {
  const [keypers, stakes] = await registry.getTopKeypersByStake(limit);
  return { keypers, stakes };
}

/**
 * Get all keyper addresses
 * @param registry ThresholdKeyRegistry contract instance
 * @returns Array of keyper addresses
 */
export async function getAllKeypers(registry: Contract): Promise<string[]> {
  return await registry.getAllKeypers();
}

/**
 * Batch check keyper active status
 * @param registry ThresholdKeyRegistry contract instance
 * @param keypers Array of keyper addresses
 * @returns Array of active statuses
 */
export async function batchCheckKeyperActive(
  registry: Contract,
  keypers: string[]
): Promise<boolean[]> {
  return await registry.batchIsKeyperActive(keypers);
}

/**
 * Batch get keyper stakes
 * @param registry ThresholdKeyRegistry contract instance
 * @param keypers Array of keyper addresses
 * @returns Array of stake amounts
 */
export async function batchGetKeyperStakes(
  registry: Contract,
  keypers: string[]
): Promise<bigint[]> {
  return await registry.batchGetStakes(keypers);
}

/**
 * Batch check DKG registration
 * @param registry ThresholdKeyRegistry contract instance
 * @param keypers Array of keyper addresses
 * @returns Array of registration statuses
 */
export async function batchCheckDKGRegistration(
  registry: Contract,
  keypers: string[]
): Promise<boolean[]> {
  return await registry.batchIsRegisteredForDKG(keypers);
}

/**
 * Batch check epoch key validity
 * @param registry ThresholdKeyRegistry contract instance
 * @param epochs Array of epoch numbers
 * @returns Array of validity statuses
 */
export async function batchCheckEpochKeyValid(
  registry: Contract,
  epochs: bigint[]
): Promise<boolean[]> {
  return await registry.batchIsEpochKeyValid(epochs);
}

/**
 * Batch get keyper summaries
 * @param registry ThresholdKeyRegistry contract instance
 * @param keypers Array of keyper addresses
 * @returns Array of keyper summaries
 */
export async function batchGetKeyperSummaries(
  registry: Contract,
  keypers: string[]
): Promise<KeyperSummary[]> {
  const [active, stakes, slashCounts, registeredForDKG] =
    await registry.batchGetKeyperSummary(keypers);

  const summaries: KeyperSummary[] = [];
  for (let i = 0; i < keypers.length; i++) {
    summaries.push({
      active: active[i],
      stake: stakes[i],
      slashCount: slashCounts[i],
      registeredForDKG: registeredForDKG[i]
    });
  }
  return summaries;
}

/**
 * Get epoch history
 * @param registry ThresholdKeyRegistry contract instance
 * @param epochStart Starting epoch
 * @param epochEnd Ending epoch
 * @returns Array of epoch history entries
 */
export async function getEpochHistory(
  registry: Contract,
  epochStart: number,
  epochEnd: number
): Promise<EpochHistoryEntry[]> {
  const [epochs, valid, revoked, thresholds] =
    await registry.getEpochHistory(epochStart, epochEnd);

  const entries: EpochHistoryEntry[] = [];
  for (let i = 0; i < epochs.length; i++) {
    entries.push({
      epoch: epochs[i],
      valid: valid[i],
      revoked: revoked[i],
      threshold: thresholds[i]
    });
  }
  return entries;
}

/**
 * Check if keyper is registered for current DKG
 * @param registry ThresholdKeyRegistry contract instance
 * @param keyper Keyper address
 * @returns Whether keyper is registered
 */
export async function isKeyperRegisteredForDKG(
  registry: Contract,
  keyper: string
): Promise<boolean> {
  return await registry.isRegisteredForDKG(keyper);
}

// =========================================================================
// EncryptedMempool Helper Functions
// =========================================================================

/**
 * Encrypted mempool status
 */
export interface MempoolStatus {
  pendingCount: bigint;
  queueCapacity: bigint;
  submitted: bigint;
  executed: bigint;
  failed: bigint;
  expired: bigint;
  isPaused: boolean;
  currentMaxQueueSize: bigint;
}

/**
 * Encrypted transaction status
 */
export interface EncryptedTxStatus {
  status: number;
  statusName: string;
  blocksUntilExpiry: bigint;
  canExecute: boolean;
}

/**
 * Encrypted transaction info
 */
export interface EncryptedTxInfo {
  id: string;
  sender: string;
  payloadHash: string;
  epoch: bigint;
  gasLimit: bigint;
  maxFeePerGas: bigint;
  valueDeposit: bigint;
  submittedAt: bigint;
  orderPosition: bigint;
  status: number;
}

/**
 * Decrypted transaction info
 */
export interface DecryptedTxInfo {
  encryptedId: string;
  to: string;
  data: string;
  value: bigint;
  decryptedAt: bigint;
  executed: boolean;
  success: boolean;
}

/**
 * Fetch encrypted mempool status
 * @param mempool EncryptedMempool contract instance
 * @returns Mempool status
 */
export async function fetchMempoolStatus(mempool: Contract): Promise<MempoolStatus> {
  const [pendingCount, queueCapacity, submitted, executed, failed, expired, isPaused, currentMaxQueueSize] =
    await mempool.getMempoolStatus();
  return { pendingCount, queueCapacity, submitted, executed, failed, expired, isPaused, currentMaxQueueSize };
}

/**
 * Get encrypted mempool statistics
 * @param mempool EncryptedMempool contract instance
 * @returns Statistics
 */
export async function getMempoolStats(mempool: Contract): Promise<{
  submitted: bigint;
  executed: bigint;
  failed: bigint;
  expired: bigint;
}> {
  const [submitted, executed, failed, expired] = await mempool.getStats();
  return { submitted, executed, failed, expired };
}

/**
 * Get encrypted transaction status
 * @param mempool EncryptedMempool contract instance
 * @param txId Transaction ID
 * @returns Transaction status
 */
export async function getEncryptedTxStatus(
  mempool: Contract,
  txId: string
): Promise<EncryptedTxStatus> {
  const [status, statusName, blocksUntilExpiry, canExecute] = await mempool.getTxStatus(txId);
  return { status, statusName, blocksUntilExpiry, canExecute };
}

/**
 * Batch get encrypted transaction statuses
 * @param mempool EncryptedMempool contract instance
 * @param txIds Transaction IDs
 * @returns Array of status values
 */
export async function batchGetEncryptedTxStatuses(
  mempool: Contract,
  txIds: string[]
): Promise<number[]> {
  return await mempool.getBatchTxStatuses(txIds);
}

/**
 * Check if user can submit to encrypted mempool
 * @param mempool EncryptedMempool contract instance
 * @param user User address
 * @returns Submission status
 */
export async function canUserSubmitToMempool(
  mempool: Contract,
  user: string
): Promise<{ canSubmit: boolean; remainingSubmissions: bigint }> {
  const [canSubmit, remainingSubmissions] = await mempool.canUserSubmit(user);
  return { canSubmit, remainingSubmissions };
}

/**
 * Get user's pending encrypted transactions
 * @param mempool EncryptedMempool contract instance
 * @param user User address
 * @returns Array of transaction IDs
 */
export async function getUserPendingEncryptedTxs(
  mempool: Contract,
  user: string
): Promise<string[]> {
  return await mempool.getUserPendingTxs(user);
}

/**
 * Batch get pending transaction counts for users
 * @param mempool EncryptedMempool contract instance
 * @param users User addresses
 * @returns Array of pending counts
 */
export async function batchGetUserPendingCounts(
  mempool: Contract,
  users: string[]
): Promise<bigint[]> {
  return await mempool.getBatchUserPendingCounts(users);
}

/**
 * Get mempool success rate
 * @param mempool EncryptedMempool contract instance
 * @returns Success rate in basis points (10000 = 100%)
 */
export async function getMempoolSuccessRate(mempool: Contract): Promise<bigint> {
  return await mempool.getSuccessRate();
}

/**
 * Get pending queue length
 * @param mempool EncryptedMempool contract instance
 * @returns Queue length
 */
export async function getPendingQueueLength(mempool: Contract): Promise<bigint> {
  return await mempool.getPendingQueueLength();
}

/**
 * Check if mempool is paused
 * @param mempool EncryptedMempool contract instance
 * @returns True if paused
 */
export async function isMempoolPaused(mempool: Contract): Promise<boolean> {
  return await mempool.paused();
}

/**
 * Get mempool health summary
 * @param mempool EncryptedMempool contract instance
 * @returns Health summary
 */
export async function getMempoolHealthSummary(mempool: Contract): Promise<{
  isPaused: boolean;
  pendingCount: bigint;
  queueCapacity: bigint;
  successRate: bigint;
  isHealthy: boolean;
}> {
  const [status, successRate] = await Promise.all([
    fetchMempoolStatus(mempool),
    getMempoolSuccessRate(mempool)
  ]);

  return {
    isPaused: status.isPaused,
    pendingCount: status.pendingCount,
    queueCapacity: status.queueCapacity,
    successRate,
    isHealthy: !status.isPaused && status.queueCapacity > BigInt(0)
  };
}

/**
 * Categorize encrypted transactions by status
 * @param mempool EncryptedMempool contract instance
 * @param txIds Transaction IDs
 * @returns Categorized transactions
 */
export async function categorizeEncryptedTxs(
  mempool: Contract,
  txIds: string[]
): Promise<{
  pending: string[];
  ordered: string[];
  decrypted: string[];
  executed: string[];
  failed: string[];
  expired: string[];
}> {
  const statuses = await batchGetEncryptedTxStatuses(mempool, txIds);
  const result = {
    pending: [] as string[],
    ordered: [] as string[],
    decrypted: [] as string[],
    executed: [] as string[],
    failed: [] as string[],
    expired: [] as string[]
  };

  for (let i = 0; i < txIds.length; i++) {
    const status = statuses[i];
    const txId = txIds[i];
    switch (status) {
      case 0: result.pending.push(txId); break;
      case 1: result.ordered.push(txId); break;
      case 3: result.decrypted.push(txId); break;
      case 4: result.executed.push(txId); break;
      case 5: result.failed.push(txId); break;
      case 6: result.expired.push(txId); break;
    }
  }

  return result;
}

/**
 * Find executable transactions
 * @param mempool EncryptedMempool contract instance
 * @param txIds Transaction IDs to check
 * @returns Transaction IDs that can be executed
 */
export async function findExecutableEncryptedTxs(
  mempool: Contract,
  txIds: string[]
): Promise<string[]> {
  const executable: string[] = [];
  for (const txId of txIds) {
    const status = await getEncryptedTxStatus(mempool, txId);
    if (status.canExecute) {
      executable.push(txId);
    }
  }
  return executable;
}

// =========================================================================
// ForcedInclusion Helper Functions
// =========================================================================

/**
 * Forced inclusion system status
 */
export interface ForcedInclusionStatus {
  pendingCount: bigint;
  totalForced: bigint;
  totalIncluded: bigint;
  totalExpired: bigint;
  bondsLocked: bigint;
  isPaused: boolean;
  circuitBreakerCapacity: bigint;
}

/**
 * Forced transaction details
 */
export interface ForcedTxDetails {
  sender: string;
  target: string;
  bond: bigint;
  deadline: bigint;
  isResolved: boolean;
  isExpiredNow: boolean;
  timeRemaining: bigint;
}

/**
 * User forced inclusion summary
 */
export interface ForcedInclusionUserSummary {
  totalSubmitted: bigint;
  pendingCount: bigint;
  currentRateUsed: bigint;
  canSubmitNow: boolean;
}

/**
 * Fetch forced inclusion system status
 * @param forcedInclusion ForcedInclusion contract instance
 * @returns System status
 */
export async function fetchForcedInclusionStatus(
  forcedInclusion: Contract
): Promise<ForcedInclusionStatus> {
  const [pendingCount, totalForced, totalIncluded, totalExpired, bondsLocked, isPaused, circuitBreakerCapacity] =
    await forcedInclusion.getSystemStatus();
  return { pendingCount, totalForced, totalIncluded, totalExpired, bondsLocked, isPaused, circuitBreakerCapacity };
}

/**
 * Get forced transaction details
 * @param forcedInclusion ForcedInclusion contract instance
 * @param txId Transaction ID
 * @returns Transaction details
 */
export async function getForcedTxDetails(
  forcedInclusion: Contract,
  txId: string
): Promise<ForcedTxDetails> {
  const [sender, target, bond, deadline, isResolved, isExpiredNow, timeRemaining] =
    await forcedInclusion.getTxDetails(txId);
  return { sender, target, bond, deadline, isResolved, isExpiredNow, timeRemaining };
}

/**
 * Get user's pending forced transactions
 * @param forcedInclusion ForcedInclusion contract instance
 * @param user User address
 * @returns Array of transaction IDs
 */
export async function getUserForcedPendingTxs(
  forcedInclusion: Contract,
  user: string
): Promise<string[]> {
  return await forcedInclusion.getUserPendingTxs(user);
}

/**
 * Get user's forced inclusion summary
 * @param forcedInclusion ForcedInclusion contract instance
 * @param user User address
 * @returns User summary
 */
export async function getForcedInclusionUserSummary(
  forcedInclusion: Contract,
  user: string
): Promise<ForcedInclusionUserSummary> {
  const [totalSubmitted, pendingCount, currentRateUsed, canSubmitNow] =
    await forcedInclusion.getUserSummary(user);
  return { totalSubmitted, pendingCount, currentRateUsed, canSubmitNow };
}

/**
 * Check if user is rate limited for forced inclusion
 * @param forcedInclusion ForcedInclusion contract instance
 * @param user User address
 * @returns Rate limit status
 */
export async function isForcedInclusionRateLimited(
  forcedInclusion: Contract,
  user: string
): Promise<{ limited: boolean; remaining: bigint }> {
  const [limited, remaining] = await forcedInclusion.isRateLimited(user);
  return { limited, remaining };
}

/**
 * Check if forced transaction is pending
 * @param forcedInclusion ForcedInclusion contract instance
 * @param txId Transaction ID
 * @returns True if pending
 */
export async function isForcedTxPending(
  forcedInclusion: Contract,
  txId: string
): Promise<boolean> {
  return await forcedInclusion.isPending(txId);
}

/**
 * Check if forced transaction has expired
 * @param forcedInclusion ForcedInclusion contract instance
 * @param txId Transaction ID
 * @returns True if expired
 */
export async function isForcedTxExpired(
  forcedInclusion: Contract,
  txId: string
): Promise<boolean> {
  return await forcedInclusion.isExpired(txId);
}

/**
 * Batch get forced transaction statuses
 * @param forcedInclusion ForcedInclusion contract instance
 * @param txIds Transaction IDs
 * @returns Batch status
 */
export async function batchGetForcedTxStatuses(
  forcedInclusion: Contract,
  txIds: string[]
): Promise<{ resolved: boolean[]; expired: boolean[] }> {
  const [resolved, expired] = await forcedInclusion.getBatchTxStatuses(txIds);
  return { resolved, expired };
}

/**
 * Get forced inclusion rate
 * @param forcedInclusion ForcedInclusion contract instance
 * @returns Inclusion rate in basis points (10000 = 100%)
 */
export async function getForcedInclusionRate(
  forcedInclusion: Contract
): Promise<bigint> {
  return await forcedInclusion.getInclusionRate();
}

/**
 * Get pending forced transaction count
 * @param forcedInclusion ForcedInclusion contract instance
 * @returns Pending count
 */
export async function getForcedPendingCount(
  forcedInclusion: Contract
): Promise<bigint> {
  return await forcedInclusion.getPendingCount();
}

/**
 * Check if forced inclusion is paused
 * @param forcedInclusion ForcedInclusion contract instance
 * @returns True if paused
 */
export async function isForcedInclusionPaused(
  forcedInclusion: Contract
): Promise<boolean> {
  return await forcedInclusion.paused();
}

/**
 * Get forced inclusion health summary
 * @param forcedInclusion ForcedInclusion contract instance
 * @returns Health summary
 */
export async function getForcedInclusionHealthSummary(
  forcedInclusion: Contract
): Promise<{
  isPaused: boolean;
  pendingCount: bigint;
  circuitBreakerCapacity: bigint;
  inclusionRate: bigint;
  bondsLocked: bigint;
  isHealthy: boolean;
}> {
  const [status, inclusionRate] = await Promise.all([
    fetchForcedInclusionStatus(forcedInclusion),
    getForcedInclusionRate(forcedInclusion)
  ]);

  return {
    isPaused: status.isPaused,
    pendingCount: status.pendingCount,
    circuitBreakerCapacity: status.circuitBreakerCapacity,
    inclusionRate,
    bondsLocked: status.bondsLocked,
    isHealthy: !status.isPaused && status.circuitBreakerCapacity > BigInt(0)
  };
}

/**
 * Find expired forced transactions that can be claimed
 * @param forcedInclusion ForcedInclusion contract instance
 * @param txIds Transaction IDs to check
 * @returns Array of expired transaction IDs
 */
export async function findExpiredForcedTxs(
  forcedInclusion: Contract,
  txIds: string[]
): Promise<string[]> {
  const { resolved, expired } = await batchGetForcedTxStatuses(forcedInclusion, txIds);
  const expiredTxs: string[] = [];

  for (let i = 0; i < txIds.length; i++) {
    if (!resolved[i] && expired[i]) {
      expiredTxs.push(txIds[i]);
    }
  }

  return expiredTxs;
}

/**
 * Categorize forced transactions by status
 * @param forcedInclusion ForcedInclusion contract instance
 * @param txIds Transaction IDs to categorize
 * @returns Categorized transactions
 */
export async function categorizeForcedTxs(
  forcedInclusion: Contract,
  txIds: string[]
): Promise<{
  pending: string[];
  resolved: string[];
  expired: string[];
}> {
  const { resolved, expired } = await batchGetForcedTxStatuses(forcedInclusion, txIds);
  const result = {
    pending: [] as string[],
    resolved: [] as string[],
    expired: [] as string[]
  };

  for (let i = 0; i < txIds.length; i++) {
    if (resolved[i]) {
      result.resolved.push(txIds[i]);
    } else if (expired[i]) {
      result.expired.push(txIds[i]);
    } else {
      result.pending.push(txIds[i]);
    }
  }

  return result;
}

// =========================================================================
// SequencerAttestation Helper Functions
// =========================================================================

/**
 * Sequencer attestation statistics
 */
export interface AttestationStats {
  totalCommitments: bigint;
  totalVerifications: bigint;
  failedVerifications: bigint;
  lastCommitmentTime: bigint;
}

/**
 * Ordering commitment info
 */
export interface OrderingCommitmentInfo {
  blockHash: string;
  txOrderingRoot: string;
  blockNumber: bigint;
  timestamp: bigint;
  txCount: number;
  sequencer: string;
}

/**
 * Fetch sequencer attestation statistics
 * @param attestation SequencerAttestation contract instance
 * @returns Statistics
 */
export async function fetchAttestationStats(
  attestation: Contract
): Promise<AttestationStats> {
  const stats = await attestation.getStats();
  return {
    totalCommitments: stats.totalCommitments,
    totalVerifications: stats.totalVerifications,
    failedVerifications: stats.failedVerifications,
    lastCommitmentTime: stats.lastCommitmentTime
  };
}

/**
 * Get ordering commitment by block hash
 * @param attestation SequencerAttestation contract instance
 * @param blockHash Block hash
 * @returns Ordering commitment
 */
export async function getOrderingCommitment(
  attestation: Contract,
  blockHash: string
): Promise<OrderingCommitmentInfo> {
  const [hash, txOrderingRoot, blockNumber, timestamp, txCount, sequencer] =
    await attestation.commitments(blockHash);
  return { blockHash: hash, txOrderingRoot, blockNumber, timestamp, txCount, sequencer };
}

/**
 * Get ordering commitment by block number
 * @param attestation SequencerAttestation contract instance
 * @param blockNumber Block number
 * @returns Ordering commitment
 */
export async function getCommitmentByBlockNumber(
  attestation: Contract,
  blockNumber: number
): Promise<OrderingCommitmentInfo> {
  const commitment = await attestation.getCommitmentByBlockNumber(blockNumber);
  return {
    blockHash: commitment.blockHash,
    txOrderingRoot: commitment.txOrderingRoot,
    blockNumber: commitment.blockNumber,
    timestamp: commitment.timestamp,
    txCount: commitment.txCount,
    sequencer: commitment.sequencer
  };
}

/**
 * Check if commitment exists for block
 * @param attestation SequencerAttestation contract instance
 * @param blockHash Block hash
 * @returns True if commitment exists
 */
export async function hasOrderingCommitment(
  attestation: Contract,
  blockHash: string
): Promise<boolean> {
  return await attestation.hasCommitment(blockHash);
}

/**
 * Check if sequencer is authorized
 * @param attestation SequencerAttestation contract instance
 * @param sequencer Sequencer address
 * @returns True if authorized
 */
export async function isSequencerAuthorized(
  attestation: Contract,
  sequencer: string
): Promise<boolean> {
  return await attestation.authorizedSequencers(sequencer);
}

/**
 * Verify transaction position in ordering
 * @param attestation SequencerAttestation contract instance
 * @param blockHash Block hash
 * @param txHash Transaction hash
 * @param position Expected position
 * @param proof Merkle proof
 * @returns True if valid
 */
export async function verifyTxPosition(
  attestation: Contract,
  blockHash: string,
  txHash: string,
  position: number,
  proof: string[]
): Promise<boolean> {
  return await attestation.verifyTxPositionView(blockHash, txHash, position, proof);
}

/**
 * Batch verify transaction positions
 * @param attestation SequencerAttestation contract instance
 * @param blockHash Block hash
 * @param txHashes Transaction hashes
 * @param positions Expected positions
 * @param proofs Flattened proofs
 * @param proofLength Length of each proof
 * @returns Array of verification results
 */
export async function batchVerifyTxPositions(
  attestation: Contract,
  blockHash: string,
  txHashes: string[],
  positions: number[],
  proofs: string[],
  proofLength: number
): Promise<boolean[]> {
  return await attestation.batchVerify(blockHash, txHashes, positions, proofs, proofLength);
}

/**
 * Get block hash for block number
 * @param attestation SequencerAttestation contract instance
 * @param blockNumber Block number
 * @returns Block hash
 */
export async function getBlockHashForNumber(
  attestation: Contract,
  blockNumber: number
): Promise<string> {
  return await attestation.blockNumberToHash(blockNumber);
}

/**
 * Get attestation verification success rate
 * @param attestation SequencerAttestation contract instance
 * @returns Success rate in basis points (10000 = 100%)
 */
export async function getAttestationSuccessRate(
  attestation: Contract
): Promise<bigint> {
  const stats = await fetchAttestationStats(attestation);
  if (stats.totalVerifications === BigInt(0)) {
    return BigInt(10000); // 100% if no verifications
  }
  const successful = stats.totalVerifications - stats.failedVerifications;
  return (successful * BigInt(10000)) / stats.totalVerifications;
}

/**
 * Get attestation health summary
 * @param attestation SequencerAttestation contract instance
 * @returns Health summary
 */
export async function getAttestationHealthSummary(
  attestation: Contract
): Promise<{
  totalCommitments: bigint;
  successRate: bigint;
  lastCommitmentTime: bigint;
  secondsSinceLastCommitment: bigint;
  isHealthy: boolean;
}> {
  const stats = await fetchAttestationStats(attestation);
  const successRate = await getAttestationSuccessRate(attestation);
  const now = BigInt(Math.floor(Date.now() / 1000));
  const secondsSince = stats.lastCommitmentTime > BigInt(0)
    ? now - stats.lastCommitmentTime
    : BigInt(0);

  return {
    totalCommitments: stats.totalCommitments,
    successRate,
    lastCommitmentTime: stats.lastCommitmentTime,
    secondsSinceLastCommitment: secondsSince,
    isHealthy: stats.totalCommitments > BigInt(0) && successRate >= BigInt(9500) // 95%+
  };
}

/**
 * Check if multiple sequencers are authorized
 * @param attestation SequencerAttestation contract instance
 * @param sequencers Sequencer addresses
 * @returns Array of authorization statuses
 */
export async function batchCheckSequencerAuthorization(
  attestation: Contract,
  sequencers: string[]
): Promise<boolean[]> {
  const results: boolean[] = [];
  for (const seq of sequencers) {
    results.push(await isSequencerAuthorized(attestation, seq));
  }
  return results;
}

// =========================================================================
// SetTimelock Helper Functions
// =========================================================================

/**
 * Fetch timelock operation status
 * @param timelock SetTimelock contract instance
 * @param operationId Operation ID (bytes32 hash)
 * @returns Operation status
 */
export async function fetchOperationStatus(
  timelock: Contract,
  operationId: string
): Promise<OperationStatus> {
  const [isPending, isReady, isDone, timestamp] = await timelock.getOperationStatus(operationId);
  return { isPending, isReady, isDone, timestamp };
}

/**
 * Get time remaining until operation can be executed
 * @param timelock SetTimelock contract instance
 * @param operationId Operation ID
 * @returns Seconds remaining (0 if ready or not scheduled)
 */
export async function getOperationTimeRemaining(
  timelock: Contract,
  operationId: string
): Promise<bigint> {
  return await timelock.getTimeRemaining(operationId);
}

/**
 * Check if an account can propose to timelock
 * @param timelock SetTimelock contract instance
 * @param account Account to check
 * @returns True if account has proposer role
 */
export async function canProposeToTimelock(
  timelock: Contract,
  account: string
): Promise<boolean> {
  return await timelock.canPropose(account);
}

/**
 * Check if an account can execute timelock operations
 * @param timelock SetTimelock contract instance
 * @param account Account to check
 * @returns True if account has executor role
 */
export async function canExecuteTimelock(
  timelock: Contract,
  account: string
): Promise<boolean> {
  return await timelock.canExecute(account);
}

/**
 * Get extended timelock configuration
 * @param timelock SetTimelock contract instance
 * @returns Extended configuration with environment detection
 */
export async function getTimelockExtendedConfig(timelock: Contract): Promise<{
  minDelay: bigint;
  maxDelay: bigint;
  mainnetDelay: bigint;
  testnetDelay: bigint;
  devnetDelay: bigint;
  currentEnvironment: number;
}> {
  const [minDelay, maxDelay, mainnetDelay, testnetDelay, devnetDelay, currentEnvironment] =
    await timelock.getExtendedConfig();
  return { minDelay, maxDelay, mainnetDelay, testnetDelay, devnetDelay, currentEnvironment };
}

/**
 * Get operation actionability status
 * @param timelock SetTimelock contract instance
 * @param operationId Operation ID
 * @returns Actionability status
 */
export async function getOperationActionability(
  timelock: Contract,
  operationId: string
): Promise<{
  exists: boolean;
  actionable: boolean;
  secondsToActionable: bigint;
  executed: boolean;
}> {
  const [exists, actionable, secondsToActionable, executed] =
    await timelock.getOperationActionability(operationId);
  return { exists, actionable, secondsToActionable, executed };
}

/**
 * Verify roles for a proposed operation
 * @param timelock SetTimelock contract instance
 * @param proposer Address that will propose
 * @param executor Address that will execute
 * @returns Role verification result
 */
export async function verifyTimelockRoles(
  timelock: Contract,
  proposer: string,
  executor: string
): Promise<{
  canSchedule: boolean;
  canRun: boolean;
  delay: bigint;
}> {
  const [canSchedule, canRun, delay] = await timelock.verifyRolesForOperation(proposer, executor);
  return { canSchedule, canRun, delay };
}

/**
 * Get execution timeline for an operation if scheduled now
 * @param timelock SetTimelock contract instance
 * @returns Execution timeline
 */
export async function getTimelockExecutionTimeline(timelock: Contract): Promise<{
  executeableAt: bigint;
  currentTime: bigint;
  delaySeconds: bigint;
}> {
  const [executeableAt, currentTime, delaySeconds] = await timelock.getExecutionTimeline();
  return { executeableAt, currentTime, delaySeconds };
}

/**
 * Batch check roles for multiple accounts
 * @param timelock SetTimelock contract instance
 * @param accounts Accounts to check
 * @returns Arrays of role statuses
 */
export async function batchGetTimelockRoles(
  timelock: Contract,
  accounts: string[]
): Promise<{
  isProposer: boolean[];
  isExecutor: boolean[];
  isCanceller: boolean[];
  isAdmin: boolean[];
}> {
  const [isProposer, isExecutor, isCanceller, isAdmin] = await timelock.batchGetRoles(accounts);
  return { isProposer, isExecutor, isCanceller, isAdmin };
}

/**
 * Batch get operation status for multiple operations
 * @param timelock SetTimelock contract instance
 * @param operationIds Operation IDs to check
 * @returns Arrays of operation statuses
 */
export async function batchGetTimelockOperationStatus(
  timelock: Contract,
  operationIds: string[]
): Promise<{
  isPending: boolean[];
  isReady: boolean[];
  isDone: boolean[];
  timestamps: bigint[];
}> {
  const [isPending, isReady, isDone, timestamps] =
    await timelock.batchGetOperationStatus(operationIds);
  return { isPending, isReady, isDone, timestamps };
}

/**
 * Batch get time remaining for multiple operations
 * @param timelock SetTimelock contract instance
 * @param operationIds Operation IDs to check
 * @returns Array of time remaining values
 */
export async function batchGetTimelockTimeRemaining(
  timelock: Contract,
  operationIds: string[]
): Promise<bigint[]> {
  return await timelock.batchGetTimeRemaining(operationIds);
}

/**
 * Batch check if accounts can propose
 * @param timelock SetTimelock contract instance
 * @param accounts Accounts to check
 * @returns Array of proposal capabilities
 */
export async function batchCanProposeToTimelock(
  timelock: Contract,
  accounts: string[]
): Promise<boolean[]> {
  return await timelock.batchCanPropose(accounts);
}

/**
 * Batch check if accounts can execute
 * @param timelock SetTimelock contract instance
 * @param accounts Accounts to check
 * @returns Array of execution capabilities
 */
export async function batchCanExecuteTimelock(
  timelock: Contract,
  accounts: string[]
): Promise<boolean[]> {
  return await timelock.batchCanExecute(accounts);
}

/**
 * Get recommended delay for environment
 * @param timelock SetTimelock contract instance
 * @param environment 0=devnet, 1=testnet, 2=mainnet
 * @returns Recommended delay in seconds
 */
export async function getTimelockRecommendedDelay(
  timelock: Contract,
  environment: number
): Promise<bigint> {
  return await timelock.getRecommendedDelay(environment);
}

/**
 * Timelock health summary
 */
export interface TimelockHealthSummary {
  minDelay: bigint;
  maxDelay: bigint;
  currentEnvironment: string;
  environmentName: string;
  isHealthy: boolean;
}

/**
 * Get timelock health summary
 * @param timelock SetTimelock contract instance
 * @returns Health summary with environment detection
 */
export async function getTimelockHealthSummary(
  timelock: Contract
): Promise<TimelockHealthSummary> {
  const config = await getTimelockExtendedConfig(timelock);
  const envNames = ["devnet", "testnet", "mainnet"];
  const environmentName = envNames[config.currentEnvironment] || "unknown";

  return {
    minDelay: config.minDelay,
    maxDelay: config.maxDelay,
    currentEnvironment: String(config.currentEnvironment),
    environmentName,
    isHealthy: config.minDelay > BigInt(0)
  };
}

/**
 * Pending operations summary
 */
export interface PendingOperationsSummary {
  pending: Array<{ id: string; secondsRemaining: bigint }>;
  ready: string[];
  executed: string[];
}

/**
 * Categorize operations by status
 * @param timelock SetTimelock contract instance
 * @param operationIds Operation IDs to check
 * @returns Categorized operations
 */
export async function categorizeTimelockOperations(
  timelock: Contract,
  operationIds: string[]
): Promise<PendingOperationsSummary> {
  const statuses = await batchGetTimelockOperationStatus(timelock, operationIds);
  const timeRemaining = await batchGetTimelockTimeRemaining(timelock, operationIds);

  const pending: Array<{ id: string; secondsRemaining: bigint }> = [];
  const ready: string[] = [];
  const executed: string[] = [];

  for (let i = 0; i < operationIds.length; i++) {
    const id = operationIds[i];
    if (statuses.isDone[i]) {
      executed.push(id);
    } else if (statuses.isReady[i]) {
      ready.push(id);
    } else if (statuses.isPending[i]) {
      pending.push({ id, secondsRemaining: timeRemaining[i] });
    }
  }

  return { pending, ready, executed };
}

/**
 * Find all ready-to-execute operations
 * @param timelock SetTimelock contract instance
 * @param operationIds Operation IDs to check
 * @returns Operation IDs that are ready to execute
 */
export async function findReadyTimelockOperations(
  timelock: Contract,
  operationIds: string[]
): Promise<string[]> {
  const statuses = await batchGetTimelockOperationStatus(timelock, operationIds);
  const ready: string[] = [];

  for (let i = 0; i < operationIds.length; i++) {
    if (statuses.isReady[i]) {
      ready.push(operationIds[i]);
    }
  }

  return ready;
}

/**
 * Compute operation ID for a single call
 * @param timelock SetTimelock contract instance
 * @param target Target address
 * @param value ETH value
 * @param data Call data
 * @param predecessor Predecessor operation
 * @param salt Unique salt
 * @returns Operation ID (bytes32)
 */
export async function computeTimelockOperationId(
  timelock: Contract,
  target: string,
  value: bigint,
  data: string,
  predecessor: string,
  salt: string
): Promise<string> {
  return await timelock.computeOperationId(target, value, data, predecessor, salt);
}

/**
 * Compute operation ID for a batch call
 * @param timelock SetTimelock contract instance
 * @param targets Target addresses
 * @param values ETH values
 * @param payloads Call data array
 * @param predecessor Predecessor operation
 * @param salt Unique salt
 * @returns Operation ID (bytes32)
 */
export async function computeTimelockBatchOperationId(
  timelock: Contract,
  targets: string[],
  values: bigint[],
  payloads: string[],
  predecessor: string,
  salt: string
): Promise<string> {
  return await timelock.computeBatchOperationId(targets, values, payloads, predecessor, salt);
}

// =========================================================================
// wssUSD Helper Functions
// =========================================================================

/**
 * Fetch wssUSD vault status
 * @param vault wssUSD contract instance
 * @returns Vault status
 */
export async function fetchWssUSDVaultStatus(vault: Contract): Promise<WssUSDVaultStatus> {
  const [assets, supply, sharePrice, cap, deposited, remainingCap, isPaused] =
    await vault.getVaultStatus();
  return {
    assets,
    supply,
    sharePrice,
    cap,
    deposited,
    remainingCap,
    isPaused
  };
}

/**
 * Fetch wssUSD account details
 * @param vault wssUSD contract instance
 * @param account Account to query
 * @returns Account details
 */
export async function fetchWssUSDAccountDetails(
  vault: Contract,
  account: string
): Promise<WssUSDAccountDetails> {
  const [wssUSDBalance, ssUSDValue, percentOfVault] = await vault.getAccountDetails(account);
  return { wssUSDBalance, ssUSDValue, percentOfVault };
}

/**
 * Get current wssUSD share price
 * @param vault wssUSD contract instance
 * @returns Share price (1e18 = 1:1 with ssUSD)
 */
export async function getWssUSDSharePrice(vault: Contract): Promise<bigint> {
  return await vault.getSharePrice();
}

/**
 * Get yield accrued since initial 1:1 ratio
 * @param vault wssUSD contract instance
 * @returns Yield in basis points (100 = 1%)
 */
export async function getWssUSDAccruedYield(vault: Contract): Promise<bigint> {
  return await vault.getAccruedYield();
}

/**
 * Check if wssUSD vault is accepting deposits
 * @param vault wssUSD contract instance
 * @returns True if vault is operational
 */
export async function isWssUSDVaultOperational(vault: Contract): Promise<boolean> {
  return !(await vault.paused());
}

/**
 * Get maximum deposit allowed for an account
 * @param vault wssUSD contract instance
 * @param account Account to check
 * @returns Maximum depositable amount
 */
export async function getMaxWssUSDDeposit(vault: Contract, account: string): Promise<bigint> {
  return await vault.maxDeposit(account);
}

/**
 * Get rate limit status for an account
 * @param vault wssUSD contract instance
 * @param account Account to check
 * @returns Rate limit status
 */
export async function getWssUSDRateLimitStatus(
  vault: Contract,
  account: string
): Promise<WssUSDRateLimitStatus> {
  const [remainingDaily, cooldownRemaining, canWrap] = await vault.getRateLimitStatus(account);
  return { remainingDaily, cooldownRemaining, canWrap };
}

/**
 * Check if account can wrap a specific amount
 * @param vault wssUSD contract instance
 * @param account Account to check
 * @param amount Amount to wrap
 * @returns Whether wrap would succeed and failure reason code
 */
export async function canAccountWrapWssUSD(
  vault: Contract,
  account: string,
  amount: bigint
): Promise<{ canWrap: boolean; reason: number }> {
  const [canWrap, reason] = await vault.canAccountWrap(account, amount);
  return { canWrap, reason };
}

/**
 * Get vault statistics with extended analytics
 * @param vault wssUSD contract instance
 * @returns Extended vault statistics
 */
export async function getWssUSDVaultStatistics(vault: Contract): Promise<WssUSDVaultStatistics> {
  const [assets, supply, sharePrice, yieldBps, snapshotCount, dailyLimit, cooldown] =
    await vault.getVaultStatistics();
  return { assets, supply, sharePrice, yieldBps, snapshotCount, dailyLimit, cooldown };
}

/**
 * Get share price history snapshots
 * @param vault wssUSD contract instance
 * @param startIndex Starting index
 * @param count Number to fetch
 * @returns Array of snapshots
 */
export async function getWssUSDPriceHistory(
  vault: Contract,
  startIndex: number,
  count: number
): Promise<SharePriceSnapshot[]> {
  const [prices, timestamps] = await vault.getSharePriceHistoryRange(startIndex, count);
  const snapshots: SharePriceSnapshot[] = [];
  for (let i = 0; i < prices.length; i++) {
    snapshots.push({ price: prices[i], timestamp: timestamps[i] });
  }
  return snapshots;
}

/**
 * Get latest share price snapshots
 * @param vault wssUSD contract instance
 * @param count Number to fetch
 * @returns Array of snapshots (newest first)
 */
export async function getLatestWssUSDSnapshots(
  vault: Contract,
  count: number
): Promise<SharePriceSnapshot[]> {
  const [prices, timestamps] = await vault.getLatestSnapshots(count);
  const snapshots: SharePriceSnapshot[] = [];
  for (let i = 0; i < prices.length; i++) {
    snapshots.push({ price: prices[i], timestamp: timestamps[i] });
  }
  return snapshots;
}

/**
 * Get yield over a period
 * @param vault wssUSD contract instance
 * @param periodSeconds Period in seconds
 * @returns Yield and annualized yield in basis points
 */
export async function getWssUSDYieldOverPeriod(
  vault: Contract,
  periodSeconds: number
): Promise<YieldOverPeriod> {
  const [yieldBps, annualizedBps] = await vault.getYieldOverPeriod(periodSeconds);
  return { yieldBps, annualizedBps };
}

/**
 * Batch query ssUSD values for multiple accounts
 * @param vault wssUSD contract instance
 * @param accounts Accounts to query
 * @returns Array of ssUSD values
 */
export async function batchGetWssUSDValues(
  vault: Contract,
  accounts: string[]
): Promise<bigint[]> {
  return await vault.batchGetSsUSDValues(accounts);
}

/**
 * Batch query wssUSD balances
 * @param vault wssUSD contract instance
 * @param accounts Accounts to query
 * @returns Array of balances
 */
export async function batchGetWssUSDBalances(
  vault: Contract,
  accounts: string[]
): Promise<bigint[]> {
  return await vault.batchBalanceOf(accounts);
}

/**
 * Preview batch wrap amounts
 * @param vault wssUSD contract instance
 * @param amounts ssUSD amounts to wrap
 * @returns Array of wssUSD shares
 */
export async function previewBatchWssUSDWrap(
  vault: Contract,
  amounts: bigint[]
): Promise<bigint[]> {
  return await vault.previewBatchWrap(amounts);
}

/**
 * Preview batch unwrap amounts
 * @param vault wssUSD contract instance
 * @param shareAmounts wssUSD amounts to unwrap
 * @returns Array of ssUSD amounts
 */
export async function previewBatchWssUSDUnwrap(
  vault: Contract,
  shareAmounts: bigint[]
): Promise<bigint[]> {
  return await vault.previewBatchUnwrap(shareAmounts);
}

/**
 * Get snapshot count for price history
 * @param vault wssUSD contract instance
 * @returns Number of snapshots
 */
export async function getWssUSDSnapshotCount(vault: Contract): Promise<bigint> {
  return await vault.getSnapshotCount();
}

// =========================================================================
// NAVOracle Helper Functions
// =========================================================================

/**
 * Fetch NAVOracle status
 * @param oracle NAVOracle contract instance
 * @returns Oracle status
 */
export async function fetchNAVOracleStatus(oracle: Contract): Promise<NAVOracleStatus> {
  const [navPerShare, lastUpdate, isFresh, reportDate, totalAssets, configuredMaxChange] =
    await oracle.getOracleStatus();
  return { navPerShare, lastUpdate, isFresh, reportDate, totalAssets, configuredMaxChange };
}

/**
 * Fetch NAVOracle health metrics
 * @param oracle NAVOracle contract instance
 * @returns Oracle health data
 */
export async function fetchNAVOracleHealth(oracle: Contract): Promise<NAVOracleHealth> {
  const [isFresh, hasHistory, hasAttestor, ssUSDLinked, healthScore] =
    await oracle.getOracleHealth();
  return { isFresh, hasHistory, hasAttestor, ssUSDLinked, healthScore };
}

/**
 * Get current NAV per share
 * @param oracle NAVOracle contract instance
 * @returns NAV per share (1e18 = $1.00)
 */
export async function getCurrentNAVPerShare(oracle: Contract): Promise<bigint> {
  return await oracle.getCurrentNAVPerShare();
}

/**
 * Check if NAV is fresh (not stale)
 * @param oracle NAVOracle contract instance
 * @returns True if NAV is within staleness period
 */
export async function isNAVFresh(oracle: Contract): Promise<boolean> {
  return await oracle.isNAVFresh();
}

/**
 * Check if attestation is overdue
 * @param oracle NAVOracle contract instance
 * @returns True if NAV needs updating
 */
export async function isAttestationOverdue(oracle: Contract): Promise<boolean> {
  return await oracle.isAttestationOverdue();
}

/**
 * Get seconds since last NAV attestation
 * @param oracle NAVOracle contract instance
 * @returns Seconds elapsed
 */
export async function getSecondsSinceLastAttestation(oracle: Contract): Promise<bigint> {
  return await oracle.secondsSinceLastAttestation();
}

/**
 * Get NAV statistics from history
 * @param oracle NAVOracle contract instance
 * @returns NAV statistics
 */
export async function getNAVStatistics(oracle: Contract): Promise<NAVStatistics> {
  const [avgNav, minNav, maxNav, volatility, historyCount] = await oracle.getNAVStatistics();
  return { avgNav, minNav, maxNav, volatility, historyCount };
}

/**
 * Get NAV trend data
 * @param oracle NAVOracle contract instance
 * @returns NAV trend
 */
export async function getNAVTrend(oracle: Contract): Promise<NAVTrend> {
  const [currentNav, previousNav, changeBps, isPositive] = await oracle.getNAVTrend();
  return { currentNav, previousNav, changeBps, isPositive };
}

/**
 * Get annualized yield
 * @param oracle NAVOracle contract instance
 * @returns Annualized yield data
 */
export async function getNAVAnnualizedYield(oracle: Contract): Promise<AnnualizedYield> {
  const [annualizedBps, periodDays] = await oracle.getAnnualizedYield();
  return { annualizedBps, periodDays };
}

/**
 * Get cumulative yield since baseline
 * @param oracle NAVOracle contract instance
 * @param baselineNav NAV at baseline
 * @returns Cumulative yield
 */
export async function getNAVCumulativeYield(
  oracle: Contract,
  baselineNav: bigint
): Promise<CumulativeYield> {
  const [yieldBps, yieldAmount] = await oracle.getCumulativeYield(baselineNav);
  return { yieldBps, yieldAmount };
}

/**
 * Check if an address is an authorized attestor
 * @param oracle NAVOracle contract instance
 * @param attestor Address to check
 * @returns True if authorized
 */
export async function isAuthorizedAttestor(
  oracle: Contract,
  attestor: string
): Promise<boolean> {
  return await oracle.authorizedAttestors(attestor);
}

/**
 * Batch check attestor authorization
 * @param oracle NAVOracle contract instance
 * @param addresses Addresses to check
 * @returns Array of authorization statuses
 */
export async function batchCheckAttestorAuthorization(
  oracle: Contract,
  addresses: string[]
): Promise<boolean[]> {
  return await oracle.batchIsAuthorized(addresses);
}

/**
 * Get maximum allowed NAV change
 * @param oracle NAVOracle contract instance
 * @returns Maximum NAV per share allowed for next attestation
 */
export async function getMaxAllowedNAVChange(oracle: Contract): Promise<bigint> {
  return await oracle.getMaxAllowedNavChange();
}

/**
 * Get NAV history count
 * @param oracle NAVOracle contract instance
 * @returns Number of historical reports
 */
export async function getNAVHistoryCount(oracle: Contract): Promise<bigint> {
  return await oracle.getHistoryCount();
}

/**
 * Comprehensive NAV summary
 */
export interface NAVComprehensiveSummary {
  currentNav: bigint;
  lastUpdate: bigint;
  isFresh: boolean;
  isOverdue: boolean;
  secondsSinceUpdate: bigint;
  trend: NAVTrend;
  annualizedYield: AnnualizedYield;
  healthScore: bigint;
  statistics: NAVStatistics;
}

/**
 * Get comprehensive NAV summary combining multiple metrics
 * @param oracle NAVOracle contract instance
 * @returns Comprehensive summary
 */
export async function getNAVComprehensiveSummary(
  oracle: Contract
): Promise<NAVComprehensiveSummary> {
  const [status, health, trend, annualizedYield, secondsSinceUpdate, statistics] =
    await Promise.all([
      fetchNAVOracleStatus(oracle),
      fetchNAVOracleHealth(oracle),
      getNAVTrend(oracle),
      getNAVAnnualizedYield(oracle),
      getSecondsSinceLastAttestation(oracle),
      getNAVStatistics(oracle)
    ]);

  return {
    currentNav: status.navPerShare,
    lastUpdate: status.lastUpdate,
    isFresh: status.isFresh,
    isOverdue: !status.isFresh,
    secondsSinceUpdate,
    trend,
    annualizedYield,
    healthScore: health.healthScore,
    statistics
  };
}

/**
 * Calculate projected NAV based on current trend
 * @param oracle NAVOracle contract instance
 * @param daysAhead Number of days to project
 * @returns Projected NAV per share
 */
export async function getProjectedNAV(
  oracle: Contract,
  daysAhead: number
): Promise<bigint> {
  const [status, annualized] = await Promise.all([
    fetchNAVOracleStatus(oracle),
    getNAVAnnualizedYield(oracle)
  ]);

  const currentNav = status.navPerShare;
  const annualizedBps = annualized.annualizedBps;

  // Calculate daily rate from annual rate
  // dailyRate = annualizedBps / 365 / 10000 (bps to decimal)
  // projectedNav = currentNav * (1 + dailyRate * daysAhead)
  const dailyBps = annualizedBps / BigInt(365);
  const projectedNav = currentNav + (currentNav * dailyBps * BigInt(daysAhead)) / BigInt(10000);

  return projectedNav;
}

/**
 * Get time until NAV becomes stale
 * @param oracle NAVOracle contract instance
 * @returns Seconds until stale (0 if already stale)
 */
export async function getTimeUntilNAVStale(oracle: Contract): Promise<bigint> {
  const [secondsSince, stalenessPeriod] = await Promise.all([
    getSecondsSinceLastAttestation(oracle),
    oracle.stalenessPeriod() as Promise<bigint>
  ]);

  if (secondsSince >= stalenessPeriod) {
    return BigInt(0);
  }

  return stalenessPeriod - secondsSince;
}

/**
 * Check if NAV is within acceptable bounds
 * @param oracle NAVOracle contract instance
 * @param minNav Minimum acceptable NAV
 * @param maxNav Maximum acceptable NAV
 * @returns True if NAV is within bounds
 */
export async function isNAVWithinBounds(
  oracle: Contract,
  minNav: bigint,
  maxNav: bigint
): Promise<boolean> {
  const currentNav = await getCurrentNAVPerShare(oracle);
  return currentNav >= minNav && currentNav <= maxNav;
}

// =========================================================================
// TreasuryVault Helper Functions
// =========================================================================

/**
 * Fetch TreasuryVault health status
 * @param vault TreasuryVault contract instance
 * @returns Vault health status
 */
export async function fetchTreasuryVaultHealth(vault: Contract): Promise<TreasuryVaultHealth> {
  const [collateralValue, ssUSDSupply, collateralizationRatio, isDepositsEnabled, isRedemptionsEnabled, pendingRedemptionsCount] =
    await vault.getVaultHealth();
  return { collateralValue, ssUSDSupply, collateralizationRatio, isDepositsEnabled, isRedemptionsEnabled, pendingRedemptionsCount };
}

/**
 * Get collateralization ratio
 * @param vault TreasuryVault contract instance
 * @returns Ratio (1e18 = 100%)
 */
export async function getTreasuryCollateralRatio(vault: Contract): Promise<bigint> {
  return await vault.getCollateralRatio();
}

/**
 * Get collateral balance for a specific token
 * @param vault TreasuryVault contract instance
 * @param token Token address
 * @returns Balance in token decimals
 */
export async function getCollateralBalance(vault: Contract, token: string): Promise<bigint> {
  return await vault.getCollateralBalance(token);
}

/**
 * Get total collateral value
 * @param vault TreasuryVault contract instance
 * @returns Total value in USD (18 decimals)
 */
export async function getTotalCollateralValue(vault: Contract): Promise<bigint> {
  return await vault.getTotalCollateralValue();
}

/**
 * Get excess collateral above 100% backing
 * @param vault TreasuryVault contract instance
 * @returns Excess amount (0 if undercollateralized)
 */
export async function getExcessCollateral(vault: Contract): Promise<bigint> {
  return await vault.getExcessCollateral();
}

/**
 * Check undercollateralization status
 * @param vault TreasuryVault contract instance
 * @returns Undercollateralization status
 */
export async function checkUndercollateralization(
  vault: Contract
): Promise<{ isUnder: boolean; shortfall: bigint }> {
  const [isUnder, shortfall] = await vault.checkUndercollateralization();
  return { isUnder, shortfall };
}

/**
 * Get collateral breakdown
 * @param vault TreasuryVault contract instance
 * @returns Breakdown by token
 */
export async function getCollateralBreakdown(vault: Contract): Promise<CollateralBreakdown> {
  const [tokens, balances, values] = await vault.getCollateralBreakdown();
  return { tokens, balances, values };
}

/**
 * Get user vault summary
 * @param vault TreasuryVault contract instance
 * @param user User address
 * @returns User summary
 */
export async function getTreasuryUserSummary(vault: Contract, user: string): Promise<UserVaultSummary> {
  const [ssUSDBalance, pendingRedemptions, totalPendingValue, canDeposit, canRedeem] =
    await vault.getUserSummary(user);
  return { ssUSDBalance, pendingRedemptions, totalPendingValue, canDeposit, canRedeem };
}

/**
 * Get redemption request status
 * @param vault TreasuryVault contract instance
 * @param requestId Request ID
 * @returns Redemption status with timing
 */
export async function getRedemptionStatus(
  vault: Contract,
  requestId: number
): Promise<RedemptionRequestStatus> {
  const [status, timeRemaining, isReady, ssUSDValue] = await vault.getRedemptionStatus(requestId);
  return { status, timeRemaining, isReady, ssUSDValue };
}

/**
 * Get redemption request details
 * @param vault TreasuryVault contract instance
 * @param requestId Request ID
 * @returns Redemption request details
 */
export async function getRedemptionRequest(vault: Contract, requestId: number): Promise<RedemptionRequest> {
  return await vault.getRedemptionRequest(requestId);
}

/**
 * Get user's redemption request IDs
 * @param vault TreasuryVault contract instance
 * @param user User address
 * @returns Array of request IDs
 */
export async function getUserRedemptions(vault: Contract, user: string): Promise<bigint[]> {
  return await vault.getUserRedemptions(user);
}

/**
 * Get ready redemptions
 * @param vault TreasuryVault contract instance
 * @param maxCount Maximum to return
 * @returns Array of ready request IDs
 */
export async function getReadyRedemptions(vault: Contract, maxCount: number): Promise<bigint[]> {
  return await vault.getReadyRedemptions(maxCount);
}

/**
 * Get pending redemption count
 * @param vault TreasuryVault contract instance
 * @returns Count of pending redemptions
 */
export async function getPendingRedemptionCount(vault: Contract): Promise<bigint> {
  return await vault.pendingRedemptionCount();
}

/**
 * Get total pending redemption value
 * @param vault TreasuryVault contract instance
 * @returns Total value in ssUSD terms
 */
export async function getTotalPendingRedemptionValue(vault: Contract): Promise<bigint> {
  return await vault.getTotalPendingRedemptionValue();
}

/**
 * Get vault fees
 * @param vault TreasuryVault contract instance
 * @returns Mint and redeem fees in basis points
 */
export async function getTreasuryVaultFees(vault: Contract): Promise<{ mintFee: bigint; redeemFee: bigint }> {
  const [mintFee, redeemFee] = await Promise.all([
    vault.mintFee(),
    vault.redeemFee()
  ]);
  return { mintFee, redeemFee };
}

/**
 * Get redemption delay
 * @param vault TreasuryVault contract instance
 * @returns Delay in seconds
 */
export async function getRedemptionDelay(vault: Contract): Promise<bigint> {
  return await vault.redemptionDelay();
}

/**
 * Check if operator
 * @param vault TreasuryVault contract instance
 * @param operator Address to check
 * @returns True if operator
 */
export async function isTreasuryVaultOperator(vault: Contract, operator: string): Promise<boolean> {
  return await vault.operators(operator);
}

/**
 * Batch get collateral balances
 * @param vault TreasuryVault contract instance
 * @param tokens Token addresses
 * @returns Array of balances
 */
export async function batchGetCollateralBalances(vault: Contract, tokens: string[]): Promise<bigint[]> {
  return await vault.batchGetCollateralBalances(tokens);
}

/**
 * Batch get redemption requests
 * @param vault TreasuryVault contract instance
 * @param requestIds Request IDs
 * @returns Array of redemption requests
 */
export async function batchGetRedemptionRequests(
  vault: Contract,
  requestIds: number[]
): Promise<RedemptionRequest[]> {
  return await vault.batchGetRedemptionRequests(requestIds);
}

/**
 * Batch check operator status
 * @param vault TreasuryVault contract instance
 * @param addresses Addresses to check
 * @returns Array of operator statuses
 */
export async function batchCheckTreasuryVaultOperators(
  vault: Contract,
  addresses: string[]
): Promise<boolean[]> {
  return await vault.batchIsOperator(addresses);
}

// =========================================================================
// ssUSD Stablecoin ABIs and Helpers
// =========================================================================

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

/**
 * Get ssUSD contract instance
 * @param address Contract address
 * @param runner Provider or wallet
 */
export function getSsUSD(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, ssUsdAbi, runner);
}

/**
 * ssUSD token status
 */
export interface SsUSDTokenStatus {
  totalSupply: bigint;
  totalShares: bigint;
  navPerShare: bigint;
  isPaused: boolean;
  treasuryVault: string;
  navOracle: string;
}

/**
 * ssUSD account details
 */
export interface SsUSDAccountDetails {
  balance: bigint;
  shares: bigint;
  percentOfSupply: bigint;
}

/**
 * Fetch ssUSD token status
 * @param ssUSD ssUSD contract instance
 * @returns Token status
 */
export async function fetchSsUSDTokenStatus(ssUSD: Contract): Promise<SsUSDTokenStatus> {
  const [totalSupply, totalShares, navPerShare, isPaused, treasuryVault, navOracle] =
    await ssUSD.getTokenStatus();
  return { totalSupply, totalShares, navPerShare, isPaused, treasuryVault, navOracle };
}

/**
 * Fetch ssUSD account details
 * @param ssUSD ssUSD contract instance
 * @param account Account address
 * @returns Account details
 */
export async function fetchSsUSDAccountDetails(
  ssUSD: Contract,
  account: string
): Promise<SsUSDAccountDetails> {
  const [balance, shares, percentOfSupply] = await ssUSD.getAccountDetails(account);
  return { balance, shares, percentOfSupply };
}

/**
 * Get current NAV per share
 * @param ssUSD ssUSD contract instance
 * @returns NAV per share (1e18 = $1.00)
 */
export async function getSsUSDNavPerShare(ssUSD: Contract): Promise<bigint> {
  return await ssUSD.getNavPerShare();
}

/**
 * Calculate yield accrued since baseline
 * @param ssUSD ssUSD contract instance
 * @param account Account address
 * @param baselineNAV NAV at time of deposit
 * @returns Accrued yield and percentage
 */
export async function getSsUSDAccruedYield(
  ssUSD: Contract,
  account: string,
  baselineNAV: bigint
): Promise<{ yieldAccrued: bigint; yieldPercent: bigint }> {
  const [yieldAccrued, yieldPercent] = await ssUSD.getAccruedYield(account, baselineNAV);
  return { yieldAccrued, yieldPercent };
}

/**
 * Simulate balance at a hypothetical NAV
 * @param ssUSD ssUSD contract instance
 * @param account Account address
 * @param newNavPerShare Hypothetical NAV
 * @returns Expected balance at that NAV
 */
export async function simulateSsUSDBalance(
  ssUSD: Contract,
  account: string,
  newNavPerShare: bigint
): Promise<bigint> {
  return await ssUSD.simulateBalanceAtNAV(account, newNavPerShare);
}

/**
 * Get balances for multiple accounts
 * @param ssUSD ssUSD contract instance
 * @param accounts Array of account addresses
 * @returns Array of balances
 */
export async function fetchBatchSsUSDBalances(
  ssUSD: Contract,
  accounts: string[]
): Promise<bigint[]> {
  return await ssUSD.batchBalanceOf(accounts);
}

/**
 * Get shares for multiple accounts
 * @param ssUSD ssUSD contract instance
 * @param accounts Array of account addresses
 * @returns Array of shares
 */
export async function fetchBatchSsUSDShares(
  ssUSD: Contract,
  accounts: string[]
): Promise<bigint[]> {
  return await ssUSD.batchSharesOf(accounts);
}

/**
 * Convert ssUSD amount to shares
 * @param ssUSD ssUSD contract instance
 * @param amount Amount to convert
 * @returns Equivalent shares
 */
export async function ssUSDAmountToShares(
  ssUSD: Contract,
  amount: bigint
): Promise<bigint> {
  return await ssUSD.getSharesByAmount(amount);
}

/**
 * Convert shares to ssUSD amount
 * @param ssUSD ssUSD contract instance
 * @param shares Shares to convert
 * @returns Equivalent amount
 */
export async function ssUSDSharesToAmount(
  ssUSD: Contract,
  shares: bigint
): Promise<bigint> {
  return await ssUSD.getAmountByShares(shares);
}

/**
 * Batch convert amounts to shares
 * @param ssUSD ssUSD contract instance
 * @param amounts Array of amounts
 * @returns Array of equivalent shares
 */
export async function batchSsUSDAmountsToShares(
  ssUSD: Contract,
  amounts: bigint[]
): Promise<bigint[]> {
  return await ssUSD.batchGetSharesByAmount(amounts);
}

/**
 * Batch convert shares to amounts
 * @param ssUSD ssUSD contract instance
 * @param shares Array of shares
 * @returns Array of equivalent amounts
 */
export async function batchSsUSDSharesToAmounts(
  ssUSD: Contract,
  shares: bigint[]
): Promise<bigint[]> {
  return await ssUSD.batchGetAmountByShares(shares);
}

/**
 * Check if ssUSD is paused
 * @param ssUSD ssUSD contract instance
 * @returns True if paused
 */
export async function isSsUSDPaused(ssUSD: Contract): Promise<boolean> {
  return await ssUSD.paused();
}

/**
 * Get total ssUSD supply (rebased)
 * @param ssUSD ssUSD contract instance
 * @returns Total supply
 */
export async function getSsUSDTotalSupply(ssUSD: Contract): Promise<bigint> {
  return await ssUSD.totalSupply();
}

/**
 * Get total ssUSD shares
 * @param ssUSD ssUSD contract instance
 * @returns Total shares
 */
export async function getSsUSDTotalShares(ssUSD: Contract): Promise<bigint> {
  return await ssUSD.totalShares();
}

// =========================================================================
// SetPaymaster Helper Functions
// =========================================================================

/**
 * Paymaster status information
 */
export interface PaymasterStatus {
  balance: bigint;
  totalSponsored: bigint;
  tierCount: bigint;
  treasury: string;
}

/**
 * Sponsorship tier information
 */
export interface SponsorshipTier {
  tierId: bigint;
  name: string;
  maxPerTx: bigint;
  maxPerDay: bigint;
  maxPerMonth: bigint;
}

/**
 * Batch merchant status
 */
export interface BatchMerchantStatus {
  merchants: string[];
  statuses: boolean[];
  tiers: bigint[];
}

/**
 * Batch sponsorship result
 */
export interface BatchSponsorshipResult {
  succeeded: bigint;
  failed: bigint;
}

/**
 * Fetch paymaster status
 * @param paymaster SetPaymaster contract instance
 * @returns Paymaster status
 */
export async function fetchPaymasterStatus(paymaster: Contract): Promise<PaymasterStatus> {
  const [balance, totalSponsored, tierCount, treasury] = await paymaster.getPaymasterStatus();
  return { balance, totalSponsored, tierCount, treasury };
}

/**
 * Fetch all active sponsorship tiers
 * @param paymaster SetPaymaster contract instance
 * @returns Array of sponsorship tiers
 */
export async function fetchAllTiers(paymaster: Contract): Promise<SponsorshipTier[]> {
  const [tierIds, names, maxPerTx, maxPerDay, maxPerMonth] = await paymaster.getAllTiers();
  const tiers: SponsorshipTier[] = [];
  for (let i = 0; i < tierIds.length; i++) {
    tiers.push({
      tierId: tierIds[i],
      name: names[i],
      maxPerTx: maxPerTx[i],
      maxPerDay: maxPerDay[i],
      maxPerMonth: maxPerMonth[i]
    });
  }
  return tiers;
}

/**
 * Fetch merchant details
 * @param paymaster SetPaymaster contract instance
 * @param merchant Merchant address
 * @returns Merchant sponsorship details
 */
export async function fetchMerchantDetails(
  paymaster: Contract,
  merchant: string
): Promise<MerchantDetails> {
  const [active, tierId, spentToday, spentThisMonth, totalSponsored] =
    await paymaster.getMerchantDetails(merchant);
  return { active, tierId, spentToday, spentThisMonth, totalSponsored };
}

/**
 * Check if merchant can be sponsored for an amount
 * @param paymaster SetPaymaster contract instance
 * @param merchant Merchant address
 * @param amount Amount to sponsor
 * @returns Whether sponsorable and reason if not
 */
export async function checkCanSponsor(
  paymaster: Contract,
  merchant: string,
  amount: bigint
): Promise<{ canSponsor: boolean; reason: string }> {
  const [canSponsor, reason] = await paymaster.canSponsor(merchant, amount);
  return { canSponsor, reason };
}

/**
 * Get remaining daily allowance for merchant
 * @param paymaster SetPaymaster contract instance
 * @param merchant Merchant address
 * @returns Remaining daily allowance
 */
export async function getRemainingDailyAllowance(
  paymaster: Contract,
  merchant: string
): Promise<bigint> {
  return await paymaster.getRemainingDailyAllowance(merchant);
}

/**
 * Fetch batch merchant status
 * @param paymaster SetPaymaster contract instance
 * @param merchants Array of merchant addresses
 * @returns Batch merchant status
 */
export async function fetchBatchMerchantStatus(
  paymaster: Contract,
  merchants: string[]
): Promise<BatchMerchantStatus> {
  const [statuses, tiers] = await paymaster.batchGetMerchantStatus(merchants);
  return { merchants, statuses, tiers };
}

/**
 * Check if batch of merchants can be sponsored
 * @param paymaster SetPaymaster contract instance
 * @param merchants Array of merchant addresses
 * @param amounts Array of amounts
 * @returns Array of sponsorability results
 */
export async function batchCheckCanSponsor(
  paymaster: Contract,
  merchants: string[],
  amounts: bigint[]
): Promise<{ canSponsor: boolean[]; reasons: string[] }> {
  const [canSponsor, reasons] = await paymaster.batchCanSponsor(merchants, amounts);
  return { canSponsor, reasons };
}

/**
 * Fetch batch remaining daily allowances
 * @param paymaster SetPaymaster contract instance
 * @param merchants Array of merchant addresses
 * @returns Array of remaining allowances
 */
export async function fetchBatchRemainingAllowances(
  paymaster: Contract,
  merchants: string[]
): Promise<bigint[]> {
  return await paymaster.batchGetRemainingDailyAllowance(merchants);
}

/**
 * Get maximum batch size allowed by paymaster
 * @param paymaster SetPaymaster contract instance
 * @returns Maximum batch size
 */
export async function getMaxBatchSize(paymaster: Contract): Promise<bigint> {
  return await paymaster.MAX_BATCH_SIZE();
}

/**
 * Check if paymaster has sufficient balance for sponsorships
 * @param paymaster SetPaymaster contract instance
 * @param requiredAmount Total amount needed
 * @returns True if sufficient balance
 */
export async function hasSufficientBalance(
  paymaster: Contract,
  requiredAmount: bigint
): Promise<boolean> {
  const status = await fetchPaymasterStatus(paymaster);
  return status.balance >= requiredAmount;
}

/**
 * Fetch batch merchant details
 * @param paymaster SetPaymaster contract instance
 * @param merchants Array of merchant addresses
 * @returns Array of merchant details
 */
export async function fetchBatchMerchantDetails(
  paymaster: Contract,
  merchants: string[]
): Promise<MerchantDetails[]> {
  const [actives, tierIds, spentTodays, spentThisMonths, totalSponsoreds] =
    await paymaster.batchGetMerchantDetails(merchants);
  const details: MerchantDetails[] = [];
  for (let i = 0; i < merchants.length; i++) {
    details.push({
      active: actives[i],
      tierId: tierIds[i],
      spentToday: spentTodays[i],
      spentThisMonth: spentThisMonths[i],
      totalSponsored: totalSponsoreds[i]
    });
  }
  return details;
}

/**
 * Aggregate sponsorship statistics for merchants
 * @param paymaster SetPaymaster contract instance
 * @param merchants Array of merchant addresses
 * @returns Aggregated statistics
 */
export async function aggregateMerchantStats(
  paymaster: Contract,
  merchants: string[]
): Promise<{
  totalMerchants: number;
  activeMerchants: number;
  totalSpent: bigint;
  avgSpentPerMerchant: bigint;
}> {
  const details = await fetchBatchMerchantDetails(paymaster, merchants);
  let activeMerchants = 0;
  let totalSpent = BigInt(0);

  for (const detail of details) {
    if (detail.active) activeMerchants++;
    totalSpent += detail.totalSponsored;
  }

  return {
    totalMerchants: merchants.length,
    activeMerchants,
    totalSpent,
    avgSpentPerMerchant: merchants.length > 0 ? totalSpent / BigInt(merchants.length) : BigInt(0)
  };
}

/**
 * Calculate total sponsorship capacity for a list of merchants
 * @param paymaster SetPaymaster contract instance
 * @param merchants Array of merchant addresses
 * @returns Total remaining daily allowance across all merchants
 */
export async function getTotalRemainingCapacity(
  paymaster: Contract,
  merchants: string[]
): Promise<bigint> {
  const allowances = await fetchBatchRemainingAllowances(paymaster, merchants);
  return allowances.reduce((sum, a) => sum + a, BigInt(0));
}

/**
 * Find merchants that can be sponsored for given amounts
 * @param paymaster SetPaymaster contract instance
 * @param merchants Array of merchant addresses
 * @param amounts Array of amounts to check
 * @returns Object with sponsorable merchants and their amounts
 */
export async function findSponsorableMerchants(
  paymaster: Contract,
  merchants: string[],
  amounts: bigint[]
): Promise<{
  sponsorable: Array<{ merchant: string; amount: bigint }>;
  nonSponsorable: Array<{ merchant: string; amount: bigint; reason: string }>;
}> {
  const { canSponsor, reasons } = await batchCheckCanSponsor(paymaster, merchants, amounts);
  const sponsorable: Array<{ merchant: string; amount: bigint }> = [];
  const nonSponsorable: Array<{ merchant: string; amount: bigint; reason: string }> = [];

  for (let i = 0; i < merchants.length; i++) {
    if (canSponsor[i]) {
      sponsorable.push({ merchant: merchants[i], amount: amounts[i] });
    } else {
      nonSponsorable.push({ merchant: merchants[i], amount: amounts[i], reason: reasons[i] });
    }
  }

  return { sponsorable, nonSponsorable };
}

/**
 * Get paymaster health summary
 * @param paymaster SetPaymaster contract instance
 * @returns Comprehensive health summary
 */
export async function getPaymasterHealthSummary(
  paymaster: Contract
): Promise<{
  balance: bigint;
  totalSponsored: bigint;
  tierCount: bigint;
  treasury: string;
  tiers: SponsorshipTier[];
  isHealthy: boolean;
}> {
  const [status, tiers] = await Promise.all([
    fetchPaymasterStatus(paymaster),
    fetchAllTiers(paymaster)
  ]);

  return {
    ...status,
    tiers,
    isHealthy: status.balance > BigInt(0) && status.tierCount > BigInt(0)
  };
}

/**
 * Find tier by ID
 * @param paymaster SetPaymaster contract instance
 * @param tierId Tier ID to find
 * @returns Tier information or null if not found
 */
export async function findTierById(
  paymaster: Contract,
  tierId: bigint
): Promise<SponsorshipTier | null> {
  const tiers = await fetchAllTiers(paymaster);
  return tiers.find(t => t.tierId === tierId) || null;
}

/**
 * Get tier limits for a merchant
 * @param paymaster SetPaymaster contract instance
 * @param merchant Merchant address
 * @returns Tier limits for the merchant
 */
export async function getMerchantTierLimits(
  paymaster: Contract,
  merchant: string
): Promise<{
  maxPerTx: bigint;
  maxPerDay: bigint;
  maxPerMonth: bigint;
  tierName: string;
} | null> {
  const details = await fetchMerchantDetails(paymaster, merchant);
  if (!details.active) return null;

  const tier = await findTierById(paymaster, details.tierId);
  if (!tier) return null;

  return {
    maxPerTx: tier.maxPerTx,
    maxPerDay: tier.maxPerDay,
    maxPerMonth: tier.maxPerMonth,
    tierName: tier.name
  };
}

// =========================================================================
// System Health Check
// =========================================================================

/**
 * Comprehensive system health status
 */
export interface SystemHealthStatus {
  timestamp: number;
  overallHealthy: boolean;
  components: {
    registry?: { healthy: boolean; stats?: RegistryStats };
    paymaster?: { healthy: boolean; balance?: bigint; tierCount?: bigint };
    treasuryVault?: { healthy: boolean; collateralizationRatio?: bigint };
    navOracle?: { healthy: boolean; isFresh?: boolean; healthScore?: bigint };
    mempool?: { healthy: boolean; pendingCount?: bigint; successRate?: bigint };
    forcedInclusion?: { healthy: boolean; inclusionRate?: bigint; pendingCount?: bigint };
    attestation?: { healthy: boolean; successRate?: bigint; totalCommitments?: bigint };
    timelock?: { healthy: boolean; minDelay?: bigint };
    thresholdRegistry?: { healthy: boolean; activeKeypers?: bigint; threshold?: bigint };
  };
  errors: string[];
}

/**
 * Configuration for system health check
 */
export interface SystemHealthConfig {
  registry?: Contract;
  paymaster?: Contract;
  treasuryVault?: Contract;
  navOracle?: Contract;
  mempool?: Contract;
  forcedInclusion?: Contract;
  attestation?: Contract;
  timelock?: Contract;
  thresholdRegistry?: Contract;
}

/**
 * Perform comprehensive system health check across all contracts
 * @param config Configuration with contract instances to check
 * @returns Comprehensive health status
 */
export async function performSystemHealthCheck(
  config: SystemHealthConfig
): Promise<SystemHealthStatus> {
  const result: SystemHealthStatus = {
    timestamp: Date.now(),
    overallHealthy: true,
    components: {},
    errors: []
  };

  const checks: Promise<void>[] = [];

  // Registry health
  if (config.registry) {
    checks.push((async () => {
      try {
        const stats = await fetchRegistryStats(config.registry!);
        result.components.registry = {
          healthy: !stats.isPaused,
          stats
        };
        if (stats.isPaused) result.overallHealthy = false;
      } catch (e) {
        result.components.registry = { healthy: false };
        result.errors.push(`Registry: ${e instanceof Error ? e.message : 'Unknown error'}`);
        result.overallHealthy = false;
      }
    })());
  }

  // Paymaster health
  if (config.paymaster) {
    checks.push((async () => {
      try {
        const health = await getPaymasterHealthSummary(config.paymaster!);
        result.components.paymaster = {
          healthy: health.isHealthy,
          balance: health.balance,
          tierCount: health.tierCount
        };
        if (!health.isHealthy) result.overallHealthy = false;
      } catch (e) {
        result.components.paymaster = { healthy: false };
        result.errors.push(`Paymaster: ${e instanceof Error ? e.message : 'Unknown error'}`);
        result.overallHealthy = false;
      }
    })());
  }

  // TreasuryVault health
  if (config.treasuryVault) {
    checks.push((async () => {
      try {
        const health = await fetchTreasuryVaultHealth(config.treasuryVault!);
        const isHealthy = health.isDepositsEnabled && health.collateralizationRatio >= BigInt(10000);
        result.components.treasuryVault = {
          healthy: isHealthy,
          collateralizationRatio: health.collateralizationRatio
        };
        if (!isHealthy) result.overallHealthy = false;
      } catch (e) {
        result.components.treasuryVault = { healthy: false };
        result.errors.push(`TreasuryVault: ${e instanceof Error ? e.message : 'Unknown error'}`);
        result.overallHealthy = false;
      }
    })());
  }

  // NAVOracle health
  if (config.navOracle) {
    checks.push((async () => {
      try {
        const health = await fetchNAVOracleHealth(config.navOracle!);
        result.components.navOracle = {
          healthy: health.isFresh && health.healthScore >= BigInt(80),
          isFresh: health.isFresh,
          healthScore: health.healthScore
        };
        if (!health.isFresh) result.overallHealthy = false;
      } catch (e) {
        result.components.navOracle = { healthy: false };
        result.errors.push(`NAVOracle: ${e instanceof Error ? e.message : 'Unknown error'}`);
        result.overallHealthy = false;
      }
    })());
  }

  // EncryptedMempool health
  if (config.mempool) {
    checks.push((async () => {
      try {
        const health = await getMempoolHealthSummary(config.mempool!);
        result.components.mempool = {
          healthy: health.isHealthy,
          pendingCount: health.pendingCount,
          successRate: health.successRate
        };
        if (!health.isHealthy) result.overallHealthy = false;
      } catch (e) {
        result.components.mempool = { healthy: false };
        result.errors.push(`Mempool: ${e instanceof Error ? e.message : 'Unknown error'}`);
        result.overallHealthy = false;
      }
    })());
  }

  // ForcedInclusion health
  if (config.forcedInclusion) {
    checks.push((async () => {
      try {
        const health = await getForcedInclusionHealthSummary(config.forcedInclusion!);
        result.components.forcedInclusion = {
          healthy: health.isHealthy,
          inclusionRate: health.inclusionRate,
          pendingCount: health.pendingCount
        };
        if (!health.isHealthy) result.overallHealthy = false;
      } catch (e) {
        result.components.forcedInclusion = { healthy: false };
        result.errors.push(`ForcedInclusion: ${e instanceof Error ? e.message : 'Unknown error'}`);
        result.overallHealthy = false;
      }
    })());
  }

  // SequencerAttestation health
  if (config.attestation) {
    checks.push((async () => {
      try {
        const health = await getAttestationHealthSummary(config.attestation!);
        result.components.attestation = {
          healthy: health.isHealthy,
          successRate: health.successRate,
          totalCommitments: health.totalCommitments
        };
        if (!health.isHealthy) result.overallHealthy = false;
      } catch (e) {
        result.components.attestation = { healthy: false };
        result.errors.push(`Attestation: ${e instanceof Error ? e.message : 'Unknown error'}`);
        result.overallHealthy = false;
      }
    })());
  }

  // Timelock health
  if (config.timelock) {
    checks.push((async () => {
      try {
        const health = await getTimelockHealthSummary(config.timelock!);
        result.components.timelock = {
          healthy: health.isHealthy,
          minDelay: health.minDelay
        };
        if (!health.isHealthy) result.overallHealthy = false;
      } catch (e) {
        result.components.timelock = { healthy: false };
        result.errors.push(`Timelock: ${e instanceof Error ? e.message : 'Unknown error'}`);
        result.overallHealthy = false;
      }
    })());
  }

  // ThresholdKeyRegistry health
  if (config.thresholdRegistry) {
    checks.push((async () => {
      try {
        const status = await fetchThresholdRegistryStatus(config.thresholdRegistry!);
        const isHealthy = !status.isPaused && status.activeCount >= status.currentThreshold;
        result.components.thresholdRegistry = {
          healthy: isHealthy,
          activeKeypers: status.activeCount,
          threshold: status.currentThreshold
        };
        if (!isHealthy) result.overallHealthy = false;
      } catch (e) {
        result.components.thresholdRegistry = { healthy: false };
        result.errors.push(`ThresholdRegistry: ${e instanceof Error ? e.message : 'Unknown error'}`);
        result.overallHealthy = false;
      }
    })());
  }

  // Wait for all checks to complete
  await Promise.all(checks);

  return result;
}

/**
 * Get a simple health status string
 * @param health System health status
 * @returns Human-readable health summary
 */
export function formatHealthStatus(health: SystemHealthStatus): string {
  const lines: string[] = [];
  lines.push(`System Health Check - ${new Date(health.timestamp).toISOString()}`);
  lines.push(`Overall: ${health.overallHealthy ? 'HEALTHY' : 'UNHEALTHY'}`);
  lines.push('');

  for (const [name, status] of Object.entries(health.components)) {
    if (status) {
      lines.push(`${name}: ${status.healthy ? 'OK' : 'FAIL'}`);
    }
  }

  if (health.errors.length > 0) {
    lines.push('');
    lines.push('Errors:');
    for (const error of health.errors) {
      lines.push(`  - ${error}`);
    }
  }

  return lines.join('\n');
}

// =========================================================================
// Transaction Helper Utilities
// =========================================================================

/**
 * Format a bigint balance with decimals
 * @param value The raw bigint value
 * @param decimals Number of decimals (default 18)
 * @returns Formatted string representation
 */
export function formatBalance(value: bigint, decimals: number = 18): string {
  const divisor = BigInt(10 ** decimals);
  const integerPart = value / divisor;
  const fractionalPart = value % divisor;

  // Pad fractional part with leading zeros
  const fractionalStr = fractionalPart.toString().padStart(decimals, '0');

  // Trim trailing zeros and return
  const trimmed = fractionalStr.replace(/0+$/, '') || '0';

  if (trimmed === '0') {
    return integerPart.toString();
  }

  return `${integerPart}.${trimmed}`;
}

/**
 * Event from a transaction receipt
 */
export interface ParsedEvent {
  name: string;
  args: Record<string, any>;
  log: Log;
}

/**
 * Find an event in a transaction receipt by name
 * @param receipt Transaction receipt
 * @param contract Contract instance (for ABI parsing)
 * @param eventName Name of the event to find
 * @returns Parsed event or undefined if not found
 */
export function findEvent(
  receipt: TransactionReceipt,
  contract: Contract,
  eventName: string
): ParsedEvent | undefined {
  const iface = contract.interface;

  for (const log of receipt.logs) {
    try {
      const parsed = iface.parseLog({
        topics: log.topics as string[],
        data: log.data
      });

      if (parsed && parsed.name === eventName) {
        // Convert args to a plain object
        const args: Record<string, any> = {};
        for (const key of Object.keys(parsed.args)) {
          if (isNaN(Number(key))) {
            args[key] = parsed.args[key];
          }
        }
        return { name: parsed.name, args, log };
      }
    } catch {
      // Skip logs that don't match this contract's ABI
      continue;
    }
  }

  return undefined;
}

/**
 * Find all events of a given type in a transaction receipt
 * @param receipt Transaction receipt
 * @param contract Contract instance
 * @param eventName Name of the event to find
 * @returns Array of parsed events
 */
export function findAllEvents(
  receipt: TransactionReceipt,
  contract: Contract,
  eventName: string
): ParsedEvent[] {
  const iface = contract.interface;
  const events: ParsedEvent[] = [];

  for (const log of receipt.logs) {
    try {
      const parsed = iface.parseLog({
        topics: log.topics as string[],
        data: log.data
      });

      if (parsed && parsed.name === eventName) {
        const args: Record<string, any> = {};
        for (const key of Object.keys(parsed.args)) {
          if (isNaN(Number(key))) {
            args[key] = parsed.args[key];
          }
        }
        events.push({ name: parsed.name, args, log });
      }
    } catch {
      continue;
    }
  }

  return events;
}

// =========================================================================
// Transaction Builder
// =========================================================================

/**
 * Transaction status
 */
export enum TxStatus {
  PENDING = 'pending',
  SIMULATING = 'simulating',
  ESTIMATING_GAS = 'estimating_gas',
  SENDING = 'sending',
  CONFIRMING = 'confirming',
  CONFIRMED = 'confirmed',
  FAILED = 'failed',
  REVERTED = 'reverted'
}

/**
 * Transaction result
 */
export interface TxResult {
  status: TxStatus;
  hash?: string;
  receipt?: TransactionReceipt;
  error?: Error;
  gasUsed?: bigint;
  gasPrice?: bigint;
  totalCost?: bigint;
  blockNumber?: number;
  confirmations?: number;
}

/**
 * Transaction builder options
 */
export interface TxBuilderOptions {
  /** Maximum retries on failure */
  maxRetries?: number;
  /** Base delay for exponential backoff (ms) */
  baseDelayMs?: number;
  /** Maximum delay between retries (ms) */
  maxDelayMs?: number;
  /** Gas price multiplier (1.1 = 10% buffer) */
  gasPriceMultiplier?: number;
  /** Gas limit multiplier (1.2 = 20% buffer) */
  gasLimitMultiplier?: number;
  /** Confirmations to wait for */
  confirmations?: number;
  /** Timeout for confirmation (ms) */
  confirmationTimeoutMs?: number;
  /** Enable simulation before sending */
  simulate?: boolean;
  /** Status callback */
  onStatusChange?: (status: TxStatus, details?: string) => void;
}

const DEFAULT_TX_OPTIONS: Required<TxBuilderOptions> = {
  maxRetries: 3,
  baseDelayMs: 1000,
  maxDelayMs: 30000,
  gasPriceMultiplier: 1.1,
  gasLimitMultiplier: 1.2,
  confirmations: 1,
  confirmationTimeoutMs: 120000,
  simulate: true,
  onStatusChange: () => {}
};

/**
 * Sleep utility
 */
function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Calculate exponential backoff delay
 */
function getBackoffDelay(attempt: number, baseMs: number, maxMs: number): number {
  const delay = baseMs * Math.pow(2, attempt);
  return Math.min(delay, maxMs);
}

/**
 * Transaction builder for executing contract calls with retry, simulation, and gas estimation
 */
export class TransactionBuilder {
  private wallet: Wallet;
  private options: Required<TxBuilderOptions>;

  constructor(wallet: Wallet, options: TxBuilderOptions = {}) {
    this.wallet = wallet;
    this.options = { ...DEFAULT_TX_OPTIONS, ...options };
  }

  /**
   * Update status and notify callback
   */
  private updateStatus(status: TxStatus, details?: string): void {
    this.options.onStatusChange(status, details);
  }

  /**
   * Estimate gas for a transaction
   */
  async estimateGas(
    contract: Contract,
    method: string,
    args: any[],
    value?: bigint
  ): Promise<{ gasLimit: bigint; gasPrice: bigint; totalCost: bigint }> {
    this.updateStatus(TxStatus.ESTIMATING_GAS);

    const provider = this.wallet.provider!;
    const feeData = await provider.getFeeData();
    const gasPrice = feeData.gasPrice || BigInt(0);

    // Estimate gas limit
    const gasEstimate = await contract[method].estimateGas(...args, {
      value: value || BigInt(0)
    });

    // Apply multipliers
    const gasLimit = BigInt(Math.ceil(Number(gasEstimate) * this.options.gasLimitMultiplier));
    const adjustedGasPrice = BigInt(Math.ceil(Number(gasPrice) * this.options.gasPriceMultiplier));
    const totalCost = gasLimit * adjustedGasPrice + (value || BigInt(0));

    return { gasLimit, gasPrice: adjustedGasPrice, totalCost };
  }

  /**
   * Simulate a transaction (dry-run)
   */
  async simulate(
    contract: Contract,
    method: string,
    args: any[],
    value?: bigint
  ): Promise<{ success: boolean; returnData?: any; error?: string }> {
    this.updateStatus(TxStatus.SIMULATING);

    try {
      // Use staticCall for simulation
      const result = await contract[method].staticCall(...args, {
        value: value || BigInt(0)
      });
      return { success: true, returnData: result };
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown error';
      return { success: false, error: message };
    }
  }

  /**
   * Execute a transaction with retry logic
   */
  async execute(
    contract: Contract,
    method: string,
    args: any[],
    value?: bigint
  ): Promise<TxResult> {
    let lastError: Error | undefined;

    for (let attempt = 0; attempt <= this.options.maxRetries; attempt++) {
      try {
        // Simulate first if enabled
        if (this.options.simulate) {
          const simResult = await this.simulate(contract, method, args, value);
          if (!simResult.success) {
            return {
              status: TxStatus.FAILED,
              error: new Error(`Simulation failed: ${simResult.error}`)
            };
          }
        }

        // Estimate gas
        const { gasLimit, gasPrice } = await this.estimateGas(contract, method, args, value);

        // Send transaction
        this.updateStatus(TxStatus.SENDING);
        const tx = await contract[method](...args, {
          value: value || BigInt(0),
          gasLimit,
          gasPrice
        });

        this.updateStatus(TxStatus.CONFIRMING, tx.hash);

        // Wait for confirmation
        const receipt = await Promise.race([
          tx.wait(this.options.confirmations),
          sleep(this.options.confirmationTimeoutMs).then(() => {
            throw new Error('Confirmation timeout');
          })
        ]) as TransactionReceipt;

        if (receipt.status === 0) {
          return {
            status: TxStatus.REVERTED,
            hash: tx.hash,
            receipt,
            gasUsed: receipt.gasUsed,
            gasPrice: receipt.gasPrice,
            totalCost: receipt.gasUsed * receipt.gasPrice
          };
        }

        this.updateStatus(TxStatus.CONFIRMED);
        return {
          status: TxStatus.CONFIRMED,
          hash: tx.hash,
          receipt,
          gasUsed: receipt.gasUsed,
          gasPrice: receipt.gasPrice,
          totalCost: receipt.gasUsed * receipt.gasPrice,
          blockNumber: receipt.blockNumber,
          confirmations: this.options.confirmations
        };

      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));

        // Don't retry on simulation failures or user rejections
        if (lastError.message.includes('Simulation failed') ||
            lastError.message.includes('user rejected')) {
          break;
        }

        // Retry with backoff
        if (attempt < this.options.maxRetries) {
          const delay = getBackoffDelay(attempt, this.options.baseDelayMs, this.options.maxDelayMs);
          this.updateStatus(TxStatus.PENDING, `Retry ${attempt + 1}/${this.options.maxRetries} in ${delay}ms`);
          await sleep(delay);
        }
      }
    }

    return {
      status: TxStatus.FAILED,
      error: lastError
    };
  }
}

/**
 * Gas estimation result
 */
export interface GasEstimate {
  gasLimit: bigint;
  gasPrice: bigint;
  maxFeePerGas?: bigint;
  maxPriorityFeePerGas?: bigint;
  totalCost: bigint;
  totalCostEth: string;
}

/**
 * Estimate gas for any contract call
 */
export async function estimateContractGas(
  contract: Contract,
  method: string,
  args: any[],
  value?: bigint,
  multiplier: number = 1.2
): Promise<GasEstimate> {
  const provider = contract.runner?.provider;
  if (!provider) throw new Error('Contract has no provider');

  const feeData = await (provider as JsonRpcProvider).getFeeData();
  const gasEstimate = await contract[method].estimateGas(...args, {
    value: value || BigInt(0)
  });

  const gasLimit = BigInt(Math.ceil(Number(gasEstimate) * multiplier));
  const gasPrice = feeData.gasPrice || BigInt(0);
  const totalCost = gasLimit * gasPrice + (value || BigInt(0));

  return {
    gasLimit,
    gasPrice,
    maxFeePerGas: feeData.maxFeePerGas || undefined,
    maxPriorityFeePerGas: feeData.maxPriorityFeePerGas || undefined,
    totalCost,
    totalCostEth: formatBalance(totalCost, 18)
  };
}

/**
 * Simulate a contract call without sending
 */
export async function simulateContractCall<T = any>(
  contract: Contract,
  method: string,
  args: any[],
  value?: bigint
): Promise<{ success: boolean; result?: T; error?: string; gasEstimate?: bigint }> {
  try {
    const result = await contract[method].staticCall(...args, {
      value: value || BigInt(0)
    });
    const gasEstimate = await contract[method].estimateGas(...args, {
      value: value || BigInt(0)
    });
    return { success: true, result: result as T, gasEstimate };
  } catch (error) {
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

// =========================================================================
// Flow Builders - Common Transaction Sequences
// =========================================================================

/**
 * Flow step result
 */
export interface FlowStepResult {
  step: string;
  status: 'success' | 'failed' | 'skipped';
  txHash?: string;
  error?: string;
  data?: any;
}

/**
 * Flow result
 */
export interface FlowResult {
  success: boolean;
  steps: FlowStepResult[];
  totalGasUsed: bigint;
  totalCost: bigint;
  error?: string;
}

/**
 * Deposit and mint ssUSD flow
 * Steps: 1) Approve collateral, 2) Deposit to vault, 3) Receive ssUSD
 */
export async function executeDepositFlow(
  wallet: Wallet,
  treasuryVault: Contract,
  collateralToken: Contract,
  amount: bigint,
  options: TxBuilderOptions = {}
): Promise<FlowResult> {
  const builder = new TransactionBuilder(wallet, options);
  const steps: FlowStepResult[] = [];
  let totalGasUsed = BigInt(0);
  let totalCost = BigInt(0);

  try {
    // Step 1: Check and approve allowance
    const vaultAddress = await treasuryVault.getAddress();
    const allowance = await collateralToken.allowance(wallet.address, vaultAddress) as bigint;

    if (allowance < amount) {
      const approveResult = await builder.execute(
        collateralToken,
        'approve',
        [vaultAddress, amount]
      );

      if (approveResult.status !== TxStatus.CONFIRMED) {
        steps.push({
          step: 'approve',
          status: 'failed',
          error: approveResult.error?.message
        });
        return { success: false, steps, totalGasUsed, totalCost, error: 'Approval failed' };
      }

      steps.push({
        step: 'approve',
        status: 'success',
        txHash: approveResult.hash
      });
      totalGasUsed += approveResult.gasUsed || BigInt(0);
      totalCost += approveResult.totalCost || BigInt(0);
    } else {
      steps.push({ step: 'approve', status: 'skipped', data: 'Sufficient allowance' });
    }

    // Step 2: Deposit to vault
    const depositResult = await builder.execute(
      treasuryVault,
      'deposit',
      [await collateralToken.getAddress(), amount, wallet.address]
    );

    if (depositResult.status !== TxStatus.CONFIRMED) {
      steps.push({
        step: 'deposit',
        status: 'failed',
        error: depositResult.error?.message
      });
      return { success: false, steps, totalGasUsed, totalCost, error: 'Deposit failed' };
    }

    steps.push({
      step: 'deposit',
      status: 'success',
      txHash: depositResult.hash
    });
    totalGasUsed += depositResult.gasUsed || BigInt(0);
    totalCost += depositResult.totalCost || BigInt(0);

    return { success: true, steps, totalGasUsed, totalCost };

  } catch (error) {
    return {
      success: false,
      steps,
      totalGasUsed,
      totalCost,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

/**
 * Wrap ssUSD to wssUSD flow
 * Steps: 1) Approve ssUSD, 2) Wrap to wssUSD
 */
export async function executeWrapFlow(
  wallet: Wallet,
  wssUSD: Contract,
  ssUSD: Contract,
  amount: bigint,
  options: TxBuilderOptions = {}
): Promise<FlowResult> {
  const builder = new TransactionBuilder(wallet, options);
  const steps: FlowStepResult[] = [];
  let totalGasUsed = BigInt(0);
  let totalCost = BigInt(0);

  try {
    // Step 1: Check and approve allowance
    const wssUSDAddress = await wssUSD.getAddress();
    const allowance = await ssUSD.allowance(wallet.address, wssUSDAddress) as bigint;

    if (allowance < amount) {
      const approveResult = await builder.execute(
        ssUSD,
        'approve',
        [wssUSDAddress, amount]
      );

      if (approveResult.status !== TxStatus.CONFIRMED) {
        steps.push({
          step: 'approve',
          status: 'failed',
          error: approveResult.error?.message
        });
        return { success: false, steps, totalGasUsed, totalCost, error: 'Approval failed' };
      }

      steps.push({
        step: 'approve',
        status: 'success',
        txHash: approveResult.hash
      });
      totalGasUsed += approveResult.gasUsed || BigInt(0);
      totalCost += approveResult.totalCost || BigInt(0);
    } else {
      steps.push({ step: 'approve', status: 'skipped', data: 'Sufficient allowance' });
    }

    // Step 2: Wrap to wssUSD
    const wrapResult = await builder.execute(
      wssUSD,
      'wrap',
      [amount]
    );

    if (wrapResult.status !== TxStatus.CONFIRMED) {
      steps.push({
        step: 'wrap',
        status: 'failed',
        error: wrapResult.error?.message
      });
      return { success: false, steps, totalGasUsed, totalCost, error: 'Wrap failed' };
    }

    steps.push({
      step: 'wrap',
      status: 'success',
      txHash: wrapResult.hash
    });
    totalGasUsed += wrapResult.gasUsed || BigInt(0);
    totalCost += wrapResult.totalCost || BigInt(0);

    return { success: true, steps, totalGasUsed, totalCost };

  } catch (error) {
    return {
      success: false,
      steps,
      totalGasUsed,
      totalCost,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

/**
 * Unwrap wssUSD to ssUSD flow
 */
export async function executeUnwrapFlow(
  wallet: Wallet,
  wssUSD: Contract,
  shares: bigint,
  options: TxBuilderOptions = {}
): Promise<FlowResult> {
  const builder = new TransactionBuilder(wallet, options);
  const steps: FlowStepResult[] = [];
  let totalGasUsed = BigInt(0);
  let totalCost = BigInt(0);

  try {
    const unwrapResult = await builder.execute(
      wssUSD,
      'unwrap',
      [shares]
    );

    if (unwrapResult.status !== TxStatus.CONFIRMED) {
      steps.push({
        step: 'unwrap',
        status: 'failed',
        error: unwrapResult.error?.message
      });
      return { success: false, steps, totalGasUsed, totalCost, error: 'Unwrap failed' };
    }

    steps.push({
      step: 'unwrap',
      status: 'success',
      txHash: unwrapResult.hash
    });
    totalGasUsed += unwrapResult.gasUsed || BigInt(0);
    totalCost += unwrapResult.totalCost || BigInt(0);

    return { success: true, steps, totalGasUsed, totalCost };

  } catch (error) {
    return {
      success: false,
      steps,
      totalGasUsed,
      totalCost,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

/**
 * Request redemption flow
 * Steps: 1) Approve ssUSD to vault, 2) Request redemption
 */
export async function executeRedemptionRequestFlow(
  wallet: Wallet,
  treasuryVault: Contract,
  ssUSD: Contract,
  amount: bigint,
  options: TxBuilderOptions = {}
): Promise<FlowResult & { requestId?: bigint }> {
  const builder = new TransactionBuilder(wallet, options);
  const steps: FlowStepResult[] = [];
  let totalGasUsed = BigInt(0);
  let totalCost = BigInt(0);

  try {
    // Step 1: Check and approve allowance
    const vaultAddress = await treasuryVault.getAddress();
    const allowance = await ssUSD.allowance(wallet.address, vaultAddress) as bigint;

    if (allowance < amount) {
      const approveResult = await builder.execute(
        ssUSD,
        'approve',
        [vaultAddress, amount]
      );

      if (approveResult.status !== TxStatus.CONFIRMED) {
        steps.push({
          step: 'approve',
          status: 'failed',
          error: approveResult.error?.message
        });
        return { success: false, steps, totalGasUsed, totalCost, error: 'Approval failed' };
      }

      steps.push({
        step: 'approve',
        status: 'success',
        txHash: approveResult.hash
      });
      totalGasUsed += approveResult.gasUsed || BigInt(0);
      totalCost += approveResult.totalCost || BigInt(0);
    } else {
      steps.push({ step: 'approve', status: 'skipped', data: 'Sufficient allowance' });
    }

    // Step 2: Request redemption
    const requestResult = await builder.execute(
      treasuryVault,
      'requestRedemption',
      [amount]
    );

    if (requestResult.status !== TxStatus.CONFIRMED) {
      steps.push({
        step: 'requestRedemption',
        status: 'failed',
        error: requestResult.error?.message
      });
      return { success: false, steps, totalGasUsed, totalCost, error: 'Redemption request failed' };
    }

    // Extract request ID from event
    let requestId: bigint | undefined;
    if (requestResult.receipt) {
      const event = findEvent(requestResult.receipt, treasuryVault, 'RedemptionRequested');
      if (event) {
        requestId = event.args?.requestId;
      }
    }

    steps.push({
      step: 'requestRedemption',
      status: 'success',
      txHash: requestResult.hash,
      data: { requestId }
    });
    totalGasUsed += requestResult.gasUsed || BigInt(0);
    totalCost += requestResult.totalCost || BigInt(0);

    return { success: true, steps, totalGasUsed, totalCost, requestId };

  } catch (error) {
    return {
      success: false,
      steps,
      totalGasUsed,
      totalCost,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

/**
 * Batch sponsor merchants flow
 */
export async function executeBatchSponsorFlow(
  wallet: Wallet,
  paymaster: Contract,
  merchants: string[],
  tierIds: bigint[],
  options: TxBuilderOptions = {}
): Promise<FlowResult> {
  const builder = new TransactionBuilder(wallet, options);
  const steps: FlowStepResult[] = [];
  let totalGasUsed = BigInt(0);
  let totalCost = BigInt(0);

  try {
    const sponsorResult = await builder.execute(
      paymaster,
      'batchSponsorMerchants',
      [merchants, tierIds]
    );

    if (sponsorResult.status !== TxStatus.CONFIRMED) {
      steps.push({
        step: 'batchSponsor',
        status: 'failed',
        error: sponsorResult.error?.message
      });
      return { success: false, steps, totalGasUsed, totalCost, error: 'Batch sponsor failed' };
    }

    steps.push({
      step: 'batchSponsor',
      status: 'success',
      txHash: sponsorResult.hash,
      data: { merchantCount: merchants.length }
    });
    totalGasUsed += sponsorResult.gasUsed || BigInt(0);
    totalCost += sponsorResult.totalCost || BigInt(0);

    return { success: true, steps, totalGasUsed, totalCost };

  } catch (error) {
    return {
      success: false,
      steps,
      totalGasUsed,
      totalCost,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

/**
 * Commit batch to registry flow
 */
export async function executeCommitBatchFlow(
  wallet: Wallet,
  registry: Contract,
  tenantId: string,
  storeId: string,
  batchId: string,
  starkRoot: string,
  txCount: number,
  options: TxBuilderOptions = {}
): Promise<FlowResult> {
  const builder = new TransactionBuilder(wallet, options);
  const steps: FlowStepResult[] = [];
  let totalGasUsed = BigInt(0);
  let totalCost = BigInt(0);

  try {
    const commitResult = await builder.execute(
      registry,
      'commitBatch',
      [tenantId, storeId, batchId, starkRoot, txCount]
    );

    if (commitResult.status !== TxStatus.CONFIRMED) {
      steps.push({
        step: 'commitBatch',
        status: 'failed',
        error: commitResult.error?.message
      });
      return { success: false, steps, totalGasUsed, totalCost, error: 'Batch commit failed' };
    }

    steps.push({
      step: 'commitBatch',
      status: 'success',
      txHash: commitResult.hash,
      data: { batchId, txCount }
    });
    totalGasUsed += commitResult.gasUsed || BigInt(0);
    totalCost += commitResult.totalCost || BigInt(0);

    return { success: true, steps, totalGasUsed, totalCost };

  } catch (error) {
    return {
      success: false,
      steps,
      totalGasUsed,
      totalCost,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

/**
 * Submit encrypted transaction flow
 */
export async function executeEncryptedTxFlow(
  wallet: Wallet,
  mempool: Contract,
  encryptedPayload: string,
  epoch: bigint,
  gasLimit: bigint,
  maxFeePerGas: bigint,
  valueDeposit: bigint,
  options: TxBuilderOptions = {}
): Promise<FlowResult & { txId?: string }> {
  const builder = new TransactionBuilder(wallet, options);
  const steps: FlowStepResult[] = [];
  let totalGasUsed = BigInt(0);
  let totalCost = BigInt(0);

  try {
    // Calculate required value (gas deposit + value deposit)
    const gasDeposit = gasLimit * maxFeePerGas;
    const totalValue = gasDeposit + valueDeposit;

    const submitResult = await builder.execute(
      mempool,
      'submitEncryptedTx',
      [encryptedPayload, epoch, gasLimit, maxFeePerGas],
      totalValue
    );

    if (submitResult.status !== TxStatus.CONFIRMED) {
      steps.push({
        step: 'submitEncryptedTx',
        status: 'failed',
        error: submitResult.error?.message
      });
      return { success: false, steps, totalGasUsed, totalCost, error: 'Submit failed' };
    }

    // Extract tx ID from event
    let txId: string | undefined;
    if (submitResult.receipt) {
      const event = findEvent(submitResult.receipt, mempool, 'EncryptedTxSubmitted');
      if (event) {
        txId = event.args?.txId;
      }
    }

    steps.push({
      step: 'submitEncryptedTx',
      status: 'success',
      txHash: submitResult.hash,
      data: { txId }
    });
    totalGasUsed += submitResult.gasUsed || BigInt(0);
    totalCost += submitResult.totalCost || BigInt(0);

    return { success: true, steps, totalGasUsed, totalCost, txId };

  } catch (error) {
    return {
      success: false,
      steps,
      totalGasUsed,
      totalCost,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

/**
 * Force transaction inclusion flow (L1)
 */
export async function executeForcedInclusionFlow(
  wallet: Wallet,
  forcedInclusion: Contract,
  target: string,
  data: string,
  gasLimit: bigint,
  bond: bigint,
  options: TxBuilderOptions = {}
): Promise<FlowResult & { txId?: string; deadline?: bigint }> {
  const builder = new TransactionBuilder(wallet, options);
  const steps: FlowStepResult[] = [];
  let totalGasUsed = BigInt(0);
  let totalCost = BigInt(0);

  try {
    const forceResult = await builder.execute(
      forcedInclusion,
      'forceTransaction',
      [target, data, gasLimit],
      bond
    );

    if (forceResult.status !== TxStatus.CONFIRMED) {
      steps.push({
        step: 'forceTransaction',
        status: 'failed',
        error: forceResult.error?.message
      });
      return { success: false, steps, totalGasUsed, totalCost, error: 'Force transaction failed' };
    }

    // Extract tx ID and deadline from event
    let txId: string | undefined;
    let deadline: bigint | undefined;
    if (forceResult.receipt) {
      const event = findEvent(forceResult.receipt, forcedInclusion, 'TransactionForced');
      if (event) {
        txId = event.args?.txId;
        deadline = event.args?.deadline;
      }
    }

    steps.push({
      step: 'forceTransaction',
      status: 'success',
      txHash: forceResult.hash,
      data: { txId, deadline }
    });
    totalGasUsed += forceResult.gasUsed || BigInt(0);
    totalCost += forceResult.totalCost || BigInt(0);

    return { success: true, steps, totalGasUsed, totalCost, txId, deadline };

  } catch (error) {
    return {
      success: false,
      steps,
      totalGasUsed,
      totalCost,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

// =========================================================================
// Caching Utilities
// =========================================================================

/**
 * Cache entry with value and expiration
 */
interface CacheEntry<T> {
  value: T;
  expiresAt: number;
}

/**
 * Simple in-memory cache with TTL support
 */
export class ContractCache {
  private cache: Map<string, CacheEntry<any>> = new Map();
  private defaultTtlMs: number;

  constructor(defaultTtlMs: number = 30000) {
    this.defaultTtlMs = defaultTtlMs;
  }

  /**
   * Get a cached value or fetch it
   * @param key Cache key
   * @param fetcher Function to fetch value if not cached
   * @param ttlMs Custom TTL for this entry
   */
  async getOrFetch<T>(
    key: string,
    fetcher: () => Promise<T>,
    ttlMs?: number
  ): Promise<T> {
    const now = Date.now();
    const entry = this.cache.get(key);

    if (entry && entry.expiresAt > now) {
      return entry.value as T;
    }

    const value = await fetcher();
    this.cache.set(key, {
      value,
      expiresAt: now + (ttlMs ?? this.defaultTtlMs)
    });

    return value;
  }

  /**
   * Get a cached value
   * @param key Cache key
   */
  get<T>(key: string): T | undefined {
    const entry = this.cache.get(key);
    if (entry && entry.expiresAt > Date.now()) {
      return entry.value as T;
    }
    this.cache.delete(key);
    return undefined;
  }

  /**
   * Set a cached value
   * @param key Cache key
   * @param value Value to cache
   * @param ttlMs Custom TTL
   */
  set<T>(key: string, value: T, ttlMs?: number): void {
    this.cache.set(key, {
      value,
      expiresAt: Date.now() + (ttlMs ?? this.defaultTtlMs)
    });
  }

  /**
   * Invalidate a cache entry
   * @param key Cache key
   */
  invalidate(key: string): void {
    this.cache.delete(key);
  }

  /**
   * Invalidate all entries matching a prefix
   * @param prefix Key prefix to match
   */
  invalidateByPrefix(prefix: string): void {
    for (const key of this.cache.keys()) {
      if (key.startsWith(prefix)) {
        this.cache.delete(key);
      }
    }
  }

  /**
   * Clear all cached entries
   */
  clear(): void {
    this.cache.clear();
  }

  /**
   * Get cache statistics
   */
  stats(): { size: number; keys: string[] } {
    return {
      size: this.cache.size,
      keys: Array.from(this.cache.keys())
    };
  }
}

/**
 * Cached contract wrapper for reducing RPC calls
 */
export class CachedContractWrapper {
  private cache: ContractCache;
  private contracts: Map<string, Contract> = new Map();

  constructor(cacheTtlMs: number = 30000) {
    this.cache = new ContractCache(cacheTtlMs);
  }

  /**
   * Register a contract for caching
   * @param name Contract name
   * @param contract Contract instance
   */
  registerContract(name: string, contract: Contract): void {
    this.contracts.set(name, contract);
  }

  /**
   * Get cached registry status
   */
  async getRegistryStatus(registry: Contract): Promise<RegistryStats> {
    return this.cache.getOrFetch(
      'registry:stats',
      () => fetchRegistryStats(registry)
    );
  }

  /**
   * Get cached extended registry status
   */
  async getExtendedRegistryStatus(registry: Contract): Promise<ExtendedRegistryStatus> {
    return this.cache.getOrFetch(
      'registry:extended',
      () => fetchExtendedRegistryStatus(registry)
    );
  }

  /**
   * Get cached paymaster status
   */
  async getPaymasterStatus(paymaster: Contract): Promise<PaymasterStatus> {
    return this.cache.getOrFetch(
      'paymaster:status',
      () => fetchPaymasterStatus(paymaster)
    );
  }

  /**
   * Get cached wssUSD vault status
   */
  async getWssUSDStatus(vault: Contract): Promise<WssUSDVaultStatus> {
    return this.cache.getOrFetch(
      'wssUSD:status',
      () => fetchWssUSDVaultStatus(vault)
    );
  }

  /**
   * Get cached threshold registry status
   */
  async getThresholdRegistryStatus(registry: Contract): Promise<ThresholdRegistryStatus> {
    return this.cache.getOrFetch(
      'threshold:status',
      () => fetchThresholdRegistryStatus(registry)
    );
  }

  /**
   * Invalidate all cached data for a contract type
   */
  invalidateContract(contractType: 'registry' | 'paymaster' | 'wssUSD' | 'threshold'): void {
    this.cache.invalidateByPrefix(`${contractType}:`);
  }

  /**
   * Clear all caches
   */
  clearAll(): void {
    this.cache.clear();
  }

  /**
   * Get underlying cache for custom usage
   */
  getCache(): ContractCache {
    return this.cache;
  }
}

/**
 * Create a cached contract wrapper
 * @param ttlMs Cache TTL in milliseconds (default 30 seconds)
 */
export function createCachedWrapper(ttlMs: number = 30000): CachedContractWrapper {
  return new CachedContractWrapper(ttlMs);
}

// =========================================================================
// Retry Utilities
// =========================================================================

/**
 * Retry configuration
 */
export interface RetryConfig {
  maxAttempts: number;
  initialDelayMs: number;
  maxDelayMs: number;
  backoffMultiplier: number;
}

/**
 * Default retry configuration
 */
export const DEFAULT_RETRY_CONFIG: RetryConfig = {
  maxAttempts: 3,
  initialDelayMs: 1000,
  maxDelayMs: 10000,
  backoffMultiplier: 2
};

/**
 * Execute a function with retry logic
 * @param fn Function to execute
 * @param config Retry configuration
 * @returns Result of the function
 */
export async function withRetry<T>(
  fn: () => Promise<T>,
  config: Partial<RetryConfig> = {}
): Promise<T> {
  const { maxAttempts, initialDelayMs, maxDelayMs, backoffMultiplier } = {
    ...DEFAULT_RETRY_CONFIG,
    ...config
  };

  let lastError: Error | undefined;
  let delay = initialDelayMs;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error as Error;

      if (attempt < maxAttempts) {
        await new Promise(resolve => setTimeout(resolve, delay));
        delay = Math.min(delay * backoffMultiplier, maxDelayMs);
      }
    }
  }

  throw lastError;
}

/**
 * Execute multiple calls in parallel with retry
 * @param fns Array of functions to execute
 * @param config Retry configuration
 * @returns Array of results
 */
export async function withRetryAll<T>(
  fns: Array<() => Promise<T>>,
  config: Partial<RetryConfig> = {}
): Promise<T[]> {
  return Promise.all(fns.map(fn => withRetry(fn, config)));
}

// =========================================================================
// Batching Utilities
// =========================================================================

/**
 * Execute calls in batches to avoid rate limits
 * @param items Items to process
 * @param batchSize Size of each batch
 * @param processor Function to process each batch
 * @param delayBetweenBatchesMs Delay between batches
 * @returns Flattened results
 */
export async function processBatched<T, R>(
  items: T[],
  batchSize: number,
  processor: (batch: T[]) => Promise<R[]>,
  delayBetweenBatchesMs: number = 100
): Promise<R[]> {
  const results: R[] = [];

  for (let i = 0; i < items.length; i += batchSize) {
    const batch = items.slice(i, i + batchSize);
    const batchResults = await processor(batch);
    results.push(...batchResults);

    if (i + batchSize < items.length && delayBetweenBatchesMs > 0) {
      await new Promise(resolve => setTimeout(resolve, delayBetweenBatchesMs));
    }
  }

  return results;
}

// =========================================================================
// Transaction Status Tracking
// =========================================================================

/**
 * Tracked transaction status
 */
export interface TrackedTransaction {
  hash: string;
  status: TxStatus;
  submittedAt: number;
  confirmedAt?: number;
  blockNumber?: number;
  confirmations: number;
  gasUsed?: bigint;
  effectiveGasPrice?: bigint;
  error?: string;
  metadata?: Record<string, any>;
}

/**
 * Transaction tracker event types
 */
export type TxTrackerEventType =
  | 'submitted'
  | 'confirmed'
  | 'failed'
  | 'dropped'
  | 'replaced'
  | 'confirmation';

/**
 * Transaction tracker event
 */
export interface TxTrackerEvent {
  type: TxTrackerEventType;
  txHash: string;
  transaction: TrackedTransaction;
  confirmations?: number;
}

/**
 * Transaction tracker listener
 */
export type TxTrackerListener = (event: TxTrackerEvent) => void;

/**
 * Transaction tracker for monitoring pending and confirmed transactions
 */
export class TransactionTracker {
  private provider: JsonRpcProvider;
  private transactions: Map<string, TrackedTransaction> = new Map();
  private listeners: Map<string, Set<TxTrackerListener>> = new Map();
  private globalListeners: Set<TxTrackerListener> = new Set();
  private pollingInterval: number;
  private pollTimer: ReturnType<typeof setInterval> | null = null;
  private isPolling: boolean = false;

  constructor(provider: JsonRpcProvider, pollingIntervalMs: number = 2000) {
    this.provider = provider;
    this.pollingInterval = pollingIntervalMs;
  }

  /**
   * Start tracking a transaction
   */
  async track(
    txHash: string,
    metadata?: Record<string, any>
  ): Promise<TrackedTransaction> {
    const tx: TrackedTransaction = {
      hash: txHash,
      status: TxStatus.PENDING,
      submittedAt: Date.now(),
      confirmations: 0,
      metadata
    };

    this.transactions.set(txHash, tx);
    this.emit(txHash, { type: 'submitted', txHash, transaction: tx });

    // Start polling if not already
    this.startPolling();

    // Check immediately
    await this.checkTransaction(txHash);

    return tx;
  }

  /**
   * Get a tracked transaction
   */
  get(txHash: string): TrackedTransaction | undefined {
    return this.transactions.get(txHash);
  }

  /**
   * Get all tracked transactions
   */
  getAll(): TrackedTransaction[] {
    return Array.from(this.transactions.values());
  }

  /**
   * Get pending transactions
   */
  getPending(): TrackedTransaction[] {
    return this.getAll().filter(
      tx => tx.status === TxStatus.PENDING || tx.status === TxStatus.CONFIRMING
    );
  }

  /**
   * Get confirmed transactions
   */
  getConfirmed(): TrackedTransaction[] {
    return this.getAll().filter(tx => tx.status === TxStatus.CONFIRMED);
  }

  /**
   * Subscribe to events for a specific transaction
   */
  on(txHash: string, listener: TxTrackerListener): () => void {
    if (!this.listeners.has(txHash)) {
      this.listeners.set(txHash, new Set());
    }
    this.listeners.get(txHash)!.add(listener);

    // Return unsubscribe function
    return () => {
      this.listeners.get(txHash)?.delete(listener);
    };
  }

  /**
   * Subscribe to all transaction events
   */
  onAll(listener: TxTrackerListener): () => void {
    this.globalListeners.add(listener);
    return () => {
      this.globalListeners.delete(listener);
    };
  }

  /**
   * Wait for a transaction to be confirmed
   */
  async waitForConfirmation(
    txHash: string,
    confirmations: number = 1,
    timeoutMs: number = 120000
  ): Promise<TrackedTransaction> {
    const existing = this.transactions.get(txHash);
    if (existing && existing.confirmations >= confirmations) {
      return existing;
    }

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        unsubscribe();
        reject(new Error(`Transaction confirmation timeout: ${txHash}`));
      }, timeoutMs);

      const unsubscribe = this.on(txHash, event => {
        if (
          event.type === 'confirmed' ||
          (event.type === 'confirmation' && (event.confirmations ?? 0) >= confirmations)
        ) {
          clearTimeout(timeout);
          unsubscribe();
          resolve(event.transaction);
        } else if (event.type === 'failed' || event.type === 'dropped') {
          clearTimeout(timeout);
          unsubscribe();
          reject(new Error(event.transaction.error || 'Transaction failed'));
        }
      });

      // Track if not already tracked
      if (!this.transactions.has(txHash)) {
        this.track(txHash);
      }
    });
  }

  /**
   * Stop tracking a transaction
   */
  untrack(txHash: string): void {
    this.transactions.delete(txHash);
    this.listeners.delete(txHash);

    // Stop polling if no more transactions
    if (this.transactions.size === 0) {
      this.stopPolling();
    }
  }

  /**
   * Clear all tracked transactions
   */
  clear(): void {
    this.transactions.clear();
    this.listeners.clear();
    this.stopPolling();
  }

  /**
   * Destroy the tracker
   */
  destroy(): void {
    this.clear();
    this.globalListeners.clear();
  }

  private emit(txHash: string, event: TxTrackerEvent): void {
    // Notify specific listeners
    this.listeners.get(txHash)?.forEach(listener => {
      try {
        listener(event);
      } catch (e) {
        console.error('Transaction tracker listener error:', e);
      }
    });

    // Notify global listeners
    this.globalListeners.forEach(listener => {
      try {
        listener(event);
      } catch (e) {
        console.error('Transaction tracker global listener error:', e);
      }
    });
  }

  private startPolling(): void {
    if (this.isPolling) return;

    this.isPolling = true;
    this.pollTimer = setInterval(async () => {
      await this.pollTransactions();
    }, this.pollingInterval);
  }

  private stopPolling(): void {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
    this.isPolling = false;
  }

  private async pollTransactions(): Promise<void> {
    const pendingTxs = this.getPending();
    await Promise.all(pendingTxs.map(tx => this.checkTransaction(tx.hash)));
  }

  private async checkTransaction(txHash: string): Promise<void> {
    const tx = this.transactions.get(txHash);
    if (!tx) return;

    try {
      const receipt = await this.provider.getTransactionReceipt(txHash);

      if (receipt) {
        const currentBlock = await this.provider.getBlockNumber();
        const confirmations = currentBlock - receipt.blockNumber + 1;

        const previousConfirmations = tx.confirmations;
        tx.confirmations = confirmations;
        tx.blockNumber = receipt.blockNumber;
        tx.gasUsed = receipt.gasUsed;
        tx.effectiveGasPrice = receipt.gasPrice;

        if (receipt.status === 0) {
          // Transaction reverted
          tx.status = TxStatus.REVERTED;
          tx.error = 'Transaction reverted';
          tx.confirmedAt = Date.now();
          this.emit(txHash, { type: 'failed', txHash, transaction: tx });
        } else if (previousConfirmations === 0) {
          // First confirmation
          tx.status = TxStatus.CONFIRMED;
          tx.confirmedAt = Date.now();
          this.emit(txHash, {
            type: 'confirmed',
            txHash,
            transaction: tx,
            confirmations
          });
        } else if (confirmations > previousConfirmations) {
          // Additional confirmations
          this.emit(txHash, {
            type: 'confirmation',
            txHash,
            transaction: tx,
            confirmations
          });
        }
      } else {
        // Check if transaction was dropped (no longer in mempool)
        const txData = await this.provider.getTransaction(txHash);
        if (!txData && Date.now() - tx.submittedAt > 300000) {
          // 5 minute timeout
          tx.status = TxStatus.FAILED;
          tx.error = 'Transaction dropped from mempool';
          this.emit(txHash, { type: 'dropped', txHash, transaction: tx });
        }
      }
    } catch (error) {
      // Log but don't fail
      console.error(`Error checking transaction ${txHash}:`, error);
    }
  }
}

/**
 * Create a transaction tracker for a provider
 */
export function createTransactionTracker(
  provider: JsonRpcProvider,
  pollingIntervalMs: number = 2000
): TransactionTracker {
  return new TransactionTracker(provider, pollingIntervalMs);
}

/**
 * Watch a single transaction until confirmed
 * Convenience function for one-off transaction watching
 */
export async function watchTransaction(
  provider: JsonRpcProvider,
  txHash: string,
  confirmations: number = 1,
  timeoutMs: number = 120000
): Promise<TransactionReceipt> {
  const startTime = Date.now();
  const pollInterval = 2000;

  while (Date.now() - startTime < timeoutMs) {
    try {
      const receipt = await provider.getTransactionReceipt(txHash);

      if (receipt) {
        if (receipt.status === 0) {
          throw new Error('Transaction reverted');
        }

        const currentBlock = await provider.getBlockNumber();
        const currentConfirmations = currentBlock - receipt.blockNumber + 1;

        if (currentConfirmations >= confirmations) {
          return receipt;
        }
      }
    } catch (error) {
      if ((error as Error).message === 'Transaction reverted') {
        throw error;
      }
      // Ignore other errors and continue polling
    }

    await new Promise(resolve => setTimeout(resolve, pollInterval));
  }

  throw new Error(`Transaction confirmation timeout: ${txHash}`);
}

/**
 * Get the current nonce for an address (including pending transactions)
 */
export async function getNextNonce(
  provider: JsonRpcProvider,
  address: string
): Promise<number> {
  return await provider.getTransactionCount(address, 'pending');
}

/**
 * Speed up a transaction by resubmitting with higher gas price
 */
export async function speedUpTransaction(
  wallet: Wallet,
  originalTxHash: string,
  gasPriceMultiplier: number = 1.5
): Promise<string> {
  const provider = wallet.provider as JsonRpcProvider;

  // Get the original transaction
  const tx = await provider.getTransaction(originalTxHash);
  if (!tx) {
    throw new Error('Original transaction not found');
  }

  // Check if already mined
  const receipt = await provider.getTransactionReceipt(originalTxHash);
  if (receipt) {
    throw new Error('Transaction already mined');
  }

  // Get current gas price
  const feeData = await provider.getFeeData();
  const originalGasPrice = tx.gasPrice || feeData.gasPrice || BigInt(0);
  const newGasPrice = BigInt(Math.ceil(Number(originalGasPrice) * gasPriceMultiplier));

  // Resubmit with same nonce but higher gas price
  const newTx = await wallet.sendTransaction({
    to: tx.to,
    data: tx.data,
    value: tx.value,
    nonce: tx.nonce,
    gasLimit: tx.gasLimit,
    gasPrice: newGasPrice
  });

  return newTx.hash;
}

/**
 * Cancel a transaction by sending a 0-value transaction with same nonce
 */
export async function cancelTransaction(
  wallet: Wallet,
  originalTxHash: string,
  gasPriceMultiplier: number = 1.5
): Promise<string> {
  const provider = wallet.provider as JsonRpcProvider;

  // Get the original transaction
  const tx = await provider.getTransaction(originalTxHash);
  if (!tx) {
    throw new Error('Original transaction not found');
  }

  // Check if already mined
  const receipt = await provider.getTransactionReceipt(originalTxHash);
  if (receipt) {
    throw new Error('Transaction already mined');
  }

  // Get current gas price
  const feeData = await provider.getFeeData();
  const originalGasPrice = tx.gasPrice || feeData.gasPrice || BigInt(0);
  const newGasPrice = BigInt(Math.ceil(Number(originalGasPrice) * gasPriceMultiplier));

  // Send a self-transfer with same nonce to cancel
  const cancelTx = await wallet.sendTransaction({
    to: await wallet.getAddress(),
    data: '0x',
    value: BigInt(0),
    nonce: tx.nonce,
    gasLimit: BigInt(21000),
    gasPrice: newGasPrice
  });

  return cancelTx.hash;
}
