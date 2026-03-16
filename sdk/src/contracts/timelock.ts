import { Contract } from "ethers";
import type { OperationStatus } from "../types.js";

/**
 * Timelock health summary
 */
export interface TimelockHealthSummary {
  minDelay: bigint;
  maxDelay: bigint;
  currentEnvironment: string;
  environmentName: string;
  isHealthy: boolean;
}

/**
 * Pending operations summary
 */
export interface PendingOperationsSummary {
  pending: Array<{ id: string; secondsRemaining: bigint }>;
  ready: string[];
  executed: string[];
}

/**
 * Fetch timelock operation status
 * @param timelock SetTimelock contract instance
 * @param operationId Operation ID (bytes32 hash)
 * @returns Operation status
 */
export async function fetchOperationStatus(
  timelock: Contract,
  operationId: string
): Promise<OperationStatus> {
  const [isPending, isReady, isDone, timestamp] = await timelock.getOperationStatus(operationId);
  return { isPending, isReady, isDone, timestamp };
}

/**
 * Get time remaining until operation can be executed
 * @param timelock SetTimelock contract instance
 * @param operationId Operation ID
 * @returns Seconds remaining (0 if ready or not scheduled)
 */
export async function getOperationTimeRemaining(
  timelock: Contract,
  operationId: string
): Promise<bigint> {
  return await timelock.getTimeRemaining(operationId);
}

/**
 * Check if an account can propose to timelock
 * @param timelock SetTimelock contract instance
 * @param account Account to check
 * @returns True if account has proposer role
 */
export async function canProposeToTimelock(
  timelock: Contract,
  account: string
): Promise<boolean> {
  return await timelock.canPropose(account);
}

/**
 * Check if an account can execute timelock operations
 * @param timelock SetTimelock contract instance
 * @param account Account to check
 * @returns True if account has executor role
 */
export async function canExecuteTimelock(
  timelock: Contract,
  account: string
): Promise<boolean> {
  return await timelock.canExecute(account);
}

/**
 * Get extended timelock configuration
 * @param timelock SetTimelock contract instance
 * @returns Extended configuration with environment detection
 */
export async function getTimelockExtendedConfig(timelock: Contract): Promise<{
  minDelay: bigint;
  maxDelay: bigint;
  mainnetDelay: bigint;
  testnetDelay: bigint;
  devnetDelay: bigint;
  currentEnvironment: number;
}> {
  const [minDelay, maxDelay, mainnetDelay, testnetDelay, devnetDelay, currentEnvironment] =
    await timelock.getExtendedConfig();
  return { minDelay, maxDelay, mainnetDelay, testnetDelay, devnetDelay, currentEnvironment };
}

/**
 * Get operation actionability status
 * @param timelock SetTimelock contract instance
 * @param operationId Operation ID
 * @returns Actionability status
 */
export async function getOperationActionability(
  timelock: Contract,
  operationId: string
): Promise<{
  exists: boolean;
  actionable: boolean;
  secondsToActionable: bigint;
  executed: boolean;
}> {
  const [exists, actionable, secondsToActionable, executed] =
    await timelock.getOperationActionability(operationId);
  return { exists, actionable, secondsToActionable, executed };
}

/**
 * Verify roles for a proposed operation
 * @param timelock SetTimelock contract instance
 * @param proposer Address that will propose
 * @param executor Address that will execute
 * @returns Role verification result
 */
export async function verifyTimelockRoles(
  timelock: Contract,
  proposer: string,
  executor: string
): Promise<{
  canSchedule: boolean;
  canRun: boolean;
  delay: bigint;
}> {
  const [canSchedule, canRun, delay] = await timelock.verifyRolesForOperation(proposer, executor);
  return { canSchedule, canRun, delay };
}

/**
 * Get execution timeline for an operation if scheduled now
 * @param timelock SetTimelock contract instance
 * @returns Execution timeline
 */
export async function getTimelockExecutionTimeline(timelock: Contract): Promise<{
  executeableAt: bigint;
  currentTime: bigint;
  delaySeconds: bigint;
}> {
  const [executeableAt, currentTime, delaySeconds] = await timelock.getExecutionTimeline();
  return { executeableAt, currentTime, delaySeconds };
}

/**
 * Batch check roles for multiple accounts
 * @param timelock SetTimelock contract instance
 * @param accounts Accounts to check
 * @returns Arrays of role statuses
 */
export async function batchGetTimelockRoles(
  timelock: Contract,
  accounts: string[]
): Promise<{
  isProposer: boolean[];
  isExecutor: boolean[];
  isCanceller: boolean[];
  isAdmin: boolean[];
}> {
  const [isProposer, isExecutor, isCanceller, isAdmin] = await timelock.batchGetRoles(accounts);
  return { isProposer, isExecutor, isCanceller, isAdmin };
}

/**
 * Batch get operation status for multiple operations
 * @param timelock SetTimelock contract instance
 * @param operationIds Operation IDs to check
 * @returns Arrays of operation statuses
 */
export async function batchGetTimelockOperationStatus(
  timelock: Contract,
  operationIds: string[]
): Promise<{
  isPending: boolean[];
  isReady: boolean[];
  isDone: boolean[];
  timestamps: bigint[];
}> {
  const [isPending, isReady, isDone, timestamps] =
    await timelock.batchGetOperationStatus(operationIds);
  return { isPending, isReady, isDone, timestamps };
}

/**
 * Batch get time remaining for multiple operations
 * @param timelock SetTimelock contract instance
 * @param operationIds Operation IDs to check
 * @returns Array of time remaining values
 */
export async function batchGetTimelockTimeRemaining(
  timelock: Contract,
  operationIds: string[]
): Promise<bigint[]> {
  return await timelock.batchGetTimeRemaining(operationIds);
}

/**
 * Batch check if accounts can propose
 * @param timelock SetTimelock contract instance
 * @param accounts Accounts to check
 * @returns Array of proposal capabilities
 */
export async function batchCanProposeToTimelock(
  timelock: Contract,
  accounts: string[]
): Promise<boolean[]> {
  return await timelock.batchCanPropose(accounts);
}

/**
 * Batch check if accounts can execute
 * @param timelock SetTimelock contract instance
 * @param accounts Accounts to check
 * @returns Array of execution capabilities
 */
export async function batchCanExecuteTimelock(
  timelock: Contract,
  accounts: string[]
): Promise<boolean[]> {
  return await timelock.batchCanExecute(accounts);
}

/**
 * Get recommended delay for environment
 * @param timelock SetTimelock contract instance
 * @param environment 0=devnet, 1=testnet, 2=mainnet
 * @returns Recommended delay in seconds
 */
export async function getTimelockRecommendedDelay(
  timelock: Contract,
  environment: number
): Promise<bigint> {
  return await timelock.getRecommendedDelay(environment);
}

/**
 * Get timelock health summary
 * @param timelock SetTimelock contract instance
 * @returns Health summary with environment detection
 */
export async function getTimelockHealthSummary(
  timelock: Contract
): Promise<TimelockHealthSummary> {
  const config = await getTimelockExtendedConfig(timelock);
  const envNames = ["devnet", "testnet", "mainnet"];
  const environmentName = envNames[config.currentEnvironment] || "unknown";

  return {
    minDelay: config.minDelay,
    maxDelay: config.maxDelay,
    currentEnvironment: String(config.currentEnvironment),
    environmentName,
    isHealthy: config.minDelay > BigInt(0)
  };
}

/**
 * Categorize operations by status
 * @param timelock SetTimelock contract instance
 * @param operationIds Operation IDs to check
 * @returns Categorized operations
 */
export async function categorizeTimelockOperations(
  timelock: Contract,
  operationIds: string[]
): Promise<PendingOperationsSummary> {
  const statuses = await batchGetTimelockOperationStatus(timelock, operationIds);
  const timeRemaining = await batchGetTimelockTimeRemaining(timelock, operationIds);

  const pending: Array<{ id: string; secondsRemaining: bigint }> = [];
  const ready: string[] = [];
  const executed: string[] = [];

  for (let i = 0; i < operationIds.length; i++) {
    const id = operationIds[i];
    if (statuses.isDone[i]) {
      executed.push(id);
    } else if (statuses.isReady[i]) {
      ready.push(id);
    } else if (statuses.isPending[i]) {
      pending.push({ id, secondsRemaining: timeRemaining[i] });
    }
  }

  return { pending, ready, executed };
}

/**
 * Find all ready-to-execute operations
 * @param timelock SetTimelock contract instance
 * @param operationIds Operation IDs to check
 * @returns Operation IDs that are ready to execute
 */
export async function findReadyTimelockOperations(
  timelock: Contract,
  operationIds: string[]
): Promise<string[]> {
  const statuses = await batchGetTimelockOperationStatus(timelock, operationIds);
  const ready: string[] = [];

  for (let i = 0; i < operationIds.length; i++) {
    if (statuses.isReady[i]) {
      ready.push(operationIds[i]);
    }
  }

  return ready;
}

/**
 * Compute operation ID for a single call
 * @param timelock SetTimelock contract instance
 * @param target Target address
 * @param value ETH value
 * @param data Call data
 * @param predecessor Predecessor operation
 * @param salt Unique salt
 * @returns Operation ID (bytes32)
 */
export async function computeTimelockOperationId(
  timelock: Contract,
  target: string,
  value: bigint,
  data: string,
  predecessor: string,
  salt: string
): Promise<string> {
  return await timelock.computeOperationId(target, value, data, predecessor, salt);
}

/**
 * Compute operation ID for a batch call
 * @param timelock SetTimelock contract instance
 * @param targets Target addresses
 * @param values ETH values
 * @param payloads Call data array
 * @param predecessor Predecessor operation
 * @param salt Unique salt
 * @returns Operation ID (bytes32)
 */
export async function computeTimelockBatchOperationId(
  timelock: Contract,
  targets: string[],
  values: bigint[],
  payloads: string[],
  predecessor: string,
  salt: string
): Promise<string> {
  return await timelock.computeBatchOperationId(targets, values, payloads, predecessor, salt);
}
