import { Contract } from "ethers";

/**
 * Encrypted mempool status
 */
export interface MempoolStatus {
  pendingCount: bigint;
  queueCapacity: bigint;
  submitted: bigint;
  executed: bigint;
  failed: bigint;
  expired: bigint;
  isPaused: boolean;
  currentMaxQueueSize: bigint;
}

/**
 * Encrypted transaction status
 */
export interface EncryptedTxStatus {
  status: number;
  statusName: string;
  blocksUntilExpiry: bigint;
  canExecute: boolean;
}

/**
 * Encrypted transaction info
 */
export interface EncryptedTxInfo {
  id: string;
  sender: string;
  payloadHash: string;
  epoch: bigint;
  gasLimit: bigint;
  maxFeePerGas: bigint;
  valueDeposit: bigint;
  submittedAt: bigint;
  orderPosition: bigint;
  status: number;
}

/**
 * Decrypted transaction info
 */
export interface DecryptedTxInfo {
  encryptedId: string;
  to: string;
  data: string;
  value: bigint;
  decryptedAt: bigint;
  executed: boolean;
  success: boolean;
}

/**
 * Fetch encrypted mempool status
 * @param mempool EncryptedMempool contract instance
 * @returns Mempool status
 */
export async function fetchMempoolStatus(mempool: Contract): Promise<MempoolStatus> {
  const [pendingCount, queueCapacity, submitted, executed, failed, expired, isPaused, currentMaxQueueSize] =
    await mempool.getMempoolStatus();
  return { pendingCount, queueCapacity, submitted, executed, failed, expired, isPaused, currentMaxQueueSize };
}

/**
 * Get encrypted mempool statistics
 * @param mempool EncryptedMempool contract instance
 * @returns Statistics
 */
export async function getMempoolStats(mempool: Contract): Promise<{
  submitted: bigint;
  executed: bigint;
  failed: bigint;
  expired: bigint;
}> {
  const [submitted, executed, failed, expired] = await mempool.getStats();
  return { submitted, executed, failed, expired };
}

/**
 * Get encrypted transaction status
 * @param mempool EncryptedMempool contract instance
 * @param txId Transaction ID
 * @returns Transaction status
 */
export async function getEncryptedTxStatus(
  mempool: Contract,
  txId: string
): Promise<EncryptedTxStatus> {
  const [status, statusName, blocksUntilExpiry, canExecute] = await mempool.getTxStatus(txId);
  return { status, statusName, blocksUntilExpiry, canExecute };
}

/**
 * Batch get encrypted transaction statuses
 * @param mempool EncryptedMempool contract instance
 * @param txIds Transaction IDs
 * @returns Array of status values
 */
export async function batchGetEncryptedTxStatuses(
  mempool: Contract,
  txIds: string[]
): Promise<number[]> {
  return await mempool.getBatchTxStatuses(txIds);
}

/**
 * Check if user can submit to encrypted mempool
 * @param mempool EncryptedMempool contract instance
 * @param user User address
 * @returns Submission status
 */
export async function canUserSubmitToMempool(
  mempool: Contract,
  user: string
): Promise<{ canSubmit: boolean; remainingSubmissions: bigint }> {
  const [canSubmit, remainingSubmissions] = await mempool.canUserSubmit(user);
  return { canSubmit, remainingSubmissions };
}

/**
 * Get user's pending encrypted transactions
 * @param mempool EncryptedMempool contract instance
 * @param user User address
 * @returns Array of transaction IDs
 */
export async function getUserPendingEncryptedTxs(
  mempool: Contract,
  user: string
): Promise<string[]> {
  return await mempool.getUserPendingTxs(user);
}

/**
 * Batch get pending transaction counts for users
 * @param mempool EncryptedMempool contract instance
 * @param users User addresses
 * @returns Array of pending counts
 */
export async function batchGetUserPendingCounts(
  mempool: Contract,
  users: string[]
): Promise<bigint[]> {
  return await mempool.getBatchUserPendingCounts(users);
}

/**
 * Get mempool success rate
 * @param mempool EncryptedMempool contract instance
 * @returns Success rate in basis points (10000 = 100%)
 */
export async function getMempoolSuccessRate(mempool: Contract): Promise<bigint> {
  return await mempool.getSuccessRate();
}

/**
 * Get pending queue length
 * @param mempool EncryptedMempool contract instance
 * @returns Queue length
 */
export async function getPendingQueueLength(mempool: Contract): Promise<bigint> {
  return await mempool.getPendingQueueLength();
}

/**
 * Check if mempool is paused
 * @param mempool EncryptedMempool contract instance
 * @returns True if paused
 */
export async function isMempoolPaused(mempool: Contract): Promise<boolean> {
  return await mempool.paused();
}

/**
 * Get mempool health summary
 * @param mempool EncryptedMempool contract instance
 * @returns Health summary
 */
export async function getMempoolHealthSummary(mempool: Contract): Promise<{
  isPaused: boolean;
  pendingCount: bigint;
  queueCapacity: bigint;
  successRate: bigint;
  isHealthy: boolean;
}> {
  const [status, successRate] = await Promise.all([
    fetchMempoolStatus(mempool),
    getMempoolSuccessRate(mempool)
  ]);

  return {
    isPaused: status.isPaused,
    pendingCount: status.pendingCount,
    queueCapacity: status.queueCapacity,
    successRate,
    isHealthy: !status.isPaused && status.queueCapacity > BigInt(0)
  };
}

/**
 * Categorize encrypted transactions by status
 * @param mempool EncryptedMempool contract instance
 * @param txIds Transaction IDs
 * @returns Categorized transactions
 */
export async function categorizeEncryptedTxs(
  mempool: Contract,
  txIds: string[]
): Promise<{
  pending: string[];
  ordered: string[];
  decrypted: string[];
  executed: string[];
  failed: string[];
  expired: string[];
}> {
  const statuses = await batchGetEncryptedTxStatuses(mempool, txIds);
  const result = {
    pending: [] as string[],
    ordered: [] as string[],
    decrypted: [] as string[],
    executed: [] as string[],
    failed: [] as string[],
    expired: [] as string[]
  };

  for (let i = 0; i < txIds.length; i++) {
    const status = statuses[i];
    const txId = txIds[i];
    switch (status) {
      case 0: result.pending.push(txId); break;
      case 1: result.ordered.push(txId); break;
      case 3: result.decrypted.push(txId); break;
      case 4: result.executed.push(txId); break;
      case 5: result.failed.push(txId); break;
      case 6: result.expired.push(txId); break;
    }
  }

  return result;
}

/**
 * Find executable transactions
 * @param mempool EncryptedMempool contract instance
 * @param txIds Transaction IDs to check
 * @returns Transaction IDs that can be executed
 */
export async function findExecutableEncryptedTxs(
  mempool: Contract,
  txIds: string[]
): Promise<string[]> {
  const executable: string[] = [];
  for (const txId of txIds) {
    const status = await getEncryptedTxStatus(mempool, txId);
    if (status.canExecute) {
      executable.push(txId);
    }
  }
  return executable;
}
