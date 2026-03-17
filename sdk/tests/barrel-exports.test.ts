/**
 * @setchain/sdk - Barrel Export Tests
 *
 * Ensures the SDK's public API surface is complete and backward-compatible.
 * Every export that was available from the monolithic index.ts must still
 * be importable from the package root.
 */

import { describe, it, expect } from 'vitest';
import * as SDK from '../src/index';

describe('Barrel Exports - Types', () => {
  it('should export core type names', () => {
    // These are type-only exports; we check they don't throw at import
    // by importing the module. TypeScript compilation confirms the types exist.
    expect(SDK).toBeDefined();
  });
});

describe('Barrel Exports - ABIs', () => {
  it('should export all ABI constants', () => {
    expect(SDK.setRegistryAbi).toBeDefined();
    expect(SDK.setPaymasterAbi).toBeDefined();
    expect(SDK.thresholdKeyRegistryAbi).toBeDefined();
    expect(SDK.sequencerAttestationAbi).toBeDefined();
    expect(SDK.forcedInclusionAbi).toBeDefined();
    expect(SDK.encryptedMempoolAbi).toBeDefined();
    expect(SDK.setTimelockAbi).toBeDefined();
    expect(SDK.wssUsdAbi).toBeDefined();
    expect(SDK.navOracleAbi).toBeDefined();
    expect(SDK.treasuryVaultAbi).toBeDefined();
    expect(SDK.ssUsdAbi).toBeDefined();
  });

  it('should export ABIs as arrays', () => {
    expect(Array.isArray(SDK.setRegistryAbi)).toBe(true);
    expect(Array.isArray(SDK.setPaymasterAbi)).toBe(true);
  });
});

describe('Barrel Exports - Contract Factories', () => {
  it('should export factory functions', () => {
    expect(typeof SDK.createProvider).toBe('function');
    expect(typeof SDK.createWallet).toBe('function');
    expect(typeof SDK.getSetRegistry).toBe('function');
    expect(typeof SDK.getSetPaymaster).toBe('function');
    expect(typeof SDK.getThresholdKeyRegistry).toBe('function');
    expect(typeof SDK.getSequencerAttestation).toBe('function');
    expect(typeof SDK.getForcedInclusion).toBe('function');
    expect(typeof SDK.getEncryptedMempool).toBe('function');
    expect(typeof SDK.getSetTimelock).toBe('function');
    expect(typeof SDK.getWssUSD).toBe('function');
    expect(typeof SDK.getNAVOracle).toBe('function');
    expect(typeof SDK.getTreasuryVault).toBe('function');
    expect(typeof SDK.getSsUSD).toBe('function');
  });
});

describe('Barrel Exports - Utils', () => {
  it('should export validation utilities', () => {
    expect(typeof SDK.validateAddress).toBe('function');
    expect(typeof SDK.validateNonZeroAddress).toBe('function');
    expect(typeof SDK.isValidAddress).toBe('function');
    expect(typeof SDK.validatePositiveAmount).toBe('function');
    expect(typeof SDK.validateBytes32).toBe('function');
  });

  it('should export formatting utilities', () => {
    expect(typeof SDK.formatBalance).toBe('function');
    expect(typeof SDK.parseAmount).toBe('function');
    expect(typeof SDK.formatETH).toBe('function');
    expect(typeof SDK.formatUSD).toBe('function');
    expect(typeof SDK.shortenAddress).toBe('function');
    expect(typeof SDK.shortenTxHash).toBe('function');
    expect(typeof SDK.formatGas).toBe('function');
    expect(typeof SDK.formatGasPrice).toBe('function');
    expect(typeof SDK.formatPercentage).toBe('function');
    expect(typeof SDK.formatAPY).toBe('function');
  });

  it('should export gas utilities', () => {
    expect(typeof SDK.estimateGas).toBe('function');
    expect(typeof SDK.getFeeData).toBe('function');
    expect(typeof SDK.applyGasBuffer).toBe('function');
    expect(typeof SDK.hasSufficientGas).toBe('function');
    expect(SDK.DEFAULT_GAS_LIMITS).toBeDefined();
  });

  it('should export retry utilities', () => {
    expect(typeof SDK.withRetry).toBe('function');
    expect(typeof SDK.withTimeout).toBe('function');
    expect(typeof SDK.withRetryAndTimeout).toBe('function');
    expect(typeof SDK.pollUntil).toBe('function');
    expect(SDK.DEFAULT_RETRY_OPTIONS).toBeDefined();
  });

  it('should export event utilities', () => {
    expect(typeof SDK.findEvent).toBe('function');
    expect(typeof SDK.findAllEvents).toBe('function');
    expect(typeof SDK.extractEventArg).toBe('function');
    expect(typeof SDK.parseAllEvents).toBe('function');
    expect(typeof SDK.getEventTopic).toBe('function');
    expect(SDK.EVENT_SIGNATURES).toBeDefined();
  });
});

describe('Barrel Exports - Errors', () => {
  it('should export error classes', () => {
    expect(SDK.SDKError).toBeDefined();
    expect(SDK.InvalidAddressError).toBeDefined();
    expect(SDK.InvalidAmountError).toBeDefined();
    expect(SDK.InsufficientBalanceError).toBeDefined();
    expect(SDK.NetworkError).toBeDefined();
    expect(SDK.TimeoutError).toBeDefined();
    expect(SDK.TransactionFailedError).toBeDefined();
  });

  it('should export error utilities', () => {
    expect(typeof SDK.wrapError).toBe('function');
    expect(typeof SDK.isSDKError).toBe('function');
    expect(typeof SDK.hasErrorCode).toBe('function');
  });
});

describe('Barrel Exports - Config', () => {
  it('should export config functions', () => {
    expect(typeof SDK.getConfig).toBe('function');
    expect(typeof SDK.setConfig).toBe('function');
    expect(typeof SDK.resetConfig).toBe('function');
    expect(SDK.DEFAULT_CONFIG).toBeDefined();
    expect(SDK.NETWORKS).toBeDefined();
  });
});

describe('Barrel Exports - Transaction Utilities', () => {
  it('should export transaction builder', () => {
    expect(SDK.TransactionBuilder).toBeDefined();
  });

  it('should export gas estimation', () => {
    expect(typeof SDK.estimateContractGas).toBe('function');
    expect(typeof SDK.simulateContractCall).toBe('function');
  });

  it('should export health check', () => {
    expect(typeof SDK.performSystemHealthCheck).toBe('function');
    expect(typeof SDK.formatHealthStatus).toBe('function');
  });
});

describe('Barrel Exports - Sub-modules', () => {
  it('should export stablecoin module', () => {
    expect(SDK.stablecoin).toBeDefined();
  });

  it('should export agent module', () => {
    expect(SDK.agent).toBeDefined();
  });
});
