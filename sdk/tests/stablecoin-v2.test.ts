/**
 * @setchain/sdk - SSDC V2 ABI regression tests
 */

import { describe, expect, it } from "vitest";
import { Interface } from "ethers";
import { navControllerV2Abi, ssdcStatusLensV2Abi, yieldEscrowV2Abi } from "../src/stablecoin/v2/abis";
import type { SystemStatus } from "../src/stablecoin/v2/types";

describe("SSDC V2 ABI fragments", () => {
  it("exposes the full status lens tuple in contract order", () => {
    const iface = new Interface(ssdcStatusLensV2Abi);
    const fragment = iface.getFunction("getStatus");
    const components = fragment.outputs?.[0]?.components ?? [];

    expect(components.map((component) => `${component.type} ${component.name}`)).toEqual([
      "bool transfersAllowed",
      "bool navFresh",
      "bool navConversionsAllowed",
      "bool navUpdatesPaused",
      "bool mintDepositAllowed",
      "bool redeemWithdrawAllowed",
      "bool requestRedeemAllowed",
      "bool processQueueAllowed",
      "bool queueSkipsBlockedClaims",
      "bool bridgingAllowed",
      "bool bridgeMintAllowed",
      "bool gatewayRequired",
      "bool escrowOpsPaused",
      "bool paymasterPaused",
      "uint256 bridgeOutstandingShares",
      "uint256 bridgeOutstandingLimitShares",
      "uint256 bridgeRemainingCapacityShares",
      "uint256 minBridgeLiquidityCoverageBps",
      "uint256 liabilityAssets",
      "uint256 settlementAssetsAvailable",
      "uint256 queueBufferAvailable",
      "uint256 queueReservedAssets",
      "uint256 queueDepth",
      "uint256 liquidityCoverageBps",
      "uint256 navRay",
      "uint64 navEpoch",
      "uint40 navLastUpdate",
      "uint256 totalShareSupply",
      "address reserveManager",
      "uint256 reserveFloor",
      "uint256 reserveMaxDeployBps",
      "uint256 reserveDeployedAssets",
    ]);

    const sampleStatus: SystemStatus = {
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
      bridgeOutstandingShares: 0n,
      bridgeOutstandingLimitShares: 0n,
      bridgeRemainingCapacityShares: 0n,
      minBridgeLiquidityCoverageBps: 0n,
      liabilityAssets: 0n,
      settlementAssetsAvailable: 0n,
      queueBufferAvailable: 0n,
      queueReservedAssets: 0n,
      queueDepth: 0n,
      liquidityCoverageBps: 10_000n,
      navRay: 10n ** 27n,
      navEpoch: 1n,
      navLastUpdate: 0n,
      totalShareSupply: 0n,
      reserveManager: "0x0000000000000000000000000000000000000000",
      reserveFloor: 0n,
      reserveMaxDeployBps: 0n,
      reserveDeployedAssets: 0n,
    };

    expect(sampleStatus.reserveDeployedAssets).toBe(0n);
  });

  it("keeps the NAV rate signed for drawdown scenarios", () => {
    const iface = new Interface(navControllerV2Abi);
    const fragment = iface.getFunction("ratePerSecondRay");
    expect(fragment.outputs?.[0]?.type).toBe("int256");
  });

  it("matches the current escrow method names and signatures", () => {
    const iface = new Interface(yieldEscrowV2Abi);

    expect(iface.getFunction("submitFulfillment")?.format()).toBe(
      "submitFulfillment(uint256,uint8,bytes32)"
    );
    expect(iface.getFunction("refund")?.format()).toBe("refund(uint256)");
    expect(iface.getFunction("previewReleaseSplit")?.format()).toBe(
      "previewReleaseSplit(uint256)"
    );
    expect(iface.getFunction("escrowCompletedMilestones")?.format()).toBe(
      "escrowCompletedMilestones(uint256)"
    );
    expect(iface.getFunction("escrowRequiredMilestones")?.format()).toBe(
      "escrowRequiredMilestones(uint256)"
    );
  });
});
