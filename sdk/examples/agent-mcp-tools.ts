/**
 * Example: MCP Tool Definitions for AI Agent Stablecoin Access
 *
 * These are the tool schemas that any AI agent (Claude, GPT, custom) can
 * use to interact with the SSDC V2 stablecoin system via the Model Context
 * Protocol (MCP) or equivalent function-calling interface.
 *
 * Each tool maps to an AgentClient method. The AI agent calls these tools
 * during conversation, and the tool server executes them on-chain.
 *
 * Setup:
 *   1. Deploy an MCP server that holds the agent's private key
 *   2. Register these tools with the AI agent's tool interface
 *   3. The AI agent can now hold, send, and earn yield on stablecoins
 */

import { createAgentClient, type AgentClient, type SSDCV2Addresses } from "../src/stablecoin/v2/index.js";
import { keccak256, toUtf8Bytes } from "ethers";

// ---------------------------------------------------------------------------
// Tool Definitions (MCP-compatible schemas)
// ---------------------------------------------------------------------------

export const STABLECOIN_TOOLS = [
  {
    name: "ssdc_get_balance",
    description:
      "Get the agent's current SSDC stablecoin balance including vault shares, " +
      "asset value, gas tank balance, spending limits, and grounding status.",
    inputSchema: {
      type: "object" as const,
      properties: {},
      required: [] as string[],
    },
  },
  {
    name: "ssdc_check_system",
    description:
      "Check if the SSDC system is operational. Returns which operations " +
      "(deposit, escrow, redeem, bridge) are currently available.",
    inputSchema: {
      type: "object" as const,
      properties: {},
      required: [] as string[],
    },
  },
  {
    name: "ssdc_deposit",
    description:
      "Deposit settlement assets (USDC) into the vault to receive yield-bearing " +
      "SSDC shares. This is how the agent funds its account.",
    inputSchema: {
      type: "object" as const,
      properties: {
        amount: {
          type: "string",
          description: "Amount in USDC (e.g., '100.00' for 100 USDC)",
        },
      },
      required: ["amount"],
    },
  },
  {
    name: "ssdc_pay",
    description:
      "Send a direct payment to another address. Instant transfer, no escrow. " +
      "Use this for trusted counterparties or small payments.",
    inputSchema: {
      type: "object" as const,
      properties: {
        to: {
          type: "string",
          description: "Recipient address (0x...)",
        },
        amount: {
          type: "string",
          description: "Amount in SSDC (e.g., '50.00' for 50 SSDC)",
        },
      },
      required: ["to", "amount"],
    },
  },
  {
    name: "ssdc_create_invoice",
    description:
      "Create an escrowed payment to a merchant/service provider. Funds are " +
      "locked until the provider proves fulfillment. Both parties earn yield " +
      "on the locked funds. Use this for untrusted counterparties or when " +
      "you need delivery guarantees.",
    inputSchema: {
      type: "object" as const,
      properties: {
        merchant: {
          type: "string",
          description: "Merchant/provider address",
        },
        amount: {
          type: "string",
          description: "Payment amount in SSDC",
        },
        description: {
          type: "string",
          description: "What the payment is for",
        },
        fulfillment_type: {
          type: "string",
          enum: ["delivery", "service", "digital"],
          description: "Type of fulfillment expected",
        },
        milestones: {
          type: "number",
          description: "Number of fulfillment milestones (0 for no proof needed)",
        },
        hold_minutes: {
          type: "number",
          description: "Minutes to hold funds after fulfillment (default: 5)",
        },
        dispute_hours: {
          type: "number",
          description: "Hours allowed for dispute after fulfillment (default: 6)",
        },
      },
      required: ["merchant", "amount", "description"],
    },
  },
  {
    name: "ssdc_release_escrow",
    description:
      "Release an escrow, sending payment to the merchant. Use after " +
      "verifying the merchant fulfilled the order. Yield is split per terms.",
    inputSchema: {
      type: "object" as const,
      properties: {
        escrow_id: {
          type: "string",
          description: "The escrow ID to release",
        },
      },
      required: ["escrow_id"],
    },
  },
  {
    name: "ssdc_submit_fulfillment",
    description:
      "Submit proof of work/delivery for an escrow (as service provider). " +
      "The evidence_hash should be a hash of the proof data.",
    inputSchema: {
      type: "object" as const,
      properties: {
        escrow_id: {
          type: "string",
          description: "The escrow ID to fulfill",
        },
        evidence: {
          type: "string",
          description: "Proof of fulfillment (will be hashed)",
        },
      },
      required: ["escrow_id", "evidence"],
    },
  },
  {
    name: "ssdc_dispute_escrow",
    description:
      "Dispute an escrow if the service was not delivered correctly. " +
      "An arbiter will review the dispute.",
    inputSchema: {
      type: "object" as const,
      properties: {
        escrow_id: {
          type: "string",
          description: "The escrow ID to dispute",
        },
        reason: {
          type: "string",
          enum: ["non_delivery", "quality", "not_as_described", "fraud", "other"],
          description: "Reason for the dispute",
        },
        details: {
          type: "string",
          description: "Detailed explanation of the dispute",
        },
      },
      required: ["escrow_id", "reason", "details"],
    },
  },
  {
    name: "ssdc_get_escrow",
    description: "Get the status and details of an escrow by ID.",
    inputSchema: {
      type: "object" as const,
      properties: {
        escrow_id: {
          type: "string",
          description: "The escrow ID to look up",
        },
      },
      required: ["escrow_id"],
    },
  },
  {
    name: "ssdc_redeem",
    description:
      "Redeem SSDC shares back to settlement assets (USDC). This queues " +
      "an async redemption — you'll receive a claim NFT to collect later.",
    inputSchema: {
      type: "object" as const,
      properties: {
        amount: {
          type: "string",
          description: "Amount in SSDC to redeem",
        },
      },
      required: ["amount"],
    },
  },
];

// ---------------------------------------------------------------------------
// Tool Handler (connects MCP tools to AgentClient)
// ---------------------------------------------------------------------------

/** Parse a human-readable USDC amount to 6-decimal raw integer. e.g. "50.25" → 50_250_000n */
function parseAmount(amount: string): bigint {
  const parts = amount.replace(/,/g, "").split(".");
  const whole = BigInt(parts[0]) * 1_000_000n; // 6 decimals (USDC)
  if (parts[1]) {
    const decimals = parts[1].padEnd(6, "0").slice(0, 6);
    return whole + BigInt(decimals);
  }
  return whole;
}

const FULFILLMENT_TYPE_MAP: Record<string, number> = {
  delivery: 1,
  service: 2,
  digital: 3,
};

const DISPUTE_REASON_MAP: Record<string, number> = {
  non_delivery: 1,
  quality: 2,
  not_as_described: 3,
  fraud: 4,
  other: 5,
};

export async function handleTool(
  agent: AgentClient,
  toolName: string,
  args: Record<string, unknown>
): Promise<unknown> {
  switch (toolName) {
    case "ssdc_get_balance": {
      const status = await agent.getStatus();
      return {
        address: status.address,
        shares: status.shares.toString(),
        asset_value: agent.formatAssets(status.assets) + " SSDC",
        gas_tank_shares: status.gasTankShares.toString(),
        available_spend: agent.formatAssets(status.availableSpend) + " SSDC",
        daily_spent: agent.formatAssets(status.policy.spentTodayAssets) + " SSDC",
        daily_limit: agent.formatAssets(status.policy.dailyLimitAssets) + " SSDC",
        is_grounded: status.isGrounded,
        session_active: status.sessionActive,
      };
    }

    case "ssdc_check_system": {
      const sys = await agent.getSystemStatus();
      return {
        nav_fresh: sys.navFresh,
        deposits_available: sys.mintDepositAllowed,
        escrow_available: !sys.escrowOpsPaused,
        redemptions_available: sys.requestRedeemAllowed,
        bridging_available: sys.bridgingAllowed,
      };
    }

    case "ssdc_deposit": {
      const assets = parseAmount(args.amount as string);
      const result = await agent.deposit(assets);
      return {
        tx_hash: result.txHash,
        shares_received: result.sharesReceived.toString(),
        asset_value: agent.formatAssets(assets) + " SSDC",
      };
    }

    case "ssdc_pay": {
      const amount = parseAmount(args.amount as string);
      const result = await agent.pay(args.to as string, amount);
      return {
        tx_hash: result.txHash,
        shares_sent: result.sharesSent.toString(),
        amount: agent.formatAssets(amount) + " SSDC",
        to: args.to,
      };
    }

    case "ssdc_create_invoice": {
      const amount = parseAmount(args.amount as string);
      const now = Math.floor(Date.now() / 1000);
      const holdMinutes = (args.hold_minutes as number) ?? 5;
      const disputeHours = (args.dispute_hours as number) ?? 6;
      const milestones = (args.milestones as number) ?? 1;
      const fulfillmentType = FULFILLMENT_TYPE_MAP[(args.fulfillment_type as string) ?? "digital"] ?? 3;

      const result = await agent.fundEscrow(
        args.merchant as string,
        {
          assetsDue: amount,
          expiry: now + 86400, // 24 hours
          releaseAfter: now + holdMinutes * 60,
          maxNavAge: 172800,
          maxSharesIn: BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"),
          requiresFulfillment: milestones > 0,
          fulfillmentType,
          requiredMilestones: milestones,
          challengeWindow: disputeHours * 3600,
          arbiterDeadline: 604800, // 7 day arbiter deadline
          disputeTimeoutResolution: 2, // REFUND on timeout
        },
        1000 // 10% yield to buyer
      );

      return {
        escrow_id: result.escrowId.toString(),
        tx_hash: result.txHash,
        shares_locked: result.sharesLocked.toString(),
        amount: agent.formatAssets(amount) + " SSDC",
        merchant: args.merchant,
        description: args.description,
      };
    }

    case "ssdc_release_escrow": {
      const result = await agent.releaseEscrow(BigInt(args.escrow_id as string));
      return { tx_hash: result.txHash, escrow_id: args.escrow_id, status: "released" };
    }

    case "ssdc_submit_fulfillment": {
      const evidenceHash = keccak256(toUtf8Bytes(args.evidence as string));
      const results = await agent.fulfillPayment(BigInt(args.escrow_id as string), evidenceHash);
      return {
        escrow_id: args.escrow_id,
        milestones_submitted: results.length,
        evidence_hash: evidenceHash,
        tx_hashes: results.map((r) => r.txHash),
      };
    }

    case "ssdc_dispute_escrow": {
      const reasonCode = DISPUTE_REASON_MAP[(args.reason as string) ?? "other"] ?? 5;
      const reasonHash = keccak256(toUtf8Bytes(args.details as string));
      const result = await agent.disputeEscrow(
        BigInt(args.escrow_id as string),
        reasonCode,
        1, // target milestone
        reasonHash
      );
      return {
        tx_hash: result.txHash,
        escrow_id: args.escrow_id,
        reason: args.reason,
        status: "disputed",
      };
    }

    case "ssdc_get_escrow": {
      const info = await agent.getEscrow(BigInt(args.escrow_id as string));
      const STATUS_NAMES = ["none", "funded", "released", "refunded"];
      return {
        escrow_id: info.id.toString(),
        buyer: info.buyer,
        merchant: info.merchant,
        shares_held: info.sharesHeld.toString(),
        principal: agent.formatAssets(info.principalAssetsSnapshot) + " SSDC",
        status: STATUS_NAMES[info.status] ?? "unknown",
        disputed: info.disputed,
        fulfilled_at: info.fulfilledAt > 0 ? new Date(info.fulfilledAt * 1000).toISOString() : null,
        settled_at: info.settledAt > 0 ? new Date(info.settledAt * 1000).toISOString() : null,
      };
    }

    case "ssdc_redeem": {
      const amount = parseAmount(args.amount as string);
      const shares = await agent.assetsToShares(amount);
      const result = await agent.requestRedeem(shares);
      return {
        claim_id: result.claimId.toString(),
        tx_hash: result.txHash,
        shares_redeemed: shares.toString(),
        amount: agent.formatAssets(amount) + " SSDC",
        note: "Redemption queued. Use claim_id to collect once processed.",
      };
    }

    default:
      throw new Error(`Unknown tool: ${toolName}`);
  }
}

// ---------------------------------------------------------------------------
// Example: How Claude would use these tools in conversation
// ---------------------------------------------------------------------------

/*
Human: I need to pay Agent-0xABC for translating a document. The cost is 50 SSDC.

Claude: I'll check our balance first, then create an escrowed payment.

<tool_call: ssdc_get_balance>
→ { asset_value: "1,250.00 SSDC", available_spend: "800.00 SSDC", ... }

We have 1,250 SSDC with 800 available to spend. Let me create the payment.

<tool_call: ssdc_create_invoice>
  merchant: "0xABC..."
  amount: "50.00"
  description: "Document translation, English to Spanish, 5000 words"
  fulfillment_type: "digital"
  milestones: 1
→ { escrow_id: "42", tx_hash: "0x...", shares_locked: "49850000..." }

Payment of 50 SSDC escrowed (ID: 42). Agent-0xABC needs to submit fulfillment
proof. Once they deliver, I'll verify and release the payment. Both parties
earn yield while funds are held.

---

[Later, after Agent-0xABC submits fulfillment]

<tool_call: ssdc_get_escrow>
  escrow_id: "42"
→ { status: "funded", fulfilled_at: "2026-03-11T15:30:00Z", ... }

The translation has been submitted. Let me verify the output and release payment.

<tool_call: ssdc_release_escrow>
  escrow_id: "42"
→ { status: "released", tx_hash: "0x..." }

Payment released! The 50 SSDC principal plus yield has been distributed:
- Merchant received the principal + their yield share
- We earned 10% of the yield generated during the 5-minute hold period
*/
