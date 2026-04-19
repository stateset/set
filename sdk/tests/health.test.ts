import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("../src/contracts/registry", () => ({
  fetchRegistryStats: vi.fn()
}));

vi.mock("../src/contracts/paymaster", () => ({
  getPaymasterHealthSummary: vi.fn()
}));

vi.mock("../src/contracts/treasury-vault", () => ({
  fetchTreasuryVaultHealth: vi.fn()
}));

vi.mock("../src/contracts/nav-oracle", () => ({
  fetchNAVOracleHealth: vi.fn()
}));

vi.mock("../src/contracts/encrypted-mempool", () => ({
  getMempoolHealthSummary: vi.fn()
}));

vi.mock("../src/contracts/forced-inclusion", () => ({
  getForcedInclusionHealthSummary: vi.fn()
}));

vi.mock("../src/contracts/sequencer-attestation", () => ({
  getAttestationHealthSummary: vi.fn()
}));

vi.mock("../src/contracts/timelock", () => ({
  getTimelockHealthSummary: vi.fn()
}));

vi.mock("../src/contracts/threshold-key-registry", () => ({
  fetchThresholdRegistryStatus: vi.fn()
}));

import { formatHealthStatus, performSystemHealthCheck } from "../src/contracts/health";
import { fetchNAVOracleHealth } from "../src/contracts/nav-oracle";
import { fetchRegistryStats } from "../src/contracts/registry";

describe("system health helpers", () => {
  beforeEach(() => {
    vi.resetAllMocks();
  });

  it("marks the whole system unhealthy when NAV is fresh but below the score threshold", async () => {
    vi.mocked(fetchNAVOracleHealth).mockResolvedValue({
      isFresh: true,
      hasHistory: true,
      hasAttestor: true,
      ssUSDLinked: true,
      healthScore: 79n
    });

    const health = await performSystemHealthCheck({
      navOracle: {} as any
    });

    expect(health.overallHealthy).toBe(false);
    expect(health.components.navOracle).toEqual({
      healthy: false,
      isFresh: true,
      healthScore: 79n
    });
    expect(health.errors).toEqual([]);
  });

  it("records component errors and formats them in the status output", async () => {
    vi.mocked(fetchRegistryStats).mockRejectedValue(new Error("registry offline"));

    const health = await performSystemHealthCheck({
      registry: {} as any
    });

    expect(health.overallHealthy).toBe(false);
    expect(health.components.registry).toEqual({
      healthy: false
    });
    expect(health.errors).toEqual([
      "Registry: registry offline"
    ]);

    expect(formatHealthStatus(health)).toContain("Overall: UNHEALTHY");
    expect(formatHealthStatus(health)).toContain("registry: FAIL");
    expect(formatHealthStatus(health)).toContain("Registry: registry offline");
  });
});
