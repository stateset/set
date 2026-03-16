import { Contract } from "ethers";

/**
 * ssUSD token status
 */
export interface SsUSDTokenStatus {
  totalSupply: bigint;
  totalShares: bigint;
  navPerShare: bigint;
  isPaused: boolean;
  treasuryVault: string;
  navOracle: string;
}

/**
 * ssUSD account details
 */
export interface SsUSDAccountDetails {
  balance: bigint;
  shares: bigint;
  percentOfSupply: bigint;
}

/**
 * Fetch ssUSD token status
 * @param ssUSD ssUSD contract instance
 * @returns Token status
 */
export async function fetchSsUSDTokenStatus(ssUSD: Contract): Promise<SsUSDTokenStatus> {
  const [totalSupply, totalShares, navPerShare, isPaused, treasuryVault, navOracle] =
    await ssUSD.getTokenStatus();
  return { totalSupply, totalShares, navPerShare, isPaused, treasuryVault, navOracle };
}

/**
 * Fetch ssUSD account details
 * @param ssUSD ssUSD contract instance
 * @param account Account address
 * @returns Account details
 */
export async function fetchSsUSDAccountDetails(
  ssUSD: Contract,
  account: string
): Promise<SsUSDAccountDetails> {
  const [balance, shares, percentOfSupply] = await ssUSD.getAccountDetails(account);
  return { balance, shares, percentOfSupply };
}

/**
 * Get current NAV per share
 * @param ssUSD ssUSD contract instance
 * @returns NAV per share (1e18 = $1.00)
 */
export async function getSsUSDNavPerShare(ssUSD: Contract): Promise<bigint> {
  return await ssUSD.getNavPerShare();
}

/**
 * Calculate yield accrued since baseline
 * @param ssUSD ssUSD contract instance
 * @param account Account address
 * @param baselineNAV NAV at time of deposit
 * @returns Accrued yield and percentage
 */
export async function getSsUSDAccruedYield(
  ssUSD: Contract,
  account: string,
  baselineNAV: bigint
): Promise<{ yieldAccrued: bigint; yieldPercent: bigint }> {
  const [yieldAccrued, yieldPercent] = await ssUSD.getAccruedYield(account, baselineNAV);
  return { yieldAccrued, yieldPercent };
}

/**
 * Simulate balance at a hypothetical NAV
 * @param ssUSD ssUSD contract instance
 * @param account Account address
 * @param newNavPerShare Hypothetical NAV
 * @returns Expected balance at that NAV
 */
export async function simulateSsUSDBalance(
  ssUSD: Contract,
  account: string,
  newNavPerShare: bigint
): Promise<bigint> {
  return await ssUSD.simulateBalanceAtNAV(account, newNavPerShare);
}

/**
 * Get balances for multiple accounts
 * @param ssUSD ssUSD contract instance
 * @param accounts Array of account addresses
 * @returns Array of balances
 */
export async function fetchBatchSsUSDBalances(
  ssUSD: Contract,
  accounts: string[]
): Promise<bigint[]> {
  return await ssUSD.batchBalanceOf(accounts);
}

/**
 * Get shares for multiple accounts
 * @param ssUSD ssUSD contract instance
 * @param accounts Array of account addresses
 * @returns Array of shares
 */
export async function fetchBatchSsUSDShares(
  ssUSD: Contract,
  accounts: string[]
): Promise<bigint[]> {
  return await ssUSD.batchSharesOf(accounts);
}

/**
 * Convert ssUSD amount to shares
 * @param ssUSD ssUSD contract instance
 * @param amount Amount to convert
 * @returns Equivalent shares
 */
export async function ssUSDAmountToShares(
  ssUSD: Contract,
  amount: bigint
): Promise<bigint> {
  return await ssUSD.getSharesByAmount(amount);
}

/**
 * Convert shares to ssUSD amount
 * @param ssUSD ssUSD contract instance
 * @param shares Shares to convert
 * @returns Equivalent amount
 */
export async function ssUSDSharesToAmount(
  ssUSD: Contract,
  shares: bigint
): Promise<bigint> {
  return await ssUSD.getAmountByShares(shares);
}

/**
 * Batch convert amounts to shares
 * @param ssUSD ssUSD contract instance
 * @param amounts Array of amounts
 * @returns Array of equivalent shares
 */
export async function batchSsUSDAmountsToShares(
  ssUSD: Contract,
  amounts: bigint[]
): Promise<bigint[]> {
  return await ssUSD.batchGetSharesByAmount(amounts);
}

/**
 * Batch convert shares to amounts
 * @param ssUSD ssUSD contract instance
 * @param shares Array of shares
 * @returns Array of equivalent amounts
 */
export async function batchSsUSDSharesToAmounts(
  ssUSD: Contract,
  shares: bigint[]
): Promise<bigint[]> {
  return await ssUSD.batchGetAmountByShares(shares);
}

/**
 * Check if ssUSD is paused
 * @param ssUSD ssUSD contract instance
 * @returns True if paused
 */
export async function isSsUSDPaused(ssUSD: Contract): Promise<boolean> {
  return await ssUSD.paused();
}

/**
 * Get total ssUSD supply (rebased)
 * @param ssUSD ssUSD contract instance
 * @returns Total supply
 */
export async function getSsUSDTotalSupply(ssUSD: Contract): Promise<bigint> {
  return await ssUSD.totalSupply();
}

/**
 * Get total ssUSD shares
 * @param ssUSD ssUSD contract instance
 * @returns Total shares
 */
export async function getSsUSDTotalShares(ssUSD: Contract): Promise<bigint> {
  return await ssUSD.totalShares();
}
