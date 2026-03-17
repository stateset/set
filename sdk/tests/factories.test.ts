/**
 * @setchain/sdk - Factory Function Tests
 *
 * Tests input validation for provider/wallet/contract factory functions.
 */

import { describe, it, expect } from 'vitest';
import {
  createProvider,
  createWallet,
  getSetRegistry,
  getSetPaymaster,
  getThresholdKeyRegistry,
  getEncryptedMempool,
  getForcedInclusion,
  getSequencerAttestation,
  getSetTimelock,
  getWssUSD,
  getNAVOracle,
  getTreasuryVault,
  getSsUSD,
} from '../src/contracts/factories';
import { InvalidAddressError } from '../src/errors';

const VALID_ADDRESS = '0x1234567890123456789012345678901234567890';
const VALID_RPC = 'http://localhost:8545';

describe('createProvider', () => {
  it('should create provider with valid HTTP URL', () => {
    const provider = createProvider('http://localhost:8545');
    expect(provider).toBeDefined();
  });

  it('should create provider with HTTPS URL', () => {
    const provider = createProvider('https://rpc.setchain.io');
    expect(provider).toBeDefined();
  });

  it('should reject invalid URL scheme', () => {
    expect(() => createProvider('ftp://invalid')).toThrow('Invalid RPC URL');
    expect(() => createProvider('ws://invalid')).toThrow('Invalid RPC URL');
  });

  it('should reject empty URL', () => {
    expect(() => createProvider('')).toThrow('Invalid RPC URL');
  });
});

describe('createWallet', () => {
  it('should reject empty private key', () => {
    expect(() => createWallet('', VALID_RPC)).toThrow('Private key is required');
  });

  it('should create wallet with valid inputs', () => {
    const wallet = createWallet(
      '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
      VALID_RPC
    );
    expect(wallet).toBeDefined();
    expect(wallet.address).toBeDefined();
  });
});

describe('Contract factory address validation', () => {
  // We need a provider for contract creation
  const provider = createProvider(VALID_RPC);

  const factories = [
    { name: 'getSetRegistry', fn: getSetRegistry },
    { name: 'getSetPaymaster', fn: getSetPaymaster },
    { name: 'getThresholdKeyRegistry', fn: getThresholdKeyRegistry },
    { name: 'getEncryptedMempool', fn: getEncryptedMempool },
    { name: 'getForcedInclusion', fn: getForcedInclusion },
    { name: 'getSequencerAttestation', fn: getSequencerAttestation },
    { name: 'getSetTimelock', fn: getSetTimelock },
    { name: 'getWssUSD', fn: getWssUSD },
    { name: 'getNAVOracle', fn: getNAVOracle },
    { name: 'getTreasuryVault', fn: getTreasuryVault },
    { name: 'getSsUSD', fn: getSsUSD },
  ];

  for (const { name, fn } of factories) {
    it(`${name} should accept valid address`, () => {
      const contract = fn(VALID_ADDRESS, provider);
      expect(contract).toBeDefined();
    });

    it(`${name} should reject invalid address`, () => {
      expect(() => fn('not-an-address', provider)).toThrow(InvalidAddressError);
    });

    it(`${name} should reject short address`, () => {
      expect(() => fn('0x1234', provider)).toThrow(InvalidAddressError);
    });

    it(`${name} should reject empty address`, () => {
      expect(() => fn('', provider)).toThrow(InvalidAddressError);
    });
  }
});
