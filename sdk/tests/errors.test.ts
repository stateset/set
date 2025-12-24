/**
 * @setchain/sdk - Error System Tests
 */

import { describe, it, expect } from 'vitest';
import {
  SDKError,
  SDKErrorCode,
  InvalidAddressError,
  InvalidAmountError,
  InsufficientBalanceError,
  InsufficientAllowanceError,
  NetworkError,
  TimeoutError,
  TransactionFailedError,
  GasEstimationError,
  NAVStaleError,
  DepositsPausedError,
  RedemptionsPausedError,
  InvalidCollateralError,
  wrapError,
  isSDKError,
  hasErrorCode
} from '../src/errors';

describe('SDKError', () => {
  it('should create error with code and message', () => {
    const error = new SDKError(SDKErrorCode.UNKNOWN, 'Test error');
    expect(error.code).toBe(SDKErrorCode.UNKNOWN);
    expect(error.message).toContain('Test error');
    expect(error.message).toContain(SDKErrorCode.UNKNOWN);
  });

  it('should include details', () => {
    const error = new SDKError(SDKErrorCode.UNKNOWN, 'Test', {
      details: { foo: 'bar', count: 42 }
    });
    expect(error.details).toEqual({ foo: 'bar', count: 42 });
  });

  it('should include suggestion', () => {
    const error = new SDKError(SDKErrorCode.UNKNOWN, 'Test', {
      suggestion: 'Try again'
    });
    expect(error.suggestion).toBe('Try again');
  });

  it('should include cause', () => {
    const cause = new Error('Original error');
    const error = new SDKError(SDKErrorCode.UNKNOWN, 'Test', { cause });
    expect(error.cause).toBe(cause);
  });

  it('should serialize to JSON', () => {
    const error = new SDKError(SDKErrorCode.VALIDATION_ERROR, 'Invalid input', {
      details: { field: 'email' },
      suggestion: 'Check the email format'
    });

    const json = error.toJSON();
    expect(json.name).toBe('SDKError');
    expect(json.code).toBe(SDKErrorCode.VALIDATION_ERROR);
    expect(json.details).toEqual({ field: 'email' });
    expect(json.suggestion).toBe('Check the email format');
  });
});

describe('InvalidAddressError', () => {
  it('should include address in details', () => {
    const error = new InvalidAddressError('0x123', 'Too short');
    expect(error.code).toBe(SDKErrorCode.INVALID_ADDRESS);
    expect(error.details?.address).toBe('0x123');
    expect(error.details?.reason).toBe('Too short');
  });

  it('should have helpful suggestion', () => {
    const error = new InvalidAddressError('bad');
    expect(error.suggestion).toContain('valid Ethereum address');
  });
});

describe('InvalidAmountError', () => {
  it('should handle bigint amount', () => {
    const error = new InvalidAmountError(0n, 'Must be positive');
    expect(error.code).toBe(SDKErrorCode.INVALID_AMOUNT);
    expect(error.details?.amount).toBe('0');
  });

  it('should handle string amount', () => {
    const error = new InvalidAmountError('-100');
    expect(error.details?.amount).toBe('-100');
  });
});

describe('InsufficientBalanceError', () => {
  it('should format amounts with decimals', () => {
    const error = new InsufficientBalanceError(
      500000000000000000n,  // 0.5 ETH
      1000000000000000000n, // 1 ETH
      'ETH',
      18
    );
    expect(error.code).toBe(SDKErrorCode.INSUFFICIENT_BALANCE);
    expect(error.details?.available).toBe('0.5');
    expect(error.details?.required).toBe('1.0');
    expect(error.details?.shortfall).toBe('0.5');
    expect(error.details?.tokenSymbol).toBe('ETH');
  });

  it('should provide helpful suggestion', () => {
    const error = new InsufficientBalanceError(0n, 1000000n, 'USDC', 6);
    expect(error.suggestion).toContain('1.0');
    expect(error.suggestion).toContain('USDC');
  });
});

describe('InsufficientAllowanceError', () => {
  it('should include spender address', () => {
    const spender = '0x1234567890123456789012345678901234567890';
    const error = new InsufficientAllowanceError(0n, 1000n, spender, 'USDC', 6);
    expect(error.code).toBe(SDKErrorCode.INSUFFICIENT_ALLOWANCE);
    expect(error.details?.spender).toBe(spender);
  });
});

describe('NetworkError', () => {
  it('should include cause', () => {
    const cause = new Error('Connection refused');
    const error = new NetworkError('Failed to connect', cause);
    expect(error.code).toBe(SDKErrorCode.NETWORK_ERROR);
    expect(error.cause).toBe(cause);
  });
});

describe('TimeoutError', () => {
  it('should include operation and timeout', () => {
    const error = new TimeoutError('fetchBalance', 30000);
    expect(error.code).toBe(SDKErrorCode.TIMEOUT);
    expect(error.details?.operation).toBe('fetchBalance');
    expect(error.details?.timeoutMs).toBe(30000);
  });
});

describe('TransactionFailedError', () => {
  it('should include transaction hash', () => {
    const txHash = '0x123abc';
    const error = new TransactionFailedError('Out of gas', txHash);
    expect(error.code).toBe(SDKErrorCode.TRANSACTION_FAILED);
    expect(error.txHash).toBe(txHash);
    expect(error.details?.txHash).toBe(txHash);
  });
});

describe('GasEstimationError', () => {
  it('should include function name', () => {
    const error = new GasEstimationError('deposit');
    expect(error.code).toBe(SDKErrorCode.GAS_ESTIMATION_FAILED);
    expect(error.details?.functionName).toBe('deposit');
  });
});

describe('NAVStaleError', () => {
  it('should format timestamp as ISO date', () => {
    const timestamp = BigInt(Math.floor(Date.now() / 1000) - 86400);
    const error = new NAVStaleError(timestamp);
    expect(error.code).toBe(SDKErrorCode.NAV_STALE);
    expect(error.details?.lastUpdate).toMatch(/\d{4}-\d{2}-\d{2}T/);
  });
});

describe('DepositsPausedError', () => {
  it('should have correct error code', () => {
    const error = new DepositsPausedError();
    expect(error.code).toBe(SDKErrorCode.DEPOSITS_PAUSED);
    expect(error.message).toContain('paused');
  });
});

describe('RedemptionsPausedError', () => {
  it('should have correct error code', () => {
    const error = new RedemptionsPausedError();
    expect(error.code).toBe(SDKErrorCode.REDEMPTIONS_PAUSED);
    expect(error.message).toContain('paused');
  });
});

describe('InvalidCollateralError', () => {
  it('should include token address', () => {
    const address = '0x1234567890123456789012345678901234567890';
    const error = new InvalidCollateralError(address);
    expect(error.code).toBe(SDKErrorCode.INVALID_COLLATERAL);
    expect(error.details?.tokenAddress).toBe(address);
    expect(error.suggestion).toContain('getCollateralTokens');
  });
});

describe('wrapError', () => {
  it('should return SDKError unchanged', () => {
    const original = new SDKError(SDKErrorCode.UNKNOWN, 'Test');
    const wrapped = wrapError(original);
    expect(wrapped).toBe(original);
  });

  it('should wrap regular Error', () => {
    const original = new Error('Something went wrong');
    const wrapped = wrapError(original);
    expect(wrapped).toBeInstanceOf(SDKError);
    expect(wrapped.message).toContain('Something went wrong');
    expect(wrapped.cause).toBe(original);
  });

  it('should wrap string error', () => {
    const wrapped = wrapError('String error');
    expect(wrapped).toBeInstanceOf(SDKError);
    expect(wrapped.message).toContain('String error');
  });

  it('should add context to message', () => {
    const wrapped = wrapError(new Error('Base error'), 'During deposit');
    expect(wrapped.message).toContain('During deposit');
    expect(wrapped.message).toContain('Base error');
  });

  it('should detect insufficient funds error', () => {
    const wrapped = wrapError(new Error('insufficient funds for gas'));
    expect(wrapped.code).toBe(SDKErrorCode.INSUFFICIENT_GAS);
  });

  it('should detect network error', () => {
    const wrapped = wrapError(new Error('network connection failed'));
    expect(wrapped.code).toBe(SDKErrorCode.NETWORK_ERROR);
  });

  it('should detect timeout error', () => {
    const wrapped = wrapError(new Error('request timeout'));
    expect(wrapped.code).toBe(SDKErrorCode.TIMEOUT);
  });

  it('should detect reverted transaction', () => {
    const wrapped = wrapError(new Error('transaction reverted'));
    expect(wrapped.code).toBe(SDKErrorCode.TRANSACTION_REVERTED);
  });
});

describe('isSDKError', () => {
  it('should return true for SDKError', () => {
    expect(isSDKError(new SDKError(SDKErrorCode.UNKNOWN, 'Test'))).toBe(true);
  });

  it('should return true for SDKError subclasses', () => {
    expect(isSDKError(new InvalidAddressError('0x'))).toBe(true);
    expect(isSDKError(new NetworkError('Failed'))).toBe(true);
  });

  it('should return false for regular Error', () => {
    expect(isSDKError(new Error('Test'))).toBe(false);
  });

  it('should return false for non-errors', () => {
    expect(isSDKError('string')).toBe(false);
    expect(isSDKError(null)).toBe(false);
    expect(isSDKError(undefined)).toBe(false);
    expect(isSDKError({})).toBe(false);
  });
});

describe('hasErrorCode', () => {
  it('should return true for matching code', () => {
    const error = new SDKError(SDKErrorCode.NETWORK_ERROR, 'Test');
    expect(hasErrorCode(error, SDKErrorCode.NETWORK_ERROR)).toBe(true);
  });

  it('should return false for non-matching code', () => {
    const error = new SDKError(SDKErrorCode.NETWORK_ERROR, 'Test');
    expect(hasErrorCode(error, SDKErrorCode.TIMEOUT)).toBe(false);
  });

  it('should return false for non-SDKError', () => {
    expect(hasErrorCode(new Error('Test'), SDKErrorCode.UNKNOWN)).toBe(false);
  });
});
