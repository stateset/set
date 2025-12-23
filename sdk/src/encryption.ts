/**
 * Set Chain SDK - Threshold Encryption Module
 *
 * Provides utilities for MEV-protected transactions using threshold encryption.
 * Transactions are encrypted with the current epoch's public key and can only
 * be decrypted when a threshold of keypers provide their decryption shares.
 *
 * Flow:
 * 1. Get current threshold public key from ThresholdKeyRegistry
 * 2. Encrypt transaction using threshold encryption
 * 3. Submit encrypted transaction to EncryptedMempool
 * 4. Wait for sequencer to commit ordering
 * 5. Wait for keypers to decrypt (automatic)
 * 6. Transaction is executed in committed order
 */

import { Contract, JsonRpcProvider, Wallet, keccak256, AbiCoder, toUtf8Bytes, concat, hexlify, randomBytes } from "ethers";

// ============================================================================
// Types
// ============================================================================

export interface ThresholdKey {
  epoch: bigint;
  aggregatedPubKey: string;
  keyCommitment: string;
  threshold: bigint;
  keyperCount: bigint;
  activatedAt: bigint;
  expiresAt: bigint;
  revoked: boolean;
}

export interface EncryptedTransaction {
  id: string;
  sender: string;
  encryptedPayload: string;
  payloadHash: string;
  epoch: bigint;
  gasLimit: bigint;
  maxFeePerGas: bigint;
  valueDeposit: bigint;
  submittedAt: bigint;
  orderPosition: bigint;
  status: EncryptedTxStatus;
}

export interface DecryptedTransaction {
  encryptedId: string;
  to: string;
  data: string;
  value: bigint;
  decryptedAt: bigint;
  executed: boolean;
  success: boolean;
}

export enum EncryptedTxStatus {
  Pending = 0,
  Ordered = 1,
  Decrypting = 2,
  Decrypted = 3,
  Executed = 4,
  Failed = 5,
  Expired = 6
}

export interface TransactionParams {
  to: string;
  data: string;
  value: bigint;
}

export interface SubmitOptions {
  gasLimit?: bigint;
  maxFeePerGas?: bigint;
  valueDeposit?: bigint;
}

export interface MempoolStats {
  submitted: bigint;
  executed: bigint;
  failed: bigint;
  expired: bigint;
}

// ============================================================================
// ABIs
// ============================================================================

export const thresholdKeyRegistryAbi = [
  {
    type: "function",
    name: "getCurrentPublicKey",
    inputs: [],
    outputs: [{ name: "pubKey", type: "bytes" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "currentEpoch",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getEpochKey",
    inputs: [{ name: "_epoch", type: "uint256" }],
    outputs: [
      {
        name: "key",
        type: "tuple",
        components: [
          { name: "epoch", type: "uint256" },
          { name: "aggregatedPubKey", type: "bytes" },
          { name: "keyCommitment", type: "bytes32" },
          { name: "threshold", type: "uint256" },
          { name: "keyperCount", type: "uint256" },
          { name: "activatedAt", type: "uint256" },
          { name: "expiresAt", type: "uint256" },
          { name: "revoked", type: "bool" }
        ]
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "isEpochKeyValid",
    inputs: [{ name: "_epoch", type: "uint256" }],
    outputs: [{ name: "valid", type: "bool" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getActiveKeypers",
    inputs: [],
    outputs: [{ name: "activeKeypers", type: "address[]" }],
    stateMutability: "view"
  }
] as const;

export const encryptedMempoolAbi = [
  {
    type: "function",
    name: "submitEncryptedTx",
    inputs: [
      { name: "_encryptedPayload", type: "bytes" },
      { name: "_epoch", type: "uint256" },
      { name: "_gasLimit", type: "uint256" },
      { name: "_maxFeePerGas", type: "uint256" }
    ],
    outputs: [{ name: "txId", type: "bytes32" }],
    stateMutability: "payable"
  },
  {
    type: "function",
    name: "cancelEncryptedTx",
    inputs: [{ name: "_txId", type: "bytes32" }],
    outputs: [],
    stateMutability: "nonpayable"
  },
  {
    type: "function",
    name: "getEncryptedTx",
    inputs: [{ name: "_txId", type: "bytes32" }],
    outputs: [
      {
        name: "etx",
        type: "tuple",
        components: [
          { name: "id", type: "bytes32" },
          { name: "sender", type: "address" },
          { name: "encryptedPayload", type: "bytes" },
          { name: "payloadHash", type: "bytes32" },
          { name: "epoch", type: "uint256" },
          { name: "gasLimit", type: "uint256" },
          { name: "maxFeePerGas", type: "uint256" },
          { name: "valueDeposit", type: "uint256" },
          { name: "submittedAt", type: "uint256" },
          { name: "orderPosition", type: "uint256" },
          { name: "status", type: "uint8" }
        ]
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getDecryptedTx",
    inputs: [{ name: "_txId", type: "bytes32" }],
    outputs: [
      {
        name: "dtx",
        type: "tuple",
        components: [
          { name: "encryptedId", type: "bytes32" },
          { name: "to", type: "address" },
          { name: "data", type: "bytes" },
          { name: "value", type: "uint256" },
          { name: "decryptedAt", type: "uint256" },
          { name: "executed", type: "bool" },
          { name: "success", type: "bool" }
        ]
      }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getUserPendingTxs",
    inputs: [{ name: "_user", type: "address" }],
    outputs: [{ name: "txIds", type: "bytes32[]" }],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getStats",
    inputs: [],
    outputs: [
      { name: "submitted", type: "uint256" },
      { name: "executed", type: "uint256" },
      { name: "failed", type: "uint256" },
      { name: "expired", type: "uint256" }
    ],
    stateMutability: "view"
  },
  {
    type: "function",
    name: "getPendingQueueLength",
    inputs: [],
    outputs: [{ name: "length", type: "uint256" }],
    stateMutability: "view"
  }
] as const;

// ============================================================================
// Encryption Utilities
// ============================================================================

/**
 * Threshold encryption using BLS-based scheme
 *
 * This is a simplified implementation. In production, use a proper
 * threshold encryption library like threshold-bls or shutter-crypto.
 */
export class ThresholdEncryption {
  /**
   * Encrypt transaction data with threshold public key
   *
   * @param txParams Transaction parameters (to, data, value)
   * @param publicKey Threshold public key from key registry
   * @returns Encrypted payload
   */
  static encrypt(txParams: TransactionParams, publicKey: string): string {
    // Encode transaction parameters
    const abiCoder = new AbiCoder();
    const encoded = abiCoder.encode(
      ["address", "bytes", "uint256"],
      [txParams.to, txParams.data, txParams.value]
    );

    // Generate random nonce for encryption
    const nonce = randomBytes(32);

    // Derive encryption key from public key and nonce
    // In production, this would use proper BLS-based encryption
    const encryptionKey = keccak256(concat([publicKey, nonce]));

    // XOR encryption (simplified - use AES-GCM in production)
    const plaintext = new Uint8Array(Buffer.from(encoded.slice(2), "hex"));
    const keyBytes = new Uint8Array(Buffer.from(encryptionKey.slice(2), "hex"));

    const ciphertext = new Uint8Array(plaintext.length);
    for (let i = 0; i < plaintext.length; i++) {
      ciphertext[i] = plaintext[i] ^ keyBytes[i % keyBytes.length];
    }

    // Format: [nonce (32 bytes)][ciphertext]
    return hexlify(concat([nonce, ciphertext]));
  }

  /**
   * Verify encrypted payload format
   */
  static verify(encryptedPayload: string): boolean {
    const bytes = new Uint8Array(Buffer.from(encryptedPayload.slice(2), "hex"));
    // Minimum: 32 bytes nonce + some ciphertext
    return bytes.length >= 64;
  }

  /**
   * Extract nonce from encrypted payload
   */
  static extractNonce(encryptedPayload: string): string {
    return encryptedPayload.slice(0, 66); // 0x + 64 hex chars
  }
}

// ============================================================================
// Client Classes
// ============================================================================

/**
 * Client for interacting with threshold encryption key registry
 */
export class ThresholdKeyRegistryClient {
  private contract: Contract;

  constructor(address: string, provider: JsonRpcProvider | Wallet) {
    this.contract = new Contract(address, thresholdKeyRegistryAbi, provider);
  }

  /**
   * Get current epoch number
   */
  async getCurrentEpoch(): Promise<bigint> {
    return await this.contract.currentEpoch();
  }

  /**
   * Get current threshold public key for encryption
   */
  async getCurrentPublicKey(): Promise<string> {
    return await this.contract.getCurrentPublicKey();
  }

  /**
   * Get epoch key details
   */
  async getEpochKey(epoch: bigint): Promise<ThresholdKey> {
    const key = await this.contract.getEpochKey(epoch);
    return {
      epoch: key.epoch,
      aggregatedPubKey: key.aggregatedPubKey,
      keyCommitment: key.keyCommitment,
      threshold: key.threshold,
      keyperCount: key.keyperCount,
      activatedAt: key.activatedAt,
      expiresAt: key.expiresAt,
      revoked: key.revoked
    };
  }

  /**
   * Check if epoch key is valid for encryption
   */
  async isEpochKeyValid(epoch: bigint): Promise<boolean> {
    return await this.contract.isEpochKeyValid(epoch);
  }

  /**
   * Get list of active keypers
   */
  async getActiveKeypers(): Promise<string[]> {
    return await this.contract.getActiveKeypers();
  }
}

/**
 * Client for submitting and tracking encrypted transactions
 */
export class EncryptedMempoolClient {
  private contract: Contract;
  private keyRegistry: ThresholdKeyRegistryClient;

  constructor(
    mempoolAddress: string,
    keyRegistryAddress: string,
    signer: Wallet
  ) {
    this.contract = new Contract(mempoolAddress, encryptedMempoolAbi, signer);
    this.keyRegistry = new ThresholdKeyRegistryClient(keyRegistryAddress, signer);
  }

  /**
   * Submit an encrypted transaction for MEV-protected execution
   *
   * @param txParams Transaction parameters
   * @param options Submission options
   * @returns Transaction ID
   */
  async submitEncryptedTransaction(
    txParams: TransactionParams,
    options: SubmitOptions = {}
  ): Promise<string> {
    // Get current epoch and public key
    const epoch = await this.keyRegistry.getCurrentEpoch();
    const publicKey = await this.keyRegistry.getCurrentPublicKey();

    // Encrypt transaction
    const encryptedPayload = ThresholdEncryption.encrypt(txParams, publicKey);

    // Set defaults
    const gasLimit = options.gasLimit ?? 200000n;
    const maxFeePerGas = options.maxFeePerGas ?? 1000000000n; // 1 gwei
    const valueDeposit = options.valueDeposit ?? txParams.value;

    if (valueDeposit < txParams.value) {
      throw new Error("valueDeposit must be >= txParams.value");
    }

    // Calculate required fee
    const requiredFee = gasLimit * maxFeePerGas + valueDeposit;

    // Submit encrypted transaction
    const tx = await this.contract.submitEncryptedTx(
      encryptedPayload,
      epoch,
      gasLimit,
      maxFeePerGas,
      { value: requiredFee }
    );

    const receipt = await tx.wait();

    // Extract txId from event
    const event = receipt.logs.find(
      (log: any) => log.topics[0] === keccak256(toUtf8Bytes("EncryptedTxSubmitted(bytes32,address,bytes32,uint256,uint256)"))
    );

    if (event) {
      return event.topics[1];
    }

    throw new Error("Failed to extract transaction ID from event");
  }

  /**
   * Cancel a pending encrypted transaction
   */
  async cancelTransaction(txId: string): Promise<void> {
    const tx = await this.contract.cancelEncryptedTx(txId);
    await tx.wait();
  }

  /**
   * Get encrypted transaction details
   */
  async getTransaction(txId: string): Promise<EncryptedTransaction> {
    const etx = await this.contract.getEncryptedTx(txId);
    return {
      id: etx.id,
      sender: etx.sender,
      encryptedPayload: etx.encryptedPayload,
      payloadHash: etx.payloadHash,
      epoch: etx.epoch,
      gasLimit: etx.gasLimit,
      maxFeePerGas: etx.maxFeePerGas,
      valueDeposit: etx.valueDeposit,
      submittedAt: etx.submittedAt,
      orderPosition: etx.orderPosition,
      status: etx.status as EncryptedTxStatus
    };
  }

  /**
   * Get decrypted transaction details
   */
  async getDecryptedTransaction(txId: string): Promise<DecryptedTransaction> {
    const dtx = await this.contract.getDecryptedTx(txId);
    return {
      encryptedId: dtx.encryptedId,
      to: dtx.to,
      data: dtx.data,
      value: dtx.value,
      decryptedAt: dtx.decryptedAt,
      executed: dtx.executed,
      success: dtx.success
    };
  }

  /**
   * Wait for transaction to reach a specific status
   */
  async waitForStatus(
    txId: string,
    targetStatus: EncryptedTxStatus,
    options: { timeout?: number; pollInterval?: number } = {}
  ): Promise<EncryptedTransaction> {
    const timeout = options.timeout ?? 120000; // 2 minutes
    const pollInterval = options.pollInterval ?? 2000; // 2 seconds

    const startTime = Date.now();

    while (Date.now() - startTime < timeout) {
      const tx = await this.getTransaction(txId);

      if (tx.status === targetStatus) {
        return tx;
      }

      if (tx.status === EncryptedTxStatus.Failed ||
          tx.status === EncryptedTxStatus.Expired) {
        throw new Error(`Transaction ${txId} reached terminal status: ${EncryptedTxStatus[tx.status]}`);
      }

      await new Promise(resolve => setTimeout(resolve, pollInterval));
    }

    throw new Error(`Timeout waiting for transaction ${txId} to reach status ${EncryptedTxStatus[targetStatus]}`);
  }

  /**
   * Get user's pending transactions
   */
  async getUserPendingTransactions(user: string): Promise<string[]> {
    return await this.contract.getUserPendingTxs(user);
  }

  /**
   * Get mempool statistics
   */
  async getStats(): Promise<MempoolStats> {
    const [submitted, executed, failed, expired] = await this.contract.getStats();
    return { submitted, executed, failed, expired };
  }

  /**
   * Get pending queue length
   */
  async getPendingQueueLength(): Promise<bigint> {
    return await this.contract.getPendingQueueLength();
  }
}

// ============================================================================
// High-Level API
// ============================================================================

/**
 * MEV Protection Client
 *
 * High-level interface for MEV-protected transactions on Set Chain
 */
export class MEVProtectionClient {
  private mempool: EncryptedMempoolClient;
  private keyRegistry: ThresholdKeyRegistryClient;

  constructor(
    mempoolAddress: string,
    keyRegistryAddress: string,
    signer: Wallet
  ) {
    this.mempool = new EncryptedMempoolClient(mempoolAddress, keyRegistryAddress, signer);
    this.keyRegistry = new ThresholdKeyRegistryClient(keyRegistryAddress, signer);
  }

  /**
   * Check if MEV protection is available
   */
  async isAvailable(): Promise<boolean> {
    try {
      const epoch = await this.keyRegistry.getCurrentEpoch();
      return await this.keyRegistry.isEpochKeyValid(epoch);
    } catch {
      return false;
    }
  }

  /**
   * Get current protection status
   */
  async getStatus(): Promise<{
    available: boolean;
    epoch: bigint;
    threshold: bigint;
    keyperCount: bigint;
    expiresAt: bigint;
  }> {
    const epoch = await this.keyRegistry.getCurrentEpoch();
    const key = await this.keyRegistry.getEpochKey(epoch);

    return {
      available: !key.revoked && key.expiresAt > BigInt(Math.floor(Date.now() / 1000)),
      epoch: key.epoch,
      threshold: key.threshold,
      keyperCount: key.keyperCount,
      expiresAt: key.expiresAt
    };
  }

  /**
   * Submit MEV-protected transaction
   *
   * @param to Target address
   * @param data Transaction data
   * @param value ETH value to send
   * @param options Submission options
   * @returns Transaction ID and wait helper
   */
  async submit(
    to: string,
    data: string,
    value: bigint = 0n,
    options: SubmitOptions = {}
  ): Promise<{
    txId: string;
    waitForExecution: () => Promise<{ success: boolean; data: string }>;
  }> {
    const txId = await this.mempool.submitEncryptedTransaction(
      { to, data, value },
      options
    );

    return {
      txId,
      waitForExecution: async () => {
        const tx = await this.mempool.waitForStatus(txId, EncryptedTxStatus.Executed);
        const dtx = await this.mempool.getDecryptedTransaction(txId);
        return { success: dtx.success, data: dtx.data };
      }
    };
  }

  /**
   * Cancel a pending transaction
   */
  async cancel(txId: string): Promise<void> {
    await this.mempool.cancelTransaction(txId);
  }

  /**
   * Get transaction status
   */
  async getTransactionStatus(txId: string): Promise<{
    status: string;
    executed: boolean;
    success: boolean;
  }> {
    const etx = await this.mempool.getTransaction(txId);
    const dtx = etx.status >= EncryptedTxStatus.Decrypted
      ? await this.mempool.getDecryptedTransaction(txId)
      : null;

    return {
      status: EncryptedTxStatus[etx.status],
      executed: dtx?.executed ?? false,
      success: dtx?.success ?? false
    };
  }
}

// ============================================================================
// Exports
// ============================================================================

export function createMEVProtectionClient(
  mempoolAddress: string,
  keyRegistryAddress: string,
  privateKey: string,
  rpcUrl: string
): MEVProtectionClient {
  const provider = new JsonRpcProvider(rpcUrl);
  const signer = new Wallet(privateKey, provider);
  return new MEVProtectionClient(mempoolAddress, keyRegistryAddress, signer);
}
