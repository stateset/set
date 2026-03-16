import { Contract, Wallet, TransactionReceipt, JsonRpcProvider } from "ethers";

/**
 * Transaction status
 */
export enum TxStatus {
  PENDING = 'pending',
  SIMULATING = 'simulating',
  ESTIMATING_GAS = 'estimating_gas',
  SENDING = 'sending',
  CONFIRMING = 'confirming',
  CONFIRMED = 'confirmed',
  FAILED = 'failed',
  REVERTED = 'reverted'
}

/**
 * Transaction result
 */
export interface TxResult {
  status: TxStatus;
  hash?: string;
  receipt?: TransactionReceipt;
  error?: Error;
  gasUsed?: bigint;
  gasPrice?: bigint;
  totalCost?: bigint;
  blockNumber?: number;
  confirmations?: number;
}

/**
 * Transaction builder options
 */
export interface TxBuilderOptions {
  /** Maximum retries on failure */
  maxRetries?: number;
  /** Base delay for exponential backoff (ms) */
  baseDelayMs?: number;
  /** Maximum delay between retries (ms) */
  maxDelayMs?: number;
  /** Gas price multiplier (1.1 = 10% buffer) */
  gasPriceMultiplier?: number;
  /** Gas limit multiplier (1.2 = 20% buffer) */
  gasLimitMultiplier?: number;
  /** Confirmations to wait for */
  confirmations?: number;
  /** Timeout for confirmation (ms) */
  confirmationTimeoutMs?: number;
  /** Enable simulation before sending */
  simulate?: boolean;
  /** Status callback */
  onStatusChange?: (status: TxStatus, details?: string) => void;
}

const DEFAULT_TX_OPTIONS: Required<TxBuilderOptions> = {
  maxRetries: 3,
  baseDelayMs: 1000,
  maxDelayMs: 30000,
  gasPriceMultiplier: 1.1,
  gasLimitMultiplier: 1.2,
  confirmations: 1,
  confirmationTimeoutMs: 120000,
  simulate: true,
  onStatusChange: () => {}
};

/**
 * Sleep utility
 */
function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Calculate exponential backoff delay
 */
function getBackoffDelay(attempt: number, baseMs: number, maxMs: number): number {
  const delay = baseMs * Math.pow(2, attempt);
  return Math.min(delay, maxMs);
}

/**
 * Transaction builder for executing contract calls with retry, simulation, and gas estimation
 */
export class TransactionBuilder {
  private wallet: Wallet;
  private options: Required<TxBuilderOptions>;

  constructor(wallet: Wallet, options: TxBuilderOptions = {}) {
    this.wallet = wallet;
    this.options = { ...DEFAULT_TX_OPTIONS, ...options };
  }

  /**
   * Update status and notify callback
   */
  private updateStatus(status: TxStatus, details?: string): void {
    this.options.onStatusChange(status, details);
  }

  /**
   * Estimate gas for a transaction
   */
  async estimateGas(
    contract: Contract,
    method: string,
    args: any[],
    value?: bigint
  ): Promise<{ gasLimit: bigint; gasPrice: bigint; totalCost: bigint }> {
    this.updateStatus(TxStatus.ESTIMATING_GAS);

    const provider = this.wallet.provider!;
    const feeData = await provider.getFeeData();
    const gasPrice = feeData.gasPrice || BigInt(0);

    // Estimate gas limit
    const gasEstimate = await contract[method].estimateGas(...args, {
      value: value || BigInt(0)
    });

    // Apply multipliers
    const gasLimit = BigInt(Math.ceil(Number(gasEstimate) * this.options.gasLimitMultiplier));
    const adjustedGasPrice = BigInt(Math.ceil(Number(gasPrice) * this.options.gasPriceMultiplier));
    const totalCost = gasLimit * adjustedGasPrice + (value || BigInt(0));

    return { gasLimit, gasPrice: adjustedGasPrice, totalCost };
  }

  /**
   * Simulate a transaction (dry-run)
   */
  async simulate(
    contract: Contract,
    method: string,
    args: any[],
    value?: bigint
  ): Promise<{ success: boolean; returnData?: any; error?: string }> {
    this.updateStatus(TxStatus.SIMULATING);

    try {
      // Use staticCall for simulation
      const result = await contract[method].staticCall(...args, {
        value: value || BigInt(0)
      });
      return { success: true, returnData: result };
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown error';
      return { success: false, error: message };
    }
  }

  /**
   * Execute a transaction with retry logic
   */
  async execute(
    contract: Contract,
    method: string,
    args: any[],
    value?: bigint
  ): Promise<TxResult> {
    let lastError: Error | undefined;

    for (let attempt = 0; attempt <= this.options.maxRetries; attempt++) {
      try {
        // Simulate first if enabled
        if (this.options.simulate) {
          const simResult = await this.simulate(contract, method, args, value);
          if (!simResult.success) {
            return {
              status: TxStatus.FAILED,
              error: new Error(`Simulation failed: ${simResult.error}`)
            };
          }
        }

        // Estimate gas
        const { gasLimit, gasPrice } = await this.estimateGas(contract, method, args, value);

        // Send transaction
        this.updateStatus(TxStatus.SENDING);
        const tx = await contract[method](...args, {
          value: value || BigInt(0),
          gasLimit,
          gasPrice
        });

        this.updateStatus(TxStatus.CONFIRMING, tx.hash);

        // Wait for confirmation
        const receipt = await Promise.race([
          tx.wait(this.options.confirmations),
          sleep(this.options.confirmationTimeoutMs).then(() => {
            throw new Error('Confirmation timeout');
          })
        ]) as TransactionReceipt;

        if (receipt.status === 0) {
          return {
            status: TxStatus.REVERTED,
            hash: tx.hash,
            receipt,
            gasUsed: receipt.gasUsed,
            gasPrice: receipt.gasPrice,
            totalCost: receipt.gasUsed * receipt.gasPrice
          };
        }

        this.updateStatus(TxStatus.CONFIRMED);
        return {
          status: TxStatus.CONFIRMED,
          hash: tx.hash,
          receipt,
          gasUsed: receipt.gasUsed,
          gasPrice: receipt.gasPrice,
          totalCost: receipt.gasUsed * receipt.gasPrice,
          blockNumber: receipt.blockNumber,
          confirmations: this.options.confirmations
        };

      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));

        // Don't retry on simulation failures or user rejections
        if (lastError.message.includes('Simulation failed') ||
            lastError.message.includes('user rejected')) {
          break;
        }

        // Retry with backoff
        if (attempt < this.options.maxRetries) {
          const delay = getBackoffDelay(attempt, this.options.baseDelayMs, this.options.maxDelayMs);
          this.updateStatus(TxStatus.PENDING, `Retry ${attempt + 1}/${this.options.maxRetries} in ${delay}ms`);
          await sleep(delay);
        }
      }
    }

    return {
      status: TxStatus.FAILED,
      error: lastError
    };
  }
}

/**
 * Tracked transaction status
 */
export interface TrackedTransaction {
  hash: string;
  status: TxStatus;
  submittedAt: number;
  confirmedAt?: number;
  blockNumber?: number;
  confirmations: number;
  gasUsed?: bigint;
  effectiveGasPrice?: bigint;
  error?: string;
  metadata?: Record<string, any>;
}

/**
 * Transaction tracker event types
 */
export type TxTrackerEventType =
  | 'submitted'
  | 'confirmed'
  | 'failed'
  | 'dropped'
  | 'replaced'
  | 'confirmation';

/**
 * Transaction tracker event
 */
export interface TxTrackerEvent {
  type: TxTrackerEventType;
  txHash: string;
  transaction: TrackedTransaction;
  confirmations?: number;
}

/**
 * Transaction tracker listener
 */
export type TxTrackerListener = (event: TxTrackerEvent) => void;

/**
 * Transaction tracker for monitoring pending and confirmed transactions
 */
export class TransactionTracker {
  private provider: JsonRpcProvider;
  private transactions: Map<string, TrackedTransaction> = new Map();
  private listeners: Map<string, Set<TxTrackerListener>> = new Map();
  private globalListeners: Set<TxTrackerListener> = new Set();
  private pollingInterval: number;
  private pollTimer: ReturnType<typeof setInterval> | null = null;
  private isPolling: boolean = false;

  constructor(provider: JsonRpcProvider, pollingIntervalMs: number = 2000) {
    this.provider = provider;
    this.pollingInterval = pollingIntervalMs;
  }

  /**
   * Start tracking a transaction
   */
  async track(
    txHash: string,
    metadata?: Record<string, any>
  ): Promise<TrackedTransaction> {
    const tx: TrackedTransaction = {
      hash: txHash,
      status: TxStatus.PENDING,
      submittedAt: Date.now(),
      confirmations: 0,
      metadata
    };

    this.transactions.set(txHash, tx);
    this.emit(txHash, { type: 'submitted', txHash, transaction: tx });

    // Start polling if not already
    this.startPolling();

    // Check immediately
    await this.checkTransaction(txHash);

    return tx;
  }

  /**
   * Get a tracked transaction
   */
  get(txHash: string): TrackedTransaction | undefined {
    return this.transactions.get(txHash);
  }

  /**
   * Get all tracked transactions
   */
  getAll(): TrackedTransaction[] {
    return Array.from(this.transactions.values());
  }

  /**
   * Get pending transactions
   */
  getPending(): TrackedTransaction[] {
    return this.getAll().filter(
      tx => tx.status === TxStatus.PENDING || tx.status === TxStatus.CONFIRMING
    );
  }

  /**
   * Get confirmed transactions
   */
  getConfirmed(): TrackedTransaction[] {
    return this.getAll().filter(tx => tx.status === TxStatus.CONFIRMED);
  }

  /**
   * Subscribe to events for a specific transaction
   */
  on(txHash: string, listener: TxTrackerListener): () => void {
    if (!this.listeners.has(txHash)) {
      this.listeners.set(txHash, new Set());
    }
    this.listeners.get(txHash)!.add(listener);

    // Return unsubscribe function
    return () => {
      this.listeners.get(txHash)?.delete(listener);
    };
  }

  /**
   * Subscribe to all transaction events
   */
  onAll(listener: TxTrackerListener): () => void {
    this.globalListeners.add(listener);
    return () => {
      this.globalListeners.delete(listener);
    };
  }

  /**
   * Wait for a transaction to be confirmed
   */
  async waitForConfirmation(
    txHash: string,
    confirmations: number = 1,
    timeoutMs: number = 120000
  ): Promise<TrackedTransaction> {
    const existing = this.transactions.get(txHash);
    if (existing && existing.confirmations >= confirmations) {
      return existing;
    }

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        unsubscribe();
        reject(new Error(`Transaction confirmation timeout: ${txHash}`));
      }, timeoutMs);

      const unsubscribe = this.on(txHash, event => {
        if (
          event.type === 'confirmed' ||
          (event.type === 'confirmation' && (event.confirmations ?? 0) >= confirmations)
        ) {
          clearTimeout(timeout);
          unsubscribe();
          resolve(event.transaction);
        } else if (event.type === 'failed' || event.type === 'dropped') {
          clearTimeout(timeout);
          unsubscribe();
          reject(new Error(event.transaction.error || 'Transaction failed'));
        }
      });

      // Track if not already tracked
      if (!this.transactions.has(txHash)) {
        this.track(txHash);
      }
    });
  }

  /**
   * Stop tracking a transaction
   */
  untrack(txHash: string): void {
    this.transactions.delete(txHash);
    this.listeners.delete(txHash);

    // Stop polling if no more transactions
    if (this.transactions.size === 0) {
      this.stopPolling();
    }
  }

  /**
   * Clear all tracked transactions
   */
  clear(): void {
    this.transactions.clear();
    this.listeners.clear();
    this.stopPolling();
  }

  /**
   * Destroy the tracker
   */
  destroy(): void {
    this.clear();
    this.globalListeners.clear();
  }

  private emit(txHash: string, event: TxTrackerEvent): void {
    // Notify specific listeners
    this.listeners.get(txHash)?.forEach(listener => {
      try {
        listener(event);
      } catch (e) {
        console.error('Transaction tracker listener error:', e);
      }
    });

    // Notify global listeners
    this.globalListeners.forEach(listener => {
      try {
        listener(event);
      } catch (e) {
        console.error('Transaction tracker global listener error:', e);
      }
    });
  }

  private startPolling(): void {
    if (this.isPolling) return;

    this.isPolling = true;
    this.pollTimer = setInterval(async () => {
      await this.pollTransactions();
    }, this.pollingInterval);
  }

  private stopPolling(): void {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
    this.isPolling = false;
  }

  private async pollTransactions(): Promise<void> {
    const pendingTxs = this.getPending();
    await Promise.all(pendingTxs.map(tx => this.checkTransaction(tx.hash)));
  }

  private async checkTransaction(txHash: string): Promise<void> {
    const tx = this.transactions.get(txHash);
    if (!tx) return;

    try {
      const receipt = await this.provider.getTransactionReceipt(txHash);

      if (receipt) {
        const currentBlock = await this.provider.getBlockNumber();
        const confirmations = currentBlock - receipt.blockNumber + 1;

        const previousConfirmations = tx.confirmations;
        tx.confirmations = confirmations;
        tx.blockNumber = receipt.blockNumber;
        tx.gasUsed = receipt.gasUsed;
        tx.effectiveGasPrice = receipt.gasPrice;

        if (receipt.status === 0) {
          // Transaction reverted
          tx.status = TxStatus.REVERTED;
          tx.error = 'Transaction reverted';
          tx.confirmedAt = Date.now();
          this.emit(txHash, { type: 'failed', txHash, transaction: tx });
        } else if (previousConfirmations === 0) {
          // First confirmation
          tx.status = TxStatus.CONFIRMED;
          tx.confirmedAt = Date.now();
          this.emit(txHash, {
            type: 'confirmed',
            txHash,
            transaction: tx,
            confirmations
          });
        } else if (confirmations > previousConfirmations) {
          // Additional confirmations
          this.emit(txHash, {
            type: 'confirmation',
            txHash,
            transaction: tx,
            confirmations
          });
        }
      } else {
        // Check if transaction was dropped (no longer in mempool)
        const txData = await this.provider.getTransaction(txHash);
        if (!txData && Date.now() - tx.submittedAt > 300000) {
          // 5 minute timeout
          tx.status = TxStatus.FAILED;
          tx.error = 'Transaction dropped from mempool';
          this.emit(txHash, { type: 'dropped', txHash, transaction: tx });
        }
      }
    } catch (error) {
      // Log but don't fail
      console.error(`Error checking transaction ${txHash}:`, error);
    }
  }
}

/**
 * Create a transaction tracker for a provider
 */
export function createTransactionTracker(
  provider: JsonRpcProvider,
  pollingIntervalMs: number = 2000
): TransactionTracker {
  return new TransactionTracker(provider, pollingIntervalMs);
}

/**
 * Watch a single transaction until confirmed
 * Convenience function for one-off transaction watching
 */
export async function watchTransaction(
  provider: JsonRpcProvider,
  txHash: string,
  confirmations: number = 1,
  timeoutMs: number = 120000
): Promise<TransactionReceipt> {
  const startTime = Date.now();
  const pollInterval = 2000;

  while (Date.now() - startTime < timeoutMs) {
    try {
      const receipt = await provider.getTransactionReceipt(txHash);

      if (receipt) {
        if (receipt.status === 0) {
          throw new Error('Transaction reverted');
        }

        const currentBlock = await provider.getBlockNumber();
        const currentConfirmations = currentBlock - receipt.blockNumber + 1;

        if (currentConfirmations >= confirmations) {
          return receipt;
        }
      }
    } catch (error) {
      if ((error as Error).message === 'Transaction reverted') {
        throw error;
      }
      // Ignore other errors and continue polling
    }

    await new Promise(resolve => setTimeout(resolve, pollInterval));
  }

  throw new Error(`Transaction confirmation timeout: ${txHash}`);
}

/**
 * Get the current nonce for an address (including pending transactions)
 */
export async function getNextNonce(
  provider: JsonRpcProvider,
  address: string
): Promise<number> {
  return await provider.getTransactionCount(address, 'pending');
}

/**
 * Speed up a transaction by resubmitting with higher gas price
 */
export async function speedUpTransaction(
  wallet: Wallet,
  originalTxHash: string,
  gasPriceMultiplier: number = 1.5
): Promise<string> {
  const provider = wallet.provider as JsonRpcProvider;

  // Get the original transaction
  const tx = await provider.getTransaction(originalTxHash);
  if (!tx) {
    throw new Error('Original transaction not found');
  }

  // Check if already mined
  const receipt = await provider.getTransactionReceipt(originalTxHash);
  if (receipt) {
    throw new Error('Transaction already mined');
  }

  // Get current gas price
  const feeData = await provider.getFeeData();
  const originalGasPrice = tx.gasPrice || feeData.gasPrice || BigInt(0);
  const newGasPrice = BigInt(Math.ceil(Number(originalGasPrice) * gasPriceMultiplier));

  // Resubmit with same nonce but higher gas price
  const newTx = await wallet.sendTransaction({
    to: tx.to,
    data: tx.data,
    value: tx.value,
    nonce: tx.nonce,
    gasLimit: tx.gasLimit,
    gasPrice: newGasPrice
  });

  return newTx.hash;
}

/**
 * Cancel a transaction by sending a 0-value transaction with same nonce
 */
export async function cancelTransaction(
  wallet: Wallet,
  originalTxHash: string,
  gasPriceMultiplier: number = 1.5
): Promise<string> {
  const provider = wallet.provider as JsonRpcProvider;

  // Get the original transaction
  const tx = await provider.getTransaction(originalTxHash);
  if (!tx) {
    throw new Error('Original transaction not found');
  }

  // Check if already mined
  const receipt = await provider.getTransactionReceipt(originalTxHash);
  if (receipt) {
    throw new Error('Transaction already mined');
  }

  // Get current gas price
  const feeData = await provider.getFeeData();
  const originalGasPrice = tx.gasPrice || feeData.gasPrice || BigInt(0);
  const newGasPrice = BigInt(Math.ceil(Number(originalGasPrice) * gasPriceMultiplier));

  // Send a self-transfer with same nonce to cancel
  const cancelTx = await wallet.sendTransaction({
    to: await wallet.getAddress(),
    data: '0x',
    value: BigInt(0),
    nonce: tx.nonce,
    gasLimit: BigInt(21000),
    gasPrice: newGasPrice
  });

  return cancelTx.hash;
}
