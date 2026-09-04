import { describe, expect, it, vi } from "vitest";
import {
  batchCheckDKGRegistration,
  batchCheckEpochKeyValid,
  batchCheckKeyperActive,
  batchGetKeyperSummaries,
  batchGetKeyperStakes,
  fetchDKGStatus,
  fetchThresholdRegistryStatus,
  getAllKeypers,
  getEpochHistory,
  getKeyExpirationInfo,
  getNetworkHealth,
  getTopKeypersByStake,
  getTotalKeyperStake,
  isKeyperRegisteredForDKG,
  isThresholdEncryptionAvailable
} from "../src/contracts/threshold-key-registry";

describe("threshold key registry helpers", () => {
  it("maps aligned keyper summary arrays into summary objects", async () => {
    const registry = {
      batchGetKeyperSummary: async () => [
        [true, false],
        [100n, 50n],
        [0n, 2n],
        [true, false]
      ]
    } as any;

    await expect(
      batchGetKeyperSummaries(registry, ["0x1", "0x2"])
    ).resolves.toEqual([
      {
        active: true,
        stake: 100n,
        slashCount: 0n,
        registeredForDKG: true
      },
      {
        active: false,
        stake: 50n,
        slashCount: 2n,
        registeredForDKG: false
      }
    ]);
  });

  it("rejects malformed keyper summary responses", async () => {
    const registry = {
      batchGetKeyperSummary: async () => [
        [true, false],
        [100n],
        [0n, 2n],
        [true, false]
      ]
    } as any;

    await expect(
      batchGetKeyperSummaries(registry, ["0x1", "0x2"])
    ).rejects.toThrow("batchGetKeyperSummary returned stakes length 1, expected 2");
  });

  it("rejects malformed epoch history responses", async () => {
    const registry = {
      getEpochHistory: async () => [
        [1n, 2n],
        [true, false],
        [false],
        [3n, 4n]
      ]
    } as any;

    await expect(getEpochHistory(registry, 1, 2)).rejects.toThrow(
      "getEpochHistory returned revoked length 1, expected 2"
    );
  });

  it("treats key-status read failures as encryption unavailable", async () => {
    const registry = {
      getCurrentKeyStatus: async () => {
        throw new Error("rpc unavailable");
      }
    } as any;

    await expect(isThresholdEncryptionAvailable(registry)).resolves.toBe(false);
  });

  it("maps status, DKG, health, and expiration tuples", async () => {
    const registry = {
      getRegistryStatus: vi.fn().mockResolvedValue([5n, 4n, 3n, 8n, 2, false]),
      getDKGStatus: vi.fn().mockResolvedValue([8n, 2, 100n, 5n, 4n, 20n]),
      getNetworkHealth: vi.fn().mockResolvedValue([5n, 4n, 1000n, 50n, true]),
      getKeyExpirationInfo: vi.fn().mockResolvedValue([20n, 240n, 80n])
    } as any;

    await expect(fetchThresholdRegistryStatus(registry)).resolves.toEqual({
      totalKeypers: 5n,
      activeCount: 4n,
      currentThreshold: 3n,
      epoch: 8n,
      dkgPhase: 2,
      isPaused: false
    });
    await expect(fetchDKGStatus(registry)).resolves.toEqual({
      epoch: 8n,
      phase: 2,
      deadline: 100n,
      participantCount: 5n,
      dealingsCount: 4n,
      blocksUntilDeadline: 20n
    });
    await expect(getNetworkHealth(registry)).resolves.toEqual({
      totalKeypers: 5n,
      activeCount: 4n,
      avgStake: 1000n,
      totalSlashed: 50n,
      networkSecure: true
    });
    await expect(getKeyExpirationInfo(registry)).resolves.toEqual({
      blocksRemaining: 20n,
      secondsRemaining: 240n,
      percentRemaining: 80n
    });
  });

  it("delegates stake, membership, and batch queries", async () => {
    const registry = {
      getCurrentKeyStatus: vi.fn().mockResolvedValue([true, "0xkey"]),
      getTotalStaked: vi.fn().mockResolvedValue(1500n),
      getTopKeypersByStake: vi.fn().mockResolvedValue([["a", "b"], [1000n, 500n]]),
      getAllKeypers: vi.fn().mockResolvedValue(["a", "b"]),
      batchIsKeyperActive: vi.fn().mockResolvedValue([true, false]),
      batchGetStakes: vi.fn().mockResolvedValue([1000n, 500n]),
      batchIsRegisteredForDKG: vi.fn().mockResolvedValue([true, true]),
      batchIsEpochKeyValid: vi.fn().mockResolvedValue([false, true]),
      isRegisteredForDKG: vi.fn().mockResolvedValue(true)
    } as any;
    const keypers = ["a", "b"];

    await expect(isThresholdEncryptionAvailable(registry)).resolves.toBe(true);
    await expect(getTotalKeyperStake(registry)).resolves.toBe(1500n);
    await expect(getTopKeypersByStake(registry, 2)).resolves.toEqual({
      keypers,
      stakes: [1000n, 500n]
    });
    await expect(getAllKeypers(registry)).resolves.toEqual(keypers);
    await expect(batchCheckKeyperActive(registry, keypers)).resolves.toEqual([true, false]);
    await expect(batchGetKeyperStakes(registry, keypers)).resolves.toEqual([1000n, 500n]);
    await expect(batchCheckDKGRegistration(registry, keypers)).resolves.toEqual([true, true]);
    await expect(batchCheckEpochKeyValid(registry, [7n, 8n])).resolves.toEqual([false, true]);
    await expect(isKeyperRegisteredForDKG(registry, "a")).resolves.toBe(true);
  });

  it("maps valid epoch history responses", async () => {
    const registry = {
      getEpochHistory: vi.fn().mockResolvedValue([
        [7n, 8n],
        [false, true],
        [true, false],
        [3n, 4n]
      ])
    } as any;

    await expect(getEpochHistory(registry, 7, 8)).resolves.toEqual([
      { epoch: 7n, valid: false, revoked: true, threshold: 3n },
      { epoch: 8n, valid: true, revoked: false, threshold: 4n }
    ]);
  });
});
