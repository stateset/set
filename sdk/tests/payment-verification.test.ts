import { afterEach, describe, expect, it, vi } from "vitest";
import { id } from "ethers";
import { verifyERC20Payment, type ERC20PaymentExpectation, type FinalityRpc } from "../src/index.js";

const tx = "0x" + "ab".repeat(32);
const blockHash = "0x" + "cd".repeat(32);
const token = "0x" + "11".repeat(20);
const payer = "0x" + "22".repeat(20);
const recipient = "0x" + "33".repeat(20);
const topic = (address: string) => "0x" + "0".repeat(24) + address.slice(2);
const expected: ERC20PaymentExpectation = {
  chainId: 10n, transactionHash: tx, logIndex: 7n, token, payer, recipient, amount: 1_000_000n
};

function rpc(options: {
  log?: Record<string, unknown>; missing?: boolean; duplicate?: boolean;
  reverted?: boolean; pending?: boolean; safeOnly?: boolean; disappearAfterLog?: boolean;
  missingLogs?: boolean; error?: boolean;
  preceding?: Record<string, unknown>[]; following?: Record<string, unknown>[];
} = {}): FinalityRpc {
  let receipts = 0;
  return { async send(method, params) {
    if (options.error) throw new Error("RPC unavailable");
    if (method === "eth_chainId") return "0xa";
    if (method === "eth_getBlockByNumber") {
      const isOld = params[0] === "0x0" || (options.safeOnly && params[0] === "finalized");
      return { number: isOld ? "0x0" : "0xa", hash: isOld ? "0x" + "00".repeat(32) : blockHash };
    }
    if (method === "eth_getTransactionReceipt") {
      receipts++;
      if (options.pending || (options.disappearAfterLog && receipts > 3)) return null;
      const log = { logIndex: "0x7", transactionHash: tx, blockHash, blockNumber: "0xa", removed: false,
        address: token, topics: [id("Transfer(address,address,uint256)"), topic(payer), topic(recipient)],
        data: "0x" + expected.amount.toString(16).padStart(64, "0"), ...options.log };
      return { transactionHash: tx, blockHash, blockNumber: "0xa", status: options.reverted ? "0x0" : "0x1",
        logs: options.missingLogs ? undefined : options.missing ? [] : options.duplicate ? [log, log] : [
          ...(options.preceding ?? []).map(change => ({ ...log, ...change })), log,
          ...(options.following ?? []).map(change => ({ ...log, ...change }))
        ] };
    }
    throw new Error("Unexpected method");
  } };
}

afterEach(() => vi.useRealTimers());

describe("ERC20 payment verification", () => {
  it("does not refresh evidence age during the finality recheck", async () => {
    vi.useFakeTimers();
    const started = new Date("2026-09-05T12:00:00Z");
    vi.setSystemTime(started);
    const delayed = (): FinalityRpc => {
      const underlying = rpc();
      let receipts = 0;
      return { async send(method, params) {
        if (method === "eth_getTransactionReceipt" && ++receipts === 3) {
          await new Promise(resolve => setTimeout(resolve, 61000));
        }
        return underlying.send(method, params);
      } };
    };
    const pending = verifyERC20Payment([delayed(), delayed()], expected, "finalized", { timeoutMs: 120000 });
    await vi.advanceTimersByTimeAsync(61000);
    const result = await pending;
    expect(result).toMatchObject({ status: "verified", observation: { observedAt: started.toISOString() } });
    // A ledger with a 60-second freshness policy must reject this evidence.
    expect(Date.now() - Date.parse(result.observation.observedAt)).toBe(61000);
  });

  it("snapshots payment terms before the first asynchronous step", async () => {
    const terms = { ...expected };
    const pending = verifyERC20Payment([rpc(), rpc()], terms);
    terms.amount = 1n;
    terms.logIndex = 99n;
    terms.chainId = 1n;
    terms.transactionHash = blockHash;
    terms.token = recipient;
    expect(await pending).toMatchObject({
      status: "verified", amount: "1000000", token, eventKey: `10:${tx}:0`
    });
  });

  it("snapshots payment terms while receipt requests are in flight", async () => {
    const terms = { ...expected };
    const underlying = rpc();
    let receipts = 0;
    const mutating: FinalityRpc = { async send(method, params) {
      if (method === "eth_getTransactionReceipt" && ++receipts === 3) {
        terms.amount = 2n;
        terms.chainId = 1n;
      }
      return underlying.send(method, params);
    } };
    expect(await verifyERC20Payment([mutating, rpc()], terms))
      .toMatchObject({ status: "verified", amount: "1000000", eventKey: `10:${tx}:0` });
  });

  it("does not allow later mutations to repair invalid initial expectations", async () => {
    const terms = { ...expected, amount: 0n };
    const pending = verifyERC20Payment([rpc(), rpc()], terms);
    terms.amount = expected.amount;
    await expect(pending).rejects.toThrow("Invalid payment amount");
  });

  it("snapshots deadline policy for the finality sub-operations", async () => {
    const options = { timeoutMs: 10000 };
    const pending = verifyERC20Payment([rpc(), rpc()], expected, "finalized", options);
    options.timeoutMs = 0;
    expect(await pending).toMatchObject({ status: "verified" });
  });

  it("assigns distinct keys to payments in a multi-event receipt", async () => {
    const receipt = () => rpc({ preceding: [{ logIndex: "0x6" }], following: [{ logIndex: "0x8" }] });
    const keys = [];
    for (const logIndex of [6n, 7n, 8n]) {
      const result = await verifyERC20Payment([receipt(), receipt()], { ...expected, logIndex });
      expect(result.status).toBe("verified");
      if (result.status === "verified") keys.push(result.eventKey);
    }
    expect(keys).toEqual([`10:${tx}:0`, `10:${tx}:1`, `10:${tx}:2`]);
  });

  it("allows unrelated events around the selected transfer", async () => {
    const receipt = () => rpc({
      preceding: [{ logIndex: "0x6", address: recipient, topics: [], data: "0x" }],
      following: [{ logIndex: "0x8", topics: [id("Unrelated()")], data: "0x" }]
    });
    expect(await verifyERC20Payment([receipt(), receipt()], expected))
      .toMatchObject({ status: "verified", eventKey: `10:${tx}:1` });
  });

  it.each([
    { preceding: [{ logIndex: "0x6" }, { logIndex: "0x6" }] },
    { preceding: [{ logIndex: "0x8" }] },
    { preceding: [{ logIndex: "0x5" }] },
    { following: [{ logIndex: "0x9" }] },
    { following: [{ logIndex: "0x8" }, { logIndex: "0x8" }] },
    { preceding: [{ logIndex: "0x06" }] }
  ])("rejects malformed surrounding log sequences: %j", async options => {
    await expect(verifyERC20Payment([rpc(options), rpc(options)], expected)).rejects.toThrow();
  });

  it.each([{ removed: true }, { transactionHash: blockHash }, { blockHash: tx }, { blockNumber: "0xb" }])(
    "withholds credit when an unrelated preceding event is stale: %j", async change => {
      const result = await verifyERC20Payment([
        rpc({ preceding: [{ logIndex: "0x6" }] }),
        rpc({ preceding: [{ logIndex: "0x6", ...change }] })
      ], expected);
      expect(result).toMatchObject({ status: "waiting", reason: "receipt_changed" });
      expect(result).not.toHaveProperty("eventKey");
    });

  it("rejects sources that disagree on the receipt-local event ordinal", async () => {
    await expect(verifyERC20Payment([
      rpc(), rpc({ preceding: [{ logIndex: "0x6" }] })
    ], expected)).rejects.toThrow("event position");
  });

  it("preserves a nonzero ordinal when all block-wide indexes shift", async () => {
    const first = await verifyERC20Payment([
      rpc({ preceding: [{ logIndex: "0x6" }] }), rpc({ preceding: [{ logIndex: "0x6" }] })
    ], expected);
    const shifted = () => rpc({ log: { logIndex: "0xc" }, preceding: [{ logIndex: "0xb" }] });
    const second = await verifyERC20Payment([shifted(), shifted()], { ...expected, logIndex: 12n });
    expect(first).toMatchObject({ status: "verified", eventKey: `10:${tx}:1` });
    expect(second).toMatchObject({ status: "verified", eventKey: `10:${tx}:1` });
  });

  it("verifies the exact event and emits a chain-scoped consumable key", async () => {
    const result = await verifyERC20Payment([rpc(), rpc()], expected);
    expect(result).toMatchObject({ status: "verified", eventKey: `10:${tx}:0`, amount: "1000000" });
    expect(() => JSON.stringify(result)).not.toThrow();
  });

  it.each([
    { address: payer }, { topics: [id("Approval(address,address,uint256)"), topic(payer), topic(recipient)] },
    { topics: [id("Transfer(address,address,uint256)"), topic(token), topic(recipient)] },
    { topics: [id("Transfer(address,address,uint256)"), topic(payer), topic(token)] },
    { data: "0x" + (999999n).toString(16).padStart(64, "0") },
    { data: "0x" + (1000001n).toString(16).padStart(64, "0") },
    { data: "0x01" }, { logIndex: "0x8" },
    { topics: [id("Transfer(address,address,uint256)"), topic(payer), topic(recipient), "0x" + "00".repeat(32)] }
  ])("rejects spoofed or mismatched transfers: %j", async log => {
    const result = await verifyERC20Payment([rpc(), rpc({ log })], expected);
    expect(result).toMatchObject({ status: "rejected", reason: "transfer_mismatch" });
    expect(result).not.toHaveProperty("eventKey");
  });

  it.each([{ removed: true }, { blockHash: tx }, { transactionHash: blockHash }, { blockNumber: "0xb" }])(
    "withholds verification for stale logs: %j", async log => {
      expect(await verifyERC20Payment([rpc(), rpc({ log })], expected))
        .toMatchObject({ status: "waiting", reason: "receipt_changed" });
    });

  it("does not accept a finalized reverted transaction", async () => {
    expect(await verifyERC20Payment([rpc({ reverted: true }), rpc({ reverted: true })], expected))
      .toMatchObject({ status: "rejected", reason: "execution_reverted" });
  });

  it("waits for a lagging verifier", async () => {
    expect(await verifyERC20Payment([rpc(), rpc({ pending: true })], expected)).toMatchObject({ status: "waiting" });
  });

  it("requires finalized by default and safe only by explicit policy", async () => {
    expect(await verifyERC20Payment([rpc(), rpc({ safeOnly: true })], expected))
      .toMatchObject({ status: "waiting", reason: "insufficient_finality" });
    expect(await verifyERC20Payment([rpc(), rpc({ safeOnly: true })], expected, "safe"))
      .toMatchObject({ status: "verified" });
  });

  it("detects disappearance after event inspection", async () => {
    expect(await verifyERC20Payment([rpc(), rpc({ disappearAfterLog: true })], expected))
      .toMatchObject({ status: "waiting", reason: "receipt_changed" });
  });

  it("rejects missing events", async () => {
    expect(await verifyERC20Payment([rpc(), rpc({ missing: true })], expected))
      .toMatchObject({ status: "rejected" });
  });

  it.each([{ duplicate: true }, { missingLogs: true }, { error: true }])(
    "fails closed for malformed or unavailable evidence: %j", async options => {
      await expect(verifyERC20Payment([rpc(), rpc(options)], expected)).rejects.toThrow();
    });

  it.each([{ amount: 0n }, { amount: -1n }, { amount: 2n ** 256n }, { logIndex: -1n },
    { payer: recipient }, { token: "0x" + "00".repeat(20) }, { recipient: "invalid" }])(
    "rejects invalid expectations %#", async changes => {
      await expect(verifyERC20Payment([rpc(), rpc()], { ...expected, ...changes })).rejects.toThrow();
    });

  it("requires distinct sources", async () => {
    const source = rpc();
    await expect(verifyERC20Payment([source], expected)).rejects.toThrow();
    await expect(verifyERC20Payment([source, source], expected)).rejects.toThrow();
  });

  it("keeps the consumption key stable when block-wide log indexes shift", async () => {
    const first = await verifyERC20Payment([rpc(), rpc()], expected);
    const shifted = await verifyERC20Payment([
      rpc({ log: { logIndex: "0xc" } }), rpc({ log: { logIndex: "0xc" } })
    ], { ...expected, logIndex: 12n });
    expect(first.status).toBe("verified");
    expect(shifted.status).toBe("verified");
    if (first.status === "verified" && shifted.status === "verified") {
      expect(first.eventKey).toBe(shifted.eventKey);
    }
  });
});
