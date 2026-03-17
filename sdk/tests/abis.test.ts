/**
 * @setchain/sdk - ABI Module Tests
 *
 * Validates that all ABI exports are well-formed arrays of ABI fragments.
 */

import { describe, it, expect } from 'vitest';
import {
  setRegistryAbi,
  setPaymasterAbi,
  thresholdKeyRegistryAbi,
  sequencerAttestationAbi,
  forcedInclusionAbi,
  encryptedMempoolAbi,
  setTimelockAbi,
  wssUsdAbi,
  navOracleAbi,
  treasuryVaultAbi,
  ssUsdAbi,
} from '../src/abis/index';

function validateAbi(abi: readonly any[], name: string) {
  expect(Array.isArray(abi), `${name} should be an array`).toBe(true);
  expect(abi.length, `${name} should not be empty`).toBeGreaterThan(0);

  for (const fragment of abi) {
    expect(fragment).toHaveProperty('type');
    expect(['function', 'event', 'error', 'constructor', 'fallback', 'receive'])
      .toContain(fragment.type);
  }
}

function findFunction(abi: readonly any[], name: string) {
  return abi.find(f => f.type === 'function' && f.name === name);
}

describe('ABI Exports', () => {
  it('should export setRegistryAbi with expected functions', () => {
    validateAbi(setRegistryAbi, 'setRegistryAbi');
    expect(findFunction(setRegistryAbi, 'commitBatch')).toBeDefined();
    expect(findFunction(setRegistryAbi, 'verifyInclusion')).toBeDefined();
    expect(findFunction(setRegistryAbi, 'getRegistryStats')).toBeDefined();
  });

  it('should export setPaymasterAbi with expected functions', () => {
    validateAbi(setPaymasterAbi, 'setPaymasterAbi');
    expect(findFunction(setPaymasterAbi, 'executeSponsorship')).toBeDefined();
    expect(findFunction(setPaymasterAbi, 'sponsorMerchant')).toBeDefined();
    expect(findFunction(setPaymasterAbi, 'getMerchantDetails')).toBeDefined();
  });

  it('should export thresholdKeyRegistryAbi', () => {
    validateAbi(thresholdKeyRegistryAbi, 'thresholdKeyRegistryAbi');
    expect(findFunction(thresholdKeyRegistryAbi, 'getRegistryStatus')).toBeDefined();
  });

  it('should export sequencerAttestationAbi', () => {
    validateAbi(sequencerAttestationAbi, 'sequencerAttestationAbi');
  });

  it('should export forcedInclusionAbi', () => {
    validateAbi(forcedInclusionAbi, 'forcedInclusionAbi');
    expect(findFunction(forcedInclusionAbi, 'getSystemStatus')).toBeDefined();
  });

  it('should export encryptedMempoolAbi', () => {
    validateAbi(encryptedMempoolAbi, 'encryptedMempoolAbi');
  });

  it('should export setTimelockAbi', () => {
    validateAbi(setTimelockAbi, 'setTimelockAbi');
  });

  it('should export wssUsdAbi', () => {
    validateAbi(wssUsdAbi, 'wssUsdAbi');
    expect(findFunction(wssUsdAbi, 'wrap')).toBeDefined();
    expect(findFunction(wssUsdAbi, 'unwrap')).toBeDefined();
  });

  it('should export navOracleAbi', () => {
    validateAbi(navOracleAbi, 'navOracleAbi');
  });

  it('should export treasuryVaultAbi', () => {
    validateAbi(treasuryVaultAbi, 'treasuryVaultAbi');
  });

  it('should export ssUsdAbi', () => {
    validateAbi(ssUsdAbi, 'ssUsdAbi');
  });

  it('should have consistent ABI fragment structure', () => {
    const allAbis = [
      setRegistryAbi, setPaymasterAbi, thresholdKeyRegistryAbi,
      sequencerAttestationAbi, forcedInclusionAbi, encryptedMempoolAbi,
      setTimelockAbi, wssUsdAbi, navOracleAbi, treasuryVaultAbi, ssUsdAbi,
    ];

    for (const abi of allAbis) {
      for (const fragment of abi) {
        if (fragment.type === 'function') {
          expect(fragment).toHaveProperty('name');
          expect(fragment).toHaveProperty('inputs');
          expect(fragment).toHaveProperty('outputs');
          expect(fragment).toHaveProperty('stateMutability');
        }
        if (fragment.type === 'event') {
          expect(fragment).toHaveProperty('name');
          expect(fragment).toHaveProperty('inputs');
        }
      }
    }
  });
});
