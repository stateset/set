/**
 * Set Chain SDK - Protected Payments
 *
 * Stablecoin payments with buyer disputes, merchant responses, arbitrated
 * partial refunds and reserve-backed chargebacks. See docs/protected-payments.md.
 */

export {
  ProtectedPaymentStatus,
  ProtectedDisputeStage,
  ProtectedDisputeReason,
  ProtectedDisputeOutcome,
} from "./types.js";
export { buildProtectedPaymentTypedData } from "./typed-data.js";
export type { ProtectedPaymentTerms } from "./typed-data.js";
export { protectedPaymentsAbi, arbiterRegistryAbi } from "./abis.js";
export { derivePaymentActions } from "./actions.js";
export type {
  ProtectedPayment,
  ProtectedDispute,
  ProtectedPaymentAction,
  ProtectedPaymentRole,
  ActionContext,
  ActionSummary,
} from "./actions.js";
export { ProtectedPaymentsClient } from "./client.js";
export type { ProtectedParams, PartyStats, ProtectedTxResult } from "./client.js";
