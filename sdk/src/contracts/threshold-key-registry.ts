import { Contract } from "ethers";
import type {
  ThresholdRegistryStatus,
  DKGStatus,
  NetworkHealth,
  KeyExpirationInfo,
  KeyperSummary,
  EpochHistoryEntry
} from "../types.js";

/**
 * Fetch threshold key registry status
 * @param registry ThresholdKeyRegistry contract instance
 * @returns Registry status
 */
export async function fetchThresholdRegistryStatus(
  registry: Contract
): Promise<ThresholdRegistryStatus> {
  const [totalKeypers, activeCount, currentThreshold, epoch, dkgPhase, isPaused] =
    await registry.getRegistryStatus();
  return {
    totalKeypers,
    activeCount,
    currentThreshold,
    epoch,
    dkgPhase,
    isPaused
  };
}

/**
 * Fetch DKG ceremony status
 * @param registry ThresholdKeyRegistry contract instance
 * @returns DKG status
 */
export async function fetchDKGStatus(registry: Contract): Promise<DKGStatus> {
  const [epoch, phase, deadline, participantCount, dealingsCount, blocksUntilDeadline] =
    await registry.getDKGStatus();
  return {
    epoch,
    phase,
    deadline,
    participantCount,
    dealingsCount,
    blocksUntilDeadline
  };
}

/**
 * Check if threshold encryption is available
 * @param registry ThresholdKeyRegistry contract instance
 * @returns True if there is a valid current key for encryption
 */
export async function isThresholdEncryptionAvailable(registry: Contract): Promise<boolean> {
  try {
    const [valid] = await registry.getCurrentKeyStatus();
    return valid;
  } catch {
    return false;
  }
}

/**
 * Get total staked value in the key registry
 * @param registry ThresholdKeyRegistry contract instance
 * @returns Total staked in wei
 */
export async function getTotalKeyperStake(registry: Contract): Promise<bigint> {
  return await registry.getTotalStaked();
}

/**
 * Get network health metrics
 * @param registry ThresholdKeyRegistry contract instance
 * @returns Network health metrics
 */
export async function getNetworkHealth(registry: Contract): Promise<NetworkHealth> {
  const [totalKeypers, activeCount, avgStake, totalSlashed, networkSecure] =
    await registry.getNetworkHealth();
  return { totalKeypers, activeCount, avgStake, totalSlashed, networkSecure };
}

/**
 * Get key expiration info for current epoch
 * @param registry ThresholdKeyRegistry contract instance
 * @returns Expiration info
 */
export async function getKeyExpirationInfo(registry: Contract): Promise<KeyExpirationInfo> {
  const [blocksRemaining, secondsRemaining, percentRemaining] =
    await registry.getKeyExpirationInfo();
  return { blocksRemaining, secondsRemaining, percentRemaining };
}

/**
 * Get top keypers by stake
 * @param registry ThresholdKeyRegistry contract instance
 * @param limit Maximum number of keypers to return
 * @returns Arrays of keyper addresses and stakes
 */
export async function getTopKeypersByStake(
  registry: Contract,
  limit: number
): Promise<{ keypers: string[]; stakes: bigint[] }> {
  const [keypers, stakes] = await registry.getTopKeypersByStake(limit);
  return { keypers, stakes };
}

/**
 * Get all keyper addresses
 * @param registry ThresholdKeyRegistry contract instance
 * @returns Array of keyper addresses
 */
export async function getAllKeypers(registry: Contract): Promise<string[]> {
  return await registry.getAllKeypers();
}

/**
 * Batch check keyper active status
 * @param registry ThresholdKeyRegistry contract instance
 * @param keypers Array of keyper addresses
 * @returns Array of active statuses
 */
export async function batchCheckKeyperActive(
  registry: Contract,
  keypers: string[]
): Promise<boolean[]> {
  return await registry.batchIsKeyperActive(keypers);
}

/**
 * Batch get keyper stakes
 * @param registry ThresholdKeyRegistry contract instance
 * @param keypers Array of keyper addresses
 * @returns Array of stake amounts
 */
export async function batchGetKeyperStakes(
  registry: Contract,
  keypers: string[]
): Promise<bigint[]> {
  return await registry.batchGetStakes(keypers);
}

/**
 * Batch check DKG registration
 * @param registry ThresholdKeyRegistry contract instance
 * @param keypers Array of keyper addresses
 * @returns Array of registration statuses
 */
export async function batchCheckDKGRegistration(
  registry: Contract,
  keypers: string[]
): Promise<boolean[]> {
  return await registry.batchIsRegisteredForDKG(keypers);
}

/**
 * Batch check epoch key validity
 * @param registry ThresholdKeyRegistry contract instance
 * @param epochs Array of epoch numbers
 * @returns Array of validity statuses
 */
export async function batchCheckEpochKeyValid(
  registry: Contract,
  epochs: bigint[]
): Promise<boolean[]> {
  return await registry.batchIsEpochKeyValid(epochs);
}

/**
 * Batch get keyper summaries
 * @param registry ThresholdKeyRegistry contract instance
 * @param keypers Array of keyper addresses
 * @returns Array of keyper summaries
 */
export async function batchGetKeyperSummaries(
  registry: Contract,
  keypers: string[]
): Promise<KeyperSummary[]> {
  const [active, stakes, slashCounts, registeredForDKG] =
    await registry.batchGetKeyperSummary(keypers);

  const summaries: KeyperSummary[] = [];
  for (let i = 0; i < keypers.length; i++) {
    summaries.push({
      active: active[i],
      stake: stakes[i],
      slashCount: slashCounts[i],
      registeredForDKG: registeredForDKG[i]
    });
  }
  return summaries;
}

/**
 * Get epoch history
 * @param registry ThresholdKeyRegistry contract instance
 * @param epochStart Starting epoch
 * @param epochEnd Ending epoch
 * @returns Array of epoch history entries
 */
export async function getEpochHistory(
  registry: Contract,
  epochStart: number,
  epochEnd: number
): Promise<EpochHistoryEntry[]> {
  const [epochs, valid, revoked, thresholds] =
    await registry.getEpochHistory(epochStart, epochEnd);

  const entries: EpochHistoryEntry[] = [];
  for (let i = 0; i < epochs.length; i++) {
    entries.push({
      epoch: epochs[i],
      valid: valid[i],
      revoked: revoked[i],
      threshold: thresholds[i]
    });
  }
  return entries;
}

/**
 * Check if keyper is registered for current DKG
 * @param registry ThresholdKeyRegistry contract instance
 * @param keyper Keyper address
 * @returns Whether keyper is registered
 */
export async function isKeyperRegisteredForDKG(
  registry: Contract,
  keyper: string
): Promise<boolean> {
  return await registry.isRegisteredForDKG(keyper);
}
