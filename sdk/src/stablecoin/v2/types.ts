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

// ---------------------------------------------------------------------------
// System Status
// ---------------------------------------------------------------------------

export interface SystemStatus {
  transfersAllowed: boolean;
  navFresh: boolean;
  navConversionsAllowed: boolean;
  mintDepositAllowed: boolean;
  redeemWithdrawAllowed: boolean;
  requestRedeemAllowed: boolean;
  processQueueAllowed: boolean;
  bridgingAllowed: boolean;
  escrowOpsPaused: boolean;
  paymasterPaused: boolean;
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

/** Fulfillment proof submitted by service provider agent */
export interface FulfillmentProof {
  escrowId: bigint;
  milestoneNumber: number;
  evidenceHash: string;
  /** Structured proof data (IPFS CID, API response hash, etc.) */
  proofData?: Record<string, unknown>;
}
