import { describe, expect, it } from "vitest";
import {
  batchGetKeyperSummaries,
  getEpochHistory,
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
});
