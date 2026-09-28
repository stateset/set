import { describe, expect, it } from "vitest";
import { ZeroAddress, ZeroHash } from "ethers";
import {
  ProtectedDisputeStage,
  ProtectedPaymentStatus,
  derivePaymentActions,
} from "../src/protection/index.js";
import type { ProtectedDispute, ProtectedPayment } from "../src/protection/index.js";

const buyer = "0x" + "b0".repeat(20);
const merchant = "0x" + "c0".repeat(20);
const arbiter = "0x" + "a1".repeat(20);
const stranger = "0x" + "57".repeat(20);
const DAY = 86_400n;

const payment = (over: Partial<ProtectedPayment> = {}): ProtectedPayment => ({
  buyer, merchant, token: "0x" + "44".repeat(20), arbiter,
  amount: 1_000n, held: 1_000n, reserveLocked: 0n, refunded: 0n,
  createdAt: 1_000n, fulfillBy: 1_000n + 7n * DAY, fulfilledAt: 0n, protectionWindow: 30n * DAY,
  protocolFeeBps: 100n, protectionFeeBps: 50n, status: ProtectedPaymentStatus.OPEN, instant: false, orderRef: ZeroHash,
  ...over,
});

const dispute = (over: Partial<ProtectedDispute> = {}): ProtectedDispute => ({
  stage: ProtectedDisputeStage.AWAITING_MERCHANT, reason: 2, outcome: 0, reassigned: false, arbiter: ZeroAddress,
  openedAt: 2_000n, deadline: 2_000n + 3n * DAY, requested: 500n, buyerBond: 25n, merchantFee: 0n,
  refundAwarded: 0n, buyerProposal: 0n, merchantProposal: 0n,
  ...over,
});

const actions = (p: ProtectedPayment, account: string, now: bigint, d?: ProtectedDispute) =>
  derivePaymentActions({ payment: p, dispute: d, account, now }).actions;

describe("derivePaymentActions — open payments", () => {
  it("unfulfilled: merchant fulfills or refunds, buyer confirms or disputes", () => {
    const p = payment();
    expect(actions(p, merchant, 2_000n)).toEqual(["markFulfilled", "merchantRefund"]);
    expect(actions(p, buyer, 2_000n)).toEqual(["confirm", "openDispute"]);
    expect(actions(p, stranger, 2_000n)).toEqual([]);
  });

  it("past fulfillBy: buyer can cancel, strangers only after the grace window", () => {
    const p = payment();
    const late = p.fulfillBy + 1n;
    expect(actions(p, merchant, late)).not.toContain("markFulfilled");
    expect(actions(p, buyer, late)).toContain("cancelUnfulfilled");
    expect(actions(p, stranger, late)).toEqual([]);
    expect(actions(p, stranger, p.fulfillBy + p.protectionWindow)).toEqual(["cancelUnfulfilled"]);
  });

  it("fulfilled: disputable until the window closes, then anyone finalizes", () => {
    const p = payment({ fulfilledAt: 5_000n });
    const end = 5_000n + 30n * DAY;
    const summary = derivePaymentActions({ payment: p, account: buyer, now: end - 1n });
    expect(summary.protectionEndsAt).toBe(end);
    expect(summary.nextDeadline).toBe(end);
    expect(summary.actions).toEqual(["confirm", "openDispute"]);
    expect(actions(p, buyer, end)).toEqual(["confirm", "finalize"]);
    expect(actions(p, stranger, end)).toEqual(["finalize"]);
  });

  it("fully refunded amount leaves nothing to dispute or refund", () => {
    const p = payment({ refunded: 1_000n });
    expect(actions(p, buyer, 2_000n)).not.toContain("openDispute");
    expect(actions(p, merchant, 2_000n)).not.toContain("merchantRefund");
  });

  it("matches addresses case-insensitively", () => {
    expect(derivePaymentActions({ payment: payment(), account: buyer.toUpperCase().replace("0X", "0x"), now: 2_000n }).role).toBe("buyer");
  });
});

describe("derivePaymentActions — disputes", () => {
  const disputed = payment({ status: ProtectedPaymentStatus.DISPUTED, fulfilledAt: 1_500n });

  it("awaiting merchant: accept, contest, or negotiate before the deadline", () => {
    const d = dispute();
    expect(actions(disputed, merchant, 3_000n, d)).toEqual(["acceptDispute", "contest", "proposeSettlement"]);
    expect(actions(disputed, buyer, 3_000n, d)).toEqual(["proposeSettlement"]);
    expect(derivePaymentActions({ payment: disputed, dispute: d, account: buyer, now: 3_000n }).nextDeadline).toBe(d.deadline);
  });

  it("merchant silence opens default execution to anyone", () => {
    const d = dispute();
    expect(actions(disputed, merchant, d.deadline, d)).toEqual(["acceptDispute", "executeDefault", "proposeSettlement"]);
    expect(actions(disputed, stranger, d.deadline, d)).toEqual(["executeDefault"]);
  });

  it("arbitration: only the case arbiter resolves, anyone enforces the deadline", () => {
    const d = dispute({ stage: ProtectedDisputeStage.ARBITRATION, arbiter, deadline: 10_000n });
    const early = derivePaymentActions({ payment: disputed, dispute: d, account: arbiter, now: 9_999n });
    expect(early.role).toBe("arbiter");
    expect(early.actions).toEqual(["resolve"]);
    expect(actions(disputed, stranger, 9_999n, d)).toEqual([]);
    expect(actions(disputed, arbiter, 10_000n, d)).toEqual(["arbiterTimeout"]);
    expect(actions(disputed, buyer, 10_000n, d)).toEqual(["arbiterTimeout", "proposeSettlement"]);
  });

  it("the payment's named arbiter has no power before a case is contested", () => {
    expect(derivePaymentActions({ payment: disputed, dispute: dispute(), account: arbiter, now: 3_000n }).role).toBe("other");
  });
});

describe("derivePaymentActions — settled payments", () => {
  it("offers nothing on completed payments except pending claims with pool liquidity", () => {
    const p = payment({ status: ProtectedPaymentStatus.REFUNDED, instant: true });
    expect(actions(p, buyer, 9_999_999n)).toEqual([]);
    expect(derivePaymentActions({ payment: p, account: stranger, now: 1n, pendingClaim: 10n, poolBalance: 0n }).actions).toEqual([]);
    expect(derivePaymentActions({ payment: p, account: stranger, now: 1n, pendingClaim: 10n, poolBalance: 5n }).actions).toEqual(["claimPending"]);
  });
});
