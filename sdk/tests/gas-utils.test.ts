import { describe, expect, it, vi } from 'vitest';
import {
  applyGasBuffer,
  calculateRequiredFee,
  getFeeData,
  getRecommendedGasSettings,
  hasSufficientGas
} from '../src/utils/gas';

describe('gas utilities', () => {
  it('calculates fees and rounds buffered values up', () => {
    expect(calculateRequiredFee(21_000n, 2n)).toBe(42_000n);
    expect(calculateRequiredFee(21_000n, 2n, 1.1)).toBe(46_200n);
    expect(applyGasBuffer(21_001n, 1.2)).toBe(25_202n);
  });

  it('rejects invalid multipliers', () => {
    expect(() => applyGasBuffer(21_000n, 0)).toThrow('Invalid gas multiplier');
    expect(() => applyGasBuffer(21_000n, Number.NaN)).toThrow('Invalid gas multiplier');
  });

  it('normalizes incomplete provider fee data', async () => {
    const provider = {
      getFeeData: vi.fn().mockResolvedValue({
        gasPrice: 2_000_000_000n,
        maxFeePerGas: null,
        maxPriorityFeePerGas: null
      })
    } as any;

    await expect(getFeeData(provider)).resolves.toEqual({
      gasPrice: 2_000_000_000n,
      maxFeePerGas: 2_000_000_000n,
      maxPriorityFeePerGas: 1_000_000_000n
    });
  });

  it('checks balances and builds recommended settings', async () => {
    const provider = {
      getBalance: vi.fn().mockResolvedValue(50_000n),
      getFeeData: vi.fn().mockResolvedValue({
        gasPrice: 2n,
        maxFeePerGas: 3n,
        maxPriorityFeePerGas: 1n
      })
    } as any;

    await expect(hasSufficientGas(provider, '0xabc', 50_000n)).resolves.toBe(true);
    await expect(hasSufficientGas(provider, '0xabc', 50_001n)).resolves.toBe(false);
    await expect(getRecommendedGasSettings(provider)).resolves.toEqual({
      maxFeePerGas: 3n,
      maxPriorityFeePerGas: 1n,
      gasBuffer: 1.2
    });
  });
});
