/**
 * Set Chain SDK - Error System
 *
 * Custom error classes with error codes for better debugging and handling.
 */

import { formatUnits } from "ethers";

/**
 * Error codes for SDK operations
 */
export enum SDKErrorCode {
  // Validation errors (1xxx)
  INVALID_ADDRESS = "SDK_1001",
  INVALID_AMOUNT = "SDK_1002",
  INVALID_DATA = "SDK_1003",
  VALIDATION_ERROR = "SDK_1004",

  // Balance errors (2xxx)
  INSUFFICIENT_BALANCE = "SDK_2001",
  INSUFFICIENT_ALLOWANCE = "SDK_2002",
  INSUFFICIENT_GAS = "SDK_2003",

  // Network errors (3xxx)
  NETWORK_ERROR = "SDK_3001",
  RPC_ERROR = "SDK_3002",
  TIMEOUT = "SDK_3003",
  CONNECTION_FAILED = "SDK_3004",

  // Transaction errors (4xxx)
  TRANSACTION_FAILED = "SDK_4001",
  TRANSACTION_REVERTED = "SDK_4002",
  TRANSACTION_REPLACED = "SDK_4003",
  TRANSACTION_CANCELLED = "SDK_4004",

  // Contract errors (5xxx)
  CONTRACT_ERROR = "SDK_5001",
  GAS_ESTIMATION_FAILED = "SDK_5002",
  EVENT_PARSE_ERROR = "SDK_5003",
  CALL_EXCEPTION = "SDK_5004",

  // MEV errors (6xxx)
  MEV_UNAVAILABLE = "SDK_6001",
  ENCRYPTION_FAILED = "SDK_6002",
  DECRYPTION_TIMEOUT = "SDK_6003",
  INVALID_EPOCH = "SDK_6004",

  // Stablecoin errors (7xxx)
  NAV_STALE = "SDK_7001",
  DEPOSITS_PAUSED = "SDK_7002",
  REDEMPTIONS_PAUSED = "SDK_7003",
  INVALID_COLLATERAL = "SDK_7004",

  // Unknown
  UNKNOWN = "SDK_9999"
}

/**
 * Base SDK error class
 */
export class SDKError extends Error {
  readonly code: SDKErrorCode;
  readonly details?: Record<string, unknown>;
  readonly suggestion?: string;
  readonly cause?: Error;

  constructor(
    code: SDKErrorCode,
    message: string,
    options?: {
      details?: Record<string, unknown>;
      suggestion?: string;
      cause?: Error;
    }
  ) {
    super(`[${code}] ${message}`);
    this.name = "SDKError";
    this.code = code;
    this.details = options?.details;
    this.suggestion = options?.suggestion;
    this.cause = options?.cause;

    // Maintain proper stack trace
    if (Error.captureStackTrace) {
      Error.captureStackTrace(this, this.constructor);
    }
  }

  toJSON(): Record<string, unknown> {
    return {
      name: this.name,
      code: this.code,
      message: this.message,
      details: this.details,
      suggestion: this.suggestion
    };
  }
}

/**
 * Invalid address error
 */
export class InvalidAddressError extends SDKError {
  constructor(address: string, reason?: string) {
    super(SDKErrorCode.INVALID_ADDRESS, `Invalid address: ${address}`, {
      details: { address, reason },
      suggestion: "Ensure the address is a valid Ethereum address (0x followed by 40 hex characters)"
    });
    this.name = "InvalidAddressError";
  }
}

/**
 * Invalid amount error
 */
export class InvalidAmountError extends SDKError {
  constructor(amount: bigint | string | number, reason?: string) {
    super(SDKErrorCode.INVALID_AMOUNT, `Invalid amount: ${amount}`, {
      details: { amount: String(amount), reason },
      suggestion: "Amount must be a positive number"
    });
    this.name = "InvalidAmountError";
  }
}

/**
 * Insufficient balance error
 */
export class InsufficientBalanceError extends SDKError {
  constructor(
    available: bigint,
    required: bigint,
    tokenSymbol = "tokens",
    decimals = 18
  ) {
    const availableFormatted = formatUnits(available, decimals);
    const requiredFormatted = formatUnits(required, decimals);
    const shortfall = required - available;
    const shortfallFormatted = formatUnits(shortfall, decimals);

    super(SDKErrorCode.INSUFFICIENT_BALANCE, `Insufficient balance`, {
      details: {
        available: availableFormatted,
        required: requiredFormatted,
        shortfall: shortfallFormatted,
        tokenSymbol
      },
      suggestion: `Need ${shortfallFormatted} more ${tokenSymbol}`
    });
    this.name = "InsufficientBalanceError";
  }
}

/**
 * Insufficient allowance error
 */
export class InsufficientAllowanceError extends SDKError {
  constructor(
    currentAllowance: bigint,
    required: bigint,
    spender: string,
    tokenSymbol = "tokens",
    decimals = 18
  ) {
    const currentFormatted = formatUnits(currentAllowance, decimals);
    const requiredFormatted = formatUnits(required, decimals);

    super(SDKErrorCode.INSUFFICIENT_ALLOWANCE, `Insufficient allowance`, {
      details: {
        currentAllowance: currentFormatted,
        required: requiredFormatted,
        spender,
        tokenSymbol
      },
      suggestion: `Approve ${requiredFormatted} ${tokenSymbol} for ${spender}`
    });
    this.name = "InsufficientAllowanceError";
  }
}

/**
 * Network error
 */
export class NetworkError extends SDKError {
  constructor(message: string, cause?: Error) {
    super(SDKErrorCode.NETWORK_ERROR, message, {
      cause,
      suggestion: "Check your network connection and RPC endpoint"
    });
    this.name = "NetworkError";
  }
}

/**
 * Timeout error
 */
export class TimeoutError extends SDKError {
  constructor(operation: string, timeoutMs: number) {
    super(SDKErrorCode.TIMEOUT, `Operation timed out: ${operation}`, {
      details: { operation, timeoutMs },
      suggestion: `Consider increasing the timeout or check network conditions`
    });
    this.name = "TimeoutError";
  }
}

/**
 * Transaction failed error
 */
export class TransactionFailedError extends SDKError {
  readonly txHash?: string;

  constructor(reason: string, txHash?: string, cause?: Error) {
    super(SDKErrorCode.TRANSACTION_FAILED, reason, {
      details: { txHash },
      cause,
      suggestion: "Check the transaction on the block explorer for details"
    });
    this.name = "TransactionFailedError";
    this.txHash = txHash;
  }
}

/**
 * Gas estimation failed error
 */
export class GasEstimationError extends SDKError {
  constructor(functionName: string, cause?: Error) {
    super(SDKErrorCode.GAS_ESTIMATION_FAILED, `Gas estimation failed for ${functionName}`, {
      details: { functionName },
      cause,
      suggestion: "The transaction may revert. Check contract state and parameters."
    });
    this.name = "GasEstimationError";
  }
}

/**
 * Event parse error
 */
export class EventParseError extends SDKError {
  constructor(eventName: string, txHash?: string) {
    super(SDKErrorCode.EVENT_PARSE_ERROR, `Failed to parse event: ${eventName}`, {
      details: { eventName, txHash },
      suggestion: "The transaction may have succeeded but event parsing failed. Check the transaction receipt."
    });
    this.name = "EventParseError";
  }
}

/**
 * MEV protection unavailable error
 */
export class MEVUnavailableError extends SDKError {
  constructor(reason?: string) {
    super(SDKErrorCode.MEV_UNAVAILABLE, "MEV protection is not available", {
      details: { reason },
      suggestion: "Try again later or use standard transactions"
    });
    this.name = "MEVUnavailableError";
  }
}

/**
 * NAV stale error
 */
export class NAVStaleError extends SDKError {
  constructor(lastUpdate: bigint) {
    const lastUpdateDate = new Date(Number(lastUpdate) * 1000).toISOString();
    super(SDKErrorCode.NAV_STALE, "NAV data is stale", {
      details: { lastUpdate: lastUpdateDate },
      suggestion: "Wait for NAV attestor to update the NAV before proceeding"
    });
    this.name = "NAVStaleError";
  }
}

/**
 * Deposits paused error
 */
export class DepositsPausedError extends SDKError {
  constructor() {
    super(SDKErrorCode.DEPOSITS_PAUSED, "Deposits are currently paused", {
      suggestion: "Check system status and try again later"
    });
    this.name = "DepositsPausedError";
  }
}

/**
 * Redemptions paused error
 */
export class RedemptionsPausedError extends SDKError {
  constructor() {
    super(SDKErrorCode.REDEMPTIONS_PAUSED, "Redemptions are currently paused", {
      suggestion: "Check system status and try again later"
    });
    this.name = "RedemptionsPausedError";
  }
}

/**
 * Invalid collateral error
 */
export class InvalidCollateralError extends SDKError {
  constructor(tokenAddress: string) {
    super(SDKErrorCode.INVALID_COLLATERAL, `Token is not approved collateral: ${tokenAddress}`, {
      details: { tokenAddress },
      suggestion: "Use getCollateralTokens() to get the list of approved collateral tokens"
    });
    this.name = "InvalidCollateralError";
  }
}

/**
 * Wrap any error into an SDKError
 */
export function wrapError(error: unknown, context?: string): SDKError {
  if (error instanceof SDKError) {
    return error;
  }

  const message = error instanceof Error ? error.message : String(error);
  const cause = error instanceof Error ? error : undefined;

  // Try to detect error type from message
  if (message.includes("insufficient funds") || message.includes("INSUFFICIENT_FUNDS")) {
    return new SDKError(SDKErrorCode.INSUFFICIENT_GAS, "Insufficient funds for gas", { cause });
  }

  if (message.includes("network") || message.includes("NETWORK")) {
    return new NetworkError(message, cause);
  }

  if (message.includes("timeout") || message.includes("TIMEOUT")) {
    return new SDKError(SDKErrorCode.TIMEOUT, message, { cause });
  }

  if (message.includes("reverted") || message.includes("CALL_EXCEPTION")) {
    return new SDKError(SDKErrorCode.TRANSACTION_REVERTED, message, { cause });
  }

  return new SDKError(
    SDKErrorCode.UNKNOWN,
    context ? `${context}: ${message}` : message,
    { cause }
  );
}

/**
 * Type guard for SDKError
 */
export function isSDKError(error: unknown): error is SDKError {
  return error instanceof SDKError;
}

/**
 * Type guard for specific error code
 */
export function hasErrorCode(error: unknown, code: SDKErrorCode): boolean {
  return isSDKError(error) && error.code === code;
}
