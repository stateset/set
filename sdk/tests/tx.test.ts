import { describe, expect, it, vi } from 'vitest';
import { estimateContractGas } from '../src/tx/gas';
import {
  TransactionBuilder,
  cancelTransaction,
  speedUpTransaction
} from '../src/tx/builder';

const MULTIPLIER_SCALE = 10000n;

function applyMultiplier(value: bigint, multiplier: number): bigint {
  const scaled = BigInt(Math.ceil(multiplier * Number(MULTIPLIER_SCALE)));
  return (value * scaled + MULTIPLIER_SCALE - 1n) / MULTIPLIER_SCALE;
}

describe('estimateContractGas', () => {
  it('preserves bigint precision for large EIP-1559 estimates', async () => {
    const provider = {
      getFeeData: vi.fn().mockResolvedValue({
        gasPrice: 20_000_000_000n,
        maxFeePerGas: 25_000_000_000n,
        maxPriorityFeePerGas: 2_000_000_000n
      })
    };
    const contract = {
      runner: { provider },
      commitBatch: {
        estimateGas: vi.fn().mockResolvedValue(9_007_199_254_740_993n)
      }
    } as any;

    const result = await estimateContractGas(contract, 'commitBatch', [], 3n, 1.2);

    expect(result.gasLimit).toBe(10_808_639_105_689_192n);
    expect(result.gasPrice).toBe(20_000_000_000n);
    expect(result.maxFeePerGas).toBe(25_000_000_000n);
    expect(result.maxPriorityFeePerGas).toBe(2_000_000_000n);
    expect(result.totalCost).toBe(270_215_977_642_229_800_000_000_003n);
    expect(result.totalCostEth).toBe('270215977.642229800000000003');
  });
});

describe('TransactionBuilder', () => {
  it('uses bigint-safe EIP-1559 fee math during estimation', async () => {
    const provider = {
      getFeeData: vi.fn().mockResolvedValue({
        gasPrice: 1_000_000_000n,
        maxFeePerGas: 1_500_000_000n,
        maxPriorityFeePerGas: 200_000_000n
      })
    };
    const wallet = { provider } as any;
    const contract = {
      settle: {
        estimateGas: vi.fn().mockResolvedValue(9_007_199_254_740_993n)
      }
    } as any;

    const builder = new TransactionBuilder(wallet, {
      gasLimitMultiplier: 1.2,
      gasPriceMultiplier: 1.1
    });

    const result = await builder.estimateGas(contract, 'settle', []);

    expect(result.gasLimit).toBe(10_808_639_105_689_192n);
    expect(result.maxFeePerGas).toBe(1_650_000_000n);
    expect(result.maxPriorityFeePerGas).toBe(220_000_000n);
    expect(result.gasPrice).toBeUndefined();
    expect(result.totalCost).toBe(17_834_254_524_387_166_800_000_000n);
  });
});

describe('replacement transactions', () => {
  it('speeds up legacy transactions with a higher gasPrice', async () => {
    const sendTransaction = vi.fn().mockResolvedValue({ hash: '0xspeed' });
    const provider = {
      getTransaction: vi.fn().mockResolvedValue({
        to: '0x00000000000000000000000000000000000000aa',
        data: '0x1234',
        value: 7n,
        nonce: 12,
        gasLimit: 55_000n,
        gasPrice: 10_000_000_000n
      }),
      getTransactionReceipt: vi.fn().mockResolvedValue(null),
      getFeeData: vi.fn().mockResolvedValue({
        gasPrice: 12_000_000_000n,
        maxFeePerGas: null,
        maxPriorityFeePerGas: null
      })
    };
    const wallet = { provider, sendTransaction } as any;

    const hash = await speedUpTransaction(wallet, '0xold', 1.5);

    expect(hash).toBe('0xspeed');
    expect(sendTransaction).toHaveBeenCalledWith({
      to: '0x00000000000000000000000000000000000000aa',
      data: '0x1234',
      value: 7n,
      nonce: 12,
      gasLimit: 55_000n,
      gasPrice: applyMultiplier(10_000_000_000n, 1.5)
    });
  });

  it('cancels EIP-1559 transactions with bumped max fees', async () => {
    const sendTransaction = vi.fn().mockResolvedValue({ hash: '0xcancel' });
    const provider = {
      getTransaction: vi.fn().mockResolvedValue({
        nonce: 9,
        gasLimit: 45_000n,
        gasPrice: null,
        maxFeePerGas: 30_000_000_000n,
        maxPriorityFeePerGas: 1_500_000_000n
      }),
      getTransactionReceipt: vi.fn().mockResolvedValue(null),
      getFeeData: vi.fn().mockResolvedValue({
        gasPrice: 25_000_000_000n,
        maxFeePerGas: 31_000_000_000n,
        maxPriorityFeePerGas: 2_000_000_000n
      })
    };
    const wallet = {
      provider,
      sendTransaction,
      getAddress: vi.fn().mockResolvedValue('0x00000000000000000000000000000000000000bb')
    } as any;

    const hash = await cancelTransaction(wallet, '0xold', 1.2);

    expect(hash).toBe('0xcancel');
    expect(sendTransaction).toHaveBeenCalledWith({
      to: '0x00000000000000000000000000000000000000bb',
      data: '0x',
      value: 0n,
      nonce: 9,
      gasLimit: 21_000n,
      maxFeePerGas: applyMultiplier(30_000_000_000n, 1.2),
      maxPriorityFeePerGas: applyMultiplier(1_500_000_000n, 1.2)
    });
  });
});
