// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2QuickstartBase} from "./SSDCV2QuickstartBase.sol";
import {YieldEscrowV2} from "../../../../stablecoin/v2/YieldEscrowV2.sol";
import {SSDCClaimQueueV2} from "../../../../stablecoin/v2/SSDCClaimQueueV2.sol";
import {SSDCStatusLensV2} from "../../../../stablecoin/v2/SSDCStatusLensV2.sol";

/// @title Quickstart 07: Advanced Agentic Commerce Scenarios
/// @notice Complex multi-step scenarios that combine multiple protocol features:
///
///   - Autonomous procurement pipeline (3 agents, 5 escrows, yield, gas, queue)
///   - Claim queue batch processing with skip-blocked mode
///   - Committed spend tracking across concurrent escrows
///   - Full StatusLens system health monitoring
///   - NAV-aware queue processing (shares appreciate before redemption)
///   - Escrow refund → re-purchase flow
///
///   Run:  forge test --match-contract AdvancedScenarios -vvv
contract AdvancedScenarios is SSDCV2QuickstartBase {

    function setUp() public override {
        super.setUp();

        _fundAgent(agentAlpha, 50_000 ether);
        _fundAgent(agentBeta, 30_000 ether);
        _fundAgent(agentGamma, 20_000 ether);

        address[] memory noMerchants = new address[](0);
        _configureAgent(
            agentAlpha, 10_000 ether, 40_000 ether, 2_000 ether,
            uint40(block.timestamp + 30 days), false, noMerchants
        );
        _configureAgent(
            agentBeta, 5_000 ether, 20_000 ether, 1_000 ether,
            uint40(block.timestamp + 30 days), false, noMerchants
        );
        _configureAgent(
            agentGamma, 3_000 ether, 10_000 ether, 500 ether,
            uint40(block.timestamp + 30 days), false, noMerchants
        );
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Autonomous procurement pipeline:
    //    Alpha orders from Beta (raw materials)
    //    Beta orders from Gamma (sub-components)
    //    Gamma fulfills -> Beta fulfills -> Alpha confirms
    //    NAV appreciates throughout -> yield split at each stage
    //    Everyone redeems profits via claim queue
    //
    //  Combines concepts from:
    //    - 02_MultiAgentMarketplace (supply chain, milestones)
    //    - 03_YieldAndNAV (yield splitting, NAV appreciation)
    //    - 01_AgentOnboarding (claim queue redemption)
    // ─────────────────────────────────────────────────────────────────────
    function test_AutonomousProcurementPipeline() public {
        // ── Stage 1: Alpha → Beta ($8,000 purchase order) ───────────────
        vm.startPrank(agentAlpha);
        vault.approve(address(escrow), type(uint256).max);
        uint256 poAlphaBeta = escrow.fundEscrow(
            agentBeta,
            _milestoneInvoice(8_000 ether, YieldEscrowV2.FulfillmentType.DELIVERY, 2, uint40(6 hours), uint40(5 days)),
            1_500 // 15% buyer yield share
        );
        vm.stopPrank();

        // ── Stage 2: Beta → Gamma ($3,000 sub-component order) ──────────
        vm.startPrank(agentBeta);
        vault.approve(address(escrow), type(uint256).max);
        uint256 poBetaGamma = escrow.fundEscrow(
            agentGamma,
            _milestoneInvoice(3_000 ether, YieldEscrowV2.FulfillmentType.DELIVERY, 1, uint40(4 hours), uint40(3 days)),
            1_000 // 10% buyer yield share
        );
        vm.stopPrank();

        // ── Stage 3: NAV appreciates (Treasury yield) ───────────────────
        vm.warp(block.timestamp + 3 days);
        _updateNAV(104e25); // 4% appreciation

        // ── Stage 4: Gamma fulfills sub-components ──────────────────────
        vm.prank(agentGamma);
        escrow.submitFulfillment(poBetaGamma, YieldEscrowV2.FulfillmentType.DELIVERY, keccak256("sub-components-shipped"));

        // Challenge window passes
        vm.warp(block.timestamp + 4 hours + 1);

        // Beta releases payment to Gamma (merchant timeout release)
        uint256 gammaBefore = vault.balanceOf(agentGamma);
        vm.prank(agentGamma);
        escrow.release(poBetaGamma);
        uint256 gammaReceived = vault.balanceOf(agentGamma) - gammaBefore;
        assertGt(gammaReceived, 0, "Gamma paid");

        // ── Stage 5: Beta fulfills Alpha's PO (2 milestones) ────────────
        vm.prank(agentBeta);
        escrow.submitFulfillment(poAlphaBeta, YieldEscrowV2.FulfillmentType.DELIVERY, keccak256("assembly-complete"));

        vm.warp(block.timestamp + 1 days);
        vm.prank(agentBeta);
        escrow.submitFulfillment(poAlphaBeta, YieldEscrowV2.FulfillmentType.DELIVERY, keccak256("qa-passed-shipped"));

        // ── Stage 6: More yield accrues ─────────────────────────────────
        vm.warp(block.timestamp + 2 days);
        _updateNAV(106e25); // 6% total appreciation

        // ── Stage 7: Challenge window passes, Beta claims payment ───────
        vm.warp(block.timestamp + 6 hours + 1);

        // Preview yield split before release
        // See 03_YieldAndNAV for detailed yield split math
        YieldEscrowV2.ReleaseSplit memory split = escrow.previewReleaseSplit(poAlphaBeta);
        assertGt(split.buyerYieldShares, 0, "Alpha earns buyer yield (15% of net)");
        assertGt(split.merchantYieldShares, 0, "Beta earns merchant yield (85% of net)");
        assertGt(split.feeShares, 0, "protocol earns 1% fee");
        assertGt(split.reserveShares, 0, "reserve earns 2% of gross");
        // Merchant should get ~85% of net yield (buyerBps = 1500 = 15%)
        assertGt(split.merchantYieldShares, split.buyerYieldShares, "merchant > buyer share");

        uint256 betaBefore = vault.balanceOf(agentBeta);
        vm.prank(agentBeta);
        escrow.release(poAlphaBeta);
        assertGt(vault.balanceOf(agentBeta), betaBefore, "Beta received principal + yield");

        // ── Stage 8: All agents redeem profits via claim queue ──────────
        _redeemViaQueue(agentAlpha, 5_000 ether);
        _redeemViaQueue(agentBeta, 5_000 ether);
        _redeemViaQueue(agentGamma, 5_000 ether);

        // All agents cashed out successfully
        assertGt(asset.balanceOf(agentAlpha), 0, "Alpha redeemed");
        assertGt(asset.balanceOf(agentBeta), 0, "Beta redeemed");
        assertGt(asset.balanceOf(agentGamma), 0, "Gamma redeemed");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Claim queue: batch processing with skip-blocked mode
    //
    //  See also: 01_AgentOnboarding test_07_RedeemProfits for basic queue usage
    // ─────────────────────────────────────────────────────────────────────
    function test_ClaimQueue_SkipBlocked() public {
        // First, drain the vault's settlement assets by deploying reserves.
        // This forces the queue to rely on the external buffer for redemptions.
        address reserveManager = address(0x7E5);
        vm.startPrank(admin);
        vault.setReserveConfig(reserveManager, 0, 10_000); // no floor, 100% deployable
        vault.deployReserve(98_000 ether); // leave only 2k liquid in vault
        vm.stopPrank();

        // All three agents request redemptions of different sizes
        vm.startPrank(agentAlpha);
        vault.approve(address(queue), type(uint256).max);
        queue.requestRedeem(10_000 ether, agentAlpha); // large
        vm.stopPrank();

        vm.startPrank(agentBeta);
        vault.approve(address(queue), type(uint256).max);
        uint256 claimB = queue.requestRedeem(500 ether, agentBeta); // small
        vm.stopPrank();

        vm.startPrank(agentGamma);
        vault.approve(address(queue), type(uint256).max);
        uint256 claimC = queue.requestRedeem(800 ether, agentGamma); // small
        vm.stopPrank();

        // Buffer has only $2,000 - not enough for Alpha's $10k claim (even combined
        // with the ~2k remaining in the vault, the total ~4k is short).
        // But the vault still has some liquidity, so we need a small buffer.
        asset.mint(admin, 2_000 ether);
        vm.startPrank(admin);
        asset.approve(address(queue), type(uint256).max);
        queue.refill(2_000 ether);
        vm.stopPrank();

        // Without skip-blocked, processing stops at Alpha's large claim
        // because vault + buffer cannot cover the full 10k
        vm.prank(admin);
        queue.processQueue(10);

        (,,,, SSDCClaimQueueV2.Status statusB1) = queue.claims(claimB);
        assertEq(uint256(statusB1), uint256(SSDCClaimQueueV2.Status.PENDING), "Beta still pending - blocked by Alpha");

        // Enable skip-blocked mode - small claims process even if large ones block
        vm.prank(admin);
        queue.setSkipBlockedClaims(true);

        // Refill more buffer for the small claims
        asset.mint(admin, 5_000 ether);
        vm.startPrank(admin);
        asset.approve(address(queue), type(uint256).max);
        queue.refill(5_000 ether);
        queue.processQueue(10);
        vm.stopPrank();

        // Beta and Gamma's small claims processed despite Alpha still blocked
        (,,,, SSDCClaimQueueV2.Status statusB2) = queue.claims(claimB);
        (,,,, SSDCClaimQueueV2.Status statusC2) = queue.claims(claimC);
        assertEq(uint256(statusB2), uint256(SSDCClaimQueueV2.Status.CLAIMABLE), "Beta processed");
        assertEq(uint256(statusC2), uint256(SSDCClaimQueueV2.Status.CLAIMABLE), "Gamma processed");

        // Beta and Gamma can claim
        vm.prank(agentBeta);
        queue.claim(claimB);
        vm.prank(agentGamma);
        queue.claim(claimC);

        assertGt(asset.balanceOf(agentBeta), 0);
        assertGt(asset.balanceOf(agentGamma), 0);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Escrow refund -> re-purchase: agent gets refund, places new order
    //
    //  See also: 05_DisputesAndSafety for dispute-driven refunds
    // ─────────────────────────────────────────────────────────────────────
    function test_RefundAndRepurchase() public {
        vm.startPrank(agentAlpha);
        vault.approve(address(escrow), type(uint256).max);

        // First order — will be refunded
        uint256 escrowId1 = escrow.fundEscrow(
            agentBeta,
            _milestoneInvoice(5_000 ether, YieldEscrowV2.FulfillmentType.DELIVERY, 1, uint40(4 hours), uint40(3 days)),
            0
        );
        vm.stopPrank();

        uint256 alphaAfterFirstOrder = vault.balanceOf(agentAlpha);

        // Alpha gets a refund (before fulfillment)
        vm.prank(agentAlpha);
        escrow.refund(escrowId1);

        uint256 alphaAfterRefund = vault.balanceOf(agentAlpha);
        assertGt(alphaAfterRefund, alphaAfterFirstOrder, "refund restored balance");

        // Alpha places a new order with a different merchant (Gamma)
        vm.prank(agentAlpha);
        uint256 escrowId2 = escrow.fundEscrow(
            agentGamma,
            _milestoneInvoice(4_000 ether, YieldEscrowV2.FulfillmentType.SERVICE, 1, uint40(2 hours), uint40(3 days)),
            0
        );

        // Gamma fulfills and Alpha releases
        vm.prank(agentGamma);
        escrow.submitFulfillment(escrowId2, YieldEscrowV2.FulfillmentType.SERVICE, keccak256("service-done"));

        vm.warp(block.timestamp + 1 hours);
        vm.prank(agentAlpha);
        escrow.release(escrowId2);

        (YieldEscrowV2.Escrow memory e1,,,) = escrow.getEscrow(escrowId1);
        (YieldEscrowV2.Escrow memory e2,,,) = escrow.getEscrow(escrowId2);
        assertEq(uint256(e1.status), uint256(YieldEscrowV2.EscrowStatus.REFUNDED));
        assertEq(uint256(e2.status), uint256(YieldEscrowV2.EscrowStatus.RELEASED));
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Full StatusLens snapshot: comprehensive system monitoring
    //
    //  See also: 01_AgentOnboarding test_01_CheckSystemHealth for basic lens usage
    //  See also: 05_DisputesAndSafety test_CircuitBreaker_EmergencyShutdown
    //            for lens state under circuit breaker
    // ─────────────────────────────────────────────────────────────────────
    function test_StatusLens_FullSnapshot() public {
        SSDCStatusLensV2.Status memory s = lens.getStatus();

        // ── Operational flags ───────────────────────────────────────────
        assertTrue(s.transfersAllowed);
        assertTrue(s.navFresh);
        assertTrue(s.navConversionsAllowed);
        assertFalse(s.navUpdatesPaused);
        assertTrue(s.mintDepositAllowed);
        assertTrue(s.redeemWithdrawAllowed);
        assertTrue(s.requestRedeemAllowed);
        assertTrue(s.processQueueAllowed);
        assertFalse(s.escrowOpsPaused);
        assertFalse(s.paymasterPaused);
        assertTrue(s.gatewayRequired);

        // ── NAV state ───────────────────────────────────────────────────
        assertEq(s.navRay, RAY, "NAV = 1.0");
        assertEq(s.navEpoch, 1, "initial epoch");
        assertGt(s.navLastUpdate, 0);

        // ── Vault state ─────────────────────────────────────────────────
        assertEq(s.totalShareSupply, 100_000 ether, "50k + 30k + 20k");
        assertEq(s.liabilityAssets, 100_000 ether, "liabilities match at par");
        assertEq(s.settlementAssetsAvailable, 100_000 ether, "fully liquid");
        assertEq(s.liquidityCoverageBps, 10_000, "100% coverage");

        // ── Queue state ─────────────────────────────────────────────────
        assertEq(s.queueBufferAvailable, 0, "no buffer refilled yet");
        assertEq(s.queueReservedAssets, 0);
        assertEq(s.queueDepth, 0, "no pending claims");

        // ── Bridge state ────────────────────────────────────────────────
        assertTrue(s.bridgingAllowed);
        assertEq(s.bridgeOutstandingShares, 0);

        // ── Reserve state ───────────────────────────────────────────────
        assertEq(s.reserveDeployedAssets, 0);
        assertEq(s.reserveFloor, 0);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  StatusLens after operations: shows real-time state changes
    // ─────────────────────────────────────────────────────────────────────
    function test_StatusLens_AfterOperations() public {
        // Create escrows, queue claims, deploy reserves
        vm.startPrank(agentAlpha);
        vault.approve(address(escrow), type(uint256).max);
        escrow.fundEscrow(agentBeta, _simpleInvoice(5_000 ether), 0);
        vm.stopPrank();

        vm.startPrank(agentBeta);
        vault.approve(address(queue), type(uint256).max);
        queue.requestRedeem(3_000 ether, agentBeta);
        vm.stopPrank();

        // Deploy reserves
        address reserveManager = address(0x7E5);
        vm.startPrank(admin);
        vault.setReserveConfig(reserveManager, 0, 10_000);
        vault.deployReserve(10_000 ether);
        vm.stopPrank();

        // NAV update
        _updateNAV(102e25); // 2% appreciation

        SSDCStatusLensV2.Status memory s = lens.getStatus();
        assertEq(s.navRay, 102e25, "NAV = 1.02");
        assertEq(s.queueDepth, 1, "one pending claim");
        assertEq(s.reserveDeployedAssets, 10_000 ether);
        assertEq(s.settlementAssetsAvailable, 90_000 ether, "100k - 10k deployed");
        assertLt(s.liquidityCoverageBps, 10_000, "coverage < 100% after reserve deploy");
    }

    // ── Helper ──────────────────────────────────────────────────────────

    function _redeemViaQueue(address agent, uint256 shares) internal {
        vm.startPrank(agent);
        vault.approve(address(queue), type(uint256).max);
        uint256 claimId = queue.requestRedeem(shares, agent);
        vm.stopPrank();

        asset.mint(admin, shares * 2);
        vm.startPrank(admin);
        asset.approve(address(queue), type(uint256).max);
        queue.refill(shares * 2);
        queue.processQueue(10);
        vm.stopPrank();

        vm.prank(agent);
        queue.claim(claimId);
    }
}
