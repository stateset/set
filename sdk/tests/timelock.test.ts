import { describe, expect, it, vi } from "vitest";
import {
  getTimelockExtendedConfig,
  getTimelockHealthSummary
} from "../src/contracts/timelock";
import { SDKErrorCode } from "../src/errors";

describe("timelock helpers", () => {
  it("normalizes bigint environment codes", async () => {
    const timelock = {
      getExtendedConfig: vi.fn().mockResolvedValue([60n, 3600n, 172800n, 3600n, 60n, 2n])
    };

    await expect(getTimelockExtendedConfig(timelock as any)).resolves.toEqual({
      minDelay: 60n,
      maxDelay: 3600n,
      mainnetDelay: 172800n,
      testnetDelay: 3600n,
      devnetDelay: 60n,
      currentEnvironment: 2
    });

    await expect(getTimelockHealthSummary(timelock as any)).resolves.toMatchObject({
      currentEnvironment: "2",
      environmentName: "mainnet",
      isHealthy: true
    });
  });

  it("rejects out-of-range environment codes", async () => {
    const timelock = {
      getExtendedConfig: vi.fn().mockResolvedValue([
        60n,
        3600n,
        172800n,
        3600n,
        60n,
        BigInt(Number.MAX_SAFE_INTEGER) + 1n
      ])
    };

    await expect(getTimelockExtendedConfig(timelock as any)).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("currentEnvironment exceeds safe integer range")
    });
  });
});
