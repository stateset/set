/**
 * @setchain/sdk - Configuration Tests
 */

import { describe, it, expect } from 'vitest';
import {
  DEFAULT_CONFIG,
  getConfig,
  setConfig,
  resetConfig,
  NETWORKS,
  NETWORK_PRESETS,
  getNetworkNamesByChainId,
  resolveNetworkName,
  getContractAddresses,
  createConfig,
  type SDKConfig
} from '../src/config';

describe('DEFAULT_CONFIG', () => {
  it('should have sensible gas defaults', () => {
    expect(DEFAULT_CONFIG.gasBuffer).toBe(1.2);
    expect(DEFAULT_CONFIG.gasBuffer).toBeGreaterThan(1);
    expect(DEFAULT_CONFIG.gasBuffer).toBeLessThan(2);
  });

  it('should have sensible timeout defaults', () => {
    expect(DEFAULT_CONFIG.transactionTimeout).toBe(120000);
    expect(DEFAULT_CONFIG.rpcTimeout).toBe(30000);
    expect(DEFAULT_CONFIG.blockConfirmations).toBe(1);
    expect(DEFAULT_CONFIG.mevTimeout).toBe(180000);
  });

  it('should have sensible retry defaults', () => {
    expect(DEFAULT_CONFIG.maxRetries).toBeGreaterThanOrEqual(1);
    expect(DEFAULT_CONFIG.initialRetryDelay).toBeGreaterThan(0);
    expect(DEFAULT_CONFIG.maxRetryDelay).toBeGreaterThan(DEFAULT_CONFIG.initialRetryDelay);
  });

  it('should have stablecoin decimal config', () => {
    expect(DEFAULT_CONFIG.ssUSDDecimals).toBe(18);
    expect(DEFAULT_CONFIG.collateralDecimals).toBe(6);
  });

  it('should have debug disabled by default', () => {
    expect(DEFAULT_CONFIG.debug).toBe(false);
  });
});

describe('NETWORKS', () => {
  it('should define known networks', () => {
    expect(NETWORKS.local).toBeDefined();
    expect(NETWORKS.sepolia).toBeDefined();
    expect(NETWORKS.mainnet).toBeDefined();
  });

  it('should align local config with the repo devnet chain ID', () => {
    expect(NETWORKS.local.chainId).toBe(84532001);
    expect(NETWORKS.local.rpcUrl).toBe('http://localhost:8545');
  });

  it('should have correct Set Chain Sepolia config', () => {
    expect(NETWORKS.sepolia.chainId).toBe(84532001);
    expect(NETWORKS.sepolia.name).toBe('Set Chain Sepolia');
    expect(NETWORKS.sepolia.nativeCurrency).toBe('ETH');
  });

  it('should expose shared chain IDs explicitly', () => {
    expect(getNetworkNamesByChainId(84532001)).toEqual(['local', 'sepolia']);
  });

  it('should have valid RPC URLs', () => {
    for (const [, network] of Object.entries(NETWORKS)) {
      expect(network.rpcUrl).toMatch(/^https?:\/\//);
    }
  });
});

describe('NETWORK_PRESETS', () => {
  it('should have presets for each environment', () => {
    expect(NETWORK_PRESETS.local.debug).toBe(true);
    expect(NETWORK_PRESETS.sepolia.debug).toBe(false);
    expect(NETWORK_PRESETS.mainnet.debug).toBe(false);
  });

  it('should have increasing gas buffers for production', () => {
    expect(NETWORK_PRESETS.local.gasBuffer).toBeLessThanOrEqual(NETWORK_PRESETS.mainnet.gasBuffer);
  });
});

describe('Config Functions', () => {
  it('should get current config', () => {
    const config = getConfig();
    expect(config).toBeDefined();
    expect(config.gasBuffer).toBe(DEFAULT_CONFIG.gasBuffer);
  });

  it('should set config with partial values', () => {
    setConfig({ debug: true });
    const config = getConfig();
    expect(config.debug).toBe(true);
    expect(config.gasBuffer).toBe(DEFAULT_CONFIG.gasBuffer);
    resetConfig();
  });

  it('should reset config to defaults', () => {
    setConfig({ debug: true, gasBuffer: 1.5 });
    resetConfig();
    const config = getConfig();
    expect(config.debug).toBe(false);
    expect(config.gasBuffer).toBe(1.2);
  });

  it('should create config with overrides', () => {
    const config = createConfig({ maxRetries: 10 });
    expect(config.maxRetries).toBe(10);
    expect(config.gasBuffer).toBe(DEFAULT_CONFIG.gasBuffer);
  });

  it('should get contract addresses by network name', () => {
    const addrs = getContractAddresses('local');
    expect(addrs).toBeDefined();
    expect(addrs?.setRegistry).toBeDefined();
  });

  it('should resolve unique chain IDs only', () => {
    expect(resolveNetworkName(84532000)).toBe('mainnet');
    expect(resolveNetworkName(84532001)).toBeUndefined();
  });

  it('should reject ambiguous chain IDs when fetching contract addresses', () => {
    expect(getContractAddresses(84532001)).toBeUndefined();
  });

  it('should return undefined for unknown network', () => {
    expect(resolveNetworkName('unknown')).toBeUndefined();
    expect(getContractAddresses('unknown')).toBeUndefined();
    expect(getContractAddresses(99999)).toBeUndefined();
  });
});
