/**
 * @setchain/sdk - Validation Utilities Tests
 */

import { describe, it, expect } from 'vitest';
import {
  validateAddress,
  validateNonZeroAddress,
  isValidAddress,
  validatePositiveAmount,
  validateNonNegativeAmount,
  validateAmountBounds,
  validateHexData,
  validateBytes32
} from '../src/utils/validation';
import { InvalidAddressError, InvalidAmountError, SDKError, SDKErrorCode } from '../src/errors';

describe('validateAddress', () => {
  it('should accept valid checksummed address', () => {
    const address = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
    expect(validateAddress(address)).toBe(address);
  });

  it('should accept valid lowercase address and return checksummed', () => {
    const address = '0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed';
    const expected = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
    expect(validateAddress(address)).toBe(expected);
  });

  it('should throw InvalidAddressError for empty string', () => {
    expect(() => validateAddress('')).toThrow(InvalidAddressError);
  });

  it('should throw InvalidAddressError for undefined', () => {
    expect(() => validateAddress(undefined as unknown as string)).toThrow(InvalidAddressError);
  });

  it('should throw InvalidAddressError for invalid format', () => {
    expect(() => validateAddress('not-an-address')).toThrow(InvalidAddressError);
  });

  it('should throw InvalidAddressError for short address', () => {
    expect(() => validateAddress('0x5aAeb6053F3E94C9b9A09f336')).toThrow(InvalidAddressError);
  });

  it('should include name in error message', () => {
    try {
      validateAddress('', 'recipientAddress');
      expect.fail('Should have thrown');
    } catch (error) {
      expect(error).toBeInstanceOf(InvalidAddressError);
      expect((error as InvalidAddressError).message).toContain('recipientAddress');
    }
  });
});

describe('validateNonZeroAddress', () => {
  it('should accept valid non-zero address', () => {
    const address = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
    expect(validateNonZeroAddress(address)).toBe(address);
  });

  it('should throw for zero address', () => {
    expect(() => validateNonZeroAddress('0x0000000000000000000000000000000000000000'))
      .toThrow(InvalidAddressError);
  });
});

describe('isValidAddress', () => {
  it('should return true for valid address', () => {
    expect(isValidAddress('0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed')).toBe(true);
  });

  it('should return false for invalid address', () => {
    expect(isValidAddress('not-an-address')).toBe(false);
  });

  it('should return false for empty string', () => {
    expect(isValidAddress('')).toBe(false);
  });
});

describe('validatePositiveAmount', () => {
  it('should accept positive bigint', () => {
    expect(() => validatePositiveAmount(100n)).not.toThrow();
  });

  it('should throw for zero', () => {
    expect(() => validatePositiveAmount(0n)).toThrow(InvalidAmountError);
  });

  it('should throw for negative', () => {
    expect(() => validatePositiveAmount(-100n)).toThrow(InvalidAmountError);
  });

  it('should throw for non-bigint', () => {
    expect(() => validatePositiveAmount(100 as unknown as bigint)).toThrow(InvalidAmountError);
  });

  it('should include name in error message', () => {
    try {
      validatePositiveAmount(0n, 'depositAmount');
      expect.fail('Should have thrown');
    } catch (error) {
      expect((error as InvalidAmountError).message).toContain('depositAmount');
    }
  });
});

describe('validateNonNegativeAmount', () => {
  it('should accept zero', () => {
    expect(() => validateNonNegativeAmount(0n)).not.toThrow();
  });

  it('should accept positive', () => {
    expect(() => validateNonNegativeAmount(100n)).not.toThrow();
  });

  it('should throw for negative', () => {
    expect(() => validateNonNegativeAmount(-1n)).toThrow(InvalidAmountError);
  });
});

describe('validateAmountBounds', () => {
  it('should accept amount within bounds', () => {
    expect(() => validateAmountBounds(50n, 0n, 100n)).not.toThrow();
  });

  it('should accept amount at min bound', () => {
    expect(() => validateAmountBounds(10n, 10n, 100n)).not.toThrow();
  });

  it('should accept amount at max bound', () => {
    expect(() => validateAmountBounds(100n, 10n, 100n)).not.toThrow();
  });

  it('should throw for amount below min', () => {
    expect(() => validateAmountBounds(5n, 10n, 100n)).toThrow(InvalidAmountError);
  });

  it('should throw for amount above max', () => {
    expect(() => validateAmountBounds(150n, 10n, 100n)).toThrow(InvalidAmountError);
  });
});

describe('validateHexData', () => {
  it('should accept valid hex data', () => {
    expect(validateHexData('0x1234abcdef')).toBe('0x1234abcdef');
  });

  it('should normalize uppercase to lowercase', () => {
    expect(validateHexData('0x1234ABCDEF')).toBe('0x1234abcdef');
  });

  it('should accept empty hex data (0x)', () => {
    expect(validateHexData('0x')).toBe('0x');
  });

  it('should throw for missing 0x prefix', () => {
    expect(() => validateHexData('1234abcdef')).toThrow(SDKError);
  });

  it('should throw for invalid hex characters', () => {
    expect(() => validateHexData('0x1234xyz')).toThrow(SDKError);
  });

  it('should throw for odd length', () => {
    expect(() => validateHexData('0x123')).toThrow(SDKError);
  });

  it('should throw for empty string', () => {
    expect(() => validateHexData('')).toThrow(SDKError);
  });
});

describe('validateBytes32', () => {
  it('should accept valid bytes32', () => {
    const bytes32 = '0x' + 'a'.repeat(64);
    expect(validateBytes32(bytes32)).toBe(bytes32);
  });

  it('should throw for too short', () => {
    const tooShort = '0x' + 'a'.repeat(62);
    expect(() => validateBytes32(tooShort)).toThrow(SDKError);
  });

  it('should throw for too long', () => {
    const tooLong = '0x' + 'a'.repeat(66);
    expect(() => validateBytes32(tooLong)).toThrow(SDKError);
  });
});
