import { Contract } from "ethers";

/**
 * Forced inclusion system status
 */
export interface ForcedInclusionStatus {
  pendingCount: bigint;
  totalForced: bigint;
  totalIncluded: bigint;
  totalExpired: bigint;
  bondsLocked: bigint;
  isPaused: boolean;
  circuitBreakerCapacity: bigint;
}

/**
 * Forced transaction details
 */
export interface ForcedTxDetails {
  sender: string;
  target: string;
  bond: bigint;
  deadline: bigint;
  isResolved: boolean;
  isExpiredNow: boolean;
  timeRemaining: bigint;
}

/**
 * User forced inclusion summary
 */
export interface ForcedInclusionUserSummary {
  totalSubmitted: bigint;
  pendingCount: bigint;
  currentRateUsed: bigint;
  canSubmitNow: boolean;
}

/**
 * Fetch forced inclusion system status
 * @param forcedInclusion ForcedInclusion contract instance
 * @returns System status
 */
export async function fetchForcedInclusionStatus(
  forcedInclusion: Contract
): Promise<ForcedInclusionStatus> {
  const [pendingCount, totalForced, totalIncluded, totalExpired, bondsLocked, isPaused, circuitBreakerCapacity] =
    await forcedInclusion.getSystemStatus();
  return { pendingCount, totalForced, totalIncluded, totalExpired, bondsLocked, isPaused, circuitBreakerCapacity };
}

/**
 * Get forced transaction details
 * @param forcedInclusion ForcedInclusion contract instance
 * @param txId Transaction ID
 * @returns Transaction details
 */
export async function getForcedTxDetails(
  forcedInclusion: Contract,
  txId: string
): Promise<ForcedTxDetails> {
  const [sender, target, bond, deadline, isResolved, isExpiredNow, timeRemaining] =
    await forcedInclusion.getTxDetails(txId);
  return { sender, target, bond, deadline, isResolved, isExpiredNow, timeRemaining };
}

/**
 * Get user's pending forced transactions
 * @param forcedInclusion ForcedInclusion contract instance
 * @param user User address
 * @returns Array of transaction IDs
 */
export async function getUserForcedPendingTxs(
  forcedInclusion: Contract,
  user: string
): Promise<string[]> {
  return await forcedInclusion.getUserPendingTxs(user);
}

/**
 * Get user's forced inclusion summary
 * @param forcedInclusion ForcedInclusion contract instance
 * @param user User address
 * @returns User summary
 */
export async function getForcedInclusionUserSummary(
  forcedInclusion: Contract,
  user: string
): Promise<ForcedInclusionUserSummary> {
  const [totalSubmitted, pendingCount, currentRateUsed, canSubmitNow] =
    await forcedInclusion.getUserSummary(user);
  return { totalSubmitted, pendingCount, currentRateUsed, canSubmitNow };
}

/**
 * Check if user is rate limited for forced inclusion
 * @param forcedInclusion ForcedInclusion contract instance
 * @param user User address
 * @returns Rate limit status
 */
export async function isForcedInclusionRateLimited(
  forcedInclusion: Contract,
  user: string
): Promise<{ limited: boolean; remaining: bigint }> {
  const [limited, remaining] = await forcedInclusion.isRateLimited(user);
  return { limited, remaining };
}

/**
 * Check if forced transaction is pending
 * @param forcedInclusion ForcedInclusion contract instance
 * @param txId Transaction ID
 * @returns True if pending
 */
export async function isForcedTxPending(
  forcedInclusion: Contract,
  txId: string
): Promise<boolean> {
  return await forcedInclusion.isPending(txId);
}

/**
 * Check if forced transaction has expired
 * @param forcedInclusion ForcedInclusion contract instance
 * @param txId Transaction ID
 * @returns True if expired
 */
export async function isForcedTxExpired(
  forcedInclusion: Contract,
  txId: string
): Promise<boolean> {
  return await forcedInclusion.isExpired(txId);
}

/**
 * Batch get forced transaction statuses
 * @param forcedInclusion ForcedInclusion contract instance
 * @param txIds Transaction IDs
 * @returns Batch status
 */
export async function batchGetForcedTxStatuses(
  forcedInclusion: Contract,
  txIds: string[]
): Promise<{ resolved: boolean[]; expired: boolean[] }> {
  const [resolved, expired] = await forcedInclusion.getBatchTxStatuses(txIds);
  return { resolved, expired };
}

/**
 * Get forced inclusion rate
 * @param forcedInclusion ForcedInclusion contract instance
 * @returns Inclusion rate in basis points (10000 = 100%)
 */
export async function getForcedInclusionRate(
  forcedInclusion: Contract
): Promise<bigint> {
  return await forcedInclusion.getInclusionRate();
}

/**
 * Get pending forced transaction count
 * @param forcedInclusion ForcedInclusion contract instance
 * @returns Pending count
 */
export async function getForcedPendingCount(
  forcedInclusion: Contract
): Promise<bigint> {
  return await forcedInclusion.getPendingCount();
}

/**
 * Check if forced inclusion is paused
 * @param forcedInclusion ForcedInclusion contract instance
 * @returns True if paused
 */
export async function isForcedInclusionPaused(
  forcedInclusion: Contract
): Promise<boolean> {
  return await forcedInclusion.paused();
}

/**
 * Get forced inclusion health summary
 * @param forcedInclusion ForcedInclusion contract instance
 * @returns Health summary
 */
export async function getForcedInclusionHealthSummary(
  forcedInclusion: Contract
): Promise<{
  isPaused: boolean;
  pendingCount: bigint;
  circuitBreakerCapacity: bigint;
  inclusionRate: bigint;
  bondsLocked: bigint;
  isHealthy: boolean;
}> {
  const [status, inclusionRate] = await Promise.all([
    fetchForcedInclusionStatus(forcedInclusion),
    getForcedInclusionRate(forcedInclusion)
  ]);

  return {
    isPaused: status.isPaused,
    pendingCount: status.pendingCount,
    circuitBreakerCapacity: status.circuitBreakerCapacity,
    inclusionRate,
    bondsLocked: status.bondsLocked,
    isHealthy: !status.isPaused && status.circuitBreakerCapacity > BigInt(0)
  };
}

/**
 * Find expired forced transactions that can be claimed
 * @param forcedInclusion ForcedInclusion contract instance
 * @param txIds Transaction IDs to check
 * @returns Array of expired transaction IDs
 */
export async function findExpiredForcedTxs(
  forcedInclusion: Contract,
  txIds: string[]
): Promise<string[]> {
  const { resolved, expired } = await batchGetForcedTxStatuses(forcedInclusion, txIds);
  const expiredTxs: string[] = [];

  for (let i = 0; i < txIds.length; i++) {
    if (!resolved[i] && expired[i]) {
      expiredTxs.push(txIds[i]);
    }
  }

  return expiredTxs;
}

/**
 * Categorize forced transactions by status
 * @param forcedInclusion ForcedInclusion contract instance
 * @param txIds Transaction IDs to categorize
 * @returns Categorized transactions
 */
export async function categorizeForcedTxs(
  forcedInclusion: Contract,
  txIds: string[]
): Promise<{
  pending: string[];
  resolved: string[];
  expired: string[];
}> {
  const { resolved, expired } = await batchGetForcedTxStatuses(forcedInclusion, txIds);
  const result = {
    pending: [] as string[],
    resolved: [] as string[],
    expired: [] as string[]
  };

  for (let i = 0; i < txIds.length; i++) {
    if (resolved[i]) {
      result.resolved.push(txIds[i]);
    } else if (expired[i]) {
      result.expired.push(txIds[i]);
    } else {
      result.pending.push(txIds[i]);
    }
  }

  return result;
}
