import { describe, expect, it, vi } from "vitest";
import { keccak256, solidityPacked } from "ethers";
import {
  batchIdFromUuid,
  checkSequencerAuthorization,
  computeEventLeaf,
  computeTenantStoreKey,
  fetchBatchCommitment,
  fetchBatchCommitments,
  fetchBatchHeadSequences,
  fetchBatchLatestStateRoots,
  fetchBatchProofStatuses,
  generateBatchId,
  getProofCoveragePercent,
  verifyMerkleProof,
} from "../src/contracts/registry";
import { SDKErrorCode } from "../src/errors";

describe("registry helpers", () => {
  it("computes tenant/store keys with ESM-safe helpers", () => {
    const tenantId = `0x${"11".repeat(32)}`;
    const storeId = `0x${"22".repeat(32)}`;

    expect(computeTenantStoreKey(tenantId, storeId)).toBe(
      keccak256(solidityPacked(["bytes32", "bytes32"], [tenantId, storeId]))
    );
  });

  it("generates deterministic batch ids", () => {
    const tenantId = `0x${"11".repeat(32)}`;
    const storeId = `0x${"22".repeat(32)}`;
    const sequenceStart = 1n;
    const sequenceEnd = 10n;
    const timestamp = 1234n;

    expect(generateBatchId(tenantId, storeId, sequenceStart, sequenceEnd, timestamp)).toBe(
      keccak256(
        solidityPacked(
          ["bytes32", "bytes32", "uint64", "uint64", "uint64"],
          [tenantId, storeId, sequenceStart, sequenceEnd, timestamp]
        )
      )
    );
  });

  it("encodes sequencer UUID batch ids into the on-chain bytes32 format", () => {
    expect(batchIdFromUuid("123e4567-e89b-12d3-a456-426614174000")).toBe(
      "0x123e4567e89b12d3a45642661417400000000000000000000000000000000000"
    );
  });

  it("rejects invalid sequencer batch UUIDs", () => {
    expect(() => batchIdFromUuid("not-a-uuid")).toThrow("Invalid batch UUID");
  });

  it("computes event leaf hashes", () => {
    const eventType = "order.created";
    const payload = "0x1234";
    const metadata = "0xabcd";

    expect(computeEventLeaf(eventType, payload, metadata)).toBe(
      keccak256(solidityPacked(["string", "bytes", "bytes"], [eventType, payload, metadata]))
    );
  });

  it("verifies merkle proofs", () => {
    const leaf0 = keccak256("0x01");
    const leaf1 = keccak256("0x02");
    const root = keccak256(solidityPacked(["bytes32", "bytes32"], [leaf0, leaf1]));

    expect(verifyMerkleProof(leaf0, [leaf1], 0, root)).toBe(true);
    expect(verifyMerkleProof(leaf1, [leaf0], 1, root)).toBe(true);
    expect(verifyMerkleProof(leaf0, [leaf1], 0, leaf0)).toBe(false);
  });

  it("normalizes bigint event counts and proof coverage percentages", async () => {
    const registry = {
      getBatchCommitment: vi.fn().mockResolvedValue({
        eventsRoot: `0x${"11".repeat(32)}`,
        prevStateRoot: `0x${"22".repeat(32)}`,
        newStateRoot: `0x${"33".repeat(32)}`,
        sequenceStart: 1n,
        sequenceEnd: 2n,
        eventCount: 3n,
        timestamp: 123n,
        submitter: "0x1000000000000000000000000000000000000001",
      }),
      getBatchCommitments: vi.fn().mockResolvedValue([{
        eventsRoot: `0x${"44".repeat(32)}`,
        prevStateRoot: `0x${"55".repeat(32)}`,
        newStateRoot: `0x${"66".repeat(32)}`,
        sequenceStart: 10n,
        sequenceEnd: 20n,
        eventCount: 7n,
        timestamp: 456n,
        submitter: "0x2000000000000000000000000000000000000002",
      }]),
      getExtendedRegistryStatus: vi.fn().mockResolvedValue([100n, 80n, 2n, false, false, 8750n]),
    };

    await expect(fetchBatchCommitment(registry as any, "batch-1")).resolves.toMatchObject({
      eventCount: 3,
    });
    await expect(fetchBatchCommitments(registry as any, ["batch-1"])).resolves.toMatchObject([
      { eventCount: 7 },
    ]);
    await expect(getProofCoveragePercent(registry as any)).resolves.toBe(87.5);
  });

  it("maps aligned batch registry helper responses", async () => {
    const registry = {
      getBatchCommitments: vi.fn().mockResolvedValue([
        {
          eventsRoot: `0x${"44".repeat(32)}`,
          prevStateRoot: `0x${"55".repeat(32)}`,
          newStateRoot: `0x${"66".repeat(32)}`,
          sequenceStart: 10n,
          sequenceEnd: 20n,
          eventCount: 7n,
          timestamp: 456n,
          submitter: "0x2000000000000000000000000000000000000002",
        },
        {
          eventsRoot: `0x${"77".repeat(32)}`,
          prevStateRoot: `0x${"88".repeat(32)}`,
          newStateRoot: `0x${"99".repeat(32)}`,
          sequenceStart: 21n,
          sequenceEnd: 30n,
          eventCount: 5n,
          timestamp: 789n,
          submitter: "0x3000000000000000000000000000000000000003",
        }
      ]),
      getBatchProofStatuses: vi.fn().mockResolvedValue([[true, false], [true, false]]),
      getBatchLatestStateRoots: vi.fn().mockResolvedValue([
        `0x${"aa".repeat(32)}`,
        `0x${"bb".repeat(32)}`
      ]),
      areSequencersAuthorized: vi.fn().mockResolvedValue([true, false]),
      getBatchHeadSequences: vi.fn().mockResolvedValue([100n, 200n]),
    };

    await expect(fetchBatchCommitments(registry as any, ["batch-1", "batch-2"])).resolves.toMatchObject([
      { eventCount: 7 },
      { eventCount: 5 }
    ]);
    await expect(fetchBatchProofStatuses(registry as any, ["batch-1", "batch-2"])).resolves.toEqual({
      hasProofs: [true, false],
      allCompliant: [true, false]
    });
    await expect(
      fetchBatchLatestStateRoots(registry as any, ["tenant-1", "tenant-2"], ["store-1", "store-2"])
    ).resolves.toEqual([
      `0x${"aa".repeat(32)}`,
      `0x${"bb".repeat(32)}`
    ]);
    await expect(
      checkSequencerAuthorization(registry as any, [
        "0x1000000000000000000000000000000000000001",
        "0x2000000000000000000000000000000000000002"
      ])
    ).resolves.toEqual([true, false]);
    await expect(
      fetchBatchHeadSequences(registry as any, ["tenant-1", "tenant-2"], ["store-1", "store-2"])
    ).resolves.toEqual([100n, 200n]);
  });

  it("rejects malformed batch registry helper responses", async () => {
    const registry = {
      getBatchCommitments: vi.fn().mockResolvedValue([]),
      getBatchProofStatuses: vi.fn().mockResolvedValue([[true], [true, false]]),
      getBatchLatestStateRoots: vi.fn().mockResolvedValue([`0x${"aa".repeat(32)}`]),
      areSequencersAuthorized: vi.fn().mockResolvedValue([true]),
      getBatchHeadSequences: vi.fn().mockResolvedValue([100n]),
    };

    await expect(fetchBatchCommitments(registry as any, ["batch-1"])).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("getBatchCommitments returned commitments length 0, expected 1"),
    });
    await expect(fetchBatchProofStatuses(registry as any, ["batch-1", "batch-2"])).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("getBatchProofStatuses returned hasProofs length 1, expected 2"),
    });
    await expect(
      fetchBatchLatestStateRoots(registry as any, ["tenant-1", "tenant-2"], ["store-1", "store-2"])
    ).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("getBatchLatestStateRoots returned stateRoots length 1, expected 2"),
    });
    await expect(
      checkSequencerAuthorization(registry as any, [
        "0x1000000000000000000000000000000000000001",
        "0x2000000000000000000000000000000000000002"
      ])
    ).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("areSequencersAuthorized returned authorizations length 1, expected 2"),
    });
    await expect(
      fetchBatchHeadSequences(registry as any, ["tenant-1", "tenant-2"], ["store-1", "store-2"])
    ).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("getBatchHeadSequences returned headSequences length 1, expected 2"),
    });
  });

  it("rejects mismatched tenant and store input lengths for batch reads", async () => {
    const registry = {} as any;

    await expect(
      fetchBatchLatestStateRoots(registry, ["tenant-1", "tenant-2"], ["store-1"])
    ).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("getBatchLatestStateRoots input returned storeIds length 1, expected 2"),
    });

    await expect(
      fetchBatchHeadSequences(registry, ["tenant-1", "tenant-2"], ["store-1"])
    ).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("getBatchHeadSequences input returned storeIds length 1, expected 2"),
    });
  });

  it("rejects out-of-range bigint event counts", async () => {
    const registry = {
      getBatchCommitment: vi.fn().mockResolvedValue({
        eventsRoot: `0x${"11".repeat(32)}`,
        prevStateRoot: `0x${"22".repeat(32)}`,
        newStateRoot: `0x${"33".repeat(32)}`,
        sequenceStart: 1n,
        sequenceEnd: 2n,
        eventCount: BigInt(Number.MAX_SAFE_INTEGER) + 1n,
        timestamp: 123n,
        submitter: "0x1000000000000000000000000000000000000001",
      }),
    };

    await expect(fetchBatchCommitment(registry as any, "batch-1")).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("eventCount exceeds safe integer range"),
    });
  });
});
