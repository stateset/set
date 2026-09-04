import { describe, expect, it, vi } from "vitest";
import {
  batchCheckSequencerAuthorization,
  batchVerifyTxPositions,
  fetchAttestationStats,
  getAttestationHealthSummary,
  getAttestationSuccessRate,
  getBlockHashForNumber,
  getCommitmentByBlockNumber,
  getOrderingCommitment,
  hasOrderingCommitment,
  isSequencerAuthorized,
  verifyTxPosition
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

  it("rejects non-integer numeric tx counts", async () => {
    const attestation = {
      getCommitmentByBlockNumber: vi.fn().mockResolvedValue({
        blockHash: "0xblock",
        txOrderingRoot: "0xroot",
        blockNumber: 1n,
        timestamp: 2n,
        txCount: 1.5,
        sequencer: "0xsequencer"
      })
    };

    await expect(getCommitmentByBlockNumber(attestation as any, 1)).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("txCount must be an integer")
    });
  });

  it("maps stats and delegates verification queries", async () => {
    const stats = {
      totalCommitments: 4n,
      totalVerifications: 10n,
      failedVerifications: 1n,
      lastCommitmentTime: 100n
    };
    const attestation = {
      getStats: vi.fn().mockResolvedValue(stats),
      hasCommitment: vi.fn().mockResolvedValue(true),
      authorizedSequencers: vi.fn().mockImplementation(async (value: string) => value === "a"),
      verifyTxPositionView: vi.fn().mockResolvedValue(true),
      batchVerify: vi.fn().mockResolvedValue([true, false]),
      blockNumberToHash: vi.fn().mockResolvedValue("0xblock")
    };
    const contract = attestation as any;

    await expect(fetchAttestationStats(contract)).resolves.toEqual(stats);
    await expect(hasOrderingCommitment(contract, "0xblock")).resolves.toBe(true);
    await expect(isSequencerAuthorized(contract, "a")).resolves.toBe(true);
    await expect(verifyTxPosition(contract, "0xblock", "0xtx", 2, ["0xproof"])).resolves.toBe(true);
    await expect(
      batchVerifyTxPositions(contract, "0xblock", ["0xa", "0xb"], [0, 1], ["0xp"], 1)
    ).resolves.toEqual([true, false]);
    await expect(getBlockHashForNumber(contract, 10)).resolves.toBe("0xblock");
    await expect(batchCheckSequencerAuthorization(contract, ["a", "b"])).resolves.toEqual([
      true,
      false
    ]);

    expect(attestation.verifyTxPositionView).toHaveBeenCalledWith(
      "0xblock",
      "0xtx",
      2,
      ["0xproof"]
    );
  });

  it("computes success rates including the no-verification default", async () => {
    const attestation = {
      getStats: vi
        .fn()
        .mockResolvedValueOnce({
          totalCommitments: 0n,
          totalVerifications: 0n,
          failedVerifications: 0n,
          lastCommitmentTime: 0n
        })
        .mockResolvedValueOnce({
          totalCommitments: 2n,
          totalVerifications: 20n,
          failedVerifications: 1n,
          lastCommitmentTime: 100n
        })
    };

    await expect(getAttestationSuccessRate(attestation as any)).resolves.toBe(10000n);
    await expect(getAttestationSuccessRate(attestation as any)).resolves.toBe(9500n);
  });

  it("derives healthy and unhealthy summaries from commitment freshness and success", async () => {
    vi.spyOn(Date, "now").mockReturnValue(200_000);
    const healthy = {
      getStats: vi.fn().mockResolvedValue({
        totalCommitments: 2n,
        totalVerifications: 100n,
        failedVerifications: 2n,
        lastCommitmentTime: 150n
      })
    };
    const unhealthy = {
      getStats: vi.fn().mockResolvedValue({
        totalCommitments: 0n,
        totalVerifications: 10n,
        failedVerifications: 2n,
        lastCommitmentTime: 0n
      })
    };

    await expect(getAttestationHealthSummary(healthy as any)).resolves.toMatchObject({
      successRate: 9800n,
      secondsSinceLastCommitment: 50n,
      isHealthy: true
    });
    await expect(getAttestationHealthSummary(unhealthy as any)).resolves.toMatchObject({
      successRate: 8000n,
      secondsSinceLastCommitment: 0n,
      isHealthy: false
    });

    vi.restoreAllMocks();
  });
});
