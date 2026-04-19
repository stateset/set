import { describe, expect, it, vi } from "vitest";
import {
  getCommitmentByBlockNumber,
  getOrderingCommitment
} from "../src/contracts/sequencer-attestation";
import { SDKErrorCode } from "../src/errors";

describe("sequencer attestation helpers", () => {
  it("normalizes bigint tx counts returned by attestation commitments", async () => {
    const attestation = {
      commitments: vi.fn().mockResolvedValue([
        `0x${"11".repeat(32)}`,
        `0x${"22".repeat(32)}`,
        123n,
        456n,
        7n,
        "0x1000000000000000000000000000000000000001"
      ]),
      getCommitmentByBlockNumber: vi.fn().mockResolvedValue({
        blockHash: `0x${"33".repeat(32)}`,
        txOrderingRoot: `0x${"44".repeat(32)}`,
        blockNumber: 789n,
        timestamp: 999n,
        txCount: 9n,
        sequencer: "0x2000000000000000000000000000000000000002"
      })
    };

    await expect(
      getOrderingCommitment(attestation as any, `0x${"11".repeat(32)}`)
    ).resolves.toMatchObject({ txCount: 7 });

    await expect(
      getCommitmentByBlockNumber(attestation as any, 789)
    ).resolves.toMatchObject({ txCount: 9 });
  });

  it("rejects out-of-range bigint tx counts", async () => {
    const attestation = {
      getCommitmentByBlockNumber: vi.fn().mockResolvedValue({
        blockHash: `0x${"33".repeat(32)}`,
        txOrderingRoot: `0x${"44".repeat(32)}`,
        blockNumber: 789n,
        timestamp: 999n,
        txCount: BigInt(Number.MAX_SAFE_INTEGER) + 1n,
        sequencer: "0x2000000000000000000000000000000000000002"
      })
    };

    await expect(
      getCommitmentByBlockNumber(attestation as any, 789)
    ).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("txCount exceeds safe integer range")
    });
  });
});
