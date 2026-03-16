import { Contract, JsonRpcProvider } from "ethers";

/**
 * Gas estimation result
 */
export interface GasEstimate {
  gasLimit: bigint;
  gasPrice: bigint;
  maxFeePerGas?: bigint;
  maxPriorityFeePerGas?: bigint;
  totalCost: bigint;
  totalCostEth: string;
}

/**
 * Format a bigint balance with decimals
 */
function formatBalance(value: bigint, decimals: number = 18): string {
  const divisor = BigInt(10 ** decimals);
  const integerPart = value / divisor;
  const fractionalPart = value % divisor;

  // Pad fractional part with leading zeros
  const fractionalStr = fractionalPart.toString().padStart(decimals, '0');

  // Trim trailing zeros and return
  const trimmed = fractionalStr.replace(/0+$/, '') || '0';

  if (trimmed === '0') {
    return integerPart.toString();
  }

  return `${integerPart}.${trimmed}`;
}

/**
 * Estimate gas for any contract call
 */
export async function estimateContractGas(
  contract: Contract,
  method: string,
  args: any[],
  value?: bigint,
  multiplier: number = 1.2
): Promise<GasEstimate> {
  const provider = contract.runner?.provider;
  if (!provider) throw new Error('Contract has no provider');

  const feeData = await (provider as JsonRpcProvider).getFeeData();
  const gasEstimate = await contract[method].estimateGas(...args, {
    value: value || BigInt(0)
  });

  const gasLimit = BigInt(Math.ceil(Number(gasEstimate) * multiplier));
  const gasPrice = feeData.gasPrice || BigInt(0);
  const totalCost = gasLimit * gasPrice + (value || BigInt(0));

  return {
    gasLimit,
    gasPrice,
    maxFeePerGas: feeData.maxFeePerGas || undefined,
    maxPriorityFeePerGas: feeData.maxPriorityFeePerGas || undefined,
    totalCost,
    totalCostEth: formatBalance(totalCost, 18)
  };
}

/**
 * Simulate a contract call without sending
 */
export async function simulateContractCall<T = any>(
  contract: Contract,
  method: string,
  args: any[],
  value?: bigint
): Promise<{ success: boolean; result?: T; error?: string; gasEstimate?: bigint }> {
  try {
    const result = await contract[method].staticCall(...args, {
      value: value || BigInt(0)
    });
    const gasEstimate = await contract[method].estimateGas(...args, {
      value: value || BigInt(0)
    });
    return { success: true, result: result as T, gasEstimate };
  } catch (error) {
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

/**
 * Execute calls in batches to avoid rate limits
 * @param items Items to process
 * @param batchSize Size of each batch
 * @param processor Function to process each batch
 * @param delayBetweenBatchesMs Delay between batches
 * @returns Flattened results
 */
export async function processBatched<T, R>(
  items: T[],
  batchSize: number,
  processor: (batch: T[]) => Promise<R[]>,
  delayBetweenBatchesMs: number = 100
): Promise<R[]> {
  const results: R[] = [];

  for (let i = 0; i < items.length; i += batchSize) {
    const batch = items.slice(i, i + batchSize);
    const batchResults = await processor(batch);
    results.push(...batchResults);

    if (i + batchSize < items.length && delayBetweenBatchesMs > 0) {
      await new Promise(resolve => setTimeout(resolve, delayBetweenBatchesMs));
    }
  }

  return results;
}

/**
 * Simple in-memory cache with TTL support
 */
export class ContractCache {
  private cache: Map<string, { value: any; expiresAt: number }> = new Map();
  private defaultTtlMs: number;

  constructor(defaultTtlMs: number = 30000) {
    this.defaultTtlMs = defaultTtlMs;
  }

  /**
   * Get a cached value or fetch it
   * @param key Cache key
   * @param fetcher Function to fetch value if not cached
   * @param ttlMs Custom TTL for this entry
   */
  async getOrFetch<T>(
    key: string,
    fetcher: () => Promise<T>,
    ttlMs?: number
  ): Promise<T> {
    const now = Date.now();
    const entry = this.cache.get(key);

    if (entry && entry.expiresAt > now) {
      return entry.value as T;
    }

    const value = await fetcher();
    this.cache.set(key, {
      value,
      expiresAt: now + (ttlMs ?? this.defaultTtlMs)
    });

    return value;
  }

  /**
   * Get a cached value
   * @param key Cache key
   */
  get<T>(key: string): T | undefined {
    const entry = this.cache.get(key);
    if (entry && entry.expiresAt > Date.now()) {
      return entry.value as T;
    }
    this.cache.delete(key);
    return undefined;
  }

  /**
   * Set a cached value
   * @param key Cache key
   * @param value Value to cache
   * @param ttlMs Custom TTL
   */
  set<T>(key: string, value: T, ttlMs?: number): void {
    this.cache.set(key, {
      value,
      expiresAt: Date.now() + (ttlMs ?? this.defaultTtlMs)
    });
  }

  /**
   * Invalidate a cache entry
   * @param key Cache key
   */
  invalidate(key: string): void {
    this.cache.delete(key);
  }

  /**
   * Invalidate all entries matching a prefix
   * @param prefix Key prefix to match
   */
  invalidateByPrefix(prefix: string): void {
    for (const key of this.cache.keys()) {
      if (key.startsWith(prefix)) {
        this.cache.delete(key);
      }
    }
  }

  /**
   * Clear all cached entries
   */
  clear(): void {
    this.cache.clear();
  }

  /**
   * Get cache statistics
   */
  stats(): { size: number; keys: string[] } {
    return {
      size: this.cache.size,
      keys: Array.from(this.cache.keys())
    };
  }
}

/**
 * Cached contract wrapper for reducing RPC calls
 */
export class CachedContractWrapper {
  private cache: ContractCache;
  private contracts: Map<string, Contract> = new Map();

  constructor(cacheTtlMs: number = 30000) {
    this.cache = new ContractCache(cacheTtlMs);
  }

  /**
   * Register a contract for caching
   * @param name Contract name
   * @param contract Contract instance
   */
  registerContract(name: string, contract: Contract): void {
    this.contracts.set(name, contract);
  }

  /**
   * Get cached registry status
   */
  async getRegistryStatus(registry: Contract): Promise<import("../types.js").RegistryStats> {
    const { fetchRegistryStats } = await import("../contracts/registry.js");
    return this.cache.getOrFetch(
      'registry:stats',
      () => fetchRegistryStats(registry)
    );
  }

  /**
   * Get cached extended registry status
   */
  async getExtendedRegistryStatus(registry: Contract): Promise<import("../contracts/registry.js").ExtendedRegistryStatus> {
    const { fetchExtendedRegistryStatus } = await import("../contracts/registry.js");
    return this.cache.getOrFetch(
      'registry:extended',
      () => fetchExtendedRegistryStatus(registry)
    );
  }

  /**
   * Get cached paymaster status
   */
  async getPaymasterStatus(paymaster: Contract): Promise<import("../contracts/paymaster.js").PaymasterStatus> {
    const { fetchPaymasterStatus } = await import("../contracts/paymaster.js");
    return this.cache.getOrFetch(
      'paymaster:status',
      () => fetchPaymasterStatus(paymaster)
    );
  }

  /**
   * Get cached wssUSD vault status
   */
  async getWssUSDStatus(vault: Contract): Promise<import("../types.js").WssUSDVaultStatus> {
    const { fetchWssUSDVaultStatus } = await import("../contracts/wss-usd.js");
    return this.cache.getOrFetch(
      'wssUSD:status',
      () => fetchWssUSDVaultStatus(vault)
    );
  }

  /**
   * Get cached threshold registry status
   */
  async getThresholdRegistryStatus(registry: Contract): Promise<import("../types.js").ThresholdRegistryStatus> {
    const { fetchThresholdRegistryStatus } = await import("../contracts/threshold-key-registry.js");
    return this.cache.getOrFetch(
      'threshold:status',
      () => fetchThresholdRegistryStatus(registry)
    );
  }

  /**
   * Invalidate all cached data for a contract type
   */
  invalidateContract(contractType: 'registry' | 'paymaster' | 'wssUSD' | 'threshold'): void {
    this.cache.invalidateByPrefix(`${contractType}:`);
  }

  /**
   * Clear all caches
   */
  clearAll(): void {
    this.cache.clear();
  }

  /**
   * Get underlying cache for custom usage
   */
  getCache(): ContractCache {
    return this.cache;
  }
}

/**
 * Create a cached contract wrapper
 * @param ttlMs Cache TTL in milliseconds (default 30 seconds)
 */
export function createCachedWrapper(ttlMs: number = 30000): CachedContractWrapper {
  return new CachedContractWrapper(ttlMs);
}
