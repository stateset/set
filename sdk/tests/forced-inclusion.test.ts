import { describe, expect, it } from "vitest";
import {
  categorizeForcedTxs,
  findExpiredForcedTxs,
  getForcedInclusionHealthSummary
} from "../src/contracts/forced-inclusion";

describe("forced inclusion helpers", () => {
  it("categorizes forced transactions by resolved and expired status", async () => {
    const forcedInclusion = {
      getBatchTxStatuses: async () => [
        [false, true, false],
        [false, false, true]
      ]
    } as any;

    await expect(
      categorizeForcedTxs(forcedInclusion, ["tx-pending", "tx-resolved", "tx-expired"])
    ).resolves.toEqual({
      pending: ["tx-pending"],
      resolved: ["tx-resolved"],
      expired: ["tx-expired"]
    });
  });

  it("finds expired unresolved forced transactions", async () => {
    const forcedInclusion = {
      getBatchTxStatuses: async () => [
        [false, true, false],
        [true, true, false]
      ]
    } as any;

    await expect(
      findExpiredForcedTxs(forcedInclusion, ["tx-expired", "tx-resolved", "tx-pending"])
    ).resolves.toEqual(["tx-expired"]);
  });

  it("rejects malformed batch status responses", async () => {
    const forcedInclusion = {
      getBatchTxStatuses: async () => [
        [false, true],
        [true]
      ]
    } as any;

    await expect(
      categorizeForcedTxs(forcedInclusion, ["tx-1", "tx-2"])
    ).rejects.toThrow("getBatchTxStatuses returned expired length 1, expected 2");
  });

  it("summarizes forced inclusion health from status and rate reads", async () => {
    const forcedInclusion = {
      getSystemStatus: async () => [3n, 10n, 8n, 2n, 50n, false, 5n],
      getInclusionRate: async () => 9_500n
    } as any;

    await expect(getForcedInclusionHealthSummary(forcedInclusion)).resolves.toEqual({
      isPaused: false,
      pendingCount: 3n,
      circuitBreakerCapacity: 5n,
      inclusionRate: 9_500n,
      bondsLocked: 50n,
      isHealthy: true
    });
  });
});
