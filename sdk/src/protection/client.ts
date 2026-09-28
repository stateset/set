/**
 * High-level client for ProtectedPayments. Reads decode into typed records;
 * writes wait for one confirmation and return the receipt hash. Amounts are raw
 * token units. The client does not verify finality: see docs/commerce-finality.md.
 */

import { Contract } from "ethers";
import type { ContractRunner, Signer } from "ethers";
import { protectedPaymentsAbi } from "./abis.js";
import { derivePaymentActions } from "./actions.js";
import type { ActionSummary, ProtectedDispute, ProtectedPayment } from "./actions.js";
import { buildProtectedPaymentTypedData } from "./typed-data.js";
import type { ProtectedPaymentTerms } from "./typed-data.js";
import { ProtectedDisputeReason } from "./types.js";
import { SDKError, SDKErrorCode, TransactionFailedError } from "../errors.js";
import { validateBytes32, validateNonZeroAddress, validatePositiveAmount } from "../utils/validation.js";

const erc20Abi = [
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
] as const;

export interface ProtectedParams {
  minProtectionWindow: bigint;
  maxProtectionWindow: bigint;
  merchantResponseWindow: bigint;
  arbitrationWindow: bigint;
  maxDisputeRatioBps: bigint;
  minPaymentsForRatio: bigint;
}

export interface PartyStats {
  payments: bigint;
  disputes: bigint;
  lost: bigint;
}

export interface ProtectedTxResult {
  hash: string;
  paymentId?: bigint;
}

type TxFn = (...args: unknown[]) => Promise<{ wait: () => Promise<{ hash: string; status?: number | null; logs: readonly unknown[] } | null> }>;

export class ProtectedPaymentsClient {
  readonly address: string;
  private readonly contract: Contract;
  private readonly runner: ContractRunner;

  constructor(address: string, runner: ContractRunner) {
    this.address = validateNonZeroAddress(address, "address");
    this.runner = runner;
    this.contract = new Contract(this.address, protectedPaymentsAbi, runner);
  }

  // ─── reads ──────────────────────────────────────────────────────────────

  async getPayment(paymentId: bigint): Promise<ProtectedPayment> {
    const r = await this.contract.getPayment(paymentId);
    return {
      buyer: r.buyer,
      merchant: r.merchant,
      token: r.token,
      arbiter: r.arbiter,
      amount: r.amount,
      held: r.held,
      reserveLocked: r.reserveLocked,
      refunded: r.refunded,
      createdAt: r.createdAt,
      fulfillBy: r.fulfillBy,
      fulfilledAt: r.fulfilledAt,
      protectionWindow: r.protectionWindow,
      protocolFeeBps: r.protocolFeeBps,
      protectionFeeBps: r.protectionFeeBps,
      status: Number(r.status),
      instant: r.instant,
      orderRef: r.orderRef,
    };
  }

  async getDispute(paymentId: bigint): Promise<ProtectedDispute> {
    const r = await this.contract.getDispute(paymentId);
    return {
      stage: Number(r.stage),
      reason: Number(r.reason),
      outcome: Number(r.outcome),
      reassigned: r.reassigned,
      arbiter: r.arbiter,
      openedAt: r.openedAt,
      deadline: r.deadline,
      requested: r.requested,
      buyerBond: r.buyerBond,
      merchantFee: r.merchantFee,
      refundAwarded: r.refundAwarded,
      buyerProposal: r.buyerProposal,
      merchantProposal: r.merchantProposal,
    };
  }

  async getParams(): Promise<ProtectedParams> {
    const r = await this.contract.params();
    return {
      minProtectionWindow: r.minProtectionWindow,
      maxProtectionWindow: r.maxProtectionWindow,
      merchantResponseWindow: r.merchantResponseWindow,
      arbitrationWindow: r.arbitrationWindow,
      maxDisputeRatioBps: r.maxDisputeRatioBps,
      minPaymentsForRatio: r.minPaymentsForRatio,
    };
  }

  async getMerchantStats(merchant: string): Promise<PartyStats & { ratioBps: bigint; instantRevoked: boolean }> {
    const m = validateNonZeroAddress(merchant, "merchant");
    const [s, ratioBps, instantRevoked] = await Promise.all([
      this.contract.merchantStats(m),
      this.contract.disputeRatioBps(m),
      this.contract.disputeRatioExceeded(m),
    ]);
    return { payments: s.payments, disputes: s.disputes, lost: s.lost, ratioBps, instantRevoked };
  }

  async getBuyerStats(buyer: string): Promise<PartyStats> {
    const s = await this.contract.buyerStats(validateNonZeroAddress(buyer, "buyer"));
    return { payments: s.payments, disputes: s.disputes, lost: s.lost };
  }

  async getReserve(merchant: string, token: string): Promise<{ free: bigint; locked: bigint; debt: bigint }> {
    const r = await this.contract.reserves(validateNonZeroAddress(merchant, "merchant"), validateNonZeroAddress(token, "token"));
    return { free: r.free, locked: r.locked, debt: r.debt };
  }

  async getCredits(token: string, account: string): Promise<bigint> {
    return this.contract.credits(validateNonZeroAddress(token, "token"), validateNonZeroAddress(account, "account"));
  }

  /**
   * What `account` can do with a payment at the latest block's timestamp.
   * Timing and authorization only: balances, allowances, arbiter eligibility
   * and paused state are checked by the contract when the transaction runs.
   */
  async actionsFor(paymentId: bigint, account: string): Promise<ActionSummary> {
    const provider = this.runner.provider;
    if (!provider) throw new SDKError(SDKErrorCode.VALIDATION_ERROR, "runner has no provider");
    const payment = await this.getPayment(paymentId);
    const [dispute, block, pendingClaim, poolBalance] = await Promise.all([
      this.getDispute(paymentId),
      provider.getBlock("latest"),
      this.contract.pendingClaims(paymentId) as Promise<bigint>,
      this.contract.poolBalance(payment.token) as Promise<bigint>,
    ]);
    if (!block) throw new SDKError(SDKErrorCode.RPC_ERROR, "latest block unavailable");
    return derivePaymentActions({
      payment,
      dispute,
      now: BigInt(block.timestamp),
      account: validateNonZeroAddress(account, "account"),
      pendingClaim,
      poolBalance,
    });
  }

  // ─── merchant offers ────────────────────────────────────────────────────

  /** Merchant signs payment terms for this contract on the signer's chain. */
  async signTerms(merchant: Signer, terms: Omit<ProtectedPaymentTerms, "chainId" | "contractAddress">): Promise<string> {
    const network = await merchant.provider?.getNetwork();
    if (!network) throw new SDKError(SDKErrorCode.VALIDATION_ERROR, "merchant signer has no provider");
    const data = buildProtectedPaymentTypedData({ ...terms, chainId: network.chainId, contractAddress: this.address });
    return merchant.signTypedData(data.domain, data.types, data.value);
  }

  // ─── writes ─────────────────────────────────────────────────────────────

  /** Pay signed terms, approving the exact shortfall first when needed. */
  async pay(terms: Omit<ProtectedPaymentTerms, "chainId" | "contractAddress">, merchantSignature: string): Promise<ProtectedTxResult> {
    validatePositiveAmount(terms.amount, "amount");
    await this.ensureAllowance(terms.token, terms.amount);
    const tuple = [
      terms.buyer, terms.merchant, terms.token, terms.amount, terms.arbiter,
      terms.fulfillBy, terms.protectionWindow, terms.orderRef, terms.deadline,
    ];
    const receipt = await this.send("pay", tuple, merchantSignature);
    let paymentId: bigint | undefined;
    for (const log of receipt.logs as { topics: string[]; data: string }[]) {
      try {
        const parsed = this.contract.interface.parseLog(log);
        if (parsed?.name === "PaymentCreated") paymentId = parsed.args.paymentId;
      } catch {
        // Not a ProtectedPayments log (e.g. the token's Transfer event).
      }
    }
    return { hash: receipt.hash, paymentId };
  }

  markFulfilled(paymentId: bigint, evidenceHash: string) {
    return this.send("markFulfilled", paymentId, validateBytes32(evidenceHash, "evidenceHash"));
  }

  confirm(paymentId: bigint) {
    return this.send("confirm", paymentId);
  }

  finalize(paymentId: bigint) {
    return this.send("finalize", paymentId);
  }

  cancelUnfulfilled(paymentId: bigint) {
    return this.send("cancelUnfulfilled", paymentId);
  }

  async merchantRefund(paymentId: bigint, amount: bigint) {
    validatePositiveAmount(amount, "amount");
    const p = await this.getPayment(paymentId);
    if (p.instant) await this.ensureAllowance(p.token, amount);
    return this.send("merchantRefund", paymentId, amount);
  }

  /** Buyer disputes `requested` units, approving the network dispute bond if needed. */
  async openDispute(paymentId: bigint, reason: ProtectedDisputeReason, requested: bigint, evidenceHash: string) {
    if (reason === ProtectedDisputeReason.NONE) throw new SDKError(SDKErrorCode.VALIDATION_ERROR, "reason is required");
    validatePositiveAmount(requested, "requested");
    const p = await this.getPayment(paymentId);
    const cfg = await this.contract.tokenConfig(p.token);
    if (cfg.buyerDisputeBond > 0n) await this.ensureAllowance(p.token, cfg.buyerDisputeBond);
    return this.send("openDispute", paymentId, reason, requested, validateBytes32(evidenceHash, "evidenceHash"));
  }

  acceptDispute(paymentId: bigint) {
    return this.send("acceptDispute", paymentId);
  }

  /** Merchant contests, approving the arbitration fee if needed. */
  async contest(paymentId: bigint, evidenceHash: string) {
    const p = await this.getPayment(paymentId);
    const cfg = await this.contract.tokenConfig(p.token);
    if (cfg.arbitrationFee > 0n) await this.ensureAllowance(p.token, cfg.arbitrationFee);
    return this.send("contest", paymentId, validateBytes32(evidenceHash, "evidenceHash"));
  }

  executeDefault(paymentId: bigint) {
    return this.send("executeDefault", paymentId);
  }

  proposeSettlement(paymentId: bigint, refundAmount: bigint) {
    if (refundAmount < 0n) throw new SDKError(SDKErrorCode.INVALID_AMOUNT, "refundAmount cannot be negative");
    return this.send("proposeSettlement", paymentId, refundAmount);
  }

  resolve(paymentId: bigint, refundAmount: bigint, rulingHash: string) {
    return this.send("resolve", paymentId, refundAmount, validateBytes32(rulingHash, "rulingHash"));
  }

  arbiterTimeout(paymentId: bigint) {
    return this.send("arbiterTimeout", paymentId);
  }

  attachVerifiedEvidence(paymentId: bigint, batchId: string, leaf: string, proof: string[], index: bigint) {
    return this.send("attachVerifiedEvidence", paymentId, validateBytes32(batchId, "batchId"), validateBytes32(leaf, "leaf"), proof, index);
  }

  async depositReserve(token: string, amount: bigint) {
    validatePositiveAmount(amount, "amount");
    await this.ensureAllowance(token, amount);
    return this.send("depositReserve", validateNonZeroAddress(token, "token"), amount);
  }

  withdrawReserve(token: string, amount: bigint) {
    return this.send("withdrawReserve", validateNonZeroAddress(token, "token"), amount);
  }

  claimPending(paymentId: bigint) {
    return this.send("claimPending", paymentId);
  }

  withdraw(token: string) {
    return this.send("withdraw", validateNonZeroAddress(token, "token"));
  }

  // ─── internals ──────────────────────────────────────────────────────────

  private async ensureAllowance(token: string, amount: bigint): Promise<void> {
    const signer = this.runner as Signer;
    if (typeof signer.getAddress !== "function") {
      throw new SDKError(SDKErrorCode.VALIDATION_ERROR, "a signer is required for writes");
    }
    const erc20 = new Contract(validateNonZeroAddress(token, "token"), erc20Abi, signer);
    const owner = await signer.getAddress();
    const current: bigint = await erc20.allowance(owner, this.address);
    if (current >= amount) return;
    // Approve only what this call needs; never an unlimited allowance.
    const tx = await erc20.approve(this.address, amount);
    const receipt = await tx.wait();
    if (!receipt || receipt.status === 0) throw new TransactionFailedError("approve failed", receipt?.hash);
  }

  private async send(method: string, ...args: unknown[]): Promise<ProtectedTxResult & { logs: readonly unknown[] }> {
    const fn = this.contract.getFunction(method) as unknown as TxFn;
    const tx = await fn(...args);
    const receipt = await tx.wait();
    if (!receipt || receipt.status === 0) throw new TransactionFailedError(`${method} reverted`, receipt?.hash);
    return { hash: receipt.hash, logs: receipt.logs };
  }
}
