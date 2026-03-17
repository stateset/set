import { describe, expect, it } from "vitest";
import { keccak256, solidityPacked } from "ethers";
import {
  batchIdFromUuid,
  computeEventLeaf,
  computeTenantStoreKey,
  generateBatchId,
  verifyMerkleProof,
} from "../src/contracts/registry";

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
});
