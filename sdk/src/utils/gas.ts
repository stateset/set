/**
 * Set Chain SDK - Gas Utilities
 *
 * Gas estimation and fee calculation helpers.
 */

import { Contract, JsonRpcProvider } from "ethers";
import { GasEstimationError, SDKError, SDKErrorCode } from "../errors";

/**
 * Gas estimation result
 */
export interface GasEstimate {
  /** Estimated gas limit */
  gasLimit: bigint;
  /** Gas limit with buffer applied */
  gasLimitWithBuffer: bigint;
  /** Current gas price */
  gasPrice: bigint;
  /** Max fee per gas (EIP-1559) */
  maxFeePerGas: bigint;
  /** Max priority fee per gas (EIP-1559) */
  maxPriorityFeePerGas: bigint;
  /** Estimated total cost in wei */
  estimatedCost: bigint;
  /** Estimated cost with buffer */
  estimatedCostWithBuffer: bigint;
}

/**
 * Options for gas estimation
 */
export interface GasEstimateOptions {
  /** Gas buffer multiplier (default: 1.2 = 20% buffer) */
  gasBuffer?: number;
  /** Override gas price */
  gasPrice?: bigint;
  /** Override max fee per gas */
  maxFeePerGas?: bigint;
  /** Override max priority fee per gas */
  maxPriorityFeePerGas?: bigint;
}

/**
 * Estimate gas for a contract function call
 * @param contract Contract instance
 * @param functionName Function name to call
 * @param args Function arguments
 * @param options Estimation options
 * @returns Gas estimate
 */
export async function estimateGas(
  contract: Contract,
  functionName: string,
  args: unknown[] = [],
  options: GasEstimateOptions = {}
): Promise<GasEstimate> {
  const { gasBuffer = 1.2 } = options;

  try {
    // Get provider from contract
    const provider = contract.runner?.provider as JsonRpcProvider | undefined;
    if (!provider) {
      throw new SDKError(SDKErrorCode.CONTRACT_ERROR, "Contract has no provider");
    }

    // Estimate gas
    const gasLimit = await contract[functionName].estimateGas(...args);

    // Apply buffer
    const gasLimitWithBuffer = BigInt(Math.ceil(Number(gasLimit) * gasBuffer));

    // Get fee data
    const feeData = await provider.getFeeData();

    const gasPrice = options.gasPrice ?? feeData.gasPrice ?? 1000000000n;
    const maxFeePerGas = options.maxFeePerGas ?? feeData.maxFeePerGas ?? gasPrice;
    const maxPriorityFeePerGas = options.maxPriorityFeePerGas ?? feeData.maxPriorityFeePerGas ?? 1000000000n;

    // Calculate costs
    const estimatedCost = gasLimit * maxFeePerGas;
    const estimatedCostWithBuffer = gasLimitWithBuffer * maxFeePerGas;

    return {
      gasLimit,
      gasLimitWithBuffer,
      gasPrice,
      maxFeePerGas,
      maxPriorityFeePerGas,
      estimatedCost,
      estimatedCostWithBuffer
    };
  } catch (error) {
    if (error instanceof SDKError) {
      throw error;
    }
    throw new GasEstimationError(functionName, error instanceof Error ? error : undefined);
  }
}

/**
 * Get current fee data from provider
 * @param provider JSON RPC provider
 * @returns Fee data with defaults
 */
export async function getFeeData(provider: JsonRpcProvider): Promise<{
  gasPrice: bigint;
  maxFeePerGas: bigint;
  maxPriorityFeePerGas: bigint;
}> {
  const feeData = await provider.getFeeData();

  return {
    gasPrice: feeData.gasPrice ?? 1000000000n,
    maxFeePerGas: feeData.maxFeePerGas ?? feeData.gasPrice ?? 1000000000n,
    maxPriorityFeePerGas: feeData.maxPriorityFeePerGas ?? 1000000000n
  };
}

/**
 * Calculate required fee for transaction
 * @param gasLimit Gas limit
 * @param maxFeePerGas Max fee per gas
 * @param buffer Optional multiplier buffer
 * @returns Required fee in wei
 */
export function calculateRequiredFee(
  gasLimit: bigint,
  maxFeePerGas: bigint,
  buffer = 1.0
): bigint {
  const fee = gasLimit * maxFeePerGas;
  if (buffer === 1.0) {
    return fee;
  }
  return BigInt(Math.ceil(Number(fee) * buffer));
}

/**
 * Apply gas buffer to a gas limit
 * @param gasLimit Original gas limit
 * @param buffer Buffer multiplier (default: 1.2)
 * @returns Gas limit with buffer
 */
export function applyGasBuffer(gasLimit: bigint, buffer = 1.2): bigint {
  return BigInt(Math.ceil(Number(gasLimit) * buffer));
}

/**
 * Default gas limits for common operations
 */
export const DEFAULT_GAS_LIMITS = {
  /** ERC20 approve */
  APPROVE: 50000n,
  /** ERC20 transfer */
  TRANSFER: 65000n,
  /** Simple ETH transfer */
  ETH_TRANSFER: 21000n,
  /** SetRegistry commitBatch */
  COMMIT_BATCH: 150000n,
  /** SetPaymaster executeSponsorship */
  EXECUTE_SPONSORSHIP: 100000n,
  /** Stablecoin deposit */
  DEPOSIT: 200000n,
  /** Stablecoin redemption */
  REDEMPTION: 150000n,
  /** Wrap ssUSD to wssUSD */
  WRAP: 100000n,
  /** Unwrap wssUSD to ssUSD */
  UNWRAP: 100000n,
  /** MEV encrypted transaction */
  ENCRYPTED_TX: 200000n
} as const;

/**
 * Check if user has sufficient balance for gas
 * @param provider JSON RPC provider
 * @param address User address
 * @param requiredGas Required gas amount
 * @returns True if sufficient balance
 */
export async function hasSufficientGas(
  provider: JsonRpcProvider,
  address: string,
  requiredGas: bigint
): Promise<boolean> {
  const balance = await provider.getBalance(address);
  return balance >= requiredGas;
}

/**
 * Get recommended gas settings for Set Chain
 * @param provider JSON RPC provider
 * @returns Recommended gas settings
 */
export async function getRecommendedGasSettings(provider: JsonRpcProvider): Promise<{
  maxFeePerGas: bigint;
  maxPriorityFeePerGas: bigint;
  gasBuffer: number;
}> {
  const feeData = await getFeeData(provider);

  // Set Chain uses 2-second blocks, so we can be more aggressive with fees
  return {
    maxFeePerGas: feeData.maxFeePerGas,
    maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
    gasBuffer: 1.2
  };
}
