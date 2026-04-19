import { describe, expect, it } from "vitest";
import {
  fetchAllTiers,
  fetchBatchMerchantDetails,
  findSponsorableMerchants,
  getMerchantTierLimits
} from "../src/contracts/paymaster";

describe("paymaster helpers", () => {
  it("maps aligned tier arrays into sponsorship tiers", async () => {
    const paymaster = {
      getAllTiers: async () => [
        [1n, 2n],
        ["Starter", "Growth"],
        [100n, 200n],
        [1000n, 2000n],
        [5000n, 7000n]
      ]
    } as any;

    await expect(fetchAllTiers(paymaster)).resolves.toEqual([
      {
        tierId: 1n,
        name: "Starter",
        maxPerTx: 100n,
        maxPerDay: 1000n,
        maxPerMonth: 5000n
      },
      {
        tierId: 2n,
        name: "Growth",
        maxPerTx: 200n,
        maxPerDay: 2000n,
        maxPerMonth: 7000n
      }
    ]);
  });

  it("rejects malformed tier responses with mismatched array lengths", async () => {
    const paymaster = {
      getAllTiers: async () => [
        [1n, 2n],
        ["Starter"],
        [100n, 200n],
        [1000n, 2000n],
        [5000n, 7000n]
      ]
    } as any;

    await expect(fetchAllTiers(paymaster)).rejects.toThrow(
      "getAllTiers returned names length 1, expected 2"
    );
  });

  it("rejects malformed batch merchant detail responses", async () => {
    const paymaster = {
      batchGetMerchantDetails: async () => [
        [true, false],
        [1n, 2n],
        [10n],
        [100n, 200n],
        [1000n, 2000n]
      ]
    } as any;

    await expect(
      fetchBatchMerchantDetails(paymaster, ["0x1", "0x2"])
    ).rejects.toThrow("batchGetMerchantDetails returned spentTodays length 1, expected 2");
  });

  it("rejects malformed sponsorable merchant responses", async () => {
    const paymaster = {
      batchCanSponsor: async () => [
        [true],
        ["daily cap reached", "ok"]
      ]
    } as any;

    await expect(
      findSponsorableMerchants(paymaster, ["0x1", "0x2"], [10n, 20n])
    ).rejects.toThrow("batchCanSponsor returned canSponsor length 1, expected 2");
  });

  it("returns the merchant tier limits when the merchant is active and the tier exists", async () => {
    const paymaster = {
      getMerchantDetails: async () => [true, 2n, 25n, 250n, 2500n],
      getAllTiers: async () => [
        [1n, 2n],
        ["Starter", "Growth"],
        [100n, 200n],
        [1000n, 2000n],
        [5000n, 7000n]
      ]
    } as any;

    await expect(getMerchantTierLimits(paymaster, "0x1")).resolves.toEqual({
      maxPerTx: 200n,
      maxPerDay: 2000n,
      maxPerMonth: 7000n,
      tierName: "Growth"
    });
  });
});
