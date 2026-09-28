/**
 * Set Chain SDK - Protected Payments
 *
 * Typed data and ABI fragments for ProtectedPayments: stablecoin payments with
 * buyer disputes, merchant responses, arbitrated partial refunds and
 * reserve-backed chargebacks. See docs/protected-payments.md.
 */

import { ZeroAddress, ZeroHash } from "ethers";
import { SDKError, SDKErrorCode } from "../errors.js";
import {
  validateAddress,
  validateBytes32,
  validateNonZeroAddress,
  validatePositiveAmount,
} from "../utils/validation.js";

export enum ProtectedPaymentStatus {
  NONE = 0,
  OPEN = 1,
  DISPUTED = 2,
  COMPLETED = 3,
  REFUNDED = 4,
}

export enum ProtectedDisputeStage {
  NONE = 0,
  AWAITING_MERCHANT = 1,
  ARBITRATION = 2,
  CLOSED = 3,
}

export enum ProtectedDisputeReason {
  NONE = 0,
  NOT_RECEIVED = 1,
  NOT_AS_DESCRIBED = 2,
  DEFECTIVE = 3,
  UNAUTHORIZED = 4,
  DUPLICATE = 5,
  CANCELLED = 6,
  OTHER = 7,
}

export enum ProtectedDisputeOutcome {
  NONE = 0,
  MERCHANT_ACCEPTED = 1,
  MERCHANT_DEFAULT = 2,
  SETTLED = 3,
  ARBITRATED = 4,
  ARBITER_TIMEOUT = 5,
}

/** Merchant-signed payment offer. `buyer` may be the zero address for open offers. */
export interface ProtectedPaymentTerms {
  chainId: bigint;
  contractAddress: string;
  buyer: string;
  merchant: string;
  token: string;
  amount: bigint;
  /** Named arbiter, or the zero address to use the network default. */
  arbiter: string;
  fulfillBy: bigint;
  protectionWindow: bigint;
  orderRef: string;
  deadline: bigint;
}

/**
 * Build the EIP-712 payload a merchant signs to offer a protected payment.
 * Does not check chain state: arbiter eligibility, window bounds, token
 * allowlisting and order-reference reuse are enforced on-chain by `pay`.
 */
export function buildProtectedPaymentTypedData(terms: ProtectedPaymentTerms) {
  for (const [name, value, bits] of [
    ["chainId", terms.chainId, 256n],
    ["amount", terms.amount, 128n],
    ["fulfillBy", terms.fulfillBy, 64n],
    ["protectionWindow", terms.protectionWindow, 32n],
    ["deadline", terms.deadline, 64n],
  ] as const) {
    validatePositiveAmount(value, name);
    if (value >= 1n << bits) {
      throw new SDKError(SDKErrorCode.VALIDATION_ERROR, `${name} exceeds uint${bits}`);
    }
  }
  const orderRef = validateBytes32(terms.orderRef, "orderRef");
  if (orderRef === ZeroHash) throw new SDKError(SDKErrorCode.VALIDATION_ERROR, "orderRef cannot be zero");
  const contractAddress = validateNonZeroAddress(terms.contractAddress, "contractAddress");
  const merchant = validateNonZeroAddress(terms.merchant, "merchant");
  const buyer = validateAddress(terms.buyer, "buyer");
  const arbiter = validateAddress(terms.arbiter, "arbiter");
  if (buyer === merchant) throw new SDKError(SDKErrorCode.VALIDATION_ERROR, "buyer cannot be the merchant");
  if (arbiter !== ZeroAddress && (arbiter === merchant || arbiter === buyer)) {
    throw new SDKError(SDKErrorCode.VALIDATION_ERROR, "arbiter cannot be a party to the payment");
  }
  return {
    domain: { name: "SetProtectedPayments", version: "1", chainId: terms.chainId, verifyingContract: contractAddress },
    types: {
      PaymentTerms: [
        { name: "buyer", type: "address" },
        { name: "merchant", type: "address" },
        { name: "token", type: "address" },
        { name: "amount", type: "uint128" },
        { name: "arbiter", type: "address" },
        { name: "fulfillBy", type: "uint64" },
        { name: "protectionWindow", type: "uint32" },
        { name: "orderRef", type: "bytes32" },
        { name: "deadline", type: "uint64" },
      ],
    },
    value: {
      buyer,
      merchant,
      token: validateNonZeroAddress(terms.token, "token"),
      amount: terms.amount,
      arbiter,
      fulfillBy: terms.fulfillBy,
      protectionWindow: terms.protectionWindow,
      orderRef,
      deadline: terms.deadline,
    },
  };
}

const TERMS_TUPLE =
  "(address buyer,address merchant,address token,uint128 amount,address arbiter,uint64 fulfillBy,uint32 protectionWindow,bytes32 orderRef,uint64 deadline)";

export const protectedPaymentsAbi = [
  `function pay(${TERMS_TUPLE} terms, bytes merchantSignature) returns (uint256)`,
  `function hashTerms(${TERMS_TUPLE} terms) view returns (bytes32)`,
  "function markFulfilled(uint256 paymentId, bytes32 evidenceHash)",
  "function confirm(uint256 paymentId)",
  "function finalize(uint256 paymentId)",
  "function cancelUnfulfilled(uint256 paymentId)",
  "function merchantRefund(uint256 paymentId, uint128 amount)",
  "function openDispute(uint256 paymentId, uint8 reason, uint128 requested, bytes32 evidenceHash)",
  "function acceptDispute(uint256 paymentId)",
  "function contest(uint256 paymentId, bytes32 evidenceHash)",
  "function executeDefault(uint256 paymentId)",
  "function proposeSettlement(uint256 paymentId, uint128 refundAmount)",
  "function resolve(uint256 paymentId, uint128 refundAmount, bytes32 rulingHash)",
  "function arbiterTimeout(uint256 paymentId)",
  "function attachVerifiedEvidence(uint256 paymentId, bytes32 batchId, bytes32 leaf, bytes32[] proof, uint256 index)",
  "function depositReserve(address token, uint128 amount)",
  "function withdrawReserve(address token, uint128 amount)",
  "function fundPool(address token, uint128 amount)",
  "function claimPending(uint256 paymentId)",
  "function withdraw(address token)",
  "function credits(address token, address account) view returns (uint256)",
  "function reserves(address merchant, address token) view returns (uint128 free, uint128 locked, uint128 debt)",
  "function poolBalance(address token) view returns (uint256)",
  "function pendingClaims(uint256 paymentId) view returns (uint128)",
  "function protectionEndsAt(uint256 paymentId) view returns (uint64)",
  "function instantCapacity(address merchant, address token) view returns (uint256)",
  "function getPayment(uint256 paymentId) view returns ((address buyer,address merchant,address token,address arbiter,uint128 amount,uint128 held,uint128 reserveLocked,uint128 refunded,uint64 createdAt,uint64 fulfillBy,uint64 fulfilledAt,uint32 protectionWindow,uint16 protocolFeeBps,uint16 protectionFeeBps,uint8 status,bool instant,bytes32 orderRef))",
  "function getDispute(uint256 paymentId) view returns ((uint8 stage,uint8 reason,uint8 outcome,bool reassigned,address arbiter,uint64 openedAt,uint64 deadline,uint128 requested,uint128 buyerBond,uint128 merchantFee,uint128 refundAwarded,uint136 buyerProposal,uint136 merchantProposal))",
  "event PaymentCreated(uint256 indexed paymentId, address indexed buyer, address indexed merchant, address token, uint256 amount, address arbiter, bytes32 orderRef, bool instant, uint256 reserveLocked)",
  "event PaymentFulfilled(uint256 indexed paymentId, bytes32 evidenceHash, uint64 protectionEndsAt)",
  "event PaymentCompleted(uint256 indexed paymentId, uint256 merchantNet, uint256 protocolFee, uint256 protectionFee)",
  "event PaymentRefunded(uint256 indexed paymentId, uint256 amount, uint256 totalRefunded, bool full)",
  "event DisputeOpened(uint256 indexed paymentId, uint8 indexed reason, uint256 requested, uint256 bond, bytes32 evidenceHash)",
  "event DisputeContested(uint256 indexed paymentId, address indexed arbiter, uint256 fee, bytes32 evidenceHash)",
  "event DisputeClosed(uint256 indexed paymentId, uint8 indexed outcome, uint256 refundAwarded, bytes32 rulingHash)",
  "event RefundSourced(uint256 indexed paymentId, uint256 fromLocked, uint256 fromFree, uint256 fromPool, uint256 pending)",
] as const;

export const arbiterRegistryAbi = [
  "function isEligible(address arbiter) view returns (bool)",
  "function arbiters(address arbiter) view returns (bool approved, uint128 bond, uint32 openCases, uint32 casesResolved, uint32 casesMissed, uint64 exitRequestedAt, bytes32 metadataHash)",
  "function depositBond(uint128 amount)",
  "function withdrawExcessBond(uint128 amount)",
  "function requestExit()",
  "function completeExit()",
  "function setMetadata(bytes32 metadataHash)",
  "function minBond() view returns (uint128)",
] as const;
