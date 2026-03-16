import { Contract } from "ethers";
import type {
  NAVOracleStatus,
  NAVOracleHealth,
  NAVStatistics,
  NAVTrend,
  AnnualizedYield,
  CumulativeYield
} from "../types.js";

/**
 * Comprehensive NAV summary
 */
export interface NAVComprehensiveSummary {
  currentNav: bigint;
  lastUpdate: bigint;
  isFresh: boolean;
  isOverdue: boolean;
  secondsSinceUpdate: bigint;
  trend: NAVTrend;
  annualizedYield: AnnualizedYield;
  healthScore: bigint;
  statistics: NAVStatistics;
}

/**
 * Fetch NAVOracle status
 * @param oracle NAVOracle contract instance
 * @returns Oracle status
 */
export async function fetchNAVOracleStatus(oracle: Contract): Promise<NAVOracleStatus> {
  const [navPerShare, lastUpdate, isFresh, reportDate, totalAssets, configuredMaxChange] =
    await oracle.getOracleStatus();
  return { navPerShare, lastUpdate, isFresh, reportDate, totalAssets, configuredMaxChange };
}

/**
 * Fetch NAVOracle health metrics
 * @param oracle NAVOracle contract instance
 * @returns Oracle health data
 */
export async function fetchNAVOracleHealth(oracle: Contract): Promise<NAVOracleHealth> {
  const [isFresh, hasHistory, hasAttestor, ssUSDLinked, healthScore] =
    await oracle.getOracleHealth();
  return { isFresh, hasHistory, hasAttestor, ssUSDLinked, healthScore };
}

/**
 * Get current NAV per share
 * @param oracle NAVOracle contract instance
 * @returns NAV per share (1e18 = $1.00)
 */
export async function getCurrentNAVPerShare(oracle: Contract): Promise<bigint> {
  return await oracle.getCurrentNAVPerShare();
}

/**
 * Check if NAV is fresh (not stale)
 * @param oracle NAVOracle contract instance
 * @returns True if NAV is within staleness period
 */
export async function isNAVFresh(oracle: Contract): Promise<boolean> {
  return await oracle.isNAVFresh();
}

/**
 * Check if attestation is overdue
 * @param oracle NAVOracle contract instance
 * @returns True if NAV needs updating
 */
export async function isAttestationOverdue(oracle: Contract): Promise<boolean> {
  return await oracle.isAttestationOverdue();
}

/**
 * Get seconds since last NAV attestation
 * @param oracle NAVOracle contract instance
 * @returns Seconds elapsed
 */
export async function getSecondsSinceLastAttestation(oracle: Contract): Promise<bigint> {
  return await oracle.secondsSinceLastAttestation();
}

/**
 * Get NAV statistics from history
 * @param oracle NAVOracle contract instance
 * @returns NAV statistics
 */
export async function getNAVStatistics(oracle: Contract): Promise<NAVStatistics> {
  const [avgNav, minNav, maxNav, volatility, historyCount] = await oracle.getNAVStatistics();
  return { avgNav, minNav, maxNav, volatility, historyCount };
}

/**
 * Get NAV trend data
 * @param oracle NAVOracle contract instance
 * @returns NAV trend
 */
export async function getNAVTrend(oracle: Contract): Promise<NAVTrend> {
  const [currentNav, previousNav, changeBps, isPositive] = await oracle.getNAVTrend();
  return { currentNav, previousNav, changeBps, isPositive };
}

/**
 * Get annualized yield
 * @param oracle NAVOracle contract instance
 * @returns Annualized yield data
 */
export async function getNAVAnnualizedYield(oracle: Contract): Promise<AnnualizedYield> {
  const [annualizedBps, periodDays] = await oracle.getAnnualizedYield();
  return { annualizedBps, periodDays };
}

/**
 * Get cumulative yield since baseline
 * @param oracle NAVOracle contract instance
 * @param baselineNav NAV at baseline
 * @returns Cumulative yield
 */
export async function getNAVCumulativeYield(
  oracle: Contract,
  baselineNav: bigint
): Promise<CumulativeYield> {
  const [yieldBps, yieldAmount] = await oracle.getCumulativeYield(baselineNav);
  return { yieldBps, yieldAmount };
}

/**
 * Check if an address is an authorized attestor
 * @param oracle NAVOracle contract instance
 * @param attestor Address to check
 * @returns True if authorized
 */
export async function isAuthorizedAttestor(
  oracle: Contract,
  attestor: string
): Promise<boolean> {
  return await oracle.authorizedAttestors(attestor);
}

/**
 * Batch check attestor authorization
 * @param oracle NAVOracle contract instance
 * @param addresses Addresses to check
 * @returns Array of authorization statuses
 */
export async function batchCheckAttestorAuthorization(
  oracle: Contract,
  addresses: string[]
): Promise<boolean[]> {
  return await oracle.batchIsAuthorized(addresses);
}

/**
 * Get maximum allowed NAV change
 * @param oracle NAVOracle contract instance
 * @returns Maximum NAV per share allowed for next attestation
 */
export async function getMaxAllowedNAVChange(oracle: Contract): Promise<bigint> {
  return await oracle.getMaxAllowedNavChange();
}

/**
 * Get NAV history count
 * @param oracle NAVOracle contract instance
 * @returns Number of historical reports
 */
export async function getNAVHistoryCount(oracle: Contract): Promise<bigint> {
  return await oracle.getHistoryCount();
}

/**
 * Get comprehensive NAV summary combining multiple metrics
 * @param oracle NAVOracle contract instance
 * @returns Comprehensive summary
 */
export async function getNAVComprehensiveSummary(
  oracle: Contract
): Promise<NAVComprehensiveSummary> {
  const [status, health, trend, annualizedYield, secondsSinceUpdate, statistics] =
    await Promise.all([
      fetchNAVOracleStatus(oracle),
      fetchNAVOracleHealth(oracle),
      getNAVTrend(oracle),
      getNAVAnnualizedYield(oracle),
      getSecondsSinceLastAttestation(oracle),
      getNAVStatistics(oracle)
    ]);

  return {
    currentNav: status.navPerShare,
    lastUpdate: status.lastUpdate,
    isFresh: status.isFresh,
    isOverdue: !status.isFresh,
    secondsSinceUpdate,
    trend,
    annualizedYield,
    healthScore: health.healthScore,
    statistics
  };
}

/**
 * Calculate projected NAV based on current trend
 * @param oracle NAVOracle contract instance
 * @param daysAhead Number of days to project
 * @returns Projected NAV per share
 */
export async function getProjectedNAV(
  oracle: Contract,
  daysAhead: number
): Promise<bigint> {
  const [status, annualized] = await Promise.all([
    fetchNAVOracleStatus(oracle),
    getNAVAnnualizedYield(oracle)
  ]);

  const currentNav = status.navPerShare;
  const annualizedBps = annualized.annualizedBps;

  // Calculate daily rate from annual rate
  // dailyRate = annualizedBps / 365 / 10000 (bps to decimal)
  // projectedNav = currentNav * (1 + dailyRate * daysAhead)
  const dailyBps = annualizedBps / BigInt(365);
  const projectedNav = currentNav + (currentNav * dailyBps * BigInt(daysAhead)) / BigInt(10000);

  return projectedNav;
}

/**
 * Get time until NAV becomes stale
 * @param oracle NAVOracle contract instance
 * @returns Seconds until stale (0 if already stale)
 */
export async function getTimeUntilNAVStale(oracle: Contract): Promise<bigint> {
  const [secondsSince, stalenessPeriod] = await Promise.all([
    getSecondsSinceLastAttestation(oracle),
    oracle.stalenessPeriod() as Promise<bigint>
  ]);

  if (secondsSince >= stalenessPeriod) {
    return BigInt(0);
  }

  return stalenessPeriod - secondsSince;
}

/**
 * Check if NAV is within acceptable bounds
 * @param oracle NAVOracle contract instance
 * @param minNav Minimum acceptable NAV
 * @param maxNav Maximum acceptable NAV
 * @returns True if NAV is within bounds
 */
export async function isNAVWithinBounds(
  oracle: Contract,
  minNav: bigint,
  maxNav: bigint
): Promise<boolean> {
  const currentNav = await getCurrentNAVPerShare(oracle);
  return currentNav >= minNav && currentNav <= maxNav;
}
