import { Contract, Wallet, TransactionReceipt, Log } from "ethers";
import { TransactionBuilder, TxStatus } from "./builder.js";
import type { TxBuilderOptions } from "./builder.js";

/**
 * Flow step result
 */
export interface FlowStepResult {
  step: string;
  status: 'success' | 'failed' | 'skipped';
  txHash?: string;
  error?: string;
  data?: any;
}

/**
 * Flow result
 */
export interface FlowResult {
  success: boolean;
  steps: FlowStepResult[];
  totalGasUsed: bigint;
  totalCost: bigint;
  error?: string;
}

/**
 * Event from a transaction receipt
 */
interface ParsedEvent {
  name: string;
  args: Record<string, any>;
  log: Log;
}

/**
 * Find an event in a transaction receipt by name
 */
function findEvent(
  receipt: TransactionReceipt,
  contract: Contract,
  eventName: string
): ParsedEvent | undefined {
  const iface = contract.interface;

  for (const log of receipt.logs) {
    try {
      const parsed = iface.parseLog({
        topics: log.topics as string[],
        data: log.data
      });

      if (parsed && parsed.name === eventName) {
        // Convert args to a plain object
        const args: Record<string, any> = {};
        for (const key of Object.keys(parsed.args)) {
          if (isNaN(Number(key))) {
            args[key] = parsed.args[key];
          }
        }
        return { name: parsed.name, args, log };
      }
    } catch {
      // Skip logs that don't match this contract's ABI
      continue;
    }
  }

  return undefined;
}

/**
 * Deposit and mint ssUSD flow
 * Steps: 1) Approve collateral, 2) Deposit to vault, 3) Receive ssUSD
 */
export async function executeDepositFlow(
  wallet: Wallet,
  treasuryVault: Contract,
  collateralToken: Contract,
  amount: bigint,
  options: TxBuilderOptions = {}
): Promise<FlowResult> {
  const builder = new TransactionBuilder(wallet, options);
  const steps: FlowStepResult[] = [];
  let totalGasUsed = BigInt(0);
  let totalCost = BigInt(0);

  try {
    // Step 1: Check and approve allowance
    const vaultAddress = await treasuryVault.getAddress();
    const allowance = await collateralToken.allowance(wallet.address, vaultAddress) as bigint;

    if (allowance < amount) {
      const approveResult = await builder.execute(
        collateralToken,
        'approve',
        [vaultAddress, amount]
      );

      if (approveResult.status !== TxStatus.CONFIRMED) {
        steps.push({
          step: 'approve',
          status: 'failed',
          error: approveResult.error?.message
        });
        return { success: false, steps, totalGasUsed, totalCost, error: 'Approval failed' };
      }

      steps.push({
        step: 'approve',
        status: 'success',
        txHash: approveResult.hash
      });
      totalGasUsed += approveResult.gasUsed || BigInt(0);
      totalCost += approveResult.totalCost || BigInt(0);
    } else {
      steps.push({ step: 'approve', status: 'skipped', data: 'Sufficient allowance' });
    }

    // Step 2: Deposit to vault
    const depositResult = await builder.execute(
      treasuryVault,
      'deposit',
      [await collateralToken.getAddress(), amount, wallet.address]
    );

    if (depositResult.status !== TxStatus.CONFIRMED) {
      steps.push({
        step: 'deposit',
        status: 'failed',
        error: depositResult.error?.message
      });
      return { success: false, steps, totalGasUsed, totalCost, error: 'Deposit failed' };
    }

    steps.push({
      step: 'deposit',
      status: 'success',
      txHash: depositResult.hash
    });
    totalGasUsed += depositResult.gasUsed || BigInt(0);
    totalCost += depositResult.totalCost || BigInt(0);

    return { success: true, steps, totalGasUsed, totalCost };

  } catch (error) {
    return {
      success: false,
      steps,
      totalGasUsed,
      totalCost,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

/**
 * Wrap ssUSD to wssUSD flow
 * Steps: 1) Approve ssUSD, 2) Wrap to wssUSD
 */
export async function executeWrapFlow(
  wallet: Wallet,
  wssUSD: Contract,
  ssUSD: Contract,
  amount: bigint,
  options: TxBuilderOptions = {}
): Promise<FlowResult> {
  const builder = new TransactionBuilder(wallet, options);
  const steps: FlowStepResult[] = [];
  let totalGasUsed = BigInt(0);
  let totalCost = BigInt(0);

  try {
    // Step 1: Check and approve allowance
    const wssUSDAddress = await wssUSD.getAddress();
    const allowance = await ssUSD.allowance(wallet.address, wssUSDAddress) as bigint;

    if (allowance < amount) {
      const approveResult = await builder.execute(
        ssUSD,
        'approve',
        [wssUSDAddress, amount]
      );

      if (approveResult.status !== TxStatus.CONFIRMED) {
        steps.push({
          step: 'approve',
          status: 'failed',
          error: approveResult.error?.message
        });
        return { success: false, steps, totalGasUsed, totalCost, error: 'Approval failed' };
      }

      steps.push({
        step: 'approve',
        status: 'success',
        txHash: approveResult.hash
      });
      totalGasUsed += approveResult.gasUsed || BigInt(0);
      totalCost += approveResult.totalCost || BigInt(0);
    } else {
      steps.push({ step: 'approve', status: 'skipped', data: 'Sufficient allowance' });
    }

    // Step 2: Wrap to wssUSD
    const wrapResult = await builder.execute(
      wssUSD,
      'wrap',
      [amount]
    );

    if (wrapResult.status !== TxStatus.CONFIRMED) {
      steps.push({
        step: 'wrap',
        status: 'failed',
        error: wrapResult.error?.message
      });
      return { success: false, steps, totalGasUsed, totalCost, error: 'Wrap failed' };
    }

    steps.push({
      step: 'wrap',
      status: 'success',
      txHash: wrapResult.hash
    });
    totalGasUsed += wrapResult.gasUsed || BigInt(0);
    totalCost += wrapResult.totalCost || BigInt(0);

    return { success: true, steps, totalGasUsed, totalCost };

  } catch (error) {
    return {
      success: false,
      steps,
      totalGasUsed,
      totalCost,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

/**
 * Unwrap wssUSD to ssUSD flow
 */
export async function executeUnwrapFlow(
  wallet: Wallet,
  wssUSD: Contract,
  shares: bigint,
  options: TxBuilderOptions = {}
): Promise<FlowResult> {
  const builder = new TransactionBuilder(wallet, options);
  const steps: FlowStepResult[] = [];
  let totalGasUsed = BigInt(0);
  let totalCost = BigInt(0);

  try {
    const unwrapResult = await builder.execute(
      wssUSD,
      'unwrap',
      [shares]
    );

    if (unwrapResult.status !== TxStatus.CONFIRMED) {
      steps.push({
        step: 'unwrap',
        status: 'failed',
        error: unwrapResult.error?.message
      });
      return { success: false, steps, totalGasUsed, totalCost, error: 'Unwrap failed' };
    }

    steps.push({
      step: 'unwrap',
      status: 'success',
      txHash: unwrapResult.hash
    });
    totalGasUsed += unwrapResult.gasUsed || BigInt(0);
    totalCost += unwrapResult.totalCost || BigInt(0);

    return { success: true, steps, totalGasUsed, totalCost };

  } catch (error) {
    return {
      success: false,
      steps,
      totalGasUsed,
      totalCost,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

/**
 * Request redemption flow
 * Steps: 1) Approve ssUSD to vault, 2) Request redemption
 */
export async function executeRedemptionRequestFlow(
  wallet: Wallet,
  treasuryVault: Contract,
  ssUSD: Contract,
  amount: bigint,
  options: TxBuilderOptions = {}
): Promise<FlowResult & { requestId?: bigint }> {
  const builder = new TransactionBuilder(wallet, options);
  const steps: FlowStepResult[] = [];
  let totalGasUsed = BigInt(0);
  let totalCost = BigInt(0);

  try {
    // Step 1: Check and approve allowance
    const vaultAddress = await treasuryVault.getAddress();
    const allowance = await ssUSD.allowance(wallet.address, vaultAddress) as bigint;

    if (allowance < amount) {
      const approveResult = await builder.execute(
        ssUSD,
        'approve',
        [vaultAddress, amount]
      );

      if (approveResult.status !== TxStatus.CONFIRMED) {
        steps.push({
          step: 'approve',
          status: 'failed',
          error: approveResult.error?.message
        });
        return { success: false, steps, totalGasUsed, totalCost, error: 'Approval failed' };
      }

      steps.push({
        step: 'approve',
        status: 'success',
        txHash: approveResult.hash
      });
      totalGasUsed += approveResult.gasUsed || BigInt(0);
      totalCost += approveResult.totalCost || BigInt(0);
    } else {
      steps.push({ step: 'approve', status: 'skipped', data: 'Sufficient allowance' });
    }

    // Step 2: Request redemption
    const requestResult = await builder.execute(
      treasuryVault,
      'requestRedemption',
      [amount]
    );

    if (requestResult.status !== TxStatus.CONFIRMED) {
      steps.push({
        step: 'requestRedemption',
        status: 'failed',
        error: requestResult.error?.message
      });
      return { success: false, steps, totalGasUsed, totalCost, error: 'Redemption request failed' };
    }

    // Extract request ID from event
    let requestId: bigint | undefined;
    if (requestResult.receipt) {
      const event = findEvent(requestResult.receipt, treasuryVault, 'RedemptionRequested');
      if (event) {
        requestId = event.args?.requestId;
      }
    }

    steps.push({
      step: 'requestRedemption',
      status: 'success',
      txHash: requestResult.hash,
      data: { requestId }
    });
    totalGasUsed += requestResult.gasUsed || BigInt(0);
    totalCost += requestResult.totalCost || BigInt(0);

    return { success: true, steps, totalGasUsed, totalCost, requestId };

  } catch (error) {
    return {
      success: false,
      steps,
      totalGasUsed,
      totalCost,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

/**
 * Batch sponsor merchants flow
 */
export async function executeBatchSponsorFlow(
  wallet: Wallet,
  paymaster: Contract,
  merchants: string[],
  tierIds: bigint[],
  options: TxBuilderOptions = {}
): Promise<FlowResult> {
  const builder = new TransactionBuilder(wallet, options);
  const steps: FlowStepResult[] = [];
  let totalGasUsed = BigInt(0);
  let totalCost = BigInt(0);

  try {
    const sponsorResult = await builder.execute(
      paymaster,
      'batchSponsorMerchants',
      [merchants, tierIds]
    );

    if (sponsorResult.status !== TxStatus.CONFIRMED) {
      steps.push({
        step: 'batchSponsor',
        status: 'failed',
        error: sponsorResult.error?.message
      });
      return { success: false, steps, totalGasUsed, totalCost, error: 'Batch sponsor failed' };
    }

    steps.push({
      step: 'batchSponsor',
      status: 'success',
      txHash: sponsorResult.hash,
      data: { merchantCount: merchants.length }
    });
    totalGasUsed += sponsorResult.gasUsed || BigInt(0);
    totalCost += sponsorResult.totalCost || BigInt(0);

    return { success: true, steps, totalGasUsed, totalCost };

  } catch (error) {
    return {
      success: false,
      steps,
      totalGasUsed,
      totalCost,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

/**
 * Commit batch to registry flow
 */
export async function executeCommitBatchFlow(
  wallet: Wallet,
  registry: Contract,
  tenantId: string,
  storeId: string,
  batchId: string,
  starkRoot: string,
  txCount: number,
  options: TxBuilderOptions = {}
): Promise<FlowResult> {
  const builder = new TransactionBuilder(wallet, options);
  const steps: FlowStepResult[] = [];
  let totalGasUsed = BigInt(0);
  let totalCost = BigInt(0);

  try {
    const commitResult = await builder.execute(
      registry,
      'commitBatch',
      [tenantId, storeId, batchId, starkRoot, txCount]
    );

    if (commitResult.status !== TxStatus.CONFIRMED) {
      steps.push({
        step: 'commitBatch',
        status: 'failed',
        error: commitResult.error?.message
      });
      return { success: false, steps, totalGasUsed, totalCost, error: 'Batch commit failed' };
    }

    steps.push({
      step: 'commitBatch',
      status: 'success',
      txHash: commitResult.hash,
      data: { batchId, txCount }
    });
    totalGasUsed += commitResult.gasUsed || BigInt(0);
    totalCost += commitResult.totalCost || BigInt(0);

    return { success: true, steps, totalGasUsed, totalCost };

  } catch (error) {
    return {
      success: false,
      steps,
      totalGasUsed,
      totalCost,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

/**
 * Submit encrypted transaction flow
 */
export async function executeEncryptedTxFlow(
  wallet: Wallet,
  mempool: Contract,
  encryptedPayload: string,
  epoch: bigint,
  gasLimit: bigint,
  maxFeePerGas: bigint,
  valueDeposit: bigint,
  options: TxBuilderOptions = {}
): Promise<FlowResult & { txId?: string }> {
  const builder = new TransactionBuilder(wallet, options);
  const steps: FlowStepResult[] = [];
  let totalGasUsed = BigInt(0);
  let totalCost = BigInt(0);

  try {
    // Calculate required value (gas deposit + value deposit)
    const gasDeposit = gasLimit * maxFeePerGas;
    const totalValue = gasDeposit + valueDeposit;

    const submitResult = await builder.execute(
      mempool,
      'submitEncryptedTx',
      [encryptedPayload, epoch, gasLimit, maxFeePerGas],
      totalValue
    );

    if (submitResult.status !== TxStatus.CONFIRMED) {
      steps.push({
        step: 'submitEncryptedTx',
        status: 'failed',
        error: submitResult.error?.message
      });
      return { success: false, steps, totalGasUsed, totalCost, error: 'Submit failed' };
    }

    // Extract tx ID from event
    let txId: string | undefined;
    if (submitResult.receipt) {
      const event = findEvent(submitResult.receipt, mempool, 'EncryptedTxSubmitted');
      if (event) {
        txId = event.args?.txId;
      }
    }

    steps.push({
      step: 'submitEncryptedTx',
      status: 'success',
      txHash: submitResult.hash,
      data: { txId }
    });
    totalGasUsed += submitResult.gasUsed || BigInt(0);
    totalCost += submitResult.totalCost || BigInt(0);

    return { success: true, steps, totalGasUsed, totalCost, txId };

  } catch (error) {
    return {
      success: false,
      steps,
      totalGasUsed,
      totalCost,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

/**
 * Force transaction inclusion flow (L1)
 */
export async function executeForcedInclusionFlow(
  wallet: Wallet,
  forcedInclusion: Contract,
  target: string,
  data: string,
  gasLimit: bigint,
  bond: bigint,
  options: TxBuilderOptions = {}
): Promise<FlowResult & { txId?: string; deadline?: bigint }> {
  const builder = new TransactionBuilder(wallet, options);
  const steps: FlowStepResult[] = [];
  let totalGasUsed = BigInt(0);
  let totalCost = BigInt(0);

  try {
    const forceResult = await builder.execute(
      forcedInclusion,
      'forceTransaction',
      [target, data, gasLimit],
      bond
    );

    if (forceResult.status !== TxStatus.CONFIRMED) {
      steps.push({
        step: 'forceTransaction',
        status: 'failed',
        error: forceResult.error?.message
      });
      return { success: false, steps, totalGasUsed, totalCost, error: 'Force transaction failed' };
    }

    // Extract tx ID and deadline from event
    let txId: string | undefined;
    let deadline: bigint | undefined;
    if (forceResult.receipt) {
      const event = findEvent(forceResult.receipt, forcedInclusion, 'TransactionForced');
      if (event) {
        txId = event.args?.txId;
        deadline = event.args?.deadline;
      }
    }

    steps.push({
      step: 'forceTransaction',
      status: 'success',
      txHash: forceResult.hash,
      data: { txId, deadline }
    });
    totalGasUsed += forceResult.gasUsed || BigInt(0);
    totalCost += forceResult.totalCost || BigInt(0);

    return { success: true, steps, totalGasUsed, totalCost, txId, deadline };

  } catch (error) {
    return {
      success: false,
      steps,
      totalGasUsed,
      totalCost,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}
