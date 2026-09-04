import { describe, expect, it, vi } from "vitest";
import {
  batchCanExecuteTimelock,
  batchCanProposeToTimelock,
  batchGetTimelockOperationStatus,
  batchGetTimelockRoles,
  batchGetTimelockTimeRemaining,
  canExecuteTimelock,
  canProposeToTimelock,
  categorizeTimelockOperations,
  computeTimelockBatchOperationId,
  computeTimelockOperationId,
  fetchOperationStatus,
  findReadyTimelockOperations,
  getOperationActionability,
  getOperationTimeRemaining,
  getTimelockExecutionTimeline,
  getTimelockExtendedConfig,
  getTimelockHealthSummary,
  getTimelockRecommendedDelay,
  verifyTimelockRoles
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

  it("rejects non-integer numeric environment codes", async () => {
    const timelock = {
      getExtendedConfig: vi.fn().mockResolvedValue([0n, 0n, 0n, 0n, 0n, 1.5])
    };

    await expect(getTimelockExtendedConfig(timelock as any)).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("currentEnvironment must be an integer")
    });
  });

  it("maps individual and batch contract responses without losing bigint precision", async () => {
    const status = [true, false, false, 123n];
    const actionability = [true, true, 0n, false];
    const roles = [[true, false], [false, true], [false, false], [true, true]];
    const batchStatus = [[true, false], [false, true], [false, false], [123n, 456n]];
    const timelock = {
      getOperationStatus: vi.fn().mockResolvedValue(status),
      getTimeRemaining: vi.fn().mockResolvedValue(42n),
      canPropose: vi.fn().mockResolvedValue(true),
      canExecute: vi.fn().mockResolvedValue(false),
      getOperationActionability: vi.fn().mockResolvedValue(actionability),
      verifyRolesForOperation: vi.fn().mockResolvedValue([true, false, 3600n]),
      getExecutionTimeline: vi.fn().mockResolvedValue([1000n, 100n, 900n]),
      batchGetRoles: vi.fn().mockResolvedValue(roles),
      batchGetOperationStatus: vi.fn().mockResolvedValue(batchStatus),
      batchGetTimeRemaining: vi.fn().mockResolvedValue([42n, 0n]),
      batchCanPropose: vi.fn().mockResolvedValue([true, false]),
      batchCanExecute: vi.fn().mockResolvedValue([false, true]),
      getRecommendedDelay: vi.fn().mockResolvedValue(86400n),
      computeOperationId: vi.fn().mockResolvedValue("0xsingle"),
      computeBatchOperationId: vi.fn().mockResolvedValue("0xbatch")
    };
    const contract = timelock as any;
    const ids = ["0x01", "0x02"];
    const accounts = ["0xa", "0xb"];

    await expect(fetchOperationStatus(contract, ids[0])).resolves.toEqual({
      isPending: true,
      isReady: false,
      isDone: false,
      timestamp: 123n
    });
    await expect(getOperationTimeRemaining(contract, ids[0])).resolves.toBe(42n);
    await expect(canProposeToTimelock(contract, accounts[0])).resolves.toBe(true);
    await expect(canExecuteTimelock(contract, accounts[0])).resolves.toBe(false);
    await expect(getOperationActionability(contract, ids[0])).resolves.toEqual({
      exists: true,
      actionable: true,
      secondsToActionable: 0n,
      executed: false
    });
    await expect(verifyTimelockRoles(contract, accounts[0], accounts[1])).resolves.toEqual({
      canSchedule: true,
      canRun: false,
      delay: 3600n
    });
    await expect(getTimelockExecutionTimeline(contract)).resolves.toEqual({
      executeableAt: 1000n,
      currentTime: 100n,
      delaySeconds: 900n
    });
    await expect(batchGetTimelockRoles(contract, accounts)).resolves.toEqual({
      isProposer: roles[0],
      isExecutor: roles[1],
      isCanceller: roles[2],
      isAdmin: roles[3]
    });
    await expect(batchGetTimelockOperationStatus(contract, ids)).resolves.toEqual({
      isPending: batchStatus[0],
      isReady: batchStatus[1],
      isDone: batchStatus[2],
      timestamps: batchStatus[3]
    });
    await expect(batchGetTimelockTimeRemaining(contract, ids)).resolves.toEqual([42n, 0n]);
    await expect(batchCanProposeToTimelock(contract, accounts)).resolves.toEqual([true, false]);
    await expect(batchCanExecuteTimelock(contract, accounts)).resolves.toEqual([false, true]);
    await expect(getTimelockRecommendedDelay(contract, 2)).resolves.toBe(86400n);
    await expect(
      computeTimelockOperationId(contract, "0xtarget", 1n, "0xdata", "0xpred", "0xsalt")
    ).resolves.toBe("0xsingle");
    await expect(
      computeTimelockBatchOperationId(
        contract,
        ["0xtarget"],
        [1n],
        ["0xdata"],
        "0xpred",
        "0xsalt"
      )
    ).resolves.toBe("0xbatch");

    expect(timelock.computeOperationId).toHaveBeenCalledWith(
      "0xtarget",
      1n,
      "0xdata",
      "0xpred",
      "0xsalt"
    );
  });

  it("categorizes pending, ready, executed, and unknown operations", async () => {
    const timelock = {
      batchGetOperationStatus: vi.fn().mockResolvedValue([
        [true, false, false, false],
        [false, true, false, false],
        [false, false, true, false],
        [10n, 20n, 30n, 0n]
      ]),
      batchGetTimeRemaining: vi.fn().mockResolvedValue([50n, 0n, 0n, 0n])
    };
    const ids = ["pending", "ready", "done", "unknown"];

    await expect(categorizeTimelockOperations(timelock as any, ids)).resolves.toEqual({
      pending: [{ id: "pending", secondsRemaining: 50n }],
      ready: ["ready"],
      executed: ["done"]
    });
    await expect(findReadyTimelockOperations(timelock as any, ids)).resolves.toEqual(["ready"]);
  });

  it("reports unknown and unhealthy environments", async () => {
    const timelock = {
      getExtendedConfig: vi.fn().mockResolvedValue([0n, 3600n, 172800n, 3600n, 60n, 99n])
    };

    await expect(getTimelockHealthSummary(timelock as any)).resolves.toMatchObject({
      currentEnvironment: "99",
      environmentName: "unknown",
      isHealthy: false
    });
  });
});
