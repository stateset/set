import { describe, expect, it, vi } from "vitest";
import {
  batchGetEncryptedTxStatuses,
  categorizeEncryptedTxs,
  getEncryptedTxStatus
} from "../src/contracts/encrypted-mempool";
import { SDKErrorCode } from "../src/errors";

describe("encrypted mempool helpers", () => {
  it("normalizes bigint status codes", async () => {
    const mempool = {
      getTxStatus: vi.fn().mockResolvedValue([4n, "Executed", 0n, false]),
      getBatchTxStatuses: vi.fn().mockResolvedValue([0n, 4n, 6n])
    };

    await expect(getEncryptedTxStatus(mempool as any, `0x${"11".repeat(32)}`)).resolves.toEqual({
      status: 4,
      statusName: "Executed",
      blocksUntilExpiry: 0n,
      canExecute: false
    });

    await expect(batchGetEncryptedTxStatuses(mempool as any, ["a", "b", "c"])).resolves.toEqual([
      0,
      4,
      6
    ]);
  });

  it("categorizes bigint-backed batch statuses correctly", async () => {
    const mempool = {
      getBatchTxStatuses: vi.fn().mockResolvedValue([0n, 1n, 4n, 5n, 6n])
    };

    await expect(
      categorizeEncryptedTxs(mempool as any, ["tx0", "tx1", "tx4", "tx5", "tx6"])
    ).resolves.toEqual({
      pending: ["tx0"],
      ordered: ["tx1"],
      decrypted: [],
      executed: ["tx4"],
      failed: ["tx5"],
      expired: ["tx6"]
    });
  });

  it("rejects out-of-range status codes", async () => {
    const mempool = {
      getTxStatus: vi.fn().mockResolvedValue([
        BigInt(Number.MAX_SAFE_INTEGER) + 1n,
        "Invalid",
        0n,
        false
      ])
    };

    await expect(
      getEncryptedTxStatus(mempool as any, `0x${"11".repeat(32)}`)
    ).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("status exceeds safe integer range")
    });
  });

  it("rejects unknown but in-range-safe status codes", async () => {
    const mempool = {
      getBatchTxStatuses: vi.fn().mockResolvedValue([0n, 99n])
    };

    await expect(
      batchGetEncryptedTxStatuses(mempool as any, ["tx0", "tx99"])
    ).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("status is not a valid encrypted transaction status")
    });
  });
});
