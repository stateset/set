/**
 * Set Chain SDK - V2 Agent Client
 *
 * High-level client for AI agents interacting with the SSDC V2 stablecoin system.
 * Handles deposits, escrow payments, gas tank management, yield earning,
 * and agent-to-agent commerce.
 *
 * Usage:
 *   const agent = createAgentClient({ addresses, privateKey, rpcUrl });
 *   await agent.deposit(1_000_000n);                      // Fund 1.000000 USDC (6 decimals)
 *   await agent.pay(merchantAddr, 400_000_000n);          // Pay 400.000000 USDC
 *   await agent.fundEscrow(merchant, terms, 2000);        // Escrowed payment (2000 bps yield)
 */

import { Contract, JsonRpcProvider, Wallet, formatUnits, MaxUint256 } from "ethers";
import {
  wSSDCVaultV2Abi,
  navControllerV2Abi,
  yieldEscrowV2Abi,
  ssdcClaimQueueV2Abi,
  ssdcPolicyModuleV2Abi,
  groundingRegistryV2Abi,
  yieldPaymasterV2Abi,
  ssdcVaultGatewayV2Abi,
  ssdcStatusLensV2Abi,
  erc20Abi,
} from "./abis.js";
import {
  SSDCV2Addresses,
  AgentPolicy,
  AgentStatus,
  InvoiceTerms,
  EscrowInfo,
  ReleaseSplit,
  SystemStatus,
  DepositResult,
  EscrowFundResult,
  RedeemRequestResult,
  GasTankTopUpResult,
  PaymentRequest,
  PaymentAcceptance,
  FulfillmentProof,
  FulfillmentType,
  DisputeResolution,
  EscrowStatus,
  TxResult,
} from "./types.js";
import { SDKError, SDKErrorCode, wrapError } from "../../errors.js";
import { getConfig, debugLog } from "../../config.js";
import { withRetry } from "../../utils/retry.js";
import { validateAddress, validatePositiveAmount } from "../../utils/validation.js";
import { extractEventArgOrThrow } from "../../utils/events.js";
import { estimateGas } from "../../utils/gas.js";

// ---------------------------------------------------------------------------
// Agent-specific error codes
// ---------------------------------------------------------------------------

export enum AgentErrorCode {
  AGENT_GROUNDED = "AGENT_8001",
  POLICY_VIOLATION = "AGENT_8002",
  SESSION_EXPIRED = "AGENT_8003",
  SYSTEM_PAUSED = "AGENT_8004",
  ESCROW_NOT_RELEASABLE = "AGENT_8005",
  NAV_STALE = "AGENT_8006",
  PAYMENT_EXPIRED = "AGENT_8007",
  INSUFFICIENT_SHARES = "AGENT_8008",
}

export class AgentError extends Error {
  readonly code: AgentErrorCode;
  readonly details?: Record<string, unknown>;

  constructor(code: AgentErrorCode, message: string, details?: Record<string, unknown>) {
    super(`[${code}] ${message}`);
    this.name = "AgentError";
    this.code = code;
    this.details = details;
  }
}

// ---------------------------------------------------------------------------
// RAY constant (1e27)
// ---------------------------------------------------------------------------

const RAY = 10n ** 27n;

// ---------------------------------------------------------------------------
// AgentClient
// ---------------------------------------------------------------------------

export class AgentClient {
  private provider: JsonRpcProvider;
  private signer: Wallet;
  private addresses: SSDCV2Addresses;

  // Contract instances
  private vault: Contract;
  private navController: Contract;
  private escrow: Contract;
  private claimQueue: Contract;
  private policyModule: Contract;
  private groundingRegistry: Contract;
  private paymaster: Contract;
  private gateway: Contract;
  private statusLens: Contract;
  private settlementAsset: Contract;

  constructor(addresses: SSDCV2Addresses, signer: Wallet) {
    this.addresses = addresses;
    this.signer = signer;
    this.provider = signer.provider as JsonRpcProvider;

    this.vault = new Contract(addresses.vault, wSSDCVaultV2Abi, signer);
    this.navController = new Contract(addresses.navController, navControllerV2Abi, signer);
    this.escrow = new Contract(addresses.escrow, yieldEscrowV2Abi, signer);
    this.claimQueue = new Contract(addresses.claimQueue, ssdcClaimQueueV2Abi, signer);
    this.policyModule = new Contract(addresses.policyModule, ssdcPolicyModuleV2Abi, signer);
    this.groundingRegistry = new Contract(addresses.groundingRegistry, groundingRegistryV2Abi, signer);
    this.paymaster = new Contract(addresses.paymaster, yieldPaymasterV2Abi, signer);
    this.gateway = new Contract(addresses.gateway, ssdcVaultGatewayV2Abi, signer);
    this.statusLens = new Contract(addresses.statusLens, ssdcStatusLensV2Abi, signer);
    this.settlementAsset = new Contract(addresses.settlementAsset, erc20Abi, signer);
  }

  /** The agent's own address */
  get address(): Promise<string> {
    return this.signer.getAddress();
  }

  // =========================================================================
  // System Queries
  // =========================================================================

  /** Get full system health status */
  async getSystemStatus(): Promise<SystemStatus> {
    try {
      return await withRetry(() => this.statusLens.getStatus());
    } catch (error) {
      throw wrapError(error, "Failed to get system status");
    }
  }

  /** Assert the system is operational for the given operation */
  async assertSystemReady(operation: "deposit" | "escrow" | "redeem" | "bridge"): Promise<void> {
    const status = await this.getSystemStatus();

    if (!status.navFresh) {
      throw new AgentError(AgentErrorCode.NAV_STALE, "NAV oracle is stale");
    }

    switch (operation) {
      case "deposit":
        if (!status.mintDepositAllowed) {
          throw new AgentError(AgentErrorCode.SYSTEM_PAUSED, "Deposits are paused");
        }
        break;
      case "escrow":
        if (status.escrowOpsPaused) {
          throw new AgentError(AgentErrorCode.SYSTEM_PAUSED, "Escrow operations are paused");
        }
        break;
      case "redeem":
        if (!status.requestRedeemAllowed) {
          throw new AgentError(AgentErrorCode.SYSTEM_PAUSED, "Redemptions are paused");
        }
        break;
      case "bridge":
        if (!status.bridgingAllowed) {
          throw new AgentError(AgentErrorCode.SYSTEM_PAUSED, "Bridging is paused");
        }
        break;
    }
  }

  /** Get current NAV (ray precision, 1e27 = $1.00) */
  async getCurrentNAV(): Promise<{ navRay: bigint; stale: boolean }> {
    const [navRay, stale] = await withRetry(() => this.navController.tryCurrentNAVRay());
    return { navRay, stale };
  }

  /** Convert share amount to asset amount at current NAV */
  async sharesToAssets(shares: bigint): Promise<bigint> {
    return await withRetry(() => this.vault.convertToAssets(shares));
  }

  /** Convert asset amount to share amount at current NAV */
  async assetsToShares(assets: bigint): Promise<bigint> {
    return await withRetry(() => this.vault.convertToShares(assets));
  }

  // =========================================================================
  // Agent Status
  // =========================================================================

  /** Get the agent's full status: balances, policy, grounding, spend budget */
  async getStatus(): Promise<AgentStatus> {
    const agentAddr = await this.signer.getAddress();

    const [shares, gasTankShares, policyRaw, isGrounded] = await Promise.all([
      withRetry(() => this.vault.balanceOf(agentAddr)),
      withRetry(() => this.paymaster.gasTankShares(agentAddr)),
      withRetry(() => this.policyModule.policies(agentAddr)),
      withRetry(() => this.groundingRegistry.isGroundedNow(agentAddr)),
    ]);

    const assets = await this.sharesToAssets(shares);

    const policy: AgentPolicy = {
      perTxLimitAssets: policyRaw.perTxLimitAssets,
      dailyLimitAssets: policyRaw.dailyLimitAssets,
      spentTodayAssets: policyRaw.spentTodayAssets,
      dayStart: Number(policyRaw.dayStart),
      minAssetsFloor: policyRaw.minAssetsFloor,
      committedAssets: policyRaw.committedAssets,
      sessionExpiry: Number(policyRaw.sessionExpiry),
      enforceMerchantAllowlist: policyRaw.enforceMerchantAllowlist,
      exists: policyRaw.exists,
    };

    const now = Math.floor(Date.now() / 1000);
    const sessionActive = policy.sessionExpiry === 0 || policy.sessionExpiry > now;

    // Available spend = min(perTxLimit, dailyLimit - spentToday) capped by (assets - floor - committed)
    let budgetRemaining = policy.dailyLimitAssets - policy.spentTodayAssets;
    if (budgetRemaining < 0n) budgetRemaining = 0n;
    let availableSpend = budgetRemaining < policy.perTxLimitAssets ? budgetRemaining : policy.perTxLimitAssets;
    const collateralCap = assets - policy.minAssetsFloor - policy.committedAssets;
    if (collateralCap < availableSpend) availableSpend = collateralCap;
    if (availableSpend < 0n) availableSpend = 0n;

    return {
      address: agentAddr,
      shares,
      assets,
      gasTankShares,
      policy,
      isGrounded,
      availableSpend,
      sessionActive,
    };
  }

  /** Check if merchant is on agent's allowlist (if enforcement is enabled) */
  async isMerchantAllowed(merchant: string): Promise<boolean> {
    const agentAddr = await this.signer.getAddress();
    return await withRetry(() => this.policyModule.merchantAllowlist(agentAddr, merchant));
  }

  // =========================================================================
  // Deposits & Funding
  // =========================================================================

  /**
   * Deposit settlement assets (USDC) into the vault to receive yield-bearing shares.
   * This is how an agent funds its account.
   *
   * @param assets Amount in settlement asset units
   * @param minSharesOut Minimum acceptable shares (slippage protection). Defaults to 0.
   */
  async deposit(assets: bigint, minSharesOut: bigint = 0n): Promise<DepositResult> {
    validatePositiveAmount(assets, "assets");
    const config = getConfig();
    const agentAddr = await this.signer.getAddress();

    await this.assertSystemReady("deposit");

    debugLog("Agent", `Depositing ${formatUnits(assets, 6)} settlement assets`);

    // Ensure allowance
    const allowance = await withRetry(() =>
      this.settlementAsset.allowance(agentAddr, this.addresses.gateway)
    );
    if (allowance < assets) {
      debugLog("Agent", "Approving settlement asset for gateway");
      const approveTx = await this.settlementAsset.approve(this.addresses.gateway, MaxUint256);
      await approveTx.wait(config.blockConfirmations);
    }

    const gasEst = await estimateGas(
      this.gateway,
      "deposit",
      [assets, agentAddr, minSharesOut],
      { gasBuffer: config.gasBuffer }
    );

    const tx = await this.gateway.deposit(assets, agentAddr, minSharesOut, {
      gasLimit: gasEst.gasLimitWithBuffer,
    });
    const receipt = await tx.wait(config.blockConfirmations);

    const sharesReceived = extractEventArgOrThrow<bigint>(
      receipt,
      this.gateway,
      "GatewayDeposit",
      "sharesOut"
    );

    debugLog("Agent", `Deposit complete: ${sharesReceived} shares received`);
    return { txHash: receipt.hash, sharesReceived };
  }

  /**
   * Top up the gas tank so this agent can send gasless (4337) transactions.
   *
   * @param assets Amount in settlement asset units to convert to gas credit
   */
  async topUpGasTank(assets: bigint, minSharesOut: bigint = 0n): Promise<GasTankTopUpResult> {
    validatePositiveAmount(assets, "assets");
    const config = getConfig();
    const agentAddr = await this.signer.getAddress();

    // Ensure allowance for gateway
    const allowance = await withRetry(() =>
      this.settlementAsset.allowance(agentAddr, this.addresses.gateway)
    );
    if (allowance < assets) {
      const approveTx = await this.settlementAsset.approve(this.addresses.gateway, MaxUint256);
      await approveTx.wait(config.blockConfirmations);
    }

    const tx = await this.gateway.depositToGasTank(
      this.addresses.paymaster,
      assets,
      agentAddr,
      minSharesOut
    );
    const receipt = await tx.wait(config.blockConfirmations);

    const sharesDeposited = extractEventArgOrThrow<bigint>(
      receipt,
      this.gateway,
      "GatewayGasTankTopUp",
      "sharesOut"
    );

    debugLog("Agent", `Gas tank topped up: ${sharesDeposited} shares`);
    return { txHash: receipt.hash, sharesDeposited };
  }

  // =========================================================================
  // Payments (Simple Transfers)
  // =========================================================================

  /**
   * Simple share transfer to another agent/address.
   * No escrow, no yield split. Immediate settlement.
   */
  async transfer(to: string, shares: bigint): Promise<TxResult> {
    const validTo = validateAddress(to, "to");
    validatePositiveAmount(shares, "shares");
    const config = getConfig();

    const tx = await this.vault.transfer(validTo, shares);
    const receipt = await tx.wait(config.blockConfirmations);

    debugLog("Agent", `Transferred ${shares} shares to ${validTo}`);
    return { txHash: receipt.hash };
  }

  /**
   * Transfer a specific asset amount worth of shares to another agent.
   * Converts assets to shares at current NAV, then transfers.
   */
  async pay(to: string, assetAmount: bigint): Promise<TxResult & { sharesSent: bigint }> {
    const shares = await this.assetsToShares(assetAmount);
    const result = await this.transfer(to, shares);
    return { ...result, sharesSent: shares };
  }

  // =========================================================================
  // Escrow Commerce (Buyer Side)
  // =========================================================================

  /**
   * Fund an escrow for a merchant with full invoice terms.
   * This is the primary way agents pay for goods/services with protection.
   *
   * @param merchant Merchant (or service provider agent) address
   * @param terms Invoice terms defining payment conditions
   * @param buyerBps Buyer's share of yield in basis points (e.g., 2000 = 20%)
   * @param maxAssetsIn Maximum assets to spend (slippage protection)
   */
  async fundEscrow(
    merchant: string,
    terms: InvoiceTerms,
    buyerBps: number = 0,
    maxAssetsIn?: bigint
  ): Promise<EscrowFundResult> {
    const validMerchant = validateAddress(merchant, "merchant");
    validatePositiveAmount(terms.assetsDue, "assetsDue");
    const config = getConfig();
    const agentAddr = await this.signer.getAddress();

    await this.assertSystemReady("escrow");

    // Check agent won't be grounded
    const status = await this.getStatus();
    if (status.isGrounded) {
      throw new AgentError(
        AgentErrorCode.AGENT_GROUNDED,
        "Agent is below collateral floor, cannot fund escrow",
        { assets: status.assets.toString(), floor: status.policy.minAssetsFloor.toString() }
      );
    }
    if (terms.assetsDue > status.availableSpend) {
      throw new AgentError(
        AgentErrorCode.POLICY_VIOLATION,
        `Payment ${formatUnits(terms.assetsDue, 6)} exceeds available spend ${formatUnits(status.availableSpend, 6)}`,
        { requested: terms.assetsDue.toString(), available: status.availableSpend.toString() }
      );
    }

    // Ensure allowance for gateway
    const allowance = await withRetry(() =>
      this.settlementAsset.allowance(agentAddr, this.addresses.gateway)
    );
    const cap = maxAssetsIn ?? terms.assetsDue + (terms.assetsDue / 100n); // 1% slippage default
    if (allowance < cap) {
      const approveTx = await this.settlementAsset.approve(this.addresses.gateway, MaxUint256);
      await approveTx.wait(config.blockConfirmations);
    }

    const contractTerms = {
      assetsDue: terms.assetsDue,
      expiry: terms.expiry,
      releaseAfter: terms.releaseAfter,
      maxNavAge: terms.maxNavAge,
      maxSharesIn: terms.maxSharesIn,
      requiresFulfillment: terms.requiresFulfillment,
      fulfillmentType: terms.fulfillmentType,
      requiredMilestones: terms.requiredMilestones,
      challengeWindow: terms.challengeWindow,
      arbiterDeadline: terms.arbiterDeadline,
      disputeTimeoutResolution: terms.disputeTimeoutResolution,
    };

    const tx = await this.gateway.depositToEscrow(
      this.addresses.escrow,
      validMerchant,
      contractTerms,
      buyerBps,
      cap
    );
    const receipt = await tx.wait(config.blockConfirmations);

    const escrowId = extractEventArgOrThrow<bigint>(
      receipt,
      this.gateway,
      "GatewayEscrowFunded",
      "escrowId"
    );
    const sharesOut = extractEventArgOrThrow<bigint>(
      receipt,
      this.gateway,
      "GatewayEscrowFunded",
      "sharesOut"
    );
    const assetsIn = extractEventArgOrThrow<bigint>(
      receipt,
      this.gateway,
      "GatewayEscrowFunded",
      "assetsIn"
    );

    debugLog("Agent", `Escrow ${escrowId} funded: ${sharesOut} shares locked for ${validMerchant}`);
    return { txHash: receipt.hash, escrowId, sharesLocked: sharesOut, assetsIn };
  }

  /**
   * Release escrow (buyer approves the merchant's work).
   * Yield accrued during the escrow period is split per the terms.
   */
  async releaseEscrow(escrowId: bigint): Promise<TxResult> {
    const config = getConfig();
    const tx = await this.escrow.release(escrowId);
    const receipt = await tx.wait(config.blockConfirmations);
    debugLog("Agent", `Escrow ${escrowId} released`);
    return { txHash: receipt.hash };
  }

  /** Dispute an escrow (as buyer) */
  async disputeEscrow(
    escrowId: bigint,
    reason: number,
    targetMilestone: number,
    reasonHash: string
  ): Promise<TxResult> {
    const config = getConfig();
    const tx = targetMilestone > 0
      ? await this.escrow.disputeMilestone(escrowId, reason, targetMilestone, reasonHash)
      : await this.escrow.dispute(escrowId, reason, reasonHash);
    const receipt = await tx.wait(config.blockConfirmations);
    debugLog("Agent", `Escrow ${escrowId} disputed`);
    return { txHash: receipt.hash };
  }

  /** Request refund on an escrow (as buyer) */
  async requestRefund(escrowId: bigint, recipient?: string): Promise<TxResult> {
    const config = getConfig();
    void recipient;
    const tx = await this.escrow.refund(escrowId);
    const receipt = await tx.wait(config.blockConfirmations);
    debugLog("Agent", `Escrow ${escrowId} refund requested`);
    return { txHash: receipt.hash };
  }

  /** Preview the yield split that would occur if an escrow is released now */
  async previewEscrowRelease(escrowId: bigint): Promise<ReleaseSplit> {
    return await withRetry(() => this.escrow.previewReleaseSplit(escrowId));
  }

  /** Get escrow info by ID */
  async getEscrow(escrowId: bigint): Promise<EscrowInfo> {
    const e = await withRetry(() => this.escrow.escrows(escrowId));
    return {
      id: escrowId,
      buyer: e.buyer,
      merchant: e.merchant,
      refundRecipient: e.refundRecipient,
      sharesHeld: e.sharesHeld,
      principalAssetsSnapshot: e.principalAssetsSnapshot,
      committedAssets: e.committedAssets,
      releaseAfter: Number(e.releaseAfter),
      buyerBps: Number(e.buyerBps),
      status: Number(e.status) as EscrowStatus,
      requiresFulfillment: e.requiresFulfillment,
      fulfillmentType: Number(e.fulfillmentType) as FulfillmentType,
      disputed: e.disputed,
      disputeReason: Number(e.disputeReason),
      fulfilledAt: Number(e.fulfilledAt),
      fulfillmentEvidence: e.fulfillmentEvidence,
      settlementMode: Number(e.settlementMode),
      settledAt: Number(e.settledAt),
    };
  }

  // =========================================================================
  // Escrow Commerce (Merchant / Service Provider Side)
  // =========================================================================

  /**
   * Submit fulfillment proof (as merchant/service agent).
   * If the escrow has milestones, call this for each milestone in order.
   */
  async submitFulfillment(proof: FulfillmentProof): Promise<TxResult> {
    const config = getConfig();
    const fulfillmentType = proof.fulfillmentType ?? (await this.getEscrow(proof.escrowId)).fulfillmentType;
    const tx = await this.escrow.submitFulfillment(
      proof.escrowId,
      fulfillmentType,
      proof.evidenceHash
    );
    const receipt = await tx.wait(config.blockConfirmations);
    debugLog("Agent", `Fulfillment submitted for escrow ${proof.escrowId}, milestone ${proof.milestoneNumber}`);
    return { txHash: receipt.hash };
  }

  /**
   * Release escrow as merchant (timeout-based release after fulfillment + hold period).
   */
  async releaseAsMerchant(escrowId: bigint): Promise<TxResult> {
    const config = getConfig();
    const tx = await this.escrow.release(escrowId);
    const receipt = await tx.wait(config.blockConfirmations);
    debugLog("Agent", `Escrow ${escrowId} released by merchant`);
    return { txHash: receipt.hash };
  }

  // =========================================================================
  // Redemption (Cash Out)
  // =========================================================================

  /**
   * Request async redemption of shares for settlement assets.
   * Returns a claim NFT that can be claimed once processed.
   *
   * @param shares Number of shares to redeem
   */
  async requestRedeem(shares: bigint): Promise<RedeemRequestResult> {
    validatePositiveAmount(shares, "shares");
    const config = getConfig();
    const agentAddr = await this.signer.getAddress();

    await this.assertSystemReady("redeem");

    // Approve claim queue to take shares
    const allowance = await withRetry(() =>
      this.vault.allowance(agentAddr, this.addresses.claimQueue)
    );
    if (allowance < shares) {
      const approveTx = await this.vault.approve(this.addresses.claimQueue, MaxUint256);
      await approveTx.wait(config.blockConfirmations);
    }

    const tx = await this.claimQueue.requestRedeem(shares, agentAddr);
    const receipt = await tx.wait(config.blockConfirmations);

    const claimId = extractEventArgOrThrow<bigint>(
      receipt,
      this.claimQueue,
      "RedeemRequested",
      "claimId"
    );

    debugLog("Agent", `Redemption requested: claim ${claimId} for ${shares} shares`);
    return { txHash: receipt.hash, claimId };
  }

  /** Claim processed redemption (receives settlement assets) */
  async claimRedemption(claimId: bigint): Promise<TxResult> {
    const config = getConfig();
    const tx = await this.claimQueue.claim(claimId);
    const receipt = await tx.wait(config.blockConfirmations);
    debugLog("Agent", `Claim ${claimId} collected`);
    return { txHash: receipt.hash };
  }

  // =========================================================================
  // Agent-to-Agent Payment Protocol
  // =========================================================================

  /**
   * Create a payment request that another agent can accept.
   * This is what a service provider agent publishes to request payment.
   */
  async createPaymentRequest(params: {
    amount: bigint;
    description: string;
    holdPeriodSeconds?: number;
    fulfillmentType?: FulfillmentType;
    milestones?: number;
    challengeWindowSeconds?: number;
    arbiterDeadlineSeconds?: number;
    buyerBps?: number;
    expiresInSeconds?: number;
    callbackUrl?: string;
    metadata?: Record<string, unknown>;
  }): Promise<PaymentRequest> {
    const agentAddr = await this.signer.getAddress();
    const now = Math.floor(Date.now() / 1000);
    const expiresAt = now + (params.expiresInSeconds ?? 3600); // 1 hour default

    const terms: InvoiceTerms = {
      assetsDue: params.amount,
      expiry: expiresAt,
      releaseAfter: now + (params.holdPeriodSeconds ?? 300), // 5 min default
      maxNavAge: 172800, // 48 hours
      maxSharesIn: MaxUint256,
      requiresFulfillment: (params.milestones ?? 0) > 0,
      fulfillmentType: params.fulfillmentType ?? FulfillmentType.DIGITAL,
      requiredMilestones: params.milestones ?? 0,
      challengeWindow: params.challengeWindowSeconds ?? 21600, // 6 hours default
      arbiterDeadline: params.arbiterDeadlineSeconds ?? 604800, // 7 days default
      disputeTimeoutResolution: DisputeResolution.REFUND,
    };

    // Generate a unique request ID
    const requestId = `pr_${agentAddr.slice(2, 10)}_${now.toString(36)}_${Math.random().toString(36).slice(2, 8)}`;

    return {
      requestId,
      payee: agentAddr,
      amount: params.amount,
      description: params.description,
      terms,
      buyerBps: params.buyerBps ?? 0,
      expiresAt,
      callbackUrl: params.callbackUrl,
      metadata: params.metadata,
    };
  }

  /**
   * Accept a payment request from another agent.
   * Validates the request, funds an escrow, and returns the acceptance.
   */
  async acceptPaymentRequest(request: PaymentRequest): Promise<PaymentAcceptance> {
    const now = Math.floor(Date.now() / 1000);

    if (now > request.expiresAt) {
      throw new AgentError(
        AgentErrorCode.PAYMENT_EXPIRED,
        `Payment request ${request.requestId} expired at ${new Date(request.expiresAt * 1000).toISOString()}`
      );
    }

    const result = await this.fundEscrow(
      request.payee,
      request.terms,
      request.buyerBps
    );

    // Estimate yield (based on current NAV rate and hold period)
    const { navRay } = await this.getCurrentNAV();
    const holdDuration = BigInt(request.terms.releaseAfter - now);
    const ratePerSecond = (await withRetry(() => this.navController.ratePerSecondRay())) as bigint;
    const projectedNAV = navRay + (ratePerSecond * holdDuration);
    const boundedProjectedNAV = projectedNAV > 0n ? projectedNAV : 0n;
    const estimatedYield =
      (result.sharesLocked * boundedProjectedNAV) / RAY - request.amount;

    debugLog("Agent", `Accepted payment ${request.requestId}: escrow ${result.escrowId}`);

    return {
      requestId: request.requestId,
      escrowId: result.escrowId,
      txHash: result.txHash,
      sharesLocked: result.sharesLocked,
      estimatedYield: estimatedYield > 0n ? estimatedYield : 0n,
    };
  }

  /**
   * Complete a service and submit fulfillment for a payment.
   * Convenience method that submits all required milestones at once.
   */
  async fulfillPayment(escrowId: bigint, evidenceHash: string): Promise<TxResult[]> {
    const info = await this.getEscrow(escrowId);
    const results: TxResult[] = [];

    if (!info.requiresFulfillment) {
      debugLog("Agent", `Escrow ${escrowId} does not require fulfillment`);
      return results;
    }

    // Get how many milestones are already completed
    const completed = await withRetry(() => this.escrow.escrowCompletedMilestones(escrowId));
    const required = await withRetry(() => this.escrow.escrowRequiredMilestones(escrowId));

    for (let m = Number(completed) + 1; m <= Number(required); m++) {
      const result = await this.submitFulfillment({
        escrowId,
        milestoneNumber: m,
        evidenceHash,
      });
      results.push(result);
    }

    return results;
  }

  // =========================================================================
  // Utility
  // =========================================================================

  /** Get the settlement asset balance (USDC) of this agent */
  async getSettlementBalance(): Promise<bigint> {
    const agentAddr = await this.signer.getAddress();
    return await withRetry(() => this.settlementAsset.balanceOf(agentAddr));
  }

  /** Get vault share balance of this agent */
  async getShareBalance(): Promise<bigint> {
    const agentAddr = await this.signer.getAddress();
    return await withRetry(() => this.vault.balanceOf(agentAddr));
  }

  /** Get the current value of this agent's shares in settlement asset terms */
  async getAssetValue(): Promise<bigint> {
    const shares = await this.getShareBalance();
    return await this.sharesToAssets(shares);
  }

  /** Format an asset amount for display */
  formatAssets(assets: bigint, decimals: number = 6): string {
    return formatUnits(assets, decimals);
  }
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

export interface CreateAgentClientOptions {
  addresses: SSDCV2Addresses;
  privateKey: string;
  rpcUrl: string;
}

/**
 * Create an agent client connected to the SSDC V2 system.
 *
 * @example
 * ```ts
 * const agent = createAgentClient({
 *   addresses: SEPOLIA_ADDRESSES,
 *   privateKey: process.env.AGENT_PRIVATE_KEY!,
 *   rpcUrl: "https://rpc.sepolia.setchain.io",
 * });
 *
 * // Fund the agent
 * await agent.deposit(1_000_000_000n);  // 1000.000000 USDC (6 decimals)
 *
 * // Pay another agent for a service
 * const acceptance = await agent.acceptPaymentRequest(paymentRequest);
 * ```
 */
export function createAgentClient(options: CreateAgentClientOptions): AgentClient {
  const provider = new JsonRpcProvider(options.rpcUrl);
  const signer = new Wallet(options.privateKey, provider);
  return new AgentClient(options.addresses, signer);
}
