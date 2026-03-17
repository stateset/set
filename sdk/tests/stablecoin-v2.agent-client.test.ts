import { describe, expect, it, vi } from "vitest";
import { Interface, zeroPadValue } from "ethers";
import { AgentClient, AgentErrorCode } from "../src/stablecoin/v2/AgentClient.js";
import { DisputeResolution, EscrowStatus, FulfillmentType, SettlementMode } from "../src/stablecoin/v2/types.js";
import type {
  AgentStatus,
  EscrowInfo,
  InvoiceTerms,
  PaymentAcceptancePreview,
  PaymentRequest,
  SettlementAction,
  SettlementPreview,
  SystemStatus,
} from "../src/stablecoin/v2/types.js";
import { wssdcCrossChainBridgeV2Abi } from "../src/stablecoin/v2/abis.js";

const RECIPIENT = "0x1000000000000000000000000000000000000001";
const RAY = 10n ** 27n;

function makeStatus(overrides: Partial<AgentStatus> = {}): AgentStatus {
  return {
    address: "0x2000000000000000000000000000000000000002",
    shares: 10_000_000n,
    assets: 10_000_000n,
    effectiveFloorAssets: 2_000_000n,
    gasTankShares: 0n,
    policy: {
      perTxLimitAssets: 0n,
      dailyLimitAssets: 0n,
      spentTodayAssets: 0n,
      dayStart: 0,
      minAssetsFloor: 2_000_000n,
      committedAssets: 0n,
      sessionExpiry: 0,
      enforceMerchantAllowlist: false,
      exists: true,
    },
    isGrounded: false,
    availableSpend: 8_000_000n,
    sessionActive: true,
    ...overrides,
  };
}

function makeClient(status: AgentStatus) {
  const client = Object.create(AgentClient.prototype) as AgentClient & {
    getStatus: ReturnType<typeof vi.fn>;
    isMerchantAllowed: ReturnType<typeof vi.fn>;
    assetsToShares: ReturnType<typeof vi.fn>;
    transfer: ReturnType<typeof vi.fn>;
  };

  client.getStatus = vi.fn().mockResolvedValue(status);
  client.isMerchantAllowed = vi.fn().mockResolvedValue(true);
  client.assetsToShares = vi.fn().mockResolvedValue(1_234_567n);
  client.transfer = vi.fn().mockResolvedValue({ txHash: "0xabc" });

  return client;
}

function makeTerms(overrides: Partial<InvoiceTerms> = {}): InvoiceTerms {
  return {
    assetsDue: 140n,
    expiry: 2_000,
    releaseAfter: 1_000,
    maxNavAge: 200,
    maxSharesIn: 100n,
    requiresFulfillment: false,
    fulfillmentType: FulfillmentType.NONE,
    requiredMilestones: 0,
    challengeWindow: 0,
    arbiterDeadline: 0,
    disputeTimeoutResolution: DisputeResolution.NONE,
    ...overrides,
  };
}

function makePaymentRequest(overrides: Partial<PaymentRequest> = {}): PaymentRequest {
  const terms = makeTerms(overrides.terms);
  return {
    requestId: "pr_test",
    payee: RECIPIENT,
    amount: terms.assetsDue,
    description: "Test service",
    terms,
    buyerBps: 0,
    expiresAt: terms.expiry,
    ...overrides,
    terms,
  };
}

function makeSettlementPreview(overrides: Partial<SettlementPreview> = {}): SettlementPreview {
  return {
    status: EscrowStatus.FUNDED,
    releaseAfterPassed: true,
    fulfillmentSubmitted: false,
    fulfillmentComplete: false,
    disputeActive: false,
    disputeResolved: false,
    disputeTimedOut: false,
    requiresArbiterResolution: false,
    canBuyerRelease: false,
    canMerchantRelease: false,
    canArbiterRelease: false,
    canBuyerRefund: false,
    canArbiterRefund: false,
    canArbiterResolve: false,
    buyerReleaseMode: SettlementMode.NONE,
    merchantReleaseMode: SettlementMode.NONE,
    arbiterReleaseMode: SettlementMode.NONE,
    buyerRefundMode: SettlementMode.NONE,
    arbiterRefundMode: SettlementMode.NONE,
    requiredMilestones: 0,
    completedMilestones: 0,
    nextMilestoneNumber: 0,
    disputedMilestone: 0,
    challengeWindowEndsAt: 0,
    disputeWindowEndsAt: 0,
    ...overrides,
  };
}

function makeSystemStatus(overrides: Partial<SystemStatus> = {}): SystemStatus {
  return {
    transfersAllowed: true,
    navFresh: true,
    navConversionsAllowed: true,
    navUpdatesPaused: false,
    mintDepositAllowed: true,
    redeemWithdrawAllowed: true,
    requestRedeemAllowed: true,
    processQueueAllowed: true,
    queueSkipsBlockedClaims: false,
    bridgingAllowed: true,
    bridgeMintAllowed: true,
    gatewayRequired: false,
    escrowOpsPaused: false,
    paymasterPaused: false,
    bridgeOutstandingShares: 40n,
    bridgeOutstandingLimitShares: 100n,
    bridgeRemainingCapacityShares: 60n,
    minBridgeLiquidityCoverageBps: 0n,
    liabilityAssets: 0n,
    settlementAssetsAvailable: 0n,
    queueBufferAvailable: 0n,
    queueReservedAssets: 0n,
    queueDepth: 0n,
    liquidityCoverageBps: 10_000n,
    navRay: 2n * RAY,
    navEpoch: 1n,
    navLastUpdate: 0n,
    totalShareSupply: 0n,
    reserveManager: "0x0000000000000000000000000000000000000000",
    reserveFloor: 0n,
    reserveMaxDeployBps: 0n,
    reserveDeployedAssets: 0n,
    ...overrides,
  };
}

function makeEscrowInfo(overrides: Partial<EscrowInfo> = {}): EscrowInfo {
  return {
    id: 1n,
    buyer: "0x2000000000000000000000000000000000000002",
    merchant: RECIPIENT,
    refundRecipient: "0x3000000000000000000000000000000000000003",
    sharesHeld: 100n,
    principalAssetsSnapshot: 140n,
    committedAssets: 0n,
    releaseAfter: 1_000,
    buyerBps: 0,
    status: EscrowStatus.FUNDED,
    requiresFulfillment: false,
    fulfillmentType: FulfillmentType.NONE,
    disputed: false,
    disputeReason: 0,
    fulfilledAt: 0,
    fulfillmentEvidence: `0x${"1".repeat(64)}`,
    resolution: DisputeResolution.NONE,
    resolvedAt: 0,
    resolutionEvidence: `0x${"2".repeat(64)}`,
    challengeWindow: 0,
    arbiterDeadline: 0,
    timeoutResolution: DisputeResolution.NONE,
    disputedAt: 0,
    settlementMode: SettlementMode.NONE,
    settledAt: 0,
    ...overrides,
  };
}

describe("AgentClient pay()", () => {
  it("applies policy preflight before sending a high-level payment", async () => {
    const client = makeClient(makeStatus());

    await expect(client.pay(RECIPIENT, 3_000_000n)).resolves.toEqual({
      txHash: "0xabc",
      sharesSent: 1_234_567n,
    });

    expect(client.getStatus).toHaveBeenCalledTimes(1);
    expect(client.assetsToShares).toHaveBeenCalledWith(3_000_000n);
    expect(client.transfer).toHaveBeenCalledWith(RECIPIENT, 1_234_567n);
  });

  it("rejects payments when the agent session has expired", async () => {
    const client = makeClient(makeStatus({ sessionActive: false }));

    await expect(client.pay(RECIPIENT, 1_000_000n)).rejects.toMatchObject({
      code: AgentErrorCode.SESSION_EXPIRED,
    });

    expect(client.assetsToShares).not.toHaveBeenCalled();
    expect(client.transfer).not.toHaveBeenCalled();
  });

  it("rejects payments that violate the merchant allowlist", async () => {
    const client = makeClient(makeStatus({
      policy: {
        ...makeStatus().policy,
        enforceMerchantAllowlist: true,
      },
    }));
    client.isMerchantAllowed.mockResolvedValue(false);

    await expect(client.pay(RECIPIENT, 1_000_000n)).rejects.toMatchObject({
      code: AgentErrorCode.POLICY_VIOLATION,
    });

    expect(client.assetsToShares).not.toHaveBeenCalled();
    expect(client.transfer).not.toHaveBeenCalled();
  });

  it("rejects payments that exceed available spend", async () => {
    const client = makeClient(makeStatus({ availableSpend: 999_999n }));

    await expect(client.pay(RECIPIENT, 1_000_000n)).rejects.toMatchObject({
      code: AgentErrorCode.POLICY_VIOLATION,
    });

    expect(client.assetsToShares).not.toHaveBeenCalled();
    expect(client.transfer).not.toHaveBeenCalled();
  });
});

describe("AgentClient previewEscrowSettlement()", () => {
  it("normalizes the settlement preview tuple to plain numbers and booleans", async () => {
    const client = Object.create(AgentClient.prototype) as AgentClient & {
      escrow: { previewSettlement: ReturnType<typeof vi.fn> };
    };

    client.escrow = {
      previewSettlement: vi.fn().mockResolvedValue({
        status: 1n,
        releaseAfterPassed: true,
        fulfillmentSubmitted: false,
        fulfillmentComplete: false,
        disputeActive: false,
        disputeResolved: false,
        disputeTimedOut: false,
        requiresArbiterResolution: false,
        canBuyerRelease: true,
        canMerchantRelease: false,
        canArbiterRelease: false,
        canBuyerRefund: true,
        canArbiterRefund: false,
        canArbiterResolve: false,
        buyerReleaseMode: 1n,
        merchantReleaseMode: 0n,
        arbiterReleaseMode: 0n,
        buyerRefundMode: 5n,
        arbiterRefundMode: 0n,
        requiredMilestones: 2n,
        completedMilestones: 1n,
        nextMilestoneNumber: 2n,
        disputedMilestone: 0n,
        challengeWindowEndsAt: 1_700_000_000n,
        disputeWindowEndsAt: 0n,
      }),
    };

    await expect(client.previewEscrowSettlement(1n)).resolves.toEqual({
      status: 1,
      releaseAfterPassed: true,
      fulfillmentSubmitted: false,
      fulfillmentComplete: false,
      disputeActive: false,
      disputeResolved: false,
      disputeTimedOut: false,
      requiresArbiterResolution: false,
      canBuyerRelease: true,
      canMerchantRelease: false,
      canArbiterRelease: false,
      canBuyerRefund: true,
      canArbiterRefund: false,
      canArbiterResolve: false,
      buyerReleaseMode: 1,
      merchantReleaseMode: 0,
      arbiterReleaseMode: 0,
      buyerRefundMode: 5,
      arbiterRefundMode: 0,
      requiredMilestones: 2,
      completedMilestones: 1,
      nextMilestoneNumber: 2,
      disputedMilestone: 0,
      challengeWindowEndsAt: 1_700_000_000,
      disputeWindowEndsAt: 0,
    });
  });
});

describe("AgentClient bridging", () => {
  it("previews bridge-outs to EVM addresses with route and capacity data", async () => {
    const client = Object.create(AgentClient.prototype) as AgentClient & {
      getSystemStatus: ReturnType<typeof vi.fn>;
      getShareBalance: ReturnType<typeof vi.fn>;
      bridge: {
        bridgePaused: ReturnType<typeof vi.fn>;
        trustedPeer: ReturnType<typeof vi.fn>;
        canBridge: ReturnType<typeof vi.fn>;
        outstandingShares: ReturnType<typeof vi.fn>;
        maxOutstandingShares: ReturnType<typeof vi.fn>;
        remainingMintCapacityShares: ReturnType<typeof vi.fn>;
      };
    };

    client.getSystemStatus = vi.fn().mockResolvedValue(makeSystemStatus());
    client.getShareBalance = vi.fn().mockResolvedValue(150n);
    client.bridge = {
      bridgePaused: vi.fn().mockResolvedValue(false),
      trustedPeer: vi.fn().mockResolvedValue(`0x${"1".repeat(64)}`),
      canBridge: vi.fn().mockResolvedValue(true),
      outstandingShares: vi.fn().mockResolvedValue(40n),
      maxOutstandingShares: vi.fn().mockResolvedValue(100n),
      remainingMintCapacityShares: vi.fn().mockResolvedValue(60n),
    };

    await expect(client.previewBridgeToAddress(42161, RECIPIENT, 100n)).resolves.toEqual({
      bridgePaused: false,
      bridgingAllowed: true,
      bridgeMintAllowed: true,
      outstandingShares: 40n,
      maxOutstandingShares: 100n,
      remainingMintCapacityShares: 60n,
      dstChain: 42161,
      recipient: RECIPIENT,
      recipientBytes32: zeroPadValue(RECIPIENT, 32),
      shares: 100n,
      assetsEquivalent: 200n,
      shareBalance: 150n,
      trustedPeer: `0x${"1".repeat(64)}`,
      routeTrusted: true,
      contractCanBridge: true,
      canBridgeNow: true,
    });
  });

  it("bridges shares to an address and returns the emitted message id", async () => {
    const iface = new Interface(wssdcCrossChainBridgeV2Abi);
    const recipientBytes32 = zeroPadValue(RECIPIENT, 32);
    const msgId = `0x${"b".repeat(64)}`;
    const event = iface.encodeEventLog(
      iface.getEvent("BridgeOut"),
      [msgId, "0x2000000000000000000000000000000000000002", 42161, recipientBytes32, 100n]
    );
    const receipt = {
      hash: "0xreceipt",
      logs: [{
        address: "0xbridge000000000000000000000000000000000000",
        topics: event.topics,
        data: event.data,
      }],
    };
    const client = Object.create(AgentClient.prototype) as AgentClient & {
      previewBridgeToAddress: ReturnType<typeof vi.fn>;
      assertSystemReady: ReturnType<typeof vi.fn>;
      bridge: {
        interface: Interface;
        bridgeOut: ReturnType<typeof vi.fn>;
      };
    };

    client.previewBridgeToAddress = vi.fn().mockResolvedValue({
      recipient: RECIPIENT,
      recipientBytes32,
      routeTrusted: true,
      contractCanBridge: true,
      shareBalance: 100n,
    });
    client.assertSystemReady = vi.fn().mockResolvedValue(undefined);
    client.bridge = {
      interface: iface,
      bridgeOut: vi.fn().mockResolvedValue({
        wait: vi.fn().mockResolvedValue(receipt),
      }),
    };

    await expect(client.bridgeToAddress(42161, RECIPIENT, 100n)).resolves.toEqual({
      txHash: "0xreceipt",
      msgId,
      dstChain: 42161,
      recipient: RECIPIENT,
      recipientBytes32,
      sharesBurned: 100n,
    });
  });

  it("rejects bridge-outs when the route preflight fails", async () => {
    const client = Object.create(AgentClient.prototype) as AgentClient & {
      previewBridgeOut: ReturnType<typeof vi.fn>;
      assertSystemReady: ReturnType<typeof vi.fn>;
    };

    client.previewBridgeOut = vi.fn().mockResolvedValue({
      recipient: `0x${"a".repeat(64)}`,
      recipientBytes32: `0x${"a".repeat(64)}`,
      routeTrusted: false,
      contractCanBridge: false,
      shareBalance: 100n,
    });
    client.assertSystemReady = vi.fn().mockResolvedValue(undefined);

    await expect(client.bridgeOut(42161, `0x${"a".repeat(64)}`, 100n)).rejects.toMatchObject({
      code: AgentErrorCode.BRIDGE_ROUTE_UNAVAILABLE,
    });
  });
});

describe("AgentClient settlement controls", () => {
  it("derives available settlement actions from preview plus escrow timeout config", async () => {
    const client = Object.create(AgentClient.prototype) as AgentClient & {
      previewEscrowSettlement: ReturnType<typeof vi.fn>;
      getEscrow: ReturnType<typeof vi.fn>;
    };
    const preview = makeSettlementPreview({
      canBuyerRelease: true,
      buyerReleaseMode: SettlementMode.BUYER_RELEASE,
      canArbiterRefund: true,
      arbiterRefundMode: SettlementMode.ARBITER_REFUND,
      canArbiterResolve: true,
      disputeTimedOut: true,
    });
    const escrow = makeEscrowInfo({
      timeoutResolution: DisputeResolution.REFUND,
    });

    client.previewEscrowSettlement = vi.fn().mockResolvedValue(preview);
    client.getEscrow = vi.fn().mockResolvedValue(escrow);

    const actions = await client.getSettlementActions(1n);

    const expectedActions: SettlementAction[] = [
      {
        type: "release",
        actor: "buyer",
        settlementMode: SettlementMode.BUYER_RELEASE,
      },
      {
        type: "refund",
        actor: "arbiter",
        settlementMode: SettlementMode.ARBITER_REFUND,
      },
      {
        type: "resolve_dispute",
        actor: "arbiter",
        resolution: DisputeResolution.RELEASE,
      },
      {
        type: "resolve_dispute",
        actor: "arbiter",
        resolution: DisputeResolution.REFUND,
      },
      {
        type: "execute_timeout",
        actor: "anyone",
        resolution: DisputeResolution.REFUND,
        settlementMode: SettlementMode.DISPUTE_TIMEOUT_REFUND,
      },
    ];

    expect(actions).toEqual(expectedActions);
  });

  it("resolves disputes only when the arbiter action is available", async () => {
    const client = Object.create(AgentClient.prototype) as AgentClient & {
      previewEscrowSettlement: ReturnType<typeof vi.fn>;
      escrow: { resolveDispute: ReturnType<typeof vi.fn> };
    };

    client.previewEscrowSettlement = vi.fn().mockResolvedValue(
      makeSettlementPreview({ canArbiterResolve: true })
    );
    client.escrow = {
      resolveDispute: vi.fn().mockResolvedValue({
        wait: vi.fn().mockResolvedValue({ hash: "0xresolve" }),
      }),
    };

    await expect(client.resolveEscrowDispute(
      7n,
      DisputeResolution.RELEASE,
      `0x${"a".repeat(64)}`
    )).resolves.toEqual({
      txHash: "0xresolve",
      resolution: DisputeResolution.RELEASE,
    });

    expect(client.escrow.resolveDispute).toHaveBeenCalledWith(
      7n,
      DisputeResolution.RELEASE,
      `0x${"a".repeat(64)}`
    );
  });

  it("rejects timeout execution when the dispute has not actually timed out", async () => {
    const client = Object.create(AgentClient.prototype) as AgentClient & {
      previewEscrowSettlement: ReturnType<typeof vi.fn>;
      getEscrow: ReturnType<typeof vi.fn>;
    };

    client.previewEscrowSettlement = vi.fn().mockResolvedValue(
      makeSettlementPreview({ disputeTimedOut: false })
    );
    client.getEscrow = vi.fn().mockResolvedValue(
      makeEscrowInfo({ timeoutResolution: DisputeResolution.REFUND })
    );

    await expect(client.executeEscrowTimeout(9n)).rejects.toMatchObject({
      code: AgentErrorCode.SETTLEMENT_ACTION_UNAVAILABLE,
    });
  });

  it("executes timeout settlements with the escrow-configured resolution", async () => {
    const client = Object.create(AgentClient.prototype) as AgentClient & {
      previewEscrowSettlement: ReturnType<typeof vi.fn>;
      getEscrow: ReturnType<typeof vi.fn>;
      escrow: { executeTimeout: ReturnType<typeof vi.fn> };
    };

    client.previewEscrowSettlement = vi.fn().mockResolvedValue(
      makeSettlementPreview({ disputeTimedOut: true })
    );
    client.getEscrow = vi.fn().mockResolvedValue(
      makeEscrowInfo({ timeoutResolution: DisputeResolution.RELEASE })
    );
    client.escrow = {
      executeTimeout: vi.fn().mockResolvedValue({
        wait: vi.fn().mockResolvedValue({ hash: "0xtimeout" }),
      }),
    };

    await expect(client.executeEscrowTimeout(11n)).resolves.toEqual({
      txHash: "0xtimeout",
      resolution: DisputeResolution.RELEASE,
      settlementMode: SettlementMode.DISPUTE_TIMEOUT_RELEASE,
    });
  });
});

describe("AgentClient createPaymentRequest()", () => {
  it("defaults non-fulfillment requests to FulfillmentType.NONE", async () => {
    const nowSpy = vi.spyOn(Date, "now").mockReturnValue(1_000_000);
    const client = Object.create(AgentClient.prototype) as AgentClient & {
      signer: { getAddress: ReturnType<typeof vi.fn> };
    };

    client.signer = {
      getAddress: vi.fn().mockResolvedValue(RECIPIENT),
    };

    await expect(client.createPaymentRequest({
      amount: 140n,
      description: "Immediate digital good",
      milestones: 0,
    })).resolves.toMatchObject({
      payee: RECIPIENT,
      amount: 140n,
      expiresAt: 4_600,
      terms: {
        assetsDue: 140n,
        expiry: 4_600,
        releaseAfter: 1_300,
        requiresFulfillment: false,
        fulfillmentType: FulfillmentType.NONE,
        requiredMilestones: 0,
      },
    });

    nowSpy.mockRestore();
  });

  it("uses no timeout resolution when both dispute windows are disabled", async () => {
    const nowSpy = vi.spyOn(Date, "now").mockReturnValue(1_000_000);
    const client = Object.create(AgentClient.prototype) as AgentClient & {
      signer: { getAddress: ReturnType<typeof vi.fn> };
    };

    client.signer = {
      getAddress: vi.fn().mockResolvedValue(RECIPIENT),
    };

    await expect(client.createPaymentRequest({
      amount: 140n,
      description: "No-dispute-window request",
      milestones: 0,
      challengeWindowSeconds: 0,
      arbiterDeadlineSeconds: 0,
    })).resolves.toMatchObject({
      terms: {
        challengeWindow: 0,
        arbiterDeadline: 0,
        disputeTimeoutResolution: DisputeResolution.NONE,
      },
    });

    nowSpy.mockRestore();
  });
});

describe("AgentClient payment request acceptance", () => {
  it("quotes payment acceptance using gateway-aligned shares and escrow principal", async () => {
    const nowSpy = vi.spyOn(Date, "now").mockReturnValue(950_000);
    const client = Object.create(AgentClient.prototype) as AgentClient & {
      vault: {
        convertToSharesInvoiceOrWithdraw: ReturnType<typeof vi.fn>;
        convertToAssets: ReturnType<typeof vi.fn>;
        previewMint: ReturnType<typeof vi.fn>;
      };
      navController: {
        nav0Ray: ReturnType<typeof vi.fn>;
        t0: ReturnType<typeof vi.fn>;
        ratePerSecondRay: ReturnType<typeof vi.fn>;
        maxStaleness: ReturnType<typeof vi.fn>;
      };
      assertSystemReady: ReturnType<typeof vi.fn>;
      assertSpendAllowed: ReturnType<typeof vi.fn>;
    };

    client.vault = {
      convertToSharesInvoiceOrWithdraw: vi.fn().mockResolvedValue(100n),
      convertToAssets: vi.fn().mockResolvedValue(150n),
      previewMint: vi.fn().mockResolvedValue(145n),
    };
    client.navController = {
      nav0Ray: vi.fn().mockResolvedValue(2n * RAY),
      t0: vi.fn().mockResolvedValue(900n),
      ratePerSecondRay: vi.fn().mockResolvedValue(0n),
      maxStaleness: vi.fn().mockResolvedValue(500n),
    };
    client.assertSystemReady = vi.fn().mockResolvedValue(undefined);
    client.assertSpendAllowed = vi.fn().mockResolvedValue(makeStatus());

    await expect(client.previewPaymentRequestAcceptance(makePaymentRequest())).resolves.toEqual({
      requestId: "pr_test",
      payee: RECIPIENT,
      assetsDue: 140n,
      principalAssetsSnapshot: 150n,
      estimatedAssetsIn: 145n,
      sharesLocked: 100n,
      projectedNavRay: 2n * RAY,
      estimatedYield: 50n,
      releaseAfter: 1_000,
      expiresAt: 2_000,
    });

    nowSpy.mockRestore();
  });

  it("rejects malformed requests before spending", async () => {
    const client = Object.create(AgentClient.prototype) as AgentClient;

    await expect(client.previewPaymentRequestAcceptance(
      makePaymentRequest({
        amount: 200n,
      })
    )).rejects.toMatchObject({
      code: AgentErrorCode.INVALID_PAYMENT_REQUEST,
    });
  });

  it("rejects payment requests whose share cap is already too low", async () => {
    const nowSpy = vi.spyOn(Date, "now").mockReturnValue(950_000);
    const client = Object.create(AgentClient.prototype) as AgentClient & {
      vault: {
        convertToSharesInvoiceOrWithdraw: ReturnType<typeof vi.fn>;
      };
      assertSystemReady: ReturnType<typeof vi.fn>;
      assertSpendAllowed: ReturnType<typeof vi.fn>;
    };

    client.vault = {
      convertToSharesInvoiceOrWithdraw: vi.fn().mockResolvedValue(101n),
    };
    client.assertSystemReady = vi.fn().mockResolvedValue(undefined);
    client.assertSpendAllowed = vi.fn().mockResolvedValue(makeStatus());

    await expect(client.previewPaymentRequestAcceptance(
      makePaymentRequest({
        terms: makeTerms({ maxSharesIn: 100n }),
      })
    )).rejects.toMatchObject({
      code: AgentErrorCode.INVALID_PAYMENT_REQUEST,
    });

    nowSpy.mockRestore();
  });

  it("accepts payments using the quoted max asset cap and quoted yield", async () => {
    const preview: PaymentAcceptancePreview = {
      requestId: "pr_test",
      payee: RECIPIENT,
      assetsDue: 140n,
      principalAssetsSnapshot: 150n,
      estimatedAssetsIn: 145n,
      sharesLocked: 100n,
      projectedNavRay: 2n * RAY,
      estimatedYield: 50n,
      releaseAfter: 1_000,
      expiresAt: 2_000,
    };
    const request = makePaymentRequest({ buyerBps: 2_000 });
    const client = Object.create(AgentClient.prototype) as AgentClient & {
      previewPaymentRequestAcceptance: ReturnType<typeof vi.fn>;
      fundEscrow: ReturnType<typeof vi.fn>;
    };

    client.previewPaymentRequestAcceptance = vi.fn().mockResolvedValue(preview);
    client.fundEscrow = vi.fn().mockResolvedValue({
      txHash: "0xescrow",
      escrowId: 77n,
      sharesLocked: 100n,
      assetsIn: 145n,
    });

    await expect(client.acceptPaymentRequest(request)).resolves.toEqual({
      requestId: "pr_test",
      escrowId: 77n,
      txHash: "0xescrow",
      sharesLocked: 100n,
      estimatedYield: 50n,
    });

    expect(client.fundEscrow).toHaveBeenCalledWith(
      RECIPIENT,
      request.terms,
      2_000,
      145n
    );
  });
});
