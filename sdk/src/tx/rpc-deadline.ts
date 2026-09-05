import type { FinalityRpc } from "./finality.js";

export interface VerificationOptions {
  /** Whole-operation deadline, not per request. Defaults to 30 seconds; maximum 5 minutes. */
  timeoutMs?: number;
  signal?: AbortSignal;
}

export class VerificationInterruptedError extends Error {
  constructor(public readonly reason: "timeout" | "aborted") {
    super(reason === "timeout" ? "Verification deadline exceeded" : "Verification aborted");
    this.name = "VerificationInterruptedError";
  }
}

/** Internal operation scope. Does not claim to cancel a transport's in-flight I/O. */
export async function withRpcDeadline<T>(
  sources: readonly FinalityRpc[], options: VerificationOptions,
  operation: (sources: readonly FinalityRpc[]) => Promise<T>
): Promise<T> {
  const timeoutMs = options.timeoutMs ?? 30000;
  const signal = options.signal;
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 300000) {
    throw new Error("Verification timeout must be an integer from 1 to 300000 ms");
  }
  if (signal?.aborted) throw new VerificationInterruptedError("aborted");
  let active = true;
  let stop!: (error: Error) => void;
  const stopped = new Promise<never>((_, reject) => {
    stop = error => { active = false; reject(error); };
  });
  const abort = () => stop(new VerificationInterruptedError("aborted"));
  const timer = setTimeout(() => stop(new VerificationInterruptedError("timeout")), timeoutMs);
  signal?.addEventListener("abort", abort, { once: true });
  // Preserve source identity so wrapping never hides duplicate-source errors.
  const wrappers = new Map<FinalityRpc, FinalityRpc>();
  const wrapped = sources.map(source => {
    let wrapper = wrappers.get(source);
    if (!wrapper) {
      wrapper = { async send(method, params) {
        if (!active) throw new Error("Verification scope closed");
        return Promise.race([stopped, source.send(method, params)]);
      } };
      wrappers.set(source, wrapper);
    }
    return wrapper;
  });
  try {
    return await Promise.race([stopped, Promise.resolve().then(() => operation(wrapped))]);
  } finally {
    active = false;
    clearTimeout(timer);
    signal?.removeEventListener("abort", abort);
    // Release other source branches after an error, without starting new RPC calls.
    stop(new Error("Verification scope closed"));
  }
}
