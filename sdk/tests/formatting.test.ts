/**
 * @setchain/sdk - Formatting Utilities Tests
 */

import { describe, it, expect } from 'vitest';
import {
  formatBalance,
  parseBalance,
  formatUSD,
  formatPercentage,
  shortenAddress,
  shortenTxHash
} from '../src/utils/formatting';

describe('formatBalance', () => {
  it('should format 18 decimal token balance', () => {
    const balance = 1500000000000000000n; // 1.5 tokens
    expect(formatBalance(balance, 18)).toBe('1.5');
  });

  it('should format 6 decimal token balance', () => {
    const balance = 1500000n; // 1.5 USDC
    expect(formatBalance(balance, 6)).toBe('1.5');
  });

  it('should format zero balance', () => {
    expect(formatBalance(0n, 18)).toBe('0.0');
  });

  it('should format large balance', () => {
    const balance = 1000000000000000000000000n; // 1M tokens
    expect(formatBalance(balance, 18)).toBe('1000000.0');
  });

  it('should add suffix', () => {
    const balance = 1000000000000000000n;
    expect(formatBalance(balance, 18, { suffix: ' ETH' })).toBe('1.0 ETH');
  });

  it('should limit decimals', () => {
    const balance = 1234567890123456789n;
    expect(formatBalance(balance, 18, { maxDecimals: 2 })).toBe('1.23');
  });

  it('should use custom separator', () => {
    const balance = 1000000000000000000000n; // 1000 tokens
    expect(formatBalance(balance, 18, { thousandsSeparator: ',' })).toBe('1,000.0');
  });
});

describe('parseBalance', () => {
  it('should parse decimal string to bigint', () => {
    expect(parseBalance('1.5', 18)).toBe(1500000000000000000n);
  });

  it('should parse integer string', () => {
    expect(parseBalance('100', 6)).toBe(100000000n);
  });

  it('should parse zero', () => {
    expect(parseBalance('0', 18)).toBe(0n);
  });

  it('should handle scientific notation', () => {
    expect(parseBalance('1e18', 0)).toBe(1000000000000000000n);
  });
});

describe('formatUSD', () => {
  it('should format as USD', () => {
    expect(formatUSD(1234.56)).toBe('$1,234.56');
  });

  it('should format zero', () => {
    expect(formatUSD(0)).toBe('$0.00');
  });

  it('should format large numbers', () => {
    expect(formatUSD(1000000)).toBe('$1,000,000.00');
  });

  it('should round to cents', () => {
    expect(formatUSD(1.999)).toBe('$2.00');
  });
});

describe('formatPercentage', () => {
  it('should format as percentage', () => {
    expect(formatPercentage(0.15)).toBe('15.00%');
  });

  it('should format zero', () => {
    expect(formatPercentage(0)).toBe('0.00%');
  });

  it('should format 100%', () => {
    expect(formatPercentage(1)).toBe('100.00%');
  });

  it('should handle custom decimals', () => {
    expect(formatPercentage(0.123456, 4)).toBe('12.3456%');
  });
});

describe('shortenAddress', () => {
  it('should shorten address', () => {
    const address = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
    expect(shortenAddress(address)).toBe('0x5aAe...eAed');
  });

  it('should handle custom length', () => {
    const address = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
    expect(shortenAddress(address, 6)).toBe('0x5aAe...1BeAed');
  });

  it('should return original if short enough', () => {
    expect(shortenAddress('0x123')).toBe('0x123');
  });
});

describe('shortenTxHash', () => {
  it('should shorten transaction hash', () => {
    const hash = '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';
    expect(shortenTxHash(hash)).toBe('0x1234...cdef');
  });

  it('should handle custom length', () => {
    const hash = '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';
    expect(shortenTxHash(hash, 8)).toBe('0x123456...90abcdef');
  });
});
