import { afterEach, describe, expect, it, vi } from "vitest";
import { SDKError, SDKErrorCode, TimeoutError } from "../src/errors";
import {
  createRetryable,
  pollUntil,
  withRetry,
  withRetryAndTimeout,
  withTimeout
} from "../src/utils/retry";

afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe("retry utilities", () => {
  it("clears timeout timers after a successful withTimeout call", async () => {
    vi.useFakeTimers();

    const resultPromise = withTimeout(async () => {
      await Promise.resolve();
      return "ok";
    }, 1_000, "success case");

    await expect(resultPromise).resolves.toBe("ok");
    expect(vi.getTimerCount()).toBe(0);
  });

  it("clears timeout timers after the wrapped function rejects", async () => {
    vi.useFakeTimers();

    const resultPromise = withTimeout(async () => {
      throw new Error("boom");
    }, 1_000, "failure case");

    await expect(resultPromise).rejects.toThrow("boom");
    expect(vi.getTimerCount()).toBe(0);
  });

  it("does not oversleep past the remaining poll timeout window", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-01-01T00:00:00.000Z"));

    const attempts: number[] = [];
    const pollPromise = pollUntil(async () => {
      attempts.push(Date.now());
      return false;
    }, {
      intervalMs: 1_000,
      timeoutMs: 2_500,
      operation: "polling check"
    });
    const settledPollPromise = pollPromise.catch(error => error);

    await vi.advanceTimersByTimeAsync(2_499);
    expect(attempts).toHaveLength(3);
    expect(vi.getTimerCount()).toBe(1);

    await vi.advanceTimersByTimeAsync(1);
    await expect(settledPollPromise).resolves.toBeInstanceOf(TimeoutError);
    expect(vi.getTimerCount()).toBe(0);
  });

  it("retries transient failures with bounded backoff", async () => {
    vi.useFakeTimers();
    const operation = vi.fn()
      .mockRejectedValueOnce(new Error("network unavailable"))
      .mockRejectedValueOnce(new Error("503"))
      .mockResolvedValue("ok");
    const onRetry = vi.fn();
    const result = withRetry(operation, {
      maxAttempts: 3,
      initialDelayMs: 10,
      maxDelayMs: 15,
      backoffMultiplier: 2,
      jitter: false,
      onRetry
    });
    await vi.runAllTimersAsync();
    await expect(result).resolves.toBe("ok");
    expect(operation).toHaveBeenCalledTimes(3);
    expect(onRetry.mock.calls.map(call => call[2])).toEqual([10, 15]);
  });

  it("does not retry validation errors and preserves SDK errors", async () => {
    const validationError = new SDKError(SDKErrorCode.INVALID_ADDRESS, "bad address");
    const operation = vi.fn().mockRejectedValue(validationError);
    await expect(withRetry(operation, { initialDelayMs: 0 })).rejects.toBe(validationError);
    expect(operation).toHaveBeenCalledTimes(1);
  });

  it("wraps exhausted unknown failures as network errors", async () => {
    await expect(withRetry(async () => { throw "failure"; }, {
      maxAttempts: 1,
      initialDelayMs: 0
    })).rejects.toMatchObject({ code: SDKErrorCode.NETWORK_ERROR });
  });

  it("composes retry, timeout, and reusable argument forwarding", async () => {
    await expect(withRetryAndTimeout(async () => 7, {
      timeoutMs: 100,
      maxAttempts: 1,
      operation: "composed"
    })).resolves.toBe(7);

    const wrapped = createRetryable(async (left: number, right: number) => left + right, {
      maxAttempts: 1
    });
    await expect(wrapped(2, 3)).resolves.toBe(5);
  });

  it("returns as soon as a polling condition is met", async () => {
    await expect(pollUntil(async () => true, { timeoutMs: 10 })).resolves.toBeUndefined();
  });
});
