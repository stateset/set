/**
 * Example: Agent-to-Agent Payment on Set Chain L2
 *
 * This demonstrates how two AI agents transact using the SSDC V2 stablecoin
 * system. Agent A (buyer) needs a translation service. Agent B (provider)
 * offers translation for 50 SSDC. The entire flow is programmatic — no human
 * in the loop.
 *
 * Flow:
 *   1. Agent B creates a PaymentRequest describing the service
 *   2. Agent A validates the request and accepts it (funds escrow)
 *   3. Agent B performs the work and submits fulfillment proof
 *   4. Agent A verifies the output and releases the escrow
 *   5. Both agents earn yield on the escrowed funds during the hold period
 */

import {
  createAgentClient,
  FulfillmentType,
  type PaymentRequest,
  type SSDCV2Addresses,
} from "../src/stablecoin/v2/index.js";
import { keccak256, toUtf8Bytes } from "ethers";

// ---------------------------------------------------------------------------
// Configuration (would come from environment in production)
// ---------------------------------------------------------------------------

const ADDRESSES: SSDCV2Addresses = {
  vault: process.env.VAULT_ADDRESS!,
  gateway: process.env.GATEWAY_ADDRESS!,
  navController: process.env.NAV_CONTROLLER_ADDRESS!,
  escrow: process.env.ESCROW_ADDRESS!,
  claimQueue: process.env.CLAIM_QUEUE_ADDRESS!,
  policyModule: process.env.POLICY_MODULE_ADDRESS!,
  groundingRegistry: process.env.GROUNDING_REGISTRY_ADDRESS!,
  paymaster: process.env.PAYMASTER_ADDRESS!,
  bridge: process.env.BRIDGE_ADDRESS!,
  statusLens: process.env.STATUS_LENS_ADDRESS!,
  circuitBreaker: process.env.CIRCUIT_BREAKER_ADDRESS!,
  settlementAsset: process.env.SETTLEMENT_ASSET_ADDRESS!,
};

const RPC_URL = process.env.SET_CHAIN_RPC ?? "https://rpc.sepolia.setchain.io";

// ---------------------------------------------------------------------------
// Agent B: Service Provider (Translation Agent)
// ---------------------------------------------------------------------------

async function agentB_createOffer(): Promise<PaymentRequest> {
  const providerAgent = createAgentClient({
    addresses: ADDRESSES,
    privateKey: process.env.AGENT_B_KEY!,
    rpcUrl: RPC_URL,
  });

  // Create a payment request for translation services
  const request = await providerAgent.createPaymentRequest({
    amount: 50_000_000n, // 50.000000 USDC (6 decimals)
    description: "Translate 5,000 words from English to Spanish",
    fulfillmentType: FulfillmentType.DIGITAL,
    milestones: 1, // Single delivery
    holdPeriodSeconds: 300, // 5 minute hold after fulfillment
    challengeWindowSeconds: 3600, // 1 hour challenge window
    arbiterDeadlineSeconds: 604800, // 7 day arbiter deadline
    buyerBps: 1000, // Buyer keeps 10% of yield
    expiresInSeconds: 7200, // Offer valid for 2 hours
    metadata: {
      service: "translation",
      sourceLang: "en",
      targetLang: "es",
      wordCount: 5000,
      model: "claude-opus-4-6",
    },
  });

  console.log(`[Agent B] Created payment request: ${request.requestId}`);
  console.log(`[Agent B] Amount: ${providerAgent.formatAssets(request.amount)} SSDC`);
  console.log(`[Agent B] Expires: ${new Date(request.expiresAt * 1000).toISOString()}`);

  return request;
}

// ---------------------------------------------------------------------------
// Agent A: Buyer (Needs translation)
// ---------------------------------------------------------------------------

async function agentA_acceptAndPay(request: PaymentRequest) {
  const buyerAgent = createAgentClient({
    addresses: ADDRESSES,
    privateKey: process.env.AGENT_A_KEY!,
    rpcUrl: RPC_URL,
  });

  // Step 1: Check system health
  const systemStatus = await buyerAgent.getSystemStatus();
  if (!systemStatus.navFresh || systemStatus.escrowOpsPaused) {
    console.log("[Agent A] System not ready, aborting");
    return null;
  }

  // Step 2: Check own status
  const status = await buyerAgent.getStatus();
  console.log(`[Agent A] Balance: ${buyerAgent.formatAssets(status.assets)} SSDC`);
  console.log(`[Agent A] Available spend: ${buyerAgent.formatAssets(status.availableSpend)} SSDC`);
  console.log(`[Agent A] Grounded: ${status.isGrounded}`);

  if (status.isGrounded || request.amount > status.availableSpend) {
    console.log("[Agent A] Cannot afford this payment");
    return null;
  }

  // Step 3: Check merchant allowlist (if policy requires it)
  if (status.policy.enforceMerchantAllowlist) {
    const allowed = await buyerAgent.isMerchantAllowed(request.payee);
    if (!allowed) {
      console.log(`[Agent A] Merchant ${request.payee} not on allowlist`);
      return null;
    }
  }

  // Step 4: Accept the payment request (funds escrow)
  const acceptance = await buyerAgent.acceptPaymentRequest(request);

  console.log(`[Agent A] Payment accepted!`);
  console.log(`[Agent A] Escrow ID: ${acceptance.escrowId}`);
  console.log(`[Agent A] Shares locked: ${acceptance.sharesLocked}`);
  console.log(`[Agent A] Estimated yield: ${buyerAgent.formatAssets(acceptance.estimatedYield)} SSDC`);
  console.log(`[Agent A] Tx: ${acceptance.txHash}`);

  return acceptance;
}

// ---------------------------------------------------------------------------
// Agent B: Perform work and submit fulfillment
// ---------------------------------------------------------------------------

async function agentB_fulfillAndCollect(escrowId: bigint) {
  const providerAgent = createAgentClient({
    addresses: ADDRESSES,
    privateKey: process.env.AGENT_B_KEY!,
    rpcUrl: RPC_URL,
  });

  // Simulate doing the actual work (translation)
  console.log("[Agent B] Performing translation...");
  const translationResult = "<<5000 words of translated text>>";

  // Create evidence hash from the work output
  const evidenceHash = keccak256(toUtf8Bytes(translationResult));

  // Submit fulfillment proof
  const results = await providerAgent.fulfillPayment(escrowId, evidenceHash);
  console.log(`[Agent B] Fulfillment submitted: ${results.length} milestone(s)`);

  // Preview what we'll receive
  const split = await providerAgent.previewEscrowRelease(escrowId);
  console.log(`[Agent B] Expected merchant shares: ${split.merchantYieldShares + split.principalShares}`);

  return { evidenceHash, translationResult };
}

// ---------------------------------------------------------------------------
// Agent A: Verify and release
// ---------------------------------------------------------------------------

async function agentA_verifyAndRelease(escrowId: bigint, expectedEvidence: string) {
  const buyerAgent = createAgentClient({
    addresses: ADDRESSES,
    privateKey: process.env.AGENT_A_KEY!,
    rpcUrl: RPC_URL,
  });

  // Check escrow state
  const escrowInfo = await buyerAgent.getEscrow(escrowId);
  console.log(`[Agent A] Escrow status: ${escrowInfo.status}`);
  console.log(`[Agent A] Fulfilled at: ${new Date(escrowInfo.fulfilledAt * 1000).toISOString()}`);
  console.log(`[Agent A] Fulfillment evidence: ${escrowInfo.fulfillmentEvidence}`);

  // Verify the evidence matches what we expected
  if (escrowInfo.fulfillmentEvidence !== expectedEvidence) {
    console.log("[Agent A] Evidence mismatch! Disputing...");
    await buyerAgent.disputeEscrow(
      escrowId,
      3, // NOT_AS_DESCRIBED
      1, // milestone 1
      keccak256(toUtf8Bytes("Evidence hash does not match expected output"))
    );
    return;
  }

  // Preview yield split before releasing
  const split = await buyerAgent.previewEscrowRelease(escrowId);
  console.log(`[Agent A] Yield split preview:`);
  console.log(`  Principal shares: ${split.principalShares}`);
  console.log(`  Gross yield: ${split.grossYieldShares}`);
  console.log(`  Buyer yield: ${split.buyerYieldShares}`);
  console.log(`  Merchant yield: ${split.merchantYieldShares}`);
  console.log(`  Reserve: ${split.reserveShares}`);
  console.log(`  Protocol fee: ${split.feeShares}`);

  // Release!
  const result = await buyerAgent.releaseEscrow(escrowId);
  console.log(`[Agent A] Escrow released! Tx: ${result.txHash}`);
}

// ---------------------------------------------------------------------------
// Full Flow
// ---------------------------------------------------------------------------

async function main() {
  // Validate required environment variables before proceeding
  const requiredVars = [
    "VAULT_ADDRESS", "GATEWAY_ADDRESS", "NAV_CONTROLLER_ADDRESS",
    "ESCROW_ADDRESS", "CLAIM_QUEUE_ADDRESS", "POLICY_MODULE_ADDRESS",
    "GROUNDING_REGISTRY_ADDRESS", "PAYMASTER_ADDRESS", "BRIDGE_ADDRESS",
    "STATUS_LENS_ADDRESS", "CIRCUIT_BREAKER_ADDRESS", "SETTLEMENT_ASSET_ADDRESS",
    "AGENT_A_KEY", "AGENT_B_KEY"
  ];

  const missing = requiredVars.filter(v => !process.env[v]);
  if (missing.length > 0) {
    console.error(`Missing required environment variables: ${missing.join(", ")}`);
    console.error("Copy .env.example to .env and fill in the values.");
    process.exit(1);
  }

  console.log("=== Agent-to-Agent Payment on Set Chain L2 ===\n");

  // 1. Provider agent creates an offer
  const paymentRequest = await agentB_createOffer();

  // 2. Buyer agent accepts and funds escrow
  const acceptance = await agentA_acceptAndPay(paymentRequest);
  if (!acceptance) return;

  // 3. Provider does the work and submits proof
  const { evidenceHash } = await agentB_fulfillAndCollect(acceptance.escrowId);

  // 4. Buyer verifies and releases payment
  // (In production, wait for releaseAfter timestamp)
  await agentA_verifyAndRelease(acceptance.escrowId, evidenceHash);

  console.log("\n=== Payment complete! Both agents earned yield. ===");
}

main().catch((error) => {
  console.error("Payment flow failed:", error.message || error);
  if (error.code) console.error("Error code:", error.code);
  if (error.details) console.error("Details:", JSON.stringify(error.details, null, 2));
  process.exit(1);
});
