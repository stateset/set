import { Contract } from "ethers";
import type { BatchCommitment, RegistryStats } from "../types.js";

/**
 * Extended registry status
 */
export interface ExtendedRegistryStatus {
  totalBatches: bigint;
  totalProofs: bigint;
  sequencerCount: bigint;
  isPaused: boolean;
  isStrictMode: boolean;
  proofCoverage: bigint;
}

/**
 * Tenant/store summary
 */
export interface TenantStoreSummary {
  latestBatchId: string;
  currentStateRoot: string;
  currentHeadSequence: bigint;
  hasLatestProof: boolean;
}

/**
 * Compute a tenant/store key for SetRegistry lookups
 * @param tenantId Tenant identifier (bytes32)
 * @param storeId Store identifier (bytes32)
 * @returns The keccak256 hash of the packed tenant and store IDs
 */
export function computeTenantStoreKey(tenantId: string, storeId: string): string {
  const { keccak256, solidityPacked } = require("ethers");
  return keccak256(solidityPacked(["bytes32", "bytes32"], [tenantId, storeId]));
}

/**
 * Generate a unique batch ID
 * @param tenantId Tenant identifier
 * @param storeId Store identifier
 * @param sequenceStart Start sequence number
 * @param sequenceEnd End sequence number
 * @param timestamp Timestamp in seconds
 * @returns A unique batch ID
 */
export function generateBatchId(
  tenantId: string,
  storeId: string,
  sequenceStart: bigint,
  sequenceEnd: bigint,
  timestamp: bigint
): string {
  const { keccak256, solidityPacked } = require("ethers");
  return keccak256(
    solidityPacked(
      ["bytes32", "bytes32", "uint64", "uint64", "uint64"],
      [tenantId, storeId, sequenceStart, sequenceEnd, timestamp]
    )
  );
}

/**
 * Compute event leaf hash for Merkle verification
 * @param eventType Type of commerce event
 * @param payload Event payload data (hex string)
 * @param metadata Event metadata (hex string)
 * @returns Leaf hash for Merkle tree
 */
export function computeEventLeaf(
  eventType: string,
  payload: string,
  metadata: string
): string {
  const { keccak256, solidityPacked } = require("ethers");
  return keccak256(solidityPacked(["string", "bytes", "bytes"], [eventType, payload, metadata]));
}

/**
 * Verify a Merkle proof against an events root
 * @param leaf The leaf hash to verify
 * @param proof Array of sibling hashes
 * @param index Index of the leaf in the tree
 * @param expectedRoot Expected root hash
 * @returns True if proof is valid
 */
export function verifyMerkleProof(
  leaf: string,
  proof: string[],
  index: number,
  expectedRoot: string
): boolean {
  const { keccak256, solidityPacked } = require("ethers");
  let computedHash = leaf;

  for (let i = 0; i < proof.length; i++) {
    const proofElement = proof[i];
    if (index % 2 === 0) {
      computedHash = keccak256(solidityPacked(["bytes32", "bytes32"], [computedHash, proofElement]));
    } else {
      computedHash = keccak256(solidityPacked(["bytes32", "bytes32"], [proofElement, computedHash]));
    }
    index = Math.floor(index / 2);
  }

  return computedHash.toLowerCase() === expectedRoot.toLowerCase();
}

/**
 * Fetch batch commitment with parsed data
 * @param registry SetRegistry contract instance
 * @param batchId Batch identifier
 * @returns Parsed batch commitment or null if not found
 */
export async function fetchBatchCommitment(
  registry: Contract,
  batchId: string
): Promise<BatchCommitment | null> {
  const commitment = await registry.getBatchCommitment(batchId);
  if (commitment.timestamp === 0n) {
    return null;
  }
  return {
    eventsRoot: commitment.eventsRoot,
    prevStateRoot: commitment.prevStateRoot,
    newStateRoot: commitment.newStateRoot,
    sequenceStart: commitment.sequenceStart,
    sequenceEnd: commitment.sequenceEnd,
    eventCount: Number(commitment.eventCount),
    timestamp: commitment.timestamp,
    submitter: commitment.submitter
  };
}

/**
 * Fetch registry statistics
 * @param registry SetRegistry contract instance
 * @returns Registry statistics
 */
export async function fetchRegistryStats(registry: Contract): Promise<RegistryStats> {
  const [commitmentCount, proofCount, isPaused, isStrictMode] = await registry.getRegistryStats();
  return {
    commitmentCount,
    proofCount,
    isPaused,
    isStrictMode
  };
}

/**
 * Check if the registry is operational (not paused)
 * @param registry SetRegistry contract instance
 * @returns True if registry is accepting new commitments
 */
export async function isRegistryOperational(registry: Contract): Promise<boolean> {
  return !(await registry.paused());
}

/**
 * Fetch extended registry status with proof coverage
 * @param registry SetRegistry contract instance
 * @returns Extended registry status
 */
export async function fetchExtendedRegistryStatus(
  registry: Contract
): Promise<ExtendedRegistryStatus> {
  const [totalBatches, totalProofs, sequencerCount, isPaused, isStrictMode, proofCoverage] =
    await registry.getExtendedRegistryStatus();
  return {
    totalBatches,
    totalProofs,
    sequencerCount,
    isPaused,
    isStrictMode,
    proofCoverage
  };
}

/**
 * Fetch tenant/store summary
 * @param registry SetRegistry contract instance
 * @param tenantId Tenant identifier
 * @param storeId Store identifier
 * @returns Summary for the tenant/store
 */
export async function fetchTenantStoreSummary(
  registry: Contract,
  tenantId: string,
  storeId: string
): Promise<TenantStoreSummary> {
  const [latestBatchId, currentStateRoot, currentHeadSequence, hasLatestProof] =
    await registry.getTenantStoreSummary(tenantId, storeId);
  return {
    latestBatchId,
    currentStateRoot,
    currentHeadSequence,
    hasLatestProof
  };
}

/**
 * Fetch multiple batch commitments
 * @param registry SetRegistry contract instance
 * @param batchIds Array of batch identifiers
 * @returns Array of batch commitments
 */
export async function fetchBatchCommitments(
  registry: Contract,
  batchIds: string[]
): Promise<BatchCommitment[]> {
  const commitments = await registry.getBatchCommitments(batchIds);
  return commitments.map((c: any) => ({
    eventsRoot: c.eventsRoot,
    prevStateRoot: c.prevStateRoot,
    newStateRoot: c.newStateRoot,
    sequenceStart: c.sequenceStart,
    sequenceEnd: c.sequenceEnd,
    eventCount: Number(c.eventCount),
    timestamp: c.timestamp,
    submitter: c.submitter
  }));
}

/**
 * Fetch proof statuses for multiple batches
 * @param registry SetRegistry contract instance
 * @param batchIds Array of batch identifiers
 * @returns Arrays of proof existence and compliance flags
 */
export async function fetchBatchProofStatuses(
  registry: Contract,
  batchIds: string[]
): Promise<{ hasProofs: boolean[]; allCompliant: boolean[] }> {
  const [hasProofs, allCompliant] = await registry.getBatchProofStatuses(batchIds);
  return { hasProofs, allCompliant };
}

/**
 * Fetch latest state roots for multiple tenant/store pairs
 * @param registry SetRegistry contract instance
 * @param tenantIds Array of tenant identifiers
 * @param storeIds Array of store identifiers
 * @returns Array of state roots
 */
export async function fetchBatchLatestStateRoots(
  registry: Contract,
  tenantIds: string[],
  storeIds: string[]
): Promise<string[]> {
  return await registry.getBatchLatestStateRoots(tenantIds, storeIds);
}

/**
 * Check if multiple addresses are authorized sequencers
 * @param registry SetRegistry contract instance
 * @param addresses Array of addresses to check
 * @returns Array of authorization flags
 */
export async function checkSequencerAuthorization(
  registry: Contract,
  addresses: string[]
): Promise<boolean[]> {
  return await registry.areSequencersAuthorized(addresses);
}

/**
 * Get the count of authorized sequencers
 * @param registry SetRegistry contract instance
 * @returns Number of authorized sequencers
 */
export async function getAuthorizedSequencerCount(registry: Contract): Promise<bigint> {
  return await registry.authorizedSequencerCount();
}

/**
 * Calculate proof coverage percentage
 * @param registry SetRegistry contract instance
 * @returns Proof coverage as a percentage (0-100)
 */
export async function getProofCoveragePercent(registry: Contract): Promise<number> {
  const status = await fetchExtendedRegistryStatus(registry);
  return Number(status.proofCoverage) / 100;
}

/**
 * Check if a batch exists
 * @param registry SetRegistry contract instance
 * @param batchId Batch identifier
 * @returns True if batch exists
 */
export async function checkBatchExists(registry: Contract, batchId: string): Promise<boolean> {
  return await registry.batchExists(batchId);
}

/**
 * Fetch head sequences for multiple tenant/store pairs
 * @param registry SetRegistry contract instance
 * @param tenantIds Array of tenant identifiers
 * @param storeIds Array of store identifiers
 * @returns Array of head sequences
 */
export async function fetchBatchHeadSequences(
  registry: Contract,
  tenantIds: string[],
  storeIds: string[]
): Promise<bigint[]> {
  return await registry.getBatchHeadSequences(tenantIds, storeIds);
}

/**
 * Check if registry is paused
 * @param registry SetRegistry contract instance
 * @returns True if paused
 */
export async function isRegistryPaused(registry: Contract): Promise<boolean> {
  return await registry.paused();
}

/**
 * Check if a batch has a STARK proof
 * @param registry SetRegistry contract instance
 * @param batchId Batch identifier
 * @returns True if batch has proof
 */
export async function checkBatchHasProof(registry: Contract, batchId: string): Promise<boolean> {
  return await registry.hasStarkProof(batchId);
}
