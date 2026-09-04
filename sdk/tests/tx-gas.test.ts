import { afterEach, describe, expect, it, vi } from 'vitest';
import type { Contract } from 'ethers';
import {
  CachedContractWrapper,
  ContractCache,
  createCachedWrapper,
  estimateContractGas,
  processBatched,
  simulateContractCall,
} from '../src/tx/gas.js';

function contractStub(options: {
  gas?: bigint;
  gasPrice?: bigint | null;
  maxFeePerGas?: bigint | null;
  priorityFee?: bigint | null;
  result?: unknown;
  error?: unknown;
  provider?: boolean;
} = {}): Contract {
  const call = {
    estimateGas: vi.fn().mockResolvedValue(options.gas ?? 100n),
    staticCall: options.error
      ? vi.fn().mockRejectedValue(options.error)
      : vi.fn().mockResolvedValue(options.result ?? 'ok'),
  };
  return {
    runner: options.provider === false ? null : {
      provider: {
        getFeeData: vi.fn().mockResolvedValue({
          gasPrice: options.gasPrice === undefined ? 2n : options.gasPrice,
          maxFeePerGas: options.maxFeePerGas ?? null,
          maxPriorityFeePerGas: options.priorityFee ?? null,
        }),
      },
    },
    execute: call,
  } as unknown as Contract;
}

describe('transaction gas helpers', () => {
  afterEach(() => vi.useRealTimers());

  it('estimates legacy fees with a rounded-up safety multiplier and value', async () => {
    const estimate = await estimateContractGas(contractStub(), 'execute', ['arg'], 10n, 1.25);
    expect(estimate).toEqual({
      gasLimit: 125n,
      gasPrice: 2n,
      maxFeePerGas: undefined,
      maxPriorityFeePerGas: undefined,
      totalCost: 260n,
      totalCostEth: '0.00000000000000026',
    });
  });

  it('uses EIP-1559 max fees for the worst-case total', async () => {
    const estimate = await estimateContractGas(
      contractStub({ gas: 101n, gasPrice: null, maxFeePerGas: 5n, priorityFee: 1n }),
      'execute',
      [],
      undefined,
      1
    );
    expect(estimate.gasLimit).toBe(101n);
    expect(estimate.gasPrice).toBe(5n);
    expect(estimate.maxPriorityFeePerGas).toBe(1n);
    expect(estimate.totalCost).toBe(505n);
  });

  it('rejects missing providers and invalid multipliers', async () => {
    await expect(estimateContractGas(contractStub({ provider: false }), 'execute', []))
      .rejects.toThrow('Contract has no provider');
    await expect(estimateContractGas(contractStub(), 'execute', [], undefined, 0))
      .rejects.toThrow('Invalid multiplier');
  });

  it('simulates successful calls and captures Error failures', async () => {
    await expect(simulateContractCall(contractStub({ gas: 77n, result: 42 }), 'execute', []))
      .resolves.toEqual({ success: true, result: 42, gasEstimate: 77n });
    await expect(simulateContractCall(contractStub({ error: new Error('reverted') }), 'execute', []))
      .resolves.toEqual({ success: false, error: 'reverted' });
    await expect(simulateContractCall(contractStub({ error: 'reverted' }), 'execute', []))
      .resolves.toEqual({ success: false, error: 'Unknown error' });
  });

  it('processes batches in order and supports inter-batch delays', async () => {
    vi.useFakeTimers();
    const processor = vi.fn(async (batch: number[]) => batch.map(value => value * 2));
    const pending = processBatched([1, 2, 3], 2, processor, 10);
    await vi.runAllTimersAsync();
    await expect(pending).resolves.toEqual([2, 4, 6]);
    expect(processor).toHaveBeenCalledTimes(2);
    await expect(processBatched([1], 1, processor, 0)).resolves.toEqual([2]);
  });
});

describe('ContractCache', () => {
  afterEach(() => vi.useRealTimers());

  it('fetches once, expires entries, and reports statistics', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(1_000);
    const cache = new ContractCache(50);
    const fetcher = vi.fn().mockResolvedValueOnce('first').mockResolvedValueOnce('second');

    await expect(cache.getOrFetch('key', fetcher)).resolves.toBe('first');
    await expect(cache.getOrFetch('key', fetcher)).resolves.toBe('first');
    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(cache.get('key')).toBe('first');
    expect(cache.stats()).toEqual({ size: 1, keys: ['key'] });

    vi.advanceTimersByTime(51);
    expect(cache.get('key')).toBeUndefined();
    await expect(cache.getOrFetch('key', fetcher, 10)).resolves.toBe('second');
  });

  it('invalidates individual entries, prefixes, and the full cache', () => {
    const cache = new ContractCache();
    cache.set('registry:a', 1);
    cache.set('registry:b', 2);
    cache.set('paymaster:a', 3, 100);
    cache.invalidate('registry:a');
    expect(cache.get('registry:a')).toBeUndefined();
    cache.invalidateByPrefix('registry:');
    expect(cache.stats().keys).toEqual(['paymaster:a']);
    cache.clear();
    expect(cache.stats()).toEqual({ size: 0, keys: [] });
  });
});

describe('CachedContractWrapper', () => {
  it('registers, exposes, invalidates, clears, and constructs wrappers', () => {
    const wrapper = new CachedContractWrapper(100);
    wrapper.registerContract('registry', contractStub());
    wrapper.getCache().set('registry:stats', 1);
    wrapper.getCache().set('paymaster:status', 2);
    wrapper.invalidateContract('registry');
    expect(wrapper.getCache().stats().keys).toEqual(['paymaster:status']);
    wrapper.clearAll();
    expect(wrapper.getCache().stats().size).toBe(0);
    expect(createCachedWrapper(5)).toBeInstanceOf(CachedContractWrapper);
  });

  it('caches each supported contract status query', async () => {
    const wrapper = createCachedWrapper();
    const registry = {
      getRegistryStats: vi.fn().mockResolvedValue([1n, 2n, false, true]),
      getExtendedRegistryStatus: vi.fn().mockResolvedValue([1n, 2n, 3n, false, true, 90n]),
    } as unknown as Contract;
    const paymaster = {
      getPaymasterStatus: vi.fn().mockResolvedValue([4n, 5n, 6n, 'treasury']),
    } as unknown as Contract;
    const vault = {
      getVaultStatus: vi.fn().mockResolvedValue([1n, 2n, 3n, 4n, 5n, 6n, false]),
    } as unknown as Contract;
    const threshold = {
      getRegistryStatus: vi.fn().mockResolvedValue([1n, 2n, 3n, 4n, 5n, false]),
    } as unknown as Contract;

    await expect(wrapper.getRegistryStatus(registry)).resolves.toMatchObject({ commitmentCount: 1n });
    await expect(wrapper.getExtendedRegistryStatus(registry)).resolves.toMatchObject({ proofCoverage: 90n });
    await expect(wrapper.getPaymasterStatus(paymaster)).resolves.toMatchObject({ balance: 4n });
    await expect(wrapper.getWssUSDStatus(vault)).resolves.toMatchObject({ assets: 1n });
    await expect(wrapper.getThresholdRegistryStatus(threshold)).resolves.toMatchObject({ totalKeypers: 1n });

    await wrapper.getRegistryStatus(registry);
    expect(registry.getRegistryStats).toHaveBeenCalledTimes(1);
  });
});
