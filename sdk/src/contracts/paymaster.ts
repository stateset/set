import { Contract } from "ethers";
import type { MerchantDetails } from "../types.js";

/**
 * Helpers for SetPaymaster, an operator-managed ETH sponsorship contract.
 * These helpers do not assume ERC-4337 paymaster semantics.
 */

/**
 * Paymaster status information
 */
export interface PaymasterStatus {
  balance: bigint;
  totalSponsored: bigint;
  tierCount: bigint;
  treasury: string;
}

/**
 * Sponsorship tier information
 */
export interface SponsorshipTier {
  tierId: bigint;
  name: string;
  maxPerTx: bigint;
  maxPerDay: bigint;
  maxPerMonth: bigint;
}

/**
 * Batch merchant status
 */
export interface BatchMerchantStatus {
  merchants: string[];
  statuses: boolean[];
  tiers: bigint[];
}

/**
 * Batch sponsorship result
 */
export interface BatchSponsorshipResult {
  succeeded: bigint;
  failed: bigint;
}

/**
 * Fetch paymaster status
 * @param paymaster SetPaymaster contract instance
 * @returns Paymaster status
 */
export async function fetchPaymasterStatus(paymaster: Contract): Promise<PaymasterStatus> {
  const [balance, totalSponsored, tierCount, treasury] = await paymaster.getPaymasterStatus();
  return { balance, totalSponsored, tierCount, treasury };
}

/**
 * Fetch all active sponsorship tiers
 * @param paymaster SetPaymaster contract instance
 * @returns Array of sponsorship tiers
 */
export async function fetchAllTiers(paymaster: Contract): Promise<SponsorshipTier[]> {
  const [tierIds, names, maxPerTx, maxPerDay, maxPerMonth] = await paymaster.getAllTiers();
  const tiers: SponsorshipTier[] = [];
  for (let i = 0; i < tierIds.length; i++) {
    tiers.push({
      tierId: tierIds[i],
      name: names[i],
      maxPerTx: maxPerTx[i],
      maxPerDay: maxPerDay[i],
      maxPerMonth: maxPerMonth[i]
    });
  }
  return tiers;
}

/**
 * Fetch merchant details
 * @param paymaster SetPaymaster contract instance
 * @param merchant Merchant address
 * @returns Merchant sponsorship details
 */
export async function fetchMerchantDetails(
  paymaster: Contract,
  merchant: string
): Promise<MerchantDetails> {
  const [active, tierId, spentToday, spentThisMonth, totalSponsored] =
    await paymaster.getMerchantDetails(merchant);
  return { active, tierId, spentToday, spentThisMonth, totalSponsored };
}

/**
 * Check if merchant can be sponsored for an amount
 * @param paymaster SetPaymaster contract instance
 * @param merchant Merchant address
 * @param amount Amount to sponsor
 * @returns Whether sponsorable and reason if not
 */
export async function checkCanSponsor(
  paymaster: Contract,
  merchant: string,
  amount: bigint
): Promise<{ canSponsor: boolean; reason: string }> {
  const [canSponsor, reason] = await paymaster.canSponsor(merchant, amount);
  return { canSponsor, reason };
}

/**
 * Get remaining daily allowance for merchant
 * @param paymaster SetPaymaster contract instance
 * @param merchant Merchant address
 * @returns Remaining daily allowance
 */
export async function getRemainingDailyAllowance(
  paymaster: Contract,
  merchant: string
): Promise<bigint> {
  return await paymaster.getRemainingDailyAllowance(merchant);
}

/**
 * Fetch batch merchant status
 * @param paymaster SetPaymaster contract instance
 * @param merchants Array of merchant addresses
 * @returns Batch merchant status
 */
export async function fetchBatchMerchantStatus(
  paymaster: Contract,
  merchants: string[]
): Promise<BatchMerchantStatus> {
  const [statuses, tiers] = await paymaster.batchGetMerchantStatus(merchants);
  return { merchants, statuses, tiers };
}

/**
 * Check if batch of merchants can be sponsored
 * @param paymaster SetPaymaster contract instance
 * @param merchants Array of merchant addresses
 * @param amounts Array of amounts
 * @returns Array of sponsorability results
 */
export async function batchCheckCanSponsor(
  paymaster: Contract,
  merchants: string[],
  amounts: bigint[]
): Promise<{ canSponsor: boolean[]; reasons: string[] }> {
  const [canSponsor, reasons] = await paymaster.batchCanSponsor(merchants, amounts);
  return { canSponsor, reasons };
}

/**
 * Fetch batch remaining daily allowances
 * @param paymaster SetPaymaster contract instance
 * @param merchants Array of merchant addresses
 * @returns Array of remaining allowances
 */
export async function fetchBatchRemainingAllowances(
  paymaster: Contract,
  merchants: string[]
): Promise<bigint[]> {
  return await paymaster.batchGetRemainingDailyAllowance(merchants);
}

/**
 * Get maximum batch size allowed by paymaster
 * @param paymaster SetPaymaster contract instance
 * @returns Maximum batch size
 */
export async function getMaxBatchSize(paymaster: Contract): Promise<bigint> {
  return await paymaster.MAX_BATCH_SIZE();
}

/**
 * Check if paymaster has sufficient balance for sponsorships
 * @param paymaster SetPaymaster contract instance
 * @param requiredAmount Total amount needed
 * @returns True if sufficient balance
 */
export async function hasSufficientBalance(
  paymaster: Contract,
  requiredAmount: bigint
): Promise<boolean> {
  const status = await fetchPaymasterStatus(paymaster);
  return status.balance >= requiredAmount;
}

/**
 * Fetch batch merchant details
 * @param paymaster SetPaymaster contract instance
 * @param merchants Array of merchant addresses
 * @returns Array of merchant details
 */
export async function fetchBatchMerchantDetails(
  paymaster: Contract,
  merchants: string[]
): Promise<MerchantDetails[]> {
  const [actives, tierIds, spentTodays, spentThisMonths, totalSponsoreds] =
    await paymaster.batchGetMerchantDetails(merchants);
  const details: MerchantDetails[] = [];
  for (let i = 0; i < merchants.length; i++) {
    details.push({
      active: actives[i],
      tierId: tierIds[i],
      spentToday: spentTodays[i],
      spentThisMonth: spentThisMonths[i],
      totalSponsored: totalSponsoreds[i]
    });
  }
  return details;
}

/**
 * Aggregate sponsorship statistics for merchants
 * @param paymaster SetPaymaster contract instance
 * @param merchants Array of merchant addresses
 * @returns Aggregated statistics
 */
export async function aggregateMerchantStats(
  paymaster: Contract,
  merchants: string[]
): Promise<{
  totalMerchants: number;
  activeMerchants: number;
  totalSpent: bigint;
  avgSpentPerMerchant: bigint;
}> {
  const details = await fetchBatchMerchantDetails(paymaster, merchants);
  let activeMerchants = 0;
  let totalSpent = BigInt(0);

  for (const detail of details) {
    if (detail.active) activeMerchants++;
    totalSpent += detail.totalSponsored;
  }

  return {
    totalMerchants: merchants.length,
    activeMerchants,
    totalSpent,
    avgSpentPerMerchant: merchants.length > 0 ? totalSpent / BigInt(merchants.length) : BigInt(0)
  };
}

/**
 * Calculate total sponsorship capacity for a list of merchants
 * @param paymaster SetPaymaster contract instance
 * @param merchants Array of merchant addresses
 * @returns Total remaining daily allowance across all merchants
 */
export async function getTotalRemainingCapacity(
  paymaster: Contract,
  merchants: string[]
): Promise<bigint> {
  const allowances = await fetchBatchRemainingAllowances(paymaster, merchants);
  return allowances.reduce((sum, a) => sum + a, BigInt(0));
}

/**
 * Find merchants that can be sponsored for given amounts
 * @param paymaster SetPaymaster contract instance
 * @param merchants Array of merchant addresses
 * @param amounts Array of amounts to check
 * @returns Object with sponsorable merchants and their amounts
 */
export async function findSponsorableMerchants(
  paymaster: Contract,
  merchants: string[],
  amounts: bigint[]
): Promise<{
  sponsorable: Array<{ merchant: string; amount: bigint }>;
  nonSponsorable: Array<{ merchant: string; amount: bigint; reason: string }>;
}> {
  const { canSponsor, reasons } = await batchCheckCanSponsor(paymaster, merchants, amounts);
  const sponsorable: Array<{ merchant: string; amount: bigint }> = [];
  const nonSponsorable: Array<{ merchant: string; amount: bigint; reason: string }> = [];

  for (let i = 0; i < merchants.length; i++) {
    if (canSponsor[i]) {
      sponsorable.push({ merchant: merchants[i], amount: amounts[i] });
    } else {
      nonSponsorable.push({ merchant: merchants[i], amount: amounts[i], reason: reasons[i] });
    }
  }

  return { sponsorable, nonSponsorable };
}

/**
 * Get paymaster health summary
 * @param paymaster SetPaymaster contract instance
 * @returns Comprehensive health summary
 */
export async function getPaymasterHealthSummary(
  paymaster: Contract
): Promise<{
  balance: bigint;
  totalSponsored: bigint;
  tierCount: bigint;
  treasury: string;
  tiers: SponsorshipTier[];
  isHealthy: boolean;
}> {
  const [status, tiers] = await Promise.all([
    fetchPaymasterStatus(paymaster),
    fetchAllTiers(paymaster)
  ]);

  return {
    ...status,
    tiers,
    isHealthy: status.balance > BigInt(0) && status.tierCount > BigInt(0)
  };
}

/**
 * Find tier by ID
 * @param paymaster SetPaymaster contract instance
 * @param tierId Tier ID to find
 * @returns Tier information or null if not found
 */
export async function findTierById(
  paymaster: Contract,
  tierId: bigint
): Promise<SponsorshipTier | null> {
  const tiers = await fetchAllTiers(paymaster);
  return tiers.find(t => t.tierId === tierId) || null;
}

/**
 * Get tier limits for a merchant
 * @param paymaster SetPaymaster contract instance
 * @param merchant Merchant address
 * @returns Tier limits for the merchant
 */
export async function getMerchantTierLimits(
  paymaster: Contract,
  merchant: string
): Promise<{
  maxPerTx: bigint;
  maxPerDay: bigint;
  maxPerMonth: bigint;
  tierName: string;
} | null> {
  const details = await fetchMerchantDetails(paymaster, merchant);
  if (!details.active) return null;

  const tier = await findTierById(paymaster, details.tierId);
  if (!tier) return null;

  return {
    maxPerTx: tier.maxPerTx,
    maxPerDay: tier.maxPerDay,
    maxPerMonth: tier.maxPerMonth,
    tierName: tier.name
  };
}
