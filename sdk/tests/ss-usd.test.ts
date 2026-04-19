import { describe, expect, it } from "vitest";
import {
  fetchBatchSsUSDBalances,
  fetchBatchSsUSDShares,
  fetchSsUSDAccountDetails,
  fetchSsUSDTokenStatus,
  getSsUSDAccruedYield,
  ssUSDAmountToShares,
  ssUSDSharesToAmount
} from "../src/contracts/ss-usd";

describe("ssUSD helpers", () => {
  it("maps token status reads into a typed status object", async () => {
    const ssUSD = {
      getTokenStatus: async () => [1_000_000n, 900_000n, 1_050_000_000_000_000_000n, false, "0xvault", "0xoracle"]
    } as any;

    await expect(fetchSsUSDTokenStatus(ssUSD)).resolves.toEqual({
      totalSupply: 1_000_000n,
      totalShares: 900_000n,
      navPerShare: 1_050_000_000_000_000_000n,
      isPaused: false,
      treasuryVault: "0xvault",
      navOracle: "0xoracle"
    });
  });

  it("maps account details and accrued yield reads", async () => {
    const ssUSD = {
      getAccountDetails: async () => [25_000n, 20_000n, 250n],
      getAccruedYield: async () => [1_500n, 600n]
    } as any;

    await expect(fetchSsUSDAccountDetails(ssUSD, "0x1")).resolves.toEqual({
      balance: 25_000n,
      shares: 20_000n,
      percentOfSupply: 250n
    });
    await expect(getSsUSDAccruedYield(ssUSD, "0x1", 1_000_000_000_000_000_000n)).resolves.toEqual({
      yieldAccrued: 1_500n,
      yieldPercent: 600n
    });
  });

  it("passes through batch balance and share reads", async () => {
    const ssUSD = {
      batchBalanceOf: async () => [10n, 20n],
      batchSharesOf: async () => [8n, 16n]
    } as any;

    await expect(fetchBatchSsUSDBalances(ssUSD, ["0x1", "0x2"])).resolves.toEqual([10n, 20n]);
    await expect(fetchBatchSsUSDShares(ssUSD, ["0x1", "0x2"])).resolves.toEqual([8n, 16n]);
  });

  it("converts between rebased amounts and shares", async () => {
    const ssUSD = {
      getSharesByAmount: async (amount: bigint) => amount / 2n,
      getAmountByShares: async (shares: bigint) => shares * 2n
    } as any;

    await expect(ssUSDAmountToShares(ssUSD, 100n)).resolves.toBe(50n);
    await expect(ssUSDSharesToAmount(ssUSD, 50n)).resolves.toBe(100n);
  });
});
