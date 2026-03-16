// Re-export all modules for backward compatibility
export * from "./types.js";
export * from "./abis/index.js";
export * from "./contracts/index.js";
export * from "./tx/index.js";

// Re-export existing modules
export * from "./errors.js";
export * from "./config.js";

// Re-export utils — but exclude names that conflict with tx/gas.ts
// (GasEstimate is exported from both utils/gas.ts and tx/gas.ts;
//  the tx/gas.ts version matches the original index.ts definition)
export {
  validateAddress,
  validateNonZeroAddress,
  isValidAddress,
  validatePositiveAmount,
  validateNonNegativeAmount,
  validateAmountBounds,
  validateHexData,
  validateBytes32,
  assertSufficientBalance,
  assertSufficientAllowance,
  formatBalance,
  parseAmount,
  formatETH,
  parseETH,
  formatUSD,
  parseUSD,
  formatssUSD,
  parsessUSD,
  formatGas,
  formatGasPrice,
  formatPercentage,
  formatAPY,
  shortenAddress,
  formatTimestamp,
  formatDuration,
  shortenTxHash,
  estimateGas,
  getFeeData,
  calculateRequiredFee,
  applyGasBuffer,
  hasSufficientGas,
  getRecommendedGasSettings,
  DEFAULT_GAS_LIMITS,
  withRetry,
  withTimeout,
  withRetryAndTimeout,
  createRetryable,
  pollUntil,
  DEFAULT_RETRY_OPTIONS,
  findEvent,
  findEventOrThrow,
  findAllEvents,
  extractEventArg,
  extractEventArgOrThrow,
  parseAllEvents,
  getEventTopic,
  findLogByTopic,
  decodeIndexedArg,
  EVENT_SIGNATURES
} from "./utils/index.js";

export type {
  FormatBalanceOptions,
  GasEstimate as UtilsGasEstimate,
  GasEstimateOptions,
  RetryOptions,
  ParsedEvent
} from "./utils/index.js";

// Re-export encryption module — but exclude names that conflict with
// types.ts, abis/, and contracts/ (ThresholdKey, EncryptedTxStatus,
// thresholdKeyRegistryAbi, encryptedMempoolAbi)
export {
  EncryptedTransaction,
  DecryptedTransaction,
  TransactionParams,
  SubmitOptions,
  MempoolStats,
  ThresholdEncryption,
  ThresholdKeyRegistryClient,
  EncryptedMempoolClient,
  MEVProtectionClient,
  createMEVProtectionClient
} from "./encryption.js";

// Re-export stablecoin modules
export * as stablecoin from "./stablecoin/index.js";
export * as agent from "./stablecoin/v2/index.js";
