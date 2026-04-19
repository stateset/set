import { describe, expect, it, vi, afterEach } from "vitest";
import {
  TransactionTracker,
  TxStatus
} from "../src/tx/builder";

afterEach(() => {
  vi.restoreAllMocks();
});

describe("TransactionTracker.waitForConfirmation", () => {
  it("waits for the requested confirmation count instead of resolving on the first confirmation", async () => {
    const tracker = new TransactionTracker({} as any);
    let listener: ((event: any) => void) | undefined;

    vi.spyOn(tracker, "on").mockImplementation((_txHash, cb) => {
      listener = cb;
      return () => {};
    });
    vi.spyOn(tracker, "track").mockResolvedValue({
      hash: "0xabc",
      status: TxStatus.PENDING,
      submittedAt: Date.now(),
      confirmations: 0
    });

    const promise = tracker.waitForConfirmation("0xabc", 3, 10_000);
    await Promise.resolve();

    listener?.({
      type: "confirmed",
      txHash: "0xabc",
      transaction: {
        hash: "0xabc",
        status: TxStatus.CONFIRMED,
        submittedAt: Date.now(),
        confirmations: 1
      },
      confirmations: 1
    });

    let resolved = false;
    promise.then(() => {
      resolved = true;
    });
    await Promise.resolve();
    expect(resolved).toBe(false);

    listener?.({
      type: "confirmation",
      txHash: "0xabc",
      transaction: {
        hash: "0xabc",
        status: TxStatus.CONFIRMED,
        submittedAt: Date.now(),
        confirmations: 2
      },
      confirmations: 2
    });
    await Promise.resolve();
    expect(resolved).toBe(false);

    listener?.({
      type: "confirmation",
      txHash: "0xabc",
      transaction: {
        hash: "0xabc",
        status: TxStatus.CONFIRMED,
        submittedAt: Date.now(),
        confirmations: 3
      },
      confirmations: 3
    });

    await expect(promise).resolves.toMatchObject({
      hash: "0xabc",
      confirmations: 3
    });
  });

  it("continues polling after the first confirmation so higher confirmation waits can resolve", async () => {
    vi.useFakeTimers();
    let currentBlock = 10;

    const provider = {
      getTransactionReceipt: vi.fn().mockResolvedValue({
        blockNumber: 10,
        gasUsed: 21_000n,
        gasPrice: 2n,
        status: 1
      }),
      getBlockNumber: vi.fn().mockImplementation(async () => currentBlock),
      getTransaction: vi.fn().mockResolvedValue({
        hash: "0xabc"
      })
    } as any;

    const tracker = new TransactionTracker(provider, 1000);

    const waitPromise = tracker.waitForConfirmation("0xabc", 3, 10_000);
    await Promise.resolve();
    await Promise.resolve();

    currentBlock = 11;
    await vi.advanceTimersByTimeAsync(1000);

    currentBlock = 12;
    await vi.advanceTimersByTimeAsync(1000);
    await expect(waitPromise).resolves.toMatchObject({
      hash: "0xabc",
      confirmations: 3,
      status: TxStatus.CONFIRMED
    });

    tracker.destroy();
    vi.useRealTimers();
  });
});
