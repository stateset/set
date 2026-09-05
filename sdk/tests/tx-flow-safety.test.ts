import { afterEach, describe, expect, it, vi } from "vitest";
import { Interface } from "ethers";
import { TransactionBuilder, TxStatus } from "../src/tx/builder.js";
import * as flows from "../src/tx/flows.js";
import { encryptedMempoolAbi } from "../src/abis/encrypted-mempool.js";
import { forcedInclusionAbi } from "../src/abis/forced-inclusion.js";

const emitter = "0x" + "ab".repeat(20);
const other = "0x" + "12".repeat(20);
const txId = "0x" + "34".repeat(32);
const confirmed = { status: TxStatus.CONFIRMED, hash: txId, gasUsed: 10n, totalCost: 20n };
const wallet = { address: other } as any;
const contract = () => ({ getAddress: vi.fn().mockResolvedValue(emitter), interface: new Interface([]) }) as any;
const token = () => ({ getAddress: vi.fn().mockResolvedValue(other), allowance: vi.fn().mockResolvedValue(0n) }) as any;

const cases = [
  { name: "deposit", approval: true, run: (c: any, t: any) => flows.executeDepositFlow(wallet, c, t, 100n) },
  { name: "wrap", approval: true, run: (c: any, t: any) => flows.executeWrapFlow(wallet, c, t, 100n) },
  { name: "unwrap", approval: false, run: (c: any) => flows.executeUnwrapFlow(wallet, c, 100n) },
  { name: "redemption", approval: true, run: (c: any, t: any) => flows.executeRedemptionRequestFlow(wallet, c, t, 100n, other) },
  { name: "sponsorship", approval: false, run: (c: any) => flows.executeBatchSponsorFlow(wallet, c, [other], [1n]) },
  { name: "batch", approval: false, run: (c: any) => flows.executeCommitBatchFlow(wallet, c, txId, txId, txId, txId, txId, txId, 1n, 2n, 2) },
  { name: "encrypted", approval: false, run: (c: any) => flows.executeEncryptedTxFlow(wallet, c, "0x1234", 1n, 100n, 2n, 3n) },
  { name: "forced request", approval: false, run: (c: any) => flows.executeForcedInclusionFlow(wallet, c, other, "0x1234", 100n, 20n) }
];

afterEach(() => vi.restoreAllMocks());

describe("transaction flow outcomes", () => {
  it.each(cases)("$name accounts for successful steps", async ({ run, approval }) => {
    const execute = vi.spyOn(TransactionBuilder.prototype, "execute").mockResolvedValue(confirmed);
    const result = await run(contract(), token());
    expect(result).toMatchObject({ success: true, totalGasUsed: approval ? 20n : 10n, totalCost: approval ? 40n : 20n });
    expect(execute).toHaveBeenCalledTimes(approval ? 2 : 1);
  });

  it.each(cases)("$name stops on the first failed transaction", async ({ run }) => {
    const execute = vi.spyOn(TransactionBuilder.prototype, "execute").mockResolvedValue({ status: TxStatus.REVERTED, error: new Error("reverted") });
    const result = await run(contract(), token());
    expect(result.success).toBe(false);
    expect(result.steps).toHaveLength(1);
    expect(result.steps[0]).toMatchObject({ status: "failed", error: "reverted" });
    expect(execute).toHaveBeenCalledTimes(1);
  });

  it.each(cases)("$name reports thrown errors without retrying", async ({ run }) => {
    const execute = vi.spyOn(TransactionBuilder.prototype, "execute").mockRejectedValue(new Error("RPC unavailable"));
    expect(await run(contract(), token())).toMatchObject({ success: false, error: "RPC unavailable" });
    expect(execute).toHaveBeenCalledTimes(1);
  });

  it.each(cases)("$name reports non-Error failures safely", async ({ run }) => {
    vi.spyOn(TransactionBuilder.prototype, "execute").mockRejectedValue("unexpected value");
    expect(await run(contract(), token())).toMatchObject({ success: false, error: "Unknown error" });
  });

  it.each(cases.filter(item => item.approval))("$name skips unnecessary approvals", async ({ run }) => {
    const execute = vi.spyOn(TransactionBuilder.prototype, "execute").mockResolvedValue(confirmed);
    const asset = token();
    asset.allowance.mockResolvedValue(100n);
    const result = await run(contract(), asset);
    expect(result.steps[0].status).toBe("skipped");
    expect(result).toMatchObject({ success: true, totalGasUsed: 10n, totalCost: 20n });
    expect(execute).toHaveBeenCalledTimes(1);
  });

  it.each(cases.filter(item => item.approval))("$name retains approval accounting when the next step fails", async ({ run }) => {
    vi.spyOn(TransactionBuilder.prototype, "execute").mockResolvedValueOnce(confirmed)
      .mockResolvedValueOnce({ status: TxStatus.FAILED, error: new Error("submit failed") });
    expect(await run(contract(), token())).toMatchObject({
      success: false, totalGasUsed: 10n, totalCost: 20n,
      steps: [{ status: "success" }, { status: "failed", error: "submit failed" }]
    });
  });
});

const eventCases = [
  { name: "redemption", iface: new Interface(["event RedemptionRequested(uint256 indexed requestId,address indexed user,uint256 amount,address collateral)"]),
    event: "RedemptionRequested", values: [7n, other, 100n, other], expected: { requestId: 7n }, field: "requestId", run: cases[3].run },
  { name: "encrypted", iface: new Interface(encryptedMempoolAbi), event: "EncryptedTxSubmitted",
    values: [txId, other, txId, 1n, 100n], expected: { txId }, field: "txId", run: cases[6].run },
  { name: "forced request", iface: new Interface(forcedInclusionAbi), event: "TransactionForced",
    values: [txId, other, other, 0n, 100n, 12345n], expected: { txId, deadline: 12345n }, field: "txId", run: cases[7].run }
];

describe("flow event emitter integrity", () => {
  it.each(eventCases)("$name ignores same-signature logs from other contracts", async item => {
    const event = item.iface.encodeEventLog(item.iface.getEvent(item.event)!, item.values);
    const c = { ...contract(), interface: item.iface };
    const asset = token();
    asset.allowance.mockResolvedValue(100n);
    vi.spyOn(TransactionBuilder.prototype, "execute").mockResolvedValue({ ...confirmed,
      receipt: { logs: [{ address: other, ...event }] } as any });
    const result = await item.run(c, asset);
    // The transaction is confirmed, but the spoofed log must not supply an identifier.
    expect(result.success).toBe(true);
    expect((result as any)[item.field]).toBeUndefined();
  });

  it.each(eventCases)("$name locates its own event after unrelated and malformed logs", async item => {
    const event = item.iface.encodeEventLog(item.iface.getEvent(item.event)!, item.values);
    const c = { ...contract(), interface: item.iface };
    const asset = token();
    asset.allowance.mockResolvedValue(100n);
    vi.spyOn(TransactionBuilder.prototype, "execute").mockResolvedValue({ ...confirmed,
      receipt: { logs: [{ address: other, ...event }, { address: emitter, topics: [], data: "0x12" },
        { address: emitter.toUpperCase(), ...event }] } as any });
    expect(await item.run(c, asset)).toMatchObject({ success: true, ...item.expected });
  });

  it.each(eventCases)("$name ignores removed or missing-emitter logs", async item => {
    const event = item.iface.encodeEventLog(item.iface.getEvent(item.event)!, item.values);
    const c = { ...contract(), interface: item.iface };
    const asset = token();
    asset.allowance.mockResolvedValue(100n);
    vi.spyOn(TransactionBuilder.prototype, "execute").mockResolvedValue({ ...confirmed,
      receipt: { logs: [{ address: emitter, removed: true, ...event }, event] } as any });
    expect((await item.run(c, asset) as any)[item.field]).toBeUndefined();
  });

  it.each(eventCases)("$name resolves the emitter before sending anything", async item => {
    const c = contract();
    c.getAddress.mockRejectedValue(new Error("Cannot resolve contract"));
    const execute = vi.spyOn(TransactionBuilder.prototype, "execute");
    expect(await item.run(c, token())).toMatchObject({ success: false, error: "Cannot resolve contract" });
    expect(execute).not.toHaveBeenCalled();
  });
});
