/**
 * Example: Agent Swarm with Orchestrator on Set Chain L2
 *
 * An orchestrator agent delegates sub-tasks to worker agents. Each worker
 * has a spending policy (per-tx limits, daily caps, merchant allowlists).
 * The orchestrator monitors grounding status to ensure the swarm stays solvent.
 *
 * Architecture:
 *   Orchestrator Agent (funded, manages policies)
 *     ├── Worker A: Content generation  (per-tx: 100 SSDC, daily: 500 SSDC)
 *     ├── Worker B: Image rendering     (per-tx: 200 SSDC, daily: 1000 SSDC)
 *     └── Worker C: Quality review      (per-tx: 50 SSDC,  daily: 200 SSDC)
 *
 * Each worker can autonomously pay service providers within their budget.
 * The orchestrator just monitors and re-funds when needed.
 */

import {
  createAgentClient,
  FulfillmentType,
  type AgentStatus,
  type SSDCV2Addresses,
} from "../src/stablecoin/v2/index.js";

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

const RPC = process.env.SET_CHAIN_RPC ?? "https://rpc.sepolia.setchain.io";

// ---------------------------------------------------------------------------
// Worker agents operate independently within their policy bounds
// ---------------------------------------------------------------------------

async function workerLoop(name: string, privateKey: string) {
  const worker = createAgentClient({
    addresses: ADDRESSES,
    privateKey,
    rpcUrl: RPC,
  });

  // Check own status
  const status = await worker.getStatus();
  console.log(`[${name}] Balance: ${worker.formatAssets(status.assets)} SSDC`);
  console.log(`[${name}] Available spend: ${worker.formatAssets(status.availableSpend)} SSDC`);
  console.log(`[${name}] Session active: ${status.sessionActive}`);

  if (!status.sessionActive) {
    console.log(`[${name}] Session expired, waiting for orchestrator to renew`);
    return;
  }

  if (status.isGrounded) {
    console.log(`[${name}] Below collateral floor, waiting for orchestrator to top up`);
    return;
  }

  // Worker autonomously pays for services it needs
  // Example: Worker A paying a content API provider
  const serviceProvider = "0x...provider_address...";
  const serviceCost = 25_000_000n; // 25.000000 USDC (6 decimals)

  if (serviceCost <= status.availableSpend) {
    console.log(`[${name}] Paying ${worker.formatAssets(serviceCost)} for service`);

    const now = Math.floor(Date.now() / 1000);
    const result = await worker.fundEscrow(
      serviceProvider,
      {
        assetsDue: serviceCost,
        expiry: now + 7200,
        releaseAfter: now + 60, // 1 minute hold
        maxNavAge: 172800,
        maxSharesIn: BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"),
        requiresFulfillment: true,
        fulfillmentType: FulfillmentType.DIGITAL,
        requiredMilestones: 1,
        challengeWindow: 1800, // 30 min challenge window
        arbiterDeadline: 604800, // 7 day arbiter deadline
        disputeTimeoutResolution: 2, // REFUND on timeout
      },
      0 // No yield share for buyer (worker doesn't need it)
    );

    console.log(`[${name}] Escrow ${result.escrowId} funded, tx: ${result.txHash}`);
  }
}

// ---------------------------------------------------------------------------
// Orchestrator monitors the swarm and manages funding
// ---------------------------------------------------------------------------

interface WorkerConfig {
  name: string;
  address: string;
  privateKey: string;
}

async function orchestratorMonitor(workers: WorkerConfig[]) {
  const orchestrator = createAgentClient({
    addresses: ADDRESSES,
    privateKey: process.env.ORCHESTRATOR_KEY!,
    rpcUrl: RPC,
  });

  console.log("=== Orchestrator Monitoring Swarm ===\n");

  // Check system health first
  const sys = await orchestrator.getSystemStatus();
  if (!sys.navFresh) {
    console.log("[Orchestrator] NAV stale! Pausing swarm operations.");
    return;
  }

  // Monitor each worker
  for (const w of workers) {
    const worker = createAgentClient({
      addresses: ADDRESSES,
      privateKey: w.privateKey,
      rpcUrl: RPC,
    });

    const status = await worker.getStatus();

    console.log(`[${w.name}]`);
    console.log(`  Shares: ${status.shares}`);
    console.log(`  Assets: ${orchestrator.formatAssets(status.assets)} SSDC`);
    console.log(`  Spent today: ${orchestrator.formatAssets(status.policy.spentTodayAssets)} SSDC`);
    console.log(`  Daily limit: ${orchestrator.formatAssets(status.policy.dailyLimitAssets)} SSDC`);
    console.log(`  Grounded: ${status.isGrounded}`);
    console.log(`  Gas tank: ${status.gasTankShares} shares`);

    // Auto-refund workers running low
    const threshold = status.policy.minAssetsFloor + status.policy.committedAssets + 100_000_000n; // 100 USDC buffer
    if (status.assets < threshold) {
      console.log(`  -> LOW BALANCE: Transferring 500 USDC to ${w.name}`);
      const topUp = 500_000_000n; // 500.000000 USDC
      const shares = await orchestrator.assetsToShares(topUp);
      await orchestrator.transfer(w.address, shares);
    }

    // Top up gas tanks running low
    if (status.gasTankShares < 10_000_000n) { // 10 shares
      console.log(`  -> LOW GAS: Topping up gas tank for ${w.name}`);
      await orchestrator.topUpGasTank(50_000_000n); // 50 shares
    }

    console.log();
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const workers: WorkerConfig[] = [
    { name: "Worker-A (Content)", address: process.env.WORKER_A_ADDR!, privateKey: process.env.WORKER_A_KEY! },
    { name: "Worker-B (Images)", address: process.env.WORKER_B_ADDR!, privateKey: process.env.WORKER_B_KEY! },
    { name: "Worker-C (Review)", address: process.env.WORKER_C_ADDR!, privateKey: process.env.WORKER_C_KEY! },
  ];

  // Orchestrator monitors and manages the swarm
  await orchestratorMonitor(workers);

  // Workers execute independently
  for (const w of workers) {
    await workerLoop(w.name, w.privateKey);
  }
}

main().catch(console.error);
