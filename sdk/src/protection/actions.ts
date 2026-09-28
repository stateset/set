/**
 * Pure derivation of what each party may do with a protected payment right now.
 * Mirrors the guards in ProtectedPayments.sol so agents and UIs can offer only
 * transactions that will not revert on timing or authorization.
 */

import { ProtectedDisputeStage, ProtectedPaymentStatus } from "./types.js";

export interface ProtectedPayment {
  buyer: string;
  merchant: string;
  token: string;
  arbiter: string;
  amount: bigint;
  held: bigint;
  reserveLocked: bigint;
  refunded: bigint;
  createdAt: bigint;
  fulfillBy: bigint;
  fulfilledAt: bigint;
  protectionWindow: bigint;
  protocolFeeBps: bigint;
  protectionFeeBps: bigint;
  status: ProtectedPaymentStatus;
  instant: boolean;
  orderRef: string;
}

export interface ProtectedDispute {
  stage: ProtectedDisputeStage;
  reason: number;
  outcome: number;
  reassigned: boolean;
  arbiter: string;
  openedAt: bigint;
  deadline: bigint;
  requested: bigint;
  buyerBond: bigint;
  merchantFee: bigint;
  refundAwarded: bigint;
  buyerProposal: bigint;
  merchantProposal: bigint;
}

export type ProtectedPaymentAction =
  | "markFulfilled"
  | "confirm"
  | "finalize"
  | "cancelUnfulfilled"
  | "merchantRefund"
  | "openDispute"
  | "acceptDispute"
  | "contest"
  | "executeDefault"
  | "proposeSettlement"
  | "resolve"
  | "arbiterTimeout"
  | "claimPending";

export type ProtectedPaymentRole = "buyer" | "merchant" | "arbiter" | "other";

export interface ActionContext {
  payment: ProtectedPayment;
  dispute?: ProtectedDispute;
  /** Current chain timestamp in seconds (use the latest block, not the local clock). */
  now: bigint;
  account: string;
  /** Unpaid refund recorded for this payment, and the pool that pays it. */
  pendingClaim?: bigint;
  poolBalance?: bigint;
}

export interface ActionSummary {
  role: ProtectedPaymentRole;
  actions: ProtectedPaymentAction[];
  /** Dispute cutoff while fulfilled; 0 while unfulfilled (disputable any time). */
  protectionEndsAt: bigint;
  /** The next timestamp at which the available actions change, if any. */
  nextDeadline?: bigint;
}

const same = (a: string, b: string) => a.toLowerCase() === b.toLowerCase();

export function derivePaymentActions(ctx: ActionContext): ActionSummary {
  const { payment: p, dispute: d, now, account } = ctx;
  const isBuyer = same(account, p.buyer);
  const isMerchant = same(account, p.merchant);
  const isArbiter = !!d && d.stage === ProtectedDisputeStage.ARBITRATION && same(account, d.arbiter);
  const role: ProtectedPaymentRole = isBuyer ? "buyer" : isMerchant ? "merchant" : isArbiter ? "arbiter" : "other";
  const protectionEndsAt = p.fulfilledAt === 0n ? 0n : p.fulfilledAt + p.protectionWindow;
  const actions: ProtectedPaymentAction[] = [];
  let nextDeadline: bigint | undefined;
  const remaining = p.amount - p.refunded;

  if (p.status === ProtectedPaymentStatus.OPEN) {
    const fulfilled = p.fulfilledAt !== 0n;
    if (isMerchant && !fulfilled && now <= p.fulfillBy) actions.push("markFulfilled");
    if (isBuyer) actions.push("confirm");
    if (fulfilled && now >= protectionEndsAt) actions.push("finalize");
    if (!fulfilled && now > p.fulfillBy) {
      if (isBuyer || now >= p.fulfillBy + p.protectionWindow) actions.push("cancelUnfulfilled");
    }
    if (isMerchant && remaining > 0n) actions.push("merchantRefund");
    if (isBuyer && remaining > 0n && (!fulfilled || now < protectionEndsAt)) actions.push("openDispute");
    nextDeadline = fulfilled ? (now < protectionEndsAt ? protectionEndsAt : undefined) : now <= p.fulfillBy ? p.fulfillBy + 1n : undefined;
  } else if (p.status === ProtectedPaymentStatus.DISPUTED && d) {
    if (d.stage === ProtectedDisputeStage.AWAITING_MERCHANT) {
      if (isMerchant) actions.push("acceptDispute");
      if (isMerchant && now < d.deadline) actions.push("contest");
      if (now >= d.deadline) actions.push("executeDefault");
      if (isBuyer || isMerchant) actions.push("proposeSettlement");
      if (now < d.deadline) nextDeadline = d.deadline;
    } else if (d.stage === ProtectedDisputeStage.ARBITRATION) {
      if (isArbiter && now < d.deadline) actions.push("resolve");
      if (now >= d.deadline) actions.push("arbiterTimeout");
      if (isBuyer || isMerchant) actions.push("proposeSettlement");
      if (now < d.deadline) nextDeadline = d.deadline;
    }
  }

  if ((ctx.pendingClaim ?? 0n) > 0n && (ctx.poolBalance ?? 0n) > 0n) actions.push("claimPending");

  return { role, actions, protectionEndsAt, nextDeadline };
}
