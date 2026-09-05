import { id } from "ethers";
import { withRpcDeadline, type VerificationOptions } from "./rpc-deadline.js";
import { validateNonZeroAddress } from "../utils/validation.js";
import { inspectTransactionFinality, type FinalityObservation, type FinalityRpc } from "./finality.js";

export interface ERC20PaymentExpectation {
  chainId: bigint;
  transactionHash: string;
  /** Block-wide log index, not the position in receipt.logs. */
  logIndex: bigint;
  token: string;
  payer: string;
  recipient: string;
  /** Exact amount in raw token units. Zero-value events are not payments. */
  amount: bigint;
}

export type ERC20PaymentVerification = {
  status: "waiting" | "rejected";
  reason: "insufficient_finality" | "execution_reverted" | "transfer_mismatch" | "receipt_changed";
  observation: FinalityObservation;
} | {
  status: "verified";
  observation: FinalityObservation;
  /** Globally consume once in the merchant ledger; do not scope uniqueness to order ID. */
  eventKey: string;
  token: string;
  payer: string;
  recipient: string;
  amount: string;
};

const transferTopic = id("Transfer(address,address,uint256)").toLowerCase();

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Malformed payment RPC data");
  return value as Record<string, unknown>;
}

function quantity(value: unknown): bigint {
  if (typeof value !== "string" || !/^0x(?:0|[1-9a-fA-F][0-9a-fA-F]*)$/.test(value)) {
    throw new Error("Malformed payment RPC quantity");
  }
  return BigInt(value);
}

function equalHex(value: unknown, expected: string): boolean {
  return typeof value === "string" && value.toLowerCase() === expected.toLowerCase();
}

function addressTopic(address: string): string {
  return "0x" + "0".repeat(24) + address.slice(2).toLowerCase();
}

/**
 * Verify one exact ERC-20 Transfer event on at least two distinct RPC sources.
 * Defaults to finalized inclusion. This is RPC evidence for allowlisted standard
 * tokens, not proof of asset backing, order intent or net balance change. A merchant
 * must atomically consume eventKey once and bind it to the authenticated order.
 */
export async function verifyERC20Payment(
  sources: readonly FinalityRpc[], expected: ERC20PaymentExpectation,
  minimumFinality: "safe" | "finalized" = "finalized", options: VerificationOptions = {}
): Promise<ERC20PaymentVerification> {
  const observedAt = new Date().toISOString();
  // Expectations and policy must not change while RPC requests are in flight.
  const terms = { ...expected };
  const policy = { ...options };
  const result = await withRpcDeadline(sources, policy,
    bounded => verifyPayment(bounded, terms, minimumFinality, policy));
  // A later finality check cannot make earlier event evidence fresh again.
  return { ...result, observation: { ...result.observation, observedAt } };
}

async function verifyPayment(
  sources: readonly FinalityRpc[], expected: ERC20PaymentExpectation,
  minimumFinality: "safe" | "finalized", options: VerificationOptions
): Promise<ERC20PaymentVerification> {
  if (sources.length < 2 || new Set(sources).size !== sources.length) {
    throw new Error("Payment verification requires at least two distinct RPC sources");
  }
  if ((minimumFinality !== "safe" && minimumFinality !== "finalized") ||
      typeof expected.amount !== "bigint" || expected.amount <= 0n || expected.amount >= 2n ** 256n ||
      typeof expected.logIndex !== "bigint" || expected.logIndex < 0n) {
    throw new Error("Invalid payment amount, event index or finality policy");
  }
  const token = validateNonZeroAddress(expected.token, "token");
  const payer = validateNonZeroAddress(expected.payer, "payer");
  const recipient = validateNonZeroAddress(expected.recipient, "recipient");
  if (payer === recipient) throw new Error("Self-transfers cannot verify a merchant payment");
  const sufficient = (value: FinalityObservation) => value.finality === "finalized" ||
    (minimumFinality === "safe" && value.finality === "safe");
  const before = await inspectTransactionFinality(sources, expected.transactionHash, expected.chainId, options);
  if (!sufficient(before)) return { status: "waiting", reason: "insufficient_finality", observation: before };
  if (before.execution !== "succeeded") {
    return { status: "rejected", reason: "execution_reverted", observation: before };
  }

  const ordinals: number[] = [];
  const matches = await Promise.all(sources.map(async (source, sourceIndex) => {
    const raw = await source.send("eth_getTransactionReceipt", [before.transactionHash]);
    if (raw === null) return "changed";
    const receipt = record(raw);
    if (!equalHex(receipt.transactionHash, before.transactionHash) ||
        !equalHex(receipt.blockHash, before.blockHash!) ||
        quantity(receipt.blockNumber).toString() !== before.blockNumber || quantity(receipt.status) !== 1n) {
      return "changed";
    }
    if (!Array.isArray(receipt.logs)) throw new Error("Receipt logs missing");
    const logs = receipt.logs.map(record);
    // The consumption key uses the receipt-local ordinal. Validate the whole
    // sequence before trusting that position, including unrelated events.
    let previousIndex: bigint | undefined;
    for (const log of logs) {
      const index = quantity(log.logIndex);
      if (previousIndex !== undefined && index !== previousIndex + 1n) {
        throw new Error("Receipt event indexes must be contiguous and ordered");
      }
      previousIndex = index;
      if (log.removed !== false || !equalHex(log.transactionHash, before.transactionHash) ||
          !equalHex(log.blockHash, before.blockHash!) ||
          quantity(log.blockNumber).toString() !== before.blockNumber) return "changed";
    }
    const selected = logs.filter(log => quantity(log.logIndex) === expected.logIndex);
    if (selected.length === 0) return "mismatch";
    const log = selected[0];
    ordinals[sourceIndex] = logs.indexOf(log);
    if (!equalHex(log.address, token) || !Array.isArray(log.topics) || log.topics.length !== 3 ||
        !equalHex(log.topics[0], transferTopic) || !equalHex(log.topics[1], addressTopic(payer)) ||
        !equalHex(log.topics[2], addressTopic(recipient)) ||
        typeof log.data !== "string" || !/^0x[0-9a-fA-F]{64}$/.test(log.data) ||
        BigInt(log.data) !== expected.amount) return "mismatch";
    return "match";
  }));
  if (matches.includes("changed")) {
    return { status: "waiting", reason: "receipt_changed", observation: before };
  }
  if (matches.includes("mismatch")) {
    return { status: "rejected", reason: "transfer_mismatch", observation: before };
  }
  if (ordinals.some(value => value !== ordinals[0])) {
    throw new Error("RPC sources disagree about the transaction event position");
  }
  const after = await inspectTransactionFinality(sources, expected.transactionHash, expected.chainId, options);
  if (!sufficient(after) || after.blockHash !== before.blockHash || after.blockNumber !== before.blockNumber ||
      after.execution !== "succeeded") {
    return { status: "waiting", reason: "receipt_changed", observation: after };
  }
  return { status: "verified", observation: after,
    // Receipt-local ordinal remains stable when preceding block transactions change.
    eventKey: `${expected.chainId}:${before.transactionHash}:${ordinals[0]}`,
    token, payer, recipient, amount: expected.amount.toString() };
}
