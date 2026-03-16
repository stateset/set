import { Contract } from "ethers";

/**
 * Sequencer attestation statistics
 */
export interface AttestationStats {
  totalCommitments: bigint;
  totalVerifications: bigint;
  failedVerifications: bigint;
  lastCommitmentTime: bigint;
}

/**
 * Ordering commitment info
 */
export interface OrderingCommitmentInfo {
  blockHash: string;
  txOrderingRoot: string;
  blockNumber: bigint;
  timestamp: bigint;
  txCount: number;
  sequencer: string;
}

/**
 * Fetch sequencer attestation statistics
 * @param attestation SequencerAttestation contract instance
 * @returns Statistics
 */
export async function fetchAttestationStats(
  attestation: Contract
): Promise<AttestationStats> {
  const stats = await attestation.getStats();
  return {
    totalCommitments: stats.totalCommitments,
    totalVerifications: stats.totalVerifications,
    failedVerifications: stats.failedVerifications,
    lastCommitmentTime: stats.lastCommitmentTime
  };
}

/**
 * Get ordering commitment by block hash
 * @param attestation SequencerAttestation contract instance
 * @param blockHash Block hash
 * @returns Ordering commitment
 */
export async function getOrderingCommitment(
  attestation: Contract,
  blockHash: string
): Promise<OrderingCommitmentInfo> {
  const [hash, txOrderingRoot, blockNumber, timestamp, txCount, sequencer] =
    await attestation.commitments(blockHash);
  return { blockHash: hash, txOrderingRoot, blockNumber, timestamp, txCount, sequencer };
}

/**
 * Get ordering commitment by block number
 * @param attestation SequencerAttestation contract instance
 * @param blockNumber Block number
 * @returns Ordering commitment
 */
export async function getCommitmentByBlockNumber(
  attestation: Contract,
  blockNumber: number
): Promise<OrderingCommitmentInfo> {
  const commitment = await attestation.getCommitmentByBlockNumber(blockNumber);
  return {
    blockHash: commitment.blockHash,
    txOrderingRoot: commitment.txOrderingRoot,
    blockNumber: commitment.blockNumber,
    timestamp: commitment.timestamp,
    txCount: commitment.txCount,
    sequencer: commitment.sequencer
  };
}

/**
 * Check if commitment exists for block
 * @param attestation SequencerAttestation contract instance
 * @param blockHash Block hash
 * @returns True if commitment exists
 */
export async function hasOrderingCommitment(
  attestation: Contract,
  blockHash: string
): Promise<boolean> {
  return await attestation.hasCommitment(blockHash);
}

/**
 * Check if sequencer is authorized
 * @param attestation SequencerAttestation contract instance
 * @param sequencer Sequencer address
 * @returns True if authorized
 */
export async function isSequencerAuthorized(
  attestation: Contract,
  sequencer: string
): Promise<boolean> {
  return await attestation.authorizedSequencers(sequencer);
}

/**
 * Verify transaction position in ordering
 * @param attestation SequencerAttestation contract instance
 * @param blockHash Block hash
 * @param txHash Transaction hash
 * @param position Expected position
 * @param proof Merkle proof
 * @returns True if valid
 */
export async function verifyTxPosition(
  attestation: Contract,
  blockHash: string,
  txHash: string,
  position: number,
  proof: string[]
): Promise<boolean> {
  return await attestation.verifyTxPositionView(blockHash, txHash, position, proof);
}

/**
 * Batch verify transaction positions
 * @param attestation SequencerAttestation contract instance
 * @param blockHash Block hash
 * @param txHashes Transaction hashes
 * @param positions Expected positions
 * @param proofs Flattened proofs
 * @param proofLength Length of each proof
 * @returns Array of verification results
 */
export async function batchVerifyTxPositions(
  attestation: Contract,
  blockHash: string,
  txHashes: string[],
  positions: number[],
  proofs: string[],
  proofLength: number
): Promise<boolean[]> {
  return await attestation.batchVerify(blockHash, txHashes, positions, proofs, proofLength);
}

/**
 * Get block hash for block number
 * @param attestation SequencerAttestation contract instance
 * @param blockNumber Block number
 * @returns Block hash
 */
export async function getBlockHashForNumber(
  attestation: Contract,
  blockNumber: number
): Promise<string> {
  return await attestation.blockNumberToHash(blockNumber);
}

/**
 * Get attestation verification success rate
 * @param attestation SequencerAttestation contract instance
 * @returns Success rate in basis points (10000 = 100%)
 */
export async function getAttestationSuccessRate(
  attestation: Contract
): Promise<bigint> {
  const stats = await fetchAttestationStats(attestation);
  if (stats.totalVerifications === BigInt(0)) {
    return BigInt(10000); // 100% if no verifications
  }
  const successful = stats.totalVerifications - stats.failedVerifications;
  return (successful * BigInt(10000)) / stats.totalVerifications;
}

/**
 * Get attestation health summary
 * @param attestation SequencerAttestation contract instance
 * @returns Health summary
 */
export async function getAttestationHealthSummary(
  attestation: Contract
): Promise<{
  totalCommitments: bigint;
  successRate: bigint;
  lastCommitmentTime: bigint;
  secondsSinceLastCommitment: bigint;
  isHealthy: boolean;
}> {
  const stats = await fetchAttestationStats(attestation);
  const successRate = await getAttestationSuccessRate(attestation);
  const now = BigInt(Math.floor(Date.now() / 1000));
  const secondsSince = stats.lastCommitmentTime > BigInt(0)
    ? now - stats.lastCommitmentTime
    : BigInt(0);

  return {
    totalCommitments: stats.totalCommitments,
    successRate,
    lastCommitmentTime: stats.lastCommitmentTime,
    secondsSinceLastCommitment: secondsSince,
    isHealthy: stats.totalCommitments > BigInt(0) && successRate >= BigInt(9500) // 95%+
  };
}

/**
 * Check if multiple sequencers are authorized
 * @param attestation SequencerAttestation contract instance
 * @param sequencers Sequencer addresses
 * @returns Array of authorization statuses
 */
export async function batchCheckSequencerAuthorization(
  attestation: Contract,
  sequencers: string[]
): Promise<boolean[]> {
  const results: boolean[] = [];
  for (const seq of sequencers) {
    results.push(await isSequencerAuthorized(attestation, seq));
  }
  return results;
}
