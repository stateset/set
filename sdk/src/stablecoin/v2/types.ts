/**
 * Set Chain SDK - V2 Stablecoin Agent Types
 *
 * Type definitions for AI agent interactions with the SSDC V2 system.
 */

// ---------------------------------------------------------------------------
// Contract Addresses
// ---------------------------------------------------------------------------

export interface SSDCV2Addresses {
  vault: string;
  gateway: string;
  navController: string;
  escrow: string;
  claimQueue: string;
  policyModule: string;
  groundingRegistry: string;
  paymaster: string;
  bridge: string;
  statusLens: string;
  circuitBreaker: string;
  settlementAsset: string;
}

// ---------------------------------------------------------------------------
// Agent Identity & Policy
// ---------------------------------------------------------------------------

export interface AgentPolicy {
  perTxLimitAssets: bigint;
  dailyLimitAssets: bigint;
  spentTodayAssets: bigint;
  dayStart: number;
  minAssetsFloor: bigint;
  committedAssets: bigint;
  sessionExpiry: number;
  enforceMerchantAllowlist: boolean;
  exists: boolean;
}

export interface AgentStatus {
  address: string;
  shares: bigint;
  assets: bigint;
  effectiveFloorAssets: bigint;
  gasTankShares: bigint;
  policy: AgentPolicy;
  isGrounded: boolean;
  availableSpend: bigint;
  sessionActive: boolean;
}

// ---------------------------------------------------------------------------
// Escrow / Invoice
// ---------------------------------------------------------------------------

export enum FulfillmentType {
  NONE = 0,
  DELIVERY = 1,
  SERVICE = 2,
  DIGITAL = 3,
  OTHER = 4,
}

export enum DisputeResolution {
  NONE = 0,
  RELEASE = 1,
  REFUND = 2,
}

export enum DisputeReason {
  NONE = 0,
  NON_DELIVERY = 1,
  QUALITY = 2,
  NOT_AS_DESCRIBED = 3,
  FRAUD_OR_CANCELLED = 4,
  OTHER = 5,
}

export enum EscrowStatus {
  NONE = 0,
  FUNDED = 1,
  RELEASED = 2,
  REFUNDED = 3,
}

export enum SettlementMode {
  NONE = 0,
  BUYER_RELEASE = 1,
  MERCHANT_TIMEOUT_RELEASE = 2,
  DISPUTE_TIMEOUT_RELEASE = 3,
  ARBITER_RELEASE = 4,
  BUYER_REFUND = 5,
  DISPUTE_TIMEOUT_REFUND = 6,
  ARBITER_REFUND = 7,
}

export interface InvoiceTerms {
  assetsDue: bigint;
  expiry: number;
  releaseAfter: number;
  maxNavAge: number;
  maxSharesIn: bigint;
  requiresFulfillment: boolean;
  fulfillmentType: FulfillmentType;
  requiredMilestones: number;
  challengeWindow: number;
  arbiterDeadline: number;
  disputeTimeoutResolution: DisputeResolution;
}

export interface EscrowInfo {
  id: bigint;
  buyer: string;
  merchant: string;
  refundRecipient: string;
  sharesHeld: bigint;
  principalAssetsSnapshot: bigint;
  committedAssets: bigint;
  releaseAfter: number;
  buyerBps: number;
  status: EscrowStatus;
  requiresFulfillment: boolean;
  fulfillmentType: FulfillmentType;
  disputed: boolean;
  disputeReason: DisputeReason;
  fulfilledAt: number;
  fulfillmentEvidence: string;
  resolution: DisputeResolution;
  resolvedAt: number;
  resolutionEvidence: string;
  challengeWindow: number;
  arbiterDeadline: number;
  timeoutResolution: DisputeResolution;
  disputedAt: number;
  settlementMode: SettlementMode;
  settledAt: number;
}

export interface ReleaseSplit {
  totalShares: bigint;
  principalShares: bigint;
  grossYieldShares: bigint;
  reserveShares: bigint;
  feeShares: bigint;
  buyerYieldShares: bigint;
  merchantYieldShares: bigint;
}

export interface SettlementPreview {
  status: EscrowStatus;
  releaseAfterPassed: boolean;
  fulfillmentSubmitted: boolean;
  fulfillmentComplete: boolean;
  disputeActive: boolean;
  disputeResolved: boolean;
  disputeTimedOut: boolean;
  requiresArbiterResolution: boolean;
  canBuyerRelease: boolean;
  canMerchantRelease: boolean;
  canArbiterRelease: boolean;
  canBuyerRefund: boolean;
  canArbiterRefund: boolean;
  canArbiterResolve: boolean;
  buyerReleaseMode: SettlementMode;
  merchantReleaseMode: SettlementMode;
  arbiterReleaseMode: SettlementMode;
  buyerRefundMode: SettlementMode;
  arbiterRefundMode: SettlementMode;
  requiredMilestones: number;
  completedMilestones: number;
  nextMilestoneNumber: number;
  disputedMilestone: number;
  challengeWindowEndsAt: number;
  disputeWindowEndsAt: number;
}

export type SettlementActionType =
  | "release"
  | "refund"
  | "resolve_dispute"
  | "execute_timeout";

export type SettlementActor =
  | "buyer"
  | "merchant"
  | "arbiter"
  | "anyone";

export interface SettlementAction {
  type: SettlementActionType;
  actor: SettlementActor;
  settlementMode?: SettlementMode;
  resolution?: DisputeResolution;
}

// ---------------------------------------------------------------------------
// System Status
// ---------------------------------------------------------------------------

export interface SystemStatus {
  transfersAllowed: boolean;
  navFresh: boolean;
  navConversionsAllowed: boolean;
  navUpdatesPaused: boolean;
  mintDepositAllowed: boolean;
  redeemWithdrawAllowed: boolean;
  requestRedeemAllowed: boolean;
  processQueueAllowed: boolean;
  queueSkipsBlockedClaims: boolean;
  bridgingAllowed: boolean;
  bridgeMintAllowed: boolean;
  gatewayRequired: boolean;
  escrowOpsPaused: boolean;
  paymasterPaused: boolean;
  bridgeOutstandingShares: bigint;
  bridgeOutstandingLimitShares: bigint;
  bridgeRemainingCapacityShares: bigint;
  minBridgeLiquidityCoverageBps: bigint;
  liabilityAssets: bigint;
  settlementAssetsAvailable: bigint;
  queueBufferAvailable: bigint;
  queueReservedAssets: bigint;
  queueDepth: bigint;
  liquidityCoverageBps: bigint;
  navRay: bigint;
  navEpoch: bigint;
  navLastUpdate: bigint;
  totalShareSupply: bigint;
  reserveManager: string;
  reserveFloor: bigint;
  reserveMaxDeployBps: bigint;
  reserveDeployedAssets: bigint;
}

export interface BridgeStatus {
  bridgePaused: boolean;
  bridgingAllowed: boolean;
  bridgeMintAllowed: boolean;
  outstandingShares: bigint;
  maxOutstandingShares: bigint;
  remainingMintCapacityShares: bigint;
}

export interface BridgeOutPreview extends BridgeStatus {
  dstChain: number;
  recipient: string;
  recipientBytes32: string;
  shares: bigint;
  assetsEquivalent: bigint;
  shareBalance: bigint;
  trustedPeer: string;
  routeTrusted: boolean;
  contractCanBridge: boolean;
  canBridgeNow: boolean;
}

// ---------------------------------------------------------------------------
// Transaction Results
// ---------------------------------------------------------------------------

export interface TxResult {
  txHash: string;
}

export interface DepositResult extends TxResult {
  sharesReceived: bigint;
}

export interface EscrowFundResult extends TxResult {
  escrowId: bigint;
  sharesLocked: bigint;
  assetsIn: bigint;
}

export interface RedeemRequestResult extends TxResult {
  claimId: bigint;
}

export interface GasTankTopUpResult extends TxResult {
  sharesDeposited: bigint;
}

export interface BridgeOutResult extends TxResult {
  msgId: string;
  dstChain: number;
  recipient: string;
  recipientBytes32: string;
  sharesBurned: bigint;
}

export interface EscrowDisputeResolutionResult extends TxResult {
  resolution: DisputeResolution;
}

export interface EscrowTimeoutExecutionResult extends TxResult {
  resolution: DisputeResolution;
  settlementMode: SettlementMode;
}

// ---------------------------------------------------------------------------
// Agent-to-Agent Payment Protocol
// ---------------------------------------------------------------------------

/** A machine-readable payment request one agent sends to another */
export interface PaymentRequest {
  /** Unique request ID (UUID or hash) */
  requestId: string;
  /** Address of the agent requesting payment (merchant/service provider) */
  payee: string;
  /** Amount in settlement asset units (e.g., USDC wei) */
  amount: bigint;
  /** Human/machine-readable description of the service */
  description: string;
  /** Invoice terms for escrow creation */
  terms: InvoiceTerms;
  /** Suggested buyer yield share in basis points */
  buyerBps: number;
  /** Expiry timestamp for this payment request */
  expiresAt: number;
  /** Optional: callback URL/endpoint for fulfillment notifications */
  callbackUrl?: string;
  /** Optional: structured metadata about the service */
  metadata?: Record<string, unknown>;
}

/** Result of accepting a payment request */
export interface PaymentAcceptance {
  requestId: string;
  escrowId: bigint;
  txHash: string;
  sharesLocked: bigint;
  estimatedYield: bigint;
}

/** Read-only quote for whether and how a payment request can be accepted now */
export interface PaymentAcceptancePreview {
  requestId: string;
  payee: string;
  assetsDue: bigint;
  principalAssetsSnapshot: bigint;
  estimatedAssetsIn: bigint;
  sharesLocked: bigint;
  projectedNavRay: bigint;
  estimatedYield: bigint;
  releaseAfter: number;
  expiresAt: number;
}

/** Fulfillment proof submitted by service provider agent */
export interface FulfillmentProof {
  escrowId: bigint;
  milestoneNumber: number;
  evidenceHash: string;
  fulfillmentType?: FulfillmentType;
  /** Structured proof data (IPFS CID, API response hash, etc.) */
  proofData?: Record<string, unknown>;
}
