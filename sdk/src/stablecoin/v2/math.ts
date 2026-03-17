/**
 * Stablecoin V2 client-side math helpers.
 *
 * These helpers intentionally mirror the on-chain policy and rounding rules so
 * agent preflight checks do not over-promise what the contracts will accept.
 */

const MAX_ASSET_AMOUNT = (1n << 256n) - 1n;
const RAY = 10n ** 27n;

export interface AvailableSpendInputs {
  collateralAssets: bigint;
  effectiveFloorAssets: bigint;
  navRay: bigint;
  perTxLimitAssets: bigint;
  dailyLimitAssets: bigint;
  spentTodayAssets: bigint;
  policyExists: boolean;
  sessionActive: boolean;
}

function saturatingSub(a: bigint, b: bigint): bigint {
  return a > b ? a - b : 0n;
}

export function computeConservativeSponsoredHeadroomAssets(
  collateralAssets: bigint,
  effectiveFloorAssets: bigint,
  navRay: bigint
): bigint {
  if (navRay <= 0n) {
    return 0n;
  }

  const collateralHeadroomAssets = saturatingSub(collateralAssets, effectiveFloorAssets);
  if (collateralHeadroomAssets === 0n) {
    return 0n;
  }

  // Sponsored escrows round assets -> shares up, then snapshot shares -> assets
  // down. We round down here so the SDK never claims more spend headroom than
  // the contract can safely reserve without breaching floor.
  const spendableShares = (collateralHeadroomAssets * RAY) / navRay;
  return (spendableShares * navRay) / RAY;
}

export function computeAvailableSpendAssets(inputs: AvailableSpendInputs): bigint {
  if (!inputs.policyExists || !inputs.sessionActive) {
    return 0n;
  }

  const collateralCap = computeConservativeSponsoredHeadroomAssets(
    inputs.collateralAssets,
    inputs.effectiveFloorAssets,
    inputs.navRay
  );
  if (collateralCap === 0n) {
    return 0n;
  }

  const perTxCap = inputs.perTxLimitAssets === 0n ? MAX_ASSET_AMOUNT : inputs.perTxLimitAssets;
  const dailyRemaining = inputs.dailyLimitAssets === 0n
    ? MAX_ASSET_AMOUNT
    : saturatingSub(inputs.dailyLimitAssets, inputs.spentTodayAssets);
  const policyCap = perTxCap < dailyRemaining ? perTxCap : dailyRemaining;

  return collateralCap < policyCap ? collateralCap : policyCap;
}

export function projectNAVRayFromBase(
  nav0Ray: bigint,
  t0Seconds: bigint,
  targetTimestampSeconds: bigint,
  ratePerSecondRay: bigint,
  maxStalenessSeconds: bigint
): bigint {
  if (targetTimestampSeconds <= t0Seconds) {
    return nav0Ray;
  }

  const elapsedSeconds = targetTimestampSeconds - t0Seconds;
  const boundedSeconds = elapsedSeconds < maxStalenessSeconds ? elapsedSeconds : maxStalenessSeconds;
  const projectedNav = nav0Ray + (ratePerSecondRay * boundedSeconds);

  return projectedNav > 0n ? projectedNav : 0n;
}
