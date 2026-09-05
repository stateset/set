import { afterEach, describe, expect, it, vi } from "vitest";
import { id } from "ethers";
import {
  inspectTransactionFinality, verifyERC20Payment, VerificationInterruptedError,
  type FinalityRpc
} from "../src/index.js";
import { withRpcDeadline } from "../src/tx/rpc-deadline.js";

const tx = "0x" + "ab".repeat(32);
const expected = {
  chainId: 10n, transactionHash: tx, logIndex: 0n, amount: 1n,
  token: "0x" + "11".repeat(20), payer: "0x" + "22".repeat(20), recipient: "0x" + "33".repeat(20)
};
const hanging = (): FinalityRpc => ({ send: vi.fn(() => new Promise(() => {})) });

afterEach(() => { vi.useRealTimers(); });

describe("verification operation deadlines", () => {
  it.each([3, 4])("bounds a payment stalled at receipt read %s", async stallAt => {
    vi.useFakeTimers();
    const source = (): FinalityRpc => {
      let receipts = 0;
      return { async send(method) {
        if (method === "eth_chainId") return "0xa";
        if (method === "eth_getBlockByNumber") return { number: "0x1", hash: tx };
        if (++receipts === stallAt) return new Promise(() => {});
        return { transactionHash: tx, blockHash: tx, blockNumber: "0x1", status: "0x1", logs: [{
          transactionHash: tx, blockHash: tx, blockNumber: "0x1", logIndex: "0x0", removed: false,
          address: expected.token, topics: [id("Transfer(address,address,uint256)"),
            "0x" + "0".repeat(24) + expected.payer.slice(2),
            "0x" + "0".repeat(24) + expected.recipient.slice(2)],
          data: "0x" + "0".repeat(63) + "1"
        }] };
      } };
    };
    const result = verifyERC20Payment([source(), source()], expected, "finalized", { timeoutMs: 100 });
    const rejected = expect(result).rejects.toMatchObject({ reason: "timeout" });
    await vi.advanceTimersByTimeAsync(100);
    await rejected;
    expect(vi.getTimerCount()).toBe(0);
  });

  it.each(["finality", "payment"])("bounds a hung %s verification by default", async kind => {
    vi.useFakeTimers();
    const sources = [hanging(), hanging()];
    const result = kind === "finality"
      ? inspectTransactionFinality(sources, tx, 10n)
      : verifyERC20Payment(sources, expected);
    const rejected = expect(result).rejects.toMatchObject({ name: "VerificationInterruptedError", reason: "timeout" });
    await vi.advanceTimersByTimeAsync(30000);
    await rejected;
    expect(vi.getTimerCount()).toBe(0);
    expect(sources[0].send).toHaveBeenCalledTimes(1);
  });

  it.each([0, -1, 1.5, NaN, Infinity, 300001])("rejects invalid timeout %s before RPC I/O", async timeoutMs => {
    const source = hanging();
    await expect(inspectTransactionFinality([source], tx, 10n, { timeoutMs })).rejects.toThrow("timeout");
    expect(source.send).not.toHaveBeenCalled();
  });

  it("rejects pre-aborted requests without RPC I/O", async () => {
    const controller = new AbortController();
    controller.abort("Do not expose user cancellation details");
    const source = hanging();
    await expect(inspectTransactionFinality([source], tx, 10n, { signal: controller.signal }))
      .rejects.toMatchObject({ reason: "aborted", message: "Verification aborted" });
    expect(source.send).not.toHaveBeenCalled();
  });

  it("aborts in-flight payment verification and cleans up timers", async () => {
    vi.useFakeTimers();
    const controller = new AbortController();
    const result = verifyERC20Payment([hanging(), hanging()], expected, "finalized", { signal: controller.signal });
    const rejected = expect(result).rejects.toMatchObject({ reason: "aborted" });
    await vi.advanceTimersByTimeAsync(1);
    controller.abort();
    await rejected;
    expect(vi.getTimerCount()).toBe(0);
  });

  it("does not restart the deadline for each RPC request", async () => {
    vi.useFakeTimers();
    const source = { send: vi.fn(() => new Promise(resolve => setTimeout(() => resolve("0xa"), 60))) };
    const result = withRpcDeadline([source], { timeoutMs: 100 }, async ([rpc]) => {
      await rpc.send("first", []);
      await rpc.send("second", []);
      await rpc.send("must-not-run", []);
    });
    const rejected = expect(result).rejects.toBeInstanceOf(VerificationInterruptedError);
    await vi.advanceTimersByTimeAsync(100);
    await rejected;
    await vi.advanceTimersByTimeAsync(100);
    expect(source.send).toHaveBeenCalledTimes(2);
    expect(vi.getTimerCount()).toBe(0);
  });

  it("does not continue after a timed-out transport resolves late", async () => {
    vi.useFakeTimers();
    let resolve!: (value: unknown) => void;
    const source = { send: vi.fn(() => new Promise(done => { resolve = done; })) };
    const result = inspectTransactionFinality([source], tx, 10n, { timeoutMs: 10 });
    const rejected = expect(result).rejects.toMatchObject({ reason: "timeout" });
    await vi.advanceTimersByTimeAsync(10);
    await rejected;
    resolve("0xa");
    await vi.advanceTimersByTimeAsync(1);
    expect(source.send).toHaveBeenCalledTimes(1);
    expect(vi.getTimerCount()).toBe(0);
  });

  it("clears deadline timers and abort listeners on success", async () => {
    vi.useFakeTimers();
    const controller = new AbortController();
    const remove = vi.spyOn(controller.signal, "removeEventListener");
    const source: FinalityRpc = { async send(method) { return method === "eth_chainId" ? "0xa" : null; } };
    expect(await inspectTransactionFinality([source], tx, 10n, { signal: controller.signal }))
      .toMatchObject({ finality: "pending" });
    expect(vi.getTimerCount()).toBe(0);
    expect(remove).toHaveBeenCalledWith("abort", expect.any(Function));
  });

  it("preserves transport errors and stops other branches", async () => {
    vi.useFakeTimers();
    const error = new Error("Unavailable");
    await expect(inspectTransactionFinality([
      { async send() { throw error; } }, hanging()
    ], tx, 10n)).rejects.toBe(error);
    expect(vi.getTimerCount()).toBe(0);
  });
});
