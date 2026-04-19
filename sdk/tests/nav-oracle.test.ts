import { describe, expect, it } from "vitest";
import {
  getNAVComprehensiveSummary,
  getProjectedNAV,
  getTimeUntilNAVStale
} from "../src/contracts/nav-oracle";

describe("nav oracle helpers", () => {
  it("uses the explicit overdue check in the comprehensive summary", async () => {
    const oracle = {
      getOracleStatus: async () => [1050n, 1_700_000_000n, true, 20260418n, 1_000_000n, 500n],
      getOracleHealth: async () => [true, true, true, true, 95n],
      getNAVTrend: async () => [1050n, 1000n, 500n, true],
      getAnnualizedYield: async () => [1200n, 30n],
      secondsSinceLastAttestation: async () => 3_600n,
      getNAVStatistics: async () => [1025n, 1000n, 1050n, 75n, 10n],
      isAttestationOverdue: async () => true
    } as any;

    await expect(getNAVComprehensiveSummary(oracle)).resolves.toEqual({
      currentNav: 1050n,
      lastUpdate: 1_700_000_000n,
      isFresh: true,
      isOverdue: true,
      secondsSinceUpdate: 3_600n,
      trend: {
        currentNav: 1050n,
        previousNav: 1000n,
        changeBps: 500n,
        isPositive: true
      },
      annualizedYield: {
        annualizedBps: 1200n,
        periodDays: 30n
      },
      healthScore: 95n,
      statistics: {
        avgNav: 1025n,
        minNav: 1000n,
        maxNav: 1050n,
        volatility: 75n,
        historyCount: 10n
      }
    });
  });

  it("projects NAV forward for whole non-negative days", async () => {
    const oracle = {
      getOracleStatus: async () => [1_000_000n, 0n, true, 0n, 0n, 0n],
      getAnnualizedYield: async () => [3650n, 30n]
    } as any;

    await expect(getProjectedNAV(oracle, 10)).resolves.toBe(1_010_000n);
  });

  it("rejects fractional or negative projection windows", async () => {
    const oracle = {} as any;

    await expect(getProjectedNAV(oracle, -1)).rejects.toThrow(
      "daysAhead must be a non-negative integer"
    );
    await expect(getProjectedNAV(oracle, 1.5)).rejects.toThrow(
      "daysAhead must be a non-negative integer"
    );
  });

  it("clamps stale time remaining at zero", async () => {
    const oracle = {
      secondsSinceLastAttestation: async () => 7_200n,
      stalenessPeriod: async () => 3_600n
    } as any;

    await expect(getTimeUntilNAVStale(oracle)).resolves.toBe(0n);
  });
});
