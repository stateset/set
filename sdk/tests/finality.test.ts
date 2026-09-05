import { afterEach, describe, expect, it, vi } from "vitest";
import { inspectTransactionFinality, type FinalityRpc } from "../src/index.js";

const tx = "0x" + "aa".repeat(32);
const h = (n: number) => "0x" + n.toString(16).padStart(64, "0");
const q = (n: number) => "0x" + n.toString(16);

function source(options: {
  safe?: number; finalized?: number; status?: string; pending?: boolean;
  chain?: string; reorg?: boolean; midReorg?: boolean; unsupported?: boolean;
  otherHash?: boolean; disappear?: boolean; badHead?: boolean;
} = {}): FinalityRpc {
  let receipts = 0;
  return { async send(method, params) {
    if (method === "eth_chainId") return options.chain ?? "0xa";
    if (method === "eth_getTransactionReceipt") {
      receipts++;
      if (options.pending || (options.disappear && receipts > 1)) return null;
      return { transactionHash: tx, blockNumber: "0xa", blockHash: options.otherHash ? h(99) : h(10),
        status: options.status ?? "0x1" };
    }
    if (method === "eth_getBlockByNumber") {
      const tag = params[0] as string;
      if (options.unsupported && tag === "finalized") throw new Error("unsupported tag");
      const n = tag === "safe" ? options.safe ?? 15 : tag === "finalized" ? options.finalized ?? 5 : Number(BigInt(tag));
      const changed = n === 10 && (options.reorg || (options.midReorg && receipts > 1));
      return { number: q(n), hash: (changed || (options.otherHash && n === 10) ||
        (options.badHead && tag === "safe")) ? h(99) : h(n) };
    }
    throw new Error("Unexpected RPC method");
  } };
}

afterEach(() => vi.useRealTimers());

describe("transaction finality observations", () => {
  it.each([false, true])("timestamps the whole observation before slow chain discovery, reversed=%s", async reverse => {
    vi.useFakeTimers();
    const started = new Date("2026-09-05T12:00:00Z");
    vi.setSystemTime(started);
    const fast = source({ finalized: 10 });
    const underlying = source({ finalized: 10 });
    const slow: FinalityRpc = { async send(method, params) {
      if (method === "eth_chainId") await new Promise(resolve => setTimeout(resolve, 1000));
      return underlying.send(method, params);
    } };
    const result = inspectTransactionFinality(reverse ? [fast, slow] : [slow, fast], tx, 10n);
    await vi.advanceTimersByTimeAsync(1000);
    expect(await result).toMatchObject({ finality: "finalized", observedAt: started.toISOString() });
  });

  it.each([
    [4, 3, "unsafe"], [10, 5, "safe"], [20, 10, "finalized"]
  ] as const)("classifies safe=%s finalized=%s as %s", async (safe, finalized, level) => {
    const result = await inspectTransactionFinality([source({ safe, finalized })], tx, 10n);
    expect(result.finality).toBe(level);
    expect(result.execution).toBe("succeeded");
    expect(result.blockNumber).toBe("10");
    expect(() => JSON.stringify(result)).not.toThrow();
  });

  it("does not confuse finalized reverts with successful payment", async () => {
    const result = await inspectTransactionFinality([source({ finalized: 10, status: "0x0" })], tx, 10n);
    expect(result.finality).toBe("finalized");
    expect(result.execution).toBe("reverted");
  });

  it.each([{ pending: true }, { reorg: true }, { midReorg: true }, { disappear: true }])(
    "does not certify missing or reorganized receipts: %j", async options => {
      const result = await inspectTransactionFinality([source(options)], tx, 10n);
      expect(result.execution).toBe("unknown");
      expect(result.blockHash).toBeNull();
      expect(result.finality).toBe(options.pending ? "pending" : "reorged");
    });

  it("uses the weaker finality across independently configured sources", async () => {
    const result = await inspectTransactionFinality([
      source({ finalized: 10 }), source({ safe: 8, finalized: 5 })
    ], tx, 10n);
    expect(result.finality).toBe("unsafe");
    expect(result.sources).toBe(2);
  });

  it("returns pending if a verifier has not seen the receipt", async () => {
    const result = await inspectTransactionFinality([source(), source({ pending: true })], tx, 10n);
    expect(result.finality).toBe("pending");
    expect(result.execution).toBe("unknown");
  });

  it.each([
    { chain: "0x1" }, { chain: "0x00" }, { status: "0x2" },
    { unsupported: true }, { safe: 3, finalized: 5 }, { badHead: true }
  ])("rejects invalid or unsupported evidence: %j", async options => {
    await expect(inspectTransactionFinality([source(options)], tx, 10n)).rejects.toThrow();
  });

  it("rejects nodes reporting different canonical inclusions", async () => {
    await expect(inspectTransactionFinality([source(), source({ otherHash: true })], tx, 10n))
      .rejects.toThrow("disagree");
  });

  it("rejects receipt execution disagreements", async () => {
    await expect(inspectTransactionFinality([source(), source({ status: "0x0" })], tx, 10n))
      .rejects.toThrow("disagree");
  });

  it("rejects duplicate sources, empty sources, bad hash and chain", async () => {
    const rpc = source();
    await expect(inspectTransactionFinality([rpc, rpc], tx, 10n)).rejects.toThrow();
    await expect(inspectTransactionFinality([], tx, 10n)).rejects.toThrow();
    await expect(inspectTransactionFinality([rpc], "0x123", 10n)).rejects.toThrow();
    await expect(inspectTransactionFinality([rpc], tx, 0n)).rejects.toThrow();
  });
});
