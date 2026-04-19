import { afterEach, describe, expect, it, vi } from "vitest";
import { TimeoutError } from "../src/errors";
import { pollUntil, withTimeout } from "../src/utils/retry";

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
});
