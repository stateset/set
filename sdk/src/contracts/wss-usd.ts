import { Contract } from "ethers";
import type {
  WssUSDVaultStatus,
  WssUSDAccountDetails,
  WssUSDRateLimitStatus,
  WssUSDVaultStatistics,
  SharePriceSnapshot,
  YieldOverPeriod
} from "../types.js";

/**
 * Fetch wssUSD vault status
 * @param vault wssUSD contract instance
 * @returns Vault status
 */
export async function fetchWssUSDVaultStatus(vault: Contract): Promise<WssUSDVaultStatus> {
  const [assets, supply, sharePrice, cap, deposited, remainingCap, isPaused] =
    await vault.getVaultStatus();
  return {
    assets,
    supply,
    sharePrice,
    cap,
    deposited,
    remainingCap,
    isPaused
  };
}

/**
 * Fetch wssUSD account details
 * @param vault wssUSD contract instance
 * @param account Account to query
 * @returns Account details
 */
export async function fetchWssUSDAccountDetails(
  vault: Contract,
  account: string
): Promise<WssUSDAccountDetails> {
  const [wssUSDBalance, ssUSDValue, percentOfVault] = await vault.getAccountDetails(account);
  return { wssUSDBalance, ssUSDValue, percentOfVault };
}

/**
 * Get current wssUSD share price
 * @param vault wssUSD contract instance
 * @returns Share price (1e18 = 1:1 with ssUSD)
 */
export async function getWssUSDSharePrice(vault: Contract): Promise<bigint> {
  return await vault.getSharePrice();
}

/**
 * Get yield accrued since initial 1:1 ratio
 * @param vault wssUSD contract instance
 * @returns Yield in basis points (100 = 1%)
 */
export async function getWssUSDAccruedYield(vault: Contract): Promise<bigint> {
  return await vault.getAccruedYield();
}

/**
 * Check if wssUSD vault is accepting deposits
 * @param vault wssUSD contract instance
 * @returns True if vault is operational
 */
export async function isWssUSDVaultOperational(vault: Contract): Promise<boolean> {
  return !(await vault.paused());
}

/**
 * Get maximum deposit allowed for an account
 * @param vault wssUSD contract instance
 * @param account Account to check
 * @returns Maximum depositable amount
 */
export async function getMaxWssUSDDeposit(vault: Contract, account: string): Promise<bigint> {
  return await vault.maxDeposit(account);
}

/**
 * Get rate limit status for an account
 * @param vault wssUSD contract instance
 * @param account Account to check
 * @returns Rate limit status
 */
export async function getWssUSDRateLimitStatus(
  vault: Contract,
  account: string
): Promise<WssUSDRateLimitStatus> {
  const [remainingDaily, cooldownRemaining, canWrap] = await vault.getRateLimitStatus(account);
  return { remainingDaily, cooldownRemaining, canWrap };
}

/**
 * Check if account can wrap a specific amount
 * @param vault wssUSD contract instance
 * @param account Account to check
 * @param amount Amount to wrap
 * @returns Whether wrap would succeed and failure reason code
 */
export async function canAccountWrapWssUSD(
  vault: Contract,
  account: string,
  amount: bigint
): Promise<{ canWrap: boolean; reason: number }> {
  const [canWrap, reason] = await vault.canAccountWrap(account, amount);
  return { canWrap, reason };
}

/**
 * Get vault statistics with extended analytics
 * @param vault wssUSD contract instance
 * @returns Extended vault statistics
 */
export async function getWssUSDVaultStatistics(vault: Contract): Promise<WssUSDVaultStatistics> {
  const [assets, supply, sharePrice, yieldBps, snapshotCount, dailyLimit, cooldown] =
    await vault.getVaultStatistics();
  return { assets, supply, sharePrice, yieldBps, snapshotCount, dailyLimit, cooldown };
}

/**
 * Get share price history snapshots
 * @param vault wssUSD contract instance
 * @param startIndex Starting index
 * @param count Number to fetch
 * @returns Array of snapshots
 */
export async function getWssUSDPriceHistory(
  vault: Contract,
  startIndex: number,
  count: number
): Promise<SharePriceSnapshot[]> {
  const [prices, timestamps] = await vault.getSharePriceHistoryRange(startIndex, count);
  const snapshots: SharePriceSnapshot[] = [];
  for (let i = 0; i < prices.length; i++) {
    snapshots.push({ price: prices[i], timestamp: timestamps[i] });
  }
  return snapshots;
}

/**
 * Get latest share price snapshots
 * @param vault wssUSD contract instance
 * @param count Number to fetch
 * @returns Array of snapshots (newest first)
 */
export async function getLatestWssUSDSnapshots(
  vault: Contract,
  count: number
): Promise<SharePriceSnapshot[]> {
  const [prices, timestamps] = await vault.getLatestSnapshots(count);
  const snapshots: SharePriceSnapshot[] = [];
  for (let i = 0; i < prices.length; i++) {
    snapshots.push({ price: prices[i], timestamp: timestamps[i] });
  }
  return snapshots;
}

/**
 * Get yield over a period
 * @param vault wssUSD contract instance
 * @param periodSeconds Period in seconds
 * @returns Yield and annualized yield in basis points
 */
export async function getWssUSDYieldOverPeriod(
  vault: Contract,
  periodSeconds: number
): Promise<YieldOverPeriod> {
  const [yieldBps, annualizedBps] = await vault.getYieldOverPeriod(periodSeconds);
  return { yieldBps, annualizedBps };
}

/**
 * Batch query ssUSD values for multiple accounts
 * @param vault wssUSD contract instance
 * @param accounts Accounts to query
 * @returns Array of ssUSD values
 */
export async function batchGetWssUSDValues(
  vault: Contract,
  accounts: string[]
): Promise<bigint[]> {
  return await vault.batchGetSsUSDValues(accounts);
}

/**
 * Batch query wssUSD balances
 * @param vault wssUSD contract instance
 * @param accounts Accounts to query
 * @returns Array of balances
 */
export async function batchGetWssUSDBalances(
  vault: Contract,
  accounts: string[]
): Promise<bigint[]> {
  return await vault.batchBalanceOf(accounts);
}

/**
 * Preview batch wrap amounts
 * @param vault wssUSD contract instance
 * @param amounts ssUSD amounts to wrap
 * @returns Array of wssUSD shares
 */
export async function previewBatchWssUSDWrap(
  vault: Contract,
  amounts: bigint[]
): Promise<bigint[]> {
  return await vault.previewBatchWrap(amounts);
}

/**
 * Preview batch unwrap amounts
 * @param vault wssUSD contract instance
 * @param shareAmounts wssUSD amounts to unwrap
 * @returns Array of ssUSD amounts
 */
export async function previewBatchWssUSDUnwrap(
  vault: Contract,
  shareAmounts: bigint[]
): Promise<bigint[]> {
  return await vault.previewBatchUnwrap(shareAmounts);
}

/**
 * Get snapshot count for price history
 * @param vault wssUSD contract instance
 * @returns Number of snapshots
 */
export async function getWssUSDSnapshotCount(vault: Contract): Promise<bigint> {
  return await vault.getSnapshotCount();
}
