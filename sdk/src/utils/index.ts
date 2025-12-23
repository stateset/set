/**
 * Set Chain SDK - Utilities
 *
 * Re-exports all utility functions for convenient access.
 */

// Validation utilities
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
  assertSufficientAllowance
} from "./validation";

// Formatting utilities
export {
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
  type FormatBalanceOptions
} from "./formatting";

// Gas utilities
export {
  estimateGas,
  getFeeData,
  calculateRequiredFee,
  applyGasBuffer,
  hasSufficientGas,
  getRecommendedGasSettings,
  DEFAULT_GAS_LIMITS,
  type GasEstimate,
  type GasEstimateOptions
} from "./gas";

// Retry utilities
export {
  withRetry,
  withTimeout,
  withRetryAndTimeout,
  createRetryable,
  pollUntil,
  DEFAULT_RETRY_OPTIONS,
  type RetryOptions
} from "./retry";

// Event utilities
export {
  findEvent,
  findEventOrThrow,
  findAllEvents,
  extractEventArg,
  extractEventArgOrThrow,
  parseAllEvents,
  getEventTopic,
  findLogByTopic,
  decodeIndexedArg,
  EVENT_SIGNATURES,
  type ParsedEvent
} from "./events";
