/** Enums mirroring ProtectedPayments.sol. */

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
