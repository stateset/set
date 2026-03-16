/**
 * Set Chain SDK - Shared TypeScript Interfaces
 *
 * Interfaces used across multiple contract modules.
 */

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
