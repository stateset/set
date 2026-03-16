import { Contract } from "ethers";
import type {
  TreasuryVaultHealth,
  CollateralBreakdown,
  UserVaultSummary,
  RedemptionRequestStatus,
  RedemptionRequest
} from "../types.js";

/**
 * Fetch TreasuryVault health status
 * @param vault TreasuryVault contract instance
 * @returns Vault health status
 */
export async function fetchTreasuryVaultHealth(vault: Contract): Promise<TreasuryVaultHealth> {
  const [collateralValue, ssUSDSupply, collateralizationRatio, isDepositsEnabled, isRedemptionsEnabled, pendingRedemptionsCount] =
    await vault.getVaultHealth();
  return { collateralValue, ssUSDSupply, collateralizationRatio, isDepositsEnabled, isRedemptionsEnabled, pendingRedemptionsCount };
}

/**
 * Get collateralization ratio
 * @param vault TreasuryVault contract instance
 * @returns Ratio (1e18 = 100%)
 */
export async function getTreasuryCollateralRatio(vault: Contract): Promise<bigint> {
  return await vault.getCollateralRatio();
}

/**
 * Get collateral balance for a specific token
 * @param vault TreasuryVault contract instance
 * @param token Token address
 * @returns Balance in token decimals
 */
export async function getCollateralBalance(vault: Contract, token: string): Promise<bigint> {
  return await vault.getCollateralBalance(token);
}

/**
 * Get total collateral value
 * @param vault TreasuryVault contract instance
 * @returns Total value in USD (18 decimals)
 */
export async function getTotalCollateralValue(vault: Contract): Promise<bigint> {
  return await vault.getTotalCollateralValue();
}

/**
 * Get excess collateral above 100% backing
 * @param vault TreasuryVault contract instance
 * @returns Excess amount (0 if undercollateralized)
 */
export async function getExcessCollateral(vault: Contract): Promise<bigint> {
  return await vault.getExcessCollateral();
}

/**
 * Check undercollateralization status
 * @param vault TreasuryVault contract instance
 * @returns Undercollateralization status
 */
export async function checkUndercollateralization(
  vault: Contract
): Promise<{ isUnder: boolean; shortfall: bigint }> {
  const [isUnder, shortfall] = await vault.checkUndercollateralization();
  return { isUnder, shortfall };
}

/**
 * Get collateral breakdown
 * @param vault TreasuryVault contract instance
 * @returns Breakdown by token
 */
export async function getCollateralBreakdown(vault: Contract): Promise<CollateralBreakdown> {
  const [tokens, balances, values] = await vault.getCollateralBreakdown();
  return { tokens, balances, values };
}

/**
 * Get user vault summary
 * @param vault TreasuryVault contract instance
 * @param user User address
 * @returns User summary
 */
export async function getTreasuryUserSummary(vault: Contract, user: string): Promise<UserVaultSummary> {
  const [ssUSDBalance, pendingRedemptions, totalPendingValue, canDeposit, canRedeem] =
    await vault.getUserSummary(user);
  return { ssUSDBalance, pendingRedemptions, totalPendingValue, canDeposit, canRedeem };
}

/**
 * Get redemption request status
 * @param vault TreasuryVault contract instance
 * @param requestId Request ID
 * @returns Redemption status with timing
 */
export async function getRedemptionStatus(
  vault: Contract,
  requestId: number
): Promise<RedemptionRequestStatus> {
  const [status, timeRemaining, isReady, ssUSDValue] = await vault.getRedemptionStatus(requestId);
  return { status, timeRemaining, isReady, ssUSDValue };
}

/**
 * Get redemption request details
 * @param vault TreasuryVault contract instance
 * @param requestId Request ID
 * @returns Redemption request details
 */
export async function getRedemptionRequest(vault: Contract, requestId: number): Promise<RedemptionRequest> {
  return await vault.getRedemptionRequest(requestId);
}

/**
 * Get user's redemption request IDs
 * @param vault TreasuryVault contract instance
 * @param user User address
 * @returns Array of request IDs
 */
export async function getUserRedemptions(vault: Contract, user: string): Promise<bigint[]> {
  return await vault.getUserRedemptions(user);
}

/**
 * Get ready redemptions
 * @param vault TreasuryVault contract instance
 * @param maxCount Maximum to return
 * @returns Array of ready request IDs
 */
export async function getReadyRedemptions(vault: Contract, maxCount: number): Promise<bigint[]> {
  return await vault.getReadyRedemptions(maxCount);
}

/**
 * Get pending redemption count
 * @param vault TreasuryVault contract instance
 * @returns Count of pending redemptions
 */
export async function getPendingRedemptionCount(vault: Contract): Promise<bigint> {
  return await vault.pendingRedemptionCount();
}

/**
 * Get total pending redemption value
 * @param vault TreasuryVault contract instance
 * @returns Total value in ssUSD terms
 */
export async function getTotalPendingRedemptionValue(vault: Contract): Promise<bigint> {
  return await vault.getTotalPendingRedemptionValue();
}

/**
 * Get vault fees
 * @param vault TreasuryVault contract instance
 * @returns Mint and redeem fees in basis points
 */
export async function getTreasuryVaultFees(vault: Contract): Promise<{ mintFee: bigint; redeemFee: bigint }> {
  const [mintFee, redeemFee] = await Promise.all([
    vault.mintFee(),
    vault.redeemFee()
  ]);
  return { mintFee, redeemFee };
}

/**
 * Get redemption delay
 * @param vault TreasuryVault contract instance
 * @returns Delay in seconds
 */
export async function getRedemptionDelay(vault: Contract): Promise<bigint> {
  return await vault.redemptionDelay();
}

/**
 * Check if operator
 * @param vault TreasuryVault contract instance
 * @param operator Address to check
 * @returns True if operator
 */
export async function isTreasuryVaultOperator(vault: Contract, operator: string): Promise<boolean> {
  return await vault.operators(operator);
}

/**
 * Batch get collateral balances
 * @param vault TreasuryVault contract instance
 * @param tokens Token addresses
 * @returns Array of balances
 */
export async function batchGetCollateralBalances(vault: Contract, tokens: string[]): Promise<bigint[]> {
  return await vault.batchGetCollateralBalances(tokens);
}

/**
 * Batch get redemption requests
 * @param vault TreasuryVault contract instance
 * @param requestIds Request IDs
 * @returns Array of redemption requests
 */
export async function batchGetRedemptionRequests(
  vault: Contract,
  requestIds: number[]
): Promise<RedemptionRequest[]> {
  return await vault.batchGetRedemptionRequests(requestIds);
}

/**
 * Batch check operator status
 * @param vault TreasuryVault contract instance
 * @param addresses Addresses to check
 * @returns Array of operator statuses
 */
export async function batchCheckTreasuryVaultOperators(
  vault: Contract,
  addresses: string[]
): Promise<boolean[]> {
  return await vault.batchIsOperator(addresses);
}
