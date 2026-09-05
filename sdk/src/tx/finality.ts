import { withRpcDeadline, type VerificationOptions } from "./rpc-deadline.js";

/** Minimal transport implemented by ethers JsonRpcProvider. */
export interface FinalityRpc {
  send(method: string, params: unknown[]): Promise<unknown>;
}

export type TransactionFinality = "pending" | "reorged" | "unsafe" | "safe" | "finalized";

export interface FinalityObservation {
  chainId: string;
  transactionHash: string;
  finality: TransactionFinality;
  /** A reverted transaction can be finalized. Finality is not payment success. */
  execution: "unknown" | "succeeded" | "reverted";
  blockNumber: string | null;
  blockHash: string | null;
  /** Start of the complete observation, before any source is queried. */
  observedAt: string;
  /** Agreement is RPC evidence, not a cryptographic proof or withdrawal completion. */
  sources: number;
}

export class FinalityObservationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "FinalityObservationError";
  }
}

function object(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new FinalityObservationError("Malformed RPC object");
  }
  return value as Record<string, unknown>;
}

function hash(value: unknown): string {
  if (typeof value !== "string" || !/^0x[0-9a-fA-F]{64}$/.test(value)) {
    throw new FinalityObservationError("Malformed block or transaction hash");
  }
  return value.toLowerCase();
}

function quantity(value: unknown): bigint {
  if (typeof value !== "string" || !/^0x(?:0|[1-9a-fA-F][0-9a-fA-F]*)$/.test(value)) {
    throw new FinalityObservationError("Malformed RPC quantity");
  }
  return BigInt(value);
}

function block(value: unknown): { number: bigint; hash: string } {
  const data = object(value);
  return { number: quantity(data.number), hash: hash(data.hash) };
}

async function inspectSource(
  rpc: FinalityRpc, transactionHash: string, expectedChainId: bigint, observedAt: string
): Promise<FinalityObservation> {
  if (quantity(await rpc.send("eth_chainId", [])) !== expectedChainId) {
    throw new FinalityObservationError("RPC chain ID does not match expected chain");
  }
  const base: FinalityObservation = {
    chainId: expectedChainId.toString(), transactionHash, finality: "pending",
    execution: "unknown", blockNumber: null, blockHash: null,
    observedAt, sources: 1
  };
  const raw = await rpc.send("eth_getTransactionReceipt", [transactionHash]);
  if (raw === null) return base;
  const receipt = object(raw);
  if (hash(receipt.transactionHash) !== transactionHash) {
    throw new FinalityObservationError("RPC returned a different transaction receipt");
  }
  const number = quantity(receipt.blockNumber);
  const receiptHash = hash(receipt.blockHash);
  const status = quantity(receipt.status);
  if (status !== 0n && status !== 1n) throw new FinalityObservationError("Invalid receipt status");
  const tag = "0x" + number.toString(16);
  const canonical = block(await rpc.send("eth_getBlockByNumber", [tag, false]));
  if (canonical.number !== number) throw new FinalityObservationError("RPC returned wrong block height");
  if (canonical.hash !== receiptHash) return { ...base, finality: "reorged" };

  // Read finalized before safe: advancing heads should preserve finalized <= safe.
  // Unsupported tags propagate errors; they must never be replaced with latest.
  const finalized = block(await rpc.send("eth_getBlockByNumber", ["finalized", false]));
  const safe = block(await rpc.send("eth_getBlockByNumber", ["safe", false]));
  if (finalized.number > safe.number ||
      (finalized.number === safe.number && finalized.hash !== safe.hash)) {
    throw new FinalityObservationError("Inconsistent safe/finalized heads");
  }
  for (const head of [finalized, safe]) {
    const current = block(await rpc.send("eth_getBlockByNumber", ["0x" + head.number.toString(16), false]));
    if (current.number !== head.number || current.hash !== head.hash) {
      throw new FinalityObservationError("Head changed during observation; retry");
    }
  }
  const finality = number <= finalized.number ? "finalized" : number <= safe.number ? "safe" : "unsafe";
  // Re-read both receipt and canonical block after head reads to detect mid-read reorgs.
  const again = await rpc.send("eth_getTransactionReceipt", [transactionHash]);
  const canonicalAgain = block(await rpc.send("eth_getBlockByNumber", [tag, false]));
  if (again === null) return { ...base, finality: "reorged" };
  const repeated = object(again);
  if (hash(repeated.transactionHash) !== transactionHash ||
      quantity(repeated.blockNumber) !== number || hash(repeated.blockHash) !== receiptHash ||
      canonicalAgain.number !== number || canonicalAgain.hash !== receiptHash) {
    return { ...base, finality: "reorged" };
  }
  if (quantity(repeated.status) !== status) throw new FinalityObservationError("Receipt status changed");
  return { ...base, finality, execution: status === 1n ? "succeeded" : "reverted",
    blockNumber: number.toString(), blockHash: receiptHash };
}

/**
 * Observe transaction inclusion using canonical blocks and OP Stack finality tags.
 * Supply independently operated RPCs for useful corroboration. Distinct objects
 * alone cannot establish infrastructure independence. RPC failures reject the
 * observation. Callers must validate payment events separately before fulfillment.
 */
export async function inspectTransactionFinality(
  sources: readonly FinalityRpc[], transactionHash: string, expectedChainId: bigint,
  options: VerificationOptions = {}
): Promise<FinalityObservation> {
  const observedAt = new Date().toISOString();
  return withRpcDeadline(sources, options,
    bounded => inspectFinality(bounded, transactionHash, expectedChainId, observedAt));
}

async function inspectFinality(
  sources: readonly FinalityRpc[], transactionHash: string, expectedChainId: bigint, observedAt: string
): Promise<FinalityObservation> {
  const tx = hash(transactionHash);
  if (expectedChainId <= 0n || sources.length === 0 || new Set(sources).size !== sources.length) {
    throw new FinalityObservationError("Provide a positive chain ID and distinct RPC sources");
  }
  const observations = await Promise.all(sources.map(source => inspectSource(source, tx, expectedChainId, observedAt)));
  const first = observations[0];
  if (observations.some(item => item.finality === "reorged")) {
    return { ...first, finality: "reorged", execution: "unknown", blockNumber: null,
      blockHash: null, sources: sources.length };
  }
  if (observations.some(item => item.finality === "pending")) {
    return { ...first, finality: "pending", execution: "unknown", blockNumber: null,
      blockHash: null, sources: sources.length };
  }
  if (observations.some(item => item.blockHash !== first.blockHash ||
      item.blockNumber !== first.blockNumber || item.execution !== first.execution)) {
    throw new FinalityObservationError("RPC sources disagree about transaction inclusion");
  }
  const levels: TransactionFinality[] = ["unsafe", "safe", "finalized"];
  const rank = Math.min(...observations.map(item => levels.indexOf(item.finality)));
  return { ...first, finality: levels[rank], sources: sources.length };
}
