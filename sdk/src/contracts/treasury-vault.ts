import { Contract } from "ethers";
import { SDKError, SDKErrorCode } from "../errors.js";
import type {
  TreasuryVaultHealth,
  CollateralBreakdown,
  UserVaultSummary,
  RedemptionRequestStatus,
  RedemptionRequest
} from "../types.js";

function assertParallelArrayLengths(
  context: string,
  expectedLength: number,
  arrays: Record<string, { length: number }>
): void {
  for (const [name, array] of Object.entries(arrays)) {
    if (array.length !== expectedLength) {
      throw new SDKError(SDKErrorCode.VALIDATION_ERROR, `${context} returned ${name} length ${array.length}, expected ${expectedLength}`, {
        details: { context, name, actualLength: array.length, expectedLength }
      });
    }
  }
}

function toSafeInteger(value: bigint | number, fieldName: string): number {
  if (typeof value === "bigint") {
    if (value < BigInt(Number.MIN_SAFE_INTEGER) || value > BigInt(Number.MAX_SAFE_INTEGER)) {
      throw new SDKError(SDKErrorCode.VALIDATION_ERROR, `${fieldName} exceeds safe integer range`, {
        details: { fieldName, value: value.toString() }
      });
    }
    return Number(value);
  }

  if (!Number.isInteger(value)) {
    throw new SDKError(SDKErrorCode.VALIDATION_ERROR, `${fieldName} must be an integer`, {
      details: { fieldName, value }
    });
  }

  return value;
}

function normalizeRedemptionRequest(
  request: RedemptionRequest | Record<string, unknown>
): RedemptionRequest {
  return {
    id: request.id as bigint,
    requester: request.requester as string,
    ssUSDAmount: request.ssUSDAmount as bigint,
    collateralToken: request.collateralToken as string,
    requestedAt: request.requestedAt as bigint,
    processedAt: request.processedAt as bigint,
    status: toSafeInteger(request.status as bigint | number, "status")
  };
}

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
  assertParallelArrayLengths("getCollateralBreakdown", tokens.length, {
    balances,
    values
  });
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
  return {
    status: toSafeInteger(status, "status"),
    timeRemaining,
    isReady,
    ssUSDValue
  };
}

/**
 * Get redemption request details
 * @param vault TreasuryVault contract instance
 * @param requestId Request ID
 * @returns Redemption request details
 */
export async function getRedemptionRequest(vault: Contract, requestId: number): Promise<RedemptionRequest> {
  const request = await vault.getRedemptionRequest(requestId);
  return normalizeRedemptionRequest(request);
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
  const balances = await vault.batchGetCollateralBalances(tokens);
  assertParallelArrayLengths("batchGetCollateralBalances", tokens.length, {
    balances
  });
  return balances;
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
  const requests = await vault.batchGetRedemptionRequests(requestIds);
  assertParallelArrayLengths("batchGetRedemptionRequests", requestIds.length, {
    requests
  });
  return requests.map((request: RedemptionRequest | Record<string, unknown>) =>
    normalizeRedemptionRequest(request)
  );
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
  const statuses = await vault.batchIsOperator(addresses);
  assertParallelArrayLengths("batchIsOperator", addresses.length, {
    statuses
  });
  return statuses;
}
