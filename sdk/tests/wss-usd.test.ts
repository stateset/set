import { describe, expect, it, vi } from "vitest";
import {
  canAccountWrapWssUSD,
  fetchWssUSDVaultStatus,
  getLatestWssUSDSnapshots,
  getWssUSDPriceHistory,
  getWssUSDVaultStatistics
} from "../src/contracts/wss-usd";
import { SDKErrorCode } from "../src/errors";

describe("wssUSD helpers", () => {
  it("maps vault status and statistics reads", async () => {
    const vault = {
      getVaultStatus: vi.fn().mockResolvedValue([1_000n, 900n, 1_050n, 5_000n, 4_000n, 1_000n, false]),
      getVaultStatistics: vi.fn().mockResolvedValue([1_000n, 900n, 1_050n, 500n, 7n, 10_000n, 3_600n])
    };

    await expect(fetchWssUSDVaultStatus(vault as any)).resolves.toEqual({
      assets: 1_000n,
      supply: 900n,
      sharePrice: 1_050n,
      cap: 5_000n,
      deposited: 4_000n,
      remainingCap: 1_000n,
      isPaused: false
    });

    await expect(getWssUSDVaultStatistics(vault as any)).resolves.toEqual({
      assets: 1_000n,
      supply: 900n,
      sharePrice: 1_050n,
      yieldBps: 500n,
      snapshotCount: 7n,
      dailyLimit: 10_000n,
      cooldown: 3_600n
    });
  });

  it("maps aligned price history snapshots", async () => {
    const vault = {
      getSharePriceHistoryRange: vi.fn().mockResolvedValue([[101n, 102n], [1_700_000_000n, 1_700_000_060n]]),
      getLatestSnapshots: vi.fn().mockResolvedValue([[103n, 102n], [1_700_000_120n, 1_700_000_060n]])
    };

    await expect(getWssUSDPriceHistory(vault as any, 0, 2)).resolves.toEqual([
      { price: 101n, timestamp: 1_700_000_000n },
      { price: 102n, timestamp: 1_700_000_060n }
    ]);

    await expect(getLatestWssUSDSnapshots(vault as any, 2)).resolves.toEqual([
      { price: 103n, timestamp: 1_700_000_120n },
      { price: 102n, timestamp: 1_700_000_060n }
    ]);
  });

  it("rejects malformed price history snapshot responses", async () => {
    const vault = {
      getSharePriceHistoryRange: vi.fn().mockResolvedValue([[101n, 102n], [1_700_000_000n]]),
      getLatestSnapshots: vi.fn().mockResolvedValue([[103n, 102n], [1_700_000_120n]])
    };

    await expect(getWssUSDPriceHistory(vault as any, 0, 2)).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("getSharePriceHistoryRange returned timestamps length 1, expected 2")
    });

    await expect(getLatestWssUSDSnapshots(vault as any, 2)).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("getLatestSnapshots returned timestamps length 1, expected 2")
    });
  });

  it("normalizes bigint wrap reason codes", async () => {
    const vault = {
      canAccountWrap: vi.fn().mockResolvedValue([false, 2n])
    };

    await expect(
      canAccountWrapWssUSD(
        vault as any,
        "0x1000000000000000000000000000000000000001",
        1_000_000n
      )
    ).resolves.toEqual({
      canWrap: false,
      reason: 2
    });
  });

  it("rejects out-of-range wrap reason codes", async () => {
    const vault = {
      canAccountWrap: vi.fn().mockResolvedValue([false, BigInt(Number.MAX_SAFE_INTEGER) + 1n])
    };

    await expect(
      canAccountWrapWssUSD(
        vault as any,
        "0x1000000000000000000000000000000000000001",
        1_000_000n
      )
    ).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("reason exceeds safe integer range")
    });
  });
});
