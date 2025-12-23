/**
 * Set Chain SDK - Retry Utilities
 *
 * Exponential backoff retry logic for network operations.
 */

import { NetworkError, TimeoutError, SDKError, SDKErrorCode } from "../errors";

/**
 * Retry options
 */
export interface RetryOptions {
  /** Maximum number of retry attempts (default: 3) */
  maxAttempts?: number;
  /** Initial delay in milliseconds (default: 1000) */
  initialDelayMs?: number;
  /** Maximum delay in milliseconds (default: 30000) */
  maxDelayMs?: number;
  /** Backoff multiplier (default: 2) */
  backoffMultiplier?: number;
  /** Whether to add jitter to delay (default: true) */
  jitter?: boolean;
  /** Custom function to determine if error is retryable */
  isRetryable?: (error: unknown) => boolean;
  /** Callback for each retry attempt */
  onRetry?: (attempt: number, error: unknown, delayMs: number) => void;
}

/**
 * Default retry options
 */
export const DEFAULT_RETRY_OPTIONS: Required<Omit<RetryOptions, "onRetry" | "isRetryable">> = {
  maxAttempts: 3,
  initialDelayMs: 1000,
  maxDelayMs: 30000,
  backoffMultiplier: 2,
  jitter: true
};

/**
 * Check if an error is retryable by default
 */
function defaultIsRetryable(error: unknown): boolean {
  // Never retry user errors
  if (error instanceof SDKError) {
    const nonRetryable = [
      SDKErrorCode.INVALID_ADDRESS,
      SDKErrorCode.INVALID_AMOUNT,
      SDKErrorCode.INVALID_DATA,
      SDKErrorCode.VALIDATION_ERROR,
      SDKErrorCode.INSUFFICIENT_BALANCE,
      SDKErrorCode.INSUFFICIENT_ALLOWANCE,
      SDKErrorCode.TRANSACTION_REVERTED
    ];
    return !nonRetryable.includes(error.code);
  }

  // Retry network errors
  if (error instanceof Error) {
    const message = error.message.toLowerCase();
    return (
      message.includes("network") ||
      message.includes("timeout") ||
      message.includes("econnreset") ||
      message.includes("econnrefused") ||
      message.includes("socket") ||
      message.includes("rate limit") ||
      message.includes("429") ||
      message.includes("503") ||
      message.includes("502")
    );
  }

  return false;
}

/**
 * Calculate delay with optional jitter
 */
function calculateDelay(
  attempt: number,
  initialDelayMs: number,
  maxDelayMs: number,
  backoffMultiplier: number,
  jitter: boolean
): number {
  // Exponential backoff
  const baseDelay = initialDelayMs * Math.pow(backoffMultiplier, attempt - 1);
  const cappedDelay = Math.min(baseDelay, maxDelayMs);

  // Add jitter (0-50% of delay)
  if (jitter) {
    const jitterAmount = cappedDelay * 0.5 * Math.random();
    return Math.floor(cappedDelay + jitterAmount);
  }

  return Math.floor(cappedDelay);
}

/**
 * Sleep for specified milliseconds
 */
function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Execute a function with retry logic
 * @param fn Function to execute
 * @param options Retry options
 * @returns Function result
 * @throws Last error if all retries fail
 */
export async function withRetry<T>(
  fn: () => Promise<T>,
  options: RetryOptions = {}
): Promise<T> {
  const {
    maxAttempts = DEFAULT_RETRY_OPTIONS.maxAttempts,
    initialDelayMs = DEFAULT_RETRY_OPTIONS.initialDelayMs,
    maxDelayMs = DEFAULT_RETRY_OPTIONS.maxDelayMs,
    backoffMultiplier = DEFAULT_RETRY_OPTIONS.backoffMultiplier,
    jitter = DEFAULT_RETRY_OPTIONS.jitter,
    isRetryable = defaultIsRetryable,
    onRetry
  } = options;

  let lastError: unknown;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;

      // Check if we should retry
      if (attempt >= maxAttempts || !isRetryable(error)) {
        break;
      }

      // Calculate delay
      const delayMs = calculateDelay(
        attempt,
        initialDelayMs,
        maxDelayMs,
        backoffMultiplier,
        jitter
      );

      // Notify callback
      if (onRetry) {
        onRetry(attempt, error, delayMs);
      }

      // Wait before retry
      await sleep(delayMs);
    }
  }

  // All retries failed
  if (lastError instanceof SDKError) {
    throw lastError;
  }

  throw new NetworkError(
    `Operation failed after ${maxAttempts} attempts: ${lastError instanceof Error ? lastError.message : String(lastError)}`,
    lastError instanceof Error ? lastError : undefined
  );
}

/**
 * Execute a function with timeout
 * @param fn Function to execute
 * @param timeoutMs Timeout in milliseconds
 * @param operation Operation name for error message
 * @returns Function result
 * @throws TimeoutError if timeout exceeded
 */
export async function withTimeout<T>(
  fn: () => Promise<T>,
  timeoutMs: number,
  operation = "Operation"
): Promise<T> {
  return Promise.race([
    fn(),
    new Promise<never>((_, reject) =>
      setTimeout(() => reject(new TimeoutError(operation, timeoutMs)), timeoutMs)
    )
  ]);
}

/**
 * Execute a function with both retry and timeout
 * @param fn Function to execute
 * @param options Options including timeout
 * @returns Function result
 */
export async function withRetryAndTimeout<T>(
  fn: () => Promise<T>,
  options: RetryOptions & { timeoutMs?: number; operation?: string } = {}
): Promise<T> {
  const { timeoutMs = 30000, operation = "Operation", ...retryOptions } = options;

  return withRetry(
    () => withTimeout(fn, timeoutMs, operation),
    retryOptions
  );
}

/**
 * Create a retryable version of a function
 * @param fn Function to wrap
 * @param options Default retry options
 * @returns Wrapped function with retry logic
 */
export function createRetryable<TArgs extends unknown[], TResult>(
  fn: (...args: TArgs) => Promise<TResult>,
  options: RetryOptions = {}
): (...args: TArgs) => Promise<TResult> {
  return (...args: TArgs) => withRetry(() => fn(...args), options);
}

/**
 * Poll for a condition with retry
 * @param fn Function that returns true when condition is met
 * @param options Polling options
 * @returns True when condition is met
 * @throws TimeoutError if timeout exceeded
 */
export async function pollUntil(
  fn: () => Promise<boolean>,
  options: {
    intervalMs?: number;
    timeoutMs?: number;
    operation?: string;
  } = {}
): Promise<void> {
  const {
    intervalMs = 2000,
    timeoutMs = 120000,
    operation = "Condition"
  } = options;

  const startTime = Date.now();

  while (Date.now() - startTime < timeoutMs) {
    const result = await fn();
    if (result) {
      return;
    }
    await sleep(intervalMs);
  }

  throw new TimeoutError(`${operation} not met`, timeoutMs);
}
