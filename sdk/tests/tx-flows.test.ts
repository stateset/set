import { describe, expect, it, vi, afterEach } from "vitest";
import { Interface } from "ethers";
import { encryptedMempoolAbi } from "../src/abis/encrypted-mempool";
import { forcedInclusionAbi } from "../src/abis/forced-inclusion";
import { TransactionBuilder, TxStatus } from "../src/tx/builder";
import {
  executeCommitBatchFlow,
  executeRedemptionRequestFlow,
  executeEncryptedTxFlow,
  executeForcedInclusionFlow
} from "../src/tx/flows";

afterEach(() => {
  vi.restoreAllMocks();
});

describe("tx flows", () => {
  it("passes the full current commitBatch argument set", async () => {
    const executeSpy = vi.spyOn(TransactionBuilder.prototype, "execute").mockResolvedValue({
      status: TxStatus.CONFIRMED,
      hash: "0xcommit",
      gasUsed: 75_000n,
      totalCost: 120n
    } as any);

    const registry = {} as any;

    await expect(
      executeCommitBatchFlow(
        {} as any,
        registry,
        `0x${"11".repeat(32)}`,
        `0x${"22".repeat(32)}`,
        `0x${"33".repeat(32)}`,
        `0x${"44".repeat(32)}`,
        `0x${"55".repeat(32)}`,
        `0x${"66".repeat(32)}`,
        10n,
        20n,
        7
      )
    ).resolves.toMatchObject({
      success: true
    });

    expect(executeSpy).toHaveBeenCalledWith(
      registry,
      "commitBatch",
      [
        `0x${"11".repeat(32)}`,
        `0x${"22".repeat(32)}`,
        `0x${"33".repeat(32)}`,
        `0x${"44".repeat(32)}`,
        `0x${"55".repeat(32)}`,
        `0x${"66".repeat(32)}`,
        10n,
        20n,
        7
      ]
    );
  });

  it("passes preferred collateral to redemption requests", async () => {
    const executeSpy = vi.spyOn(TransactionBuilder.prototype, "execute");
    executeSpy
      .mockResolvedValueOnce({
        status: TxStatus.CONFIRMED,
        hash: "0xapprove",
        gasUsed: 21_000n,
        totalCost: 42n
      } as any)
      .mockResolvedValueOnce({
        status: TxStatus.CONFIRMED,
        hash: "0xredeem",
        receipt: { logs: [] },
        gasUsed: 50_000n,
        totalCost: 84n
      } as any);

    const treasuryVault = {
      getAddress: vi.fn().mockResolvedValue("0x3000000000000000000000000000000000000003"),
      interface: new Interface([])
    } as any;
    const ssUSD = {
      allowance: vi.fn().mockResolvedValue(0n)
    } as any;
    const wallet = {
      address: "0x1000000000000000000000000000000000000001"
    } as any;

    await expect(
      executeRedemptionRequestFlow(
        wallet,
        treasuryVault,
        ssUSD,
        500n,
        "0x2000000000000000000000000000000000000002"
      )
    ).resolves.toMatchObject({
      success: true
    });

    expect(executeSpy).toHaveBeenNthCalledWith(
      2,
      treasuryVault,
      "requestRedemption",
      [500n, "0x2000000000000000000000000000000000000002"]
    );
  });

  it("extracts txId from EncryptedTxSubmitted receipts", async () => {
    const iface = new Interface(encryptedMempoolAbi);
    const txId = `0x${"11".repeat(32)}`;
    const sender = "0x1000000000000000000000000000000000000001";
    const payloadHash = `0x${"22".repeat(32)}`;
    const event = iface.encodeEventLog(
      iface.getEvent("EncryptedTxSubmitted"),
      [txId, sender, payloadHash, 7n, 200000n]
    );

    vi.spyOn(TransactionBuilder.prototype, "execute").mockResolvedValue({
      status: TxStatus.CONFIRMED,
      hash: "0xsubmit",
      receipt: {
        logs: [{ topics: event.topics, data: event.data }]
      },
      gasUsed: 21_000n,
      totalCost: 42n
    } as any);

    const mempool = {
      interface: iface
    } as any;

    await expect(
      executeEncryptedTxFlow(
        {} as any,
        mempool,
        `0x${"33".repeat(64)}`,
        7n,
        200000n,
        1_000_000_000n,
        5n
      )
    ).resolves.toMatchObject({
      success: true,
      txId,
      steps: [
        {
          step: "submitEncryptedTx",
          status: "success",
          data: { txId }
        }
      ]
    });
  });

  it("extracts txId and deadline from TransactionForced receipts", async () => {
    const iface = new Interface(forcedInclusionAbi);
    const txId = `0x${"44".repeat(32)}`;
    const sender = "0x1000000000000000000000000000000000000001";
    const target = "0x2000000000000000000000000000000000000002";
    const deadline = 1_800_000_000n;
    const event = iface.encodeEventLog(
      iface.getEvent("TransactionForced"),
      [txId, sender, target, 0n, 500000n, deadline]
    );

    vi.spyOn(TransactionBuilder.prototype, "execute").mockResolvedValue({
      status: TxStatus.CONFIRMED,
      hash: "0xforce",
      receipt: {
        logs: [{ topics: event.topics, data: event.data }]
      },
      gasUsed: 50_000n,
      totalCost: 84n
    } as any);

    const forcedInclusion = {
      interface: iface
    } as any;

    await expect(
      executeForcedInclusionFlow(
        {} as any,
        forcedInclusion,
        target,
        "0x1234",
        500000n,
        1_000_000_000_000_000n
      )
    ).resolves.toMatchObject({
      success: true,
      txId,
      deadline,
      steps: [
        {
          step: "forceTransaction",
          status: "success",
          data: { txId, deadline }
        }
      ]
    });
  });
});
