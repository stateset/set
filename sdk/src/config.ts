/**
 * Set Chain SDK - Configuration
 *
 * Global SDK configuration with sensible defaults.
 */

/**
 * SDK configuration options
 */
export interface SDKConfig {
  // Gas settings
  /** Gas buffer multiplier (default: 1.2 = 20% buffer) */
  gasBuffer: number;

  // Timeout settings
  /** Transaction confirmation timeout in ms (default: 120000) */
  transactionTimeout: number;
  /** Number of block confirmations to wait for (default: 1) */
  blockConfirmations: number;
  /** RPC call timeout in ms (default: 30000) */
  rpcTimeout: number;

  // Retry settings
  /** Maximum retry attempts (default: 3) */
  maxRetries: number;
  /** Initial retry delay in ms (default: 1000) */
  initialRetryDelay: number;
  /** Maximum retry delay in ms (default: 30000) */
  maxRetryDelay: number;

  // MEV settings
  /** MEV transaction timeout in ms (default: 180000) */
  mevTimeout: number;
  /** MEV status poll interval in ms (default: 2000) */
  mevPollInterval: number;

  // Stablecoin settings
  /** Stablecoin decimals (default: 18) */
  ssUSDDecimals: number;
  /** USDC/USDT decimals (default: 6) */
  collateralDecimals: number;

  // Debug settings
  /** Enable debug logging (default: false) */
  debug: boolean;
}

/**
 * Default SDK configuration
 */
export const DEFAULT_CONFIG: Readonly<SDKConfig> = {
  // Gas
  gasBuffer: 1.2,

  // Timeouts
  transactionTimeout: 120000,
  blockConfirmations: 1,
  rpcTimeout: 30000,

  // Retry
  maxRetries: 3,
  initialRetryDelay: 1000,
  maxRetryDelay: 30000,

  // MEV
  mevTimeout: 180000,
  mevPollInterval: 2000,

  // Stablecoin
  ssUSDDecimals: 18,
  collateralDecimals: 6,

  // Debug
  debug: false
};

// Global mutable config
let globalConfig: SDKConfig = { ...DEFAULT_CONFIG };

/**
 * Get the current SDK configuration
 * @returns Current configuration (copy)
 */
export function getConfig(): SDKConfig {
  return { ...globalConfig };
}

/**
 * Update the global SDK configuration
 * @param overrides Configuration overrides
 */
export function setConfig(overrides: Partial<SDKConfig>): void {
  globalConfig = { ...globalConfig, ...overrides };
}

/**
 * Reset configuration to defaults
 */
export function resetConfig(): void {
  globalConfig = { ...DEFAULT_CONFIG };
}

/**
 * Create a configuration object with overrides
 * @param overrides Configuration overrides
 * @returns Merged configuration
 */
export function createConfig(overrides: Partial<SDKConfig> = {}): SDKConfig {
  return { ...DEFAULT_CONFIG, ...overrides };
}

/**
 * Network-specific configuration presets
 */
export const NETWORK_PRESETS = {
  /** Local development (Anvil) */
  local: createConfig({
    gasBuffer: 1.1,
    transactionTimeout: 30000,
    maxRetries: 1,
    debug: true
  }),

  /** Sepolia testnet */
  sepolia: createConfig({
    gasBuffer: 1.3,
    transactionTimeout: 180000,
    maxRetries: 3,
    debug: false
  }),

  /** Mainnet */
  mainnet: createConfig({
    gasBuffer: 1.2,
    transactionTimeout: 300000,
    maxRetries: 5,
    blockConfirmations: 2,
    debug: false
  })
} as const;

/**
 * Set Chain network configuration
 */
export interface NetworkConfig {
  /** Chain ID */
  chainId: number;
  /** Chain name */
  name: string;
  /** RPC URL */
  rpcUrl: string;
  /** Block explorer URL */
  explorerUrl: string;
  /** Native currency symbol */
  nativeCurrency: string;
}

/**
 * Known Set Chain networks
 */
export const NETWORKS: Record<string, NetworkConfig> = {
  local: {
    chainId: 31337,
    name: "Set Chain Local",
    rpcUrl: "http://localhost:8545",
    explorerUrl: "http://localhost:4000",
    nativeCurrency: "ETH"
  },
  sepolia: {
    chainId: 84532001,
    name: "Set Chain Sepolia",
    rpcUrl: "https://rpc.sepolia.setchain.io",
    explorerUrl: "https://explorer.sepolia.setchain.io",
    nativeCurrency: "ETH"
  },
  mainnet: {
    chainId: 84532000,
    name: "Set Chain",
    rpcUrl: "https://rpc.setchain.io",
    explorerUrl: "https://explorer.setchain.io",
    nativeCurrency: "ETH"
  }
};

/**
 * Contract addresses by network
 */
export interface ContractAddresses {
  setRegistry: string;
  setPaymaster: string;
  setTimelock?: string;

  // Stablecoin
  tokenRegistry?: string;
  navOracle?: string;
  ssUSD?: string;
  wssUSD?: string;
  treasury?: string;

  // MEV
  encryptedMempool?: string;
  thresholdKeyRegistry?: string;
  sequencerAttestation?: string;
  forcedInclusion?: string;
}

/**
 * Contract addresses for known networks
 */
export const CONTRACT_ADDRESSES: Partial<Record<string, ContractAddresses>> = {
  // Will be populated with actual addresses after deployment
  local: {
    setRegistry: "0x0000000000000000000000000000000000000000",
    setPaymaster: "0x0000000000000000000000000000000000000000"
  }
};

/**
 * Get contract addresses for a network
 * @param network Network name or chain ID
 * @returns Contract addresses or undefined
 */
export function getContractAddresses(network: string | number): ContractAddresses | undefined {
  if (typeof network === "number") {
    const networkEntry = Object.entries(NETWORKS).find(([_, cfg]) => cfg.chainId === network);
    if (networkEntry) {
      return CONTRACT_ADDRESSES[networkEntry[0]];
    }
    return undefined;
  }
  return CONTRACT_ADDRESSES[network];
}

/**
 * Debug logging utility
 * @param context Context/module name
 * @param message Log message
 * @param data Optional data to log
 */
export function debugLog(context: string, message: string, data?: unknown): void {
  if (globalConfig.debug) {
    const timestamp = new Date().toISOString();
    console.log(`[${timestamp}] [SetChain/${context}] ${message}`, data ?? "");
  }
}
