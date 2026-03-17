import { describe, expect, it } from "vitest";
import {
  computeAvailableSpendAssets,
  computeConservativeSponsoredHeadroomAssets,
  projectNAVRayFromBase,
} from "../src/stablecoin/v2/math.js";

const RAY = 10n ** 27n;

describe("stablecoin v2 client math", () => {
  it("treats zero per-tx and daily limits as unlimited", () => {
    expect(computeAvailableSpendAssets({
      collateralAssets: 120_000_000n,
      effectiveFloorAssets: 20_000_000n,
      navRay: RAY,
      perTxLimitAssets: 0n,
      dailyLimitAssets: 0n,
      spentTodayAssets: 0n,
      policyExists: true,
      sessionActive: true,
    })).toBe(100_000_000n);
  });

  it("caps available spend by the tighter policy limit", () => {
    expect(computeAvailableSpendAssets({
      collateralAssets: 100_000_000n,
      effectiveFloorAssets: 10_000_000n,
      navRay: RAY,
      perTxLimitAssets: 40_000_000n,
      dailyLimitAssets: 50_000_000n,
      spentTodayAssets: 15_000_000n,
      policyExists: true,
      sessionActive: true,
    })).toBe(35_000_000n);
  });

  it("rounds sponsored collateral headroom down so escrow prechecks stay conservative", () => {
    const navRay = 11n * (10n ** 26n);

    expect(computeConservativeSponsoredHeadroomAssets(
      1_000_000n,
      0n,
      navRay
    )).toBe(999_999n);
  });

  it("returns zero spend when policy is missing or the session expired", () => {
    expect(computeAvailableSpendAssets({
      collateralAssets: 100_000_000n,
      effectiveFloorAssets: 0n,
      navRay: RAY,
      perTxLimitAssets: 0n,
      dailyLimitAssets: 0n,
      spentTodayAssets: 0n,
      policyExists: false,
      sessionActive: true,
    })).toBe(0n);

    expect(computeAvailableSpendAssets({
      collateralAssets: 100_000_000n,
      effectiveFloorAssets: 0n,
      navRay: RAY,
      perTxLimitAssets: 0n,
      dailyLimitAssets: 0n,
      spentTodayAssets: 0n,
      policyExists: true,
      sessionActive: false,
    })).toBe(0n);
  });

  it("caps NAV projection by max staleness from the controller base state", () => {
    expect(projectNAVRayFromBase(
      RAY,
      1_000n,
      1_200n,
      10n,
      50n
    )).toBe(RAY + 500n);
  });

  it("returns zero when a negative projected NAV would go below zero", () => {
    expect(projectNAVRayFromBase(
      100n,
      1_000n,
      1_100n,
      -2n,
      1_000n
    )).toBe(0n);
  });
});
