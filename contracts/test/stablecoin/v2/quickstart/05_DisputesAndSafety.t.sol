// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2QuickstartBase} from "./SSDCV2QuickstartBase.sol";
import {YieldEscrowV2} from "../../../../stablecoin/v2/YieldEscrowV2.sol";
import {SSDCClaimQueueV2} from "../../../../stablecoin/v2/SSDCClaimQueueV2.sol";
import {SSDCStatusLensV2} from "../../../../stablecoin/v2/SSDCStatusLensV2.sol";
import {SSDCV2CircuitBreaker} from "../../../../stablecoin/v2/SSDCV2CircuitBreaker.sol";

/// @title Quickstart 05: Disputes, Circuit Breaker & Safety Mechanisms
/// @notice Covers the protocol's protection layers:
///   - Milestone disputes with evidence hashes
///   - Arbiter resolution (release or refund)
///   - Dispute timeout auto-resolution
///   - Circuit breaker emergency shutdown
///   - Selective recovery after circuit breaker
///   - Claim queue cancellation
///   - Grounding poke mechanism
///
///   Run:  forge test --match-contract DisputesAndSafety -vvv
contract DisputesAndSafety is SSDCV2QuickstartBase {

    function setUp() public override {
        super.setUp();
        _fundAgent(agentAlpha, 20_000 ether);
        _fundAgent(agentBeta, 10_000 ether);
        _configureAgent(
            agentAlpha, type(uint256).max, type(uint256).max, 100 ether,
            uint40(block.timestamp + 30 days), false, new address[](0)
        );
        _configureAgent(
            agentBeta, type(uint256).max, type(uint256).max, 100 ether,
            uint40(block.timestamp + 30 days), false, new address[](0)
        );
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Milestone dispute: buyer disputes specific milestone, arbiter
    //  resolves, payment released
    // ─────────────────────────────────────────────────────────────────────
    function test_MilestoneDispute_ArbiterRelease() public {
        // Alpha orders 3-milestone service from Beta
        vm.startPrank(agentAlpha);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(
            agentBeta,
            _milestoneInvoice(
                3_000 ether,
                YieldEscrowV2.FulfillmentType.SERVICE,
                3,
                uint40(6 hours),
                uint40(5 days)
            ),
            0
        );
        vm.stopPrank();

        // Beta completes milestones 1 & 2
        vm.prank(agentBeta);
        escrow.submitFulfillment(escrowId, YieldEscrowV2.FulfillmentType.SERVICE, keccak256("m1-done"));
        vm.prank(agentBeta);
        escrow.submitFulfillment(escrowId, YieldEscrowV2.FulfillmentType.SERVICE, keccak256("m2-done"));

        // Alpha disputes milestone 2 (quality issue)
        vm.prank(agentAlpha);
        escrow.disputeMilestone(
            escrowId,
            YieldEscrowV2.DisputeReason.QUALITY,
            2,   // dispute milestone #2
            keccak256("quality-issue-photos")
        );

        // Verify escrow is in disputed state
        (YieldEscrowV2.Escrow memory e,,,) = escrow.getEscrow(escrowId);
        assertTrue(e.disputed, "escrow disputed");
        assertEq(uint256(e.disputeReason), uint256(YieldEscrowV2.DisputeReason.QUALITY));

        // Arbiter reviews evidence and resolves in favor of merchant (release)
        vm.prank(arbiter);
        escrow.resolveDispute(
            escrowId,
            YieldEscrowV2.DisputeResolution.RELEASE,
            keccak256("arbiter-reviewed-quality-acceptable")
        );

        // Beta can now release despite the dispute
        vm.warp(block.timestamp + 1 hours);
        uint256 betaBefore = vault.balanceOf(agentBeta);
        vm.prank(agentBeta);
        escrow.release(escrowId);

        assertGt(vault.balanceOf(agentBeta), betaBefore, "Beta paid after arbiter release");

        (YieldEscrowV2.Escrow memory e2,,,) = escrow.getEscrow(escrowId);
        assertEq(uint256(e2.settlementMode), uint256(YieldEscrowV2.SettlementMode.ARBITER_RELEASE));
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Dispute timeout: arbiter misses deadline → auto-refund
    // ─────────────────────────────────────────────────────────────────────
    function test_DisputeTimeout_AutoRefund() public {
        vm.startPrank(agentAlpha);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(
            agentBeta,
            _milestoneInvoice(
                2_000 ether,
                YieldEscrowV2.FulfillmentType.DELIVERY,
                1,
                uint40(4 hours),
                uint40(3 days) // arbiter has 3 days
            ),
            0
        );
        vm.stopPrank();

        // Beta fulfills
        vm.prank(agentBeta);
        escrow.submitFulfillment(escrowId, YieldEscrowV2.FulfillmentType.DELIVERY, keccak256("shipped"));

        // Alpha disputes
        vm.prank(agentAlpha);
        escrow.dispute(escrowId, YieldEscrowV2.DisputeReason.NOT_AS_DESCRIBED, keccak256("wrong-item"));

        // Arbiter does nothing. 3 days pass.
        vm.warp(block.timestamp + 3 days + 1);

        // Anyone can trigger the timeout execution
        uint256 alphaBefore = vault.balanceOf(agentAlpha);
        escrow.executeTimeout(escrowId);

        assertGt(vault.balanceOf(agentAlpha), alphaBefore, "Alpha refunded via timeout");
        (YieldEscrowV2.Escrow memory e,,,) = escrow.getEscrow(escrowId);
        assertEq(uint256(e.settlementMode), uint256(YieldEscrowV2.SettlementMode.DISPUTE_TIMEOUT_REFUND));
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Settlement preview: inspect all possible actions before settling
    // ─────────────────────────────────────────────────────────────────────
    function test_SettlementPreview() public {
        vm.startPrank(agentAlpha);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(
            agentBeta,
            _milestoneInvoice(
                1_000 ether,
                YieldEscrowV2.FulfillmentType.DIGITAL,
                1,
                uint40(2 hours),
                uint40(3 days)
            ),
            0
        );
        vm.stopPrank();

        // Before fulfillment - preview shows buyer can refund but not release
        YieldEscrowV2.SettlementPreview memory p1 = escrow.previewSettlement(escrowId);
        assertEq(uint256(p1.status), uint256(YieldEscrowV2.EscrowStatus.FUNDED));
        assertFalse(p1.fulfillmentSubmitted);
        assertTrue(p1.canBuyerRefund, "buyer can refund before fulfillment");
        assertFalse(p1.canMerchantRelease, "merchant can't release without fulfillment");

        // After fulfillment - preview shows merchant can release after challenge window
        vm.prank(agentBeta);
        escrow.submitFulfillment(escrowId, YieldEscrowV2.FulfillmentType.DIGITAL, keccak256("key"));

        vm.warp(block.timestamp + 2 hours + 1);
        YieldEscrowV2.SettlementPreview memory p2 = escrow.previewSettlement(escrowId);
        assertTrue(p2.fulfillmentComplete, "all milestones done");
        assertTrue(p2.canMerchantRelease, "merchant can claim after challenge window");
        assertTrue(p2.canBuyerRelease, "buyer can also release");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Circuit breaker: emergency shutdown of all subsystems
    // ─────────────────────────────────────────────────────────────────────
    function test_CircuitBreaker_EmergencyShutdown() public {
        // Verify system is healthy
        SSDCStatusLensV2.Status memory before = lens.getStatus();
        assertTrue(before.mintDepositAllowed);
        assertFalse(before.escrowOpsPaused);
        assertFalse(before.paymasterPaused);

        // ── Trip the breaker ────────────────────────────────────────────
        vm.prank(admin);
        breaker.tripBreaker();

        assertTrue(breaker.breakerTripped(), "breaker is tripped");

        // All operations should now be blocked
        SSDCStatusLensV2.Status memory after_ = lens.getStatus();
        assertFalse(after_.mintDepositAllowed, "deposits blocked");
        assertTrue(after_.escrowOpsPaused, "escrow blocked");
        assertTrue(after_.paymasterPaused, "paymaster blocked");
        assertTrue(after_.navUpdatesPaused, "NAV updates blocked");

        // Escrow funding fails
        vm.startPrank(agentAlpha);
        vault.approve(address(escrow), type(uint256).max);
        vm.expectRevert(YieldEscrowV2.ESCROW_OPS_PAUSED.selector);
        escrow.fundEscrow(agentBeta, _simpleInvoice(100 ether), 0);
        vm.stopPrank();

        // ── Reset the breaker ───────────────────────────────────────────
        vm.prank(admin);
        breaker.resetBreaker();

        assertFalse(breaker.breakerTripped());

        // System is operational again
        SSDCStatusLensV2.Status memory recovered = lens.getStatus();
        assertTrue(recovered.mintDepositAllowed, "deposits restored");
        assertFalse(recovered.escrowOpsPaused, "escrow restored");
        assertFalse(recovered.paymasterPaused, "paymaster restored");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Circuit breaker selective recovery: doesn't undo manual pauses
    // ─────────────────────────────────────────────────────────────────────
    function test_CircuitBreaker_SelectiveRecovery() public {
        // Admin manually pauses escrow before the breaker trip
        vm.prank(admin);
        escrow.setEscrowOpsPaused(true);

        // Trip breaker - records that escrow was ALREADY paused
        vm.prank(admin);
        breaker.tripBreaker();

        assertTrue(breaker.escrowWasPaused(), "escrow was already paused");
        assertFalse(breaker.vaultWasPaused(), "vault was NOT already paused");

        // Reset breaker - escrow stays paused (it was manually paused)
        vm.prank(admin);
        breaker.resetBreaker();

        assertTrue(escrow.escrowOpsPaused(), "escrow still paused - manual pause preserved");
        assertFalse(vault.mintRedeemPaused(), "vault unpaused - breaker-caused pause cleared");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Claim queue cancellation: agent cancels pending redemption
    // ─────────────────────────────────────────────────────────────────────
    function test_ClaimQueueCancellation() public {
        vm.startPrank(agentBeta);
        vault.approve(address(queue), type(uint256).max);
        uint256 claimId = queue.requestRedeem(2_000 ether, agentBeta);
        vm.stopPrank();

        // Beta's shares are locked in the queue
        uint256 betaSharesAfterRequest = vault.balanceOf(agentBeta);

        // Beta changes their mind - cancel the redemption
        vm.prank(agentBeta);
        queue.cancel(claimId, agentBeta);

        // Shares returned to Beta
        assertEq(vault.balanceOf(agentBeta), betaSharesAfterRequest + 2_000 ether);

        // Claim is now cancelled
        (,,,, SSDCClaimQueueV2.Status claimStatus) = queue.claims(claimId);
        assertEq(uint256(claimStatus), uint256(SSDCClaimQueueV2.Status.CANCELLED));
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Grounding poke: manual collateral status update
    // ─────────────────────────────────────────────────────────────────────
    function test_GroundingPoke() public {
        // Gamma starts above collateral floor, then we transfer shares
        // directly (not via escrow) to push below floor without triggering
        // the escrow's own floor check.
        _fundAgent(agentGamma, 1_000 ether);
        _configureAgent(
            agentGamma, type(uint256).max, type(uint256).max, 500 ether,
            uint40(block.timestamp + 30 days), false, new address[](0)
        );
        assertFalse(grounding.isGroundedNow(agentGamma));
        assertFalse(grounding.isGrounded(agentGamma), "flag not set yet");

        // Transfer shares out directly (simulates agent spending via a different path).
        // This bypasses escrow floor checks, leaving Gamma undercollateralized.
        vm.prank(agentGamma);
        vault.transfer(agentBeta, 600 ether);

        // Gamma now has 400 shares < 500 floor
        assertTrue(grounding.isGroundedNow(agentGamma), "below floor in real-time");

        // Poke updates the stored flag
        grounding.poke(agentGamma);
        assertTrue(grounding.isGrounded(agentGamma), "flag updated via poke");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Multi-dispute scenario: two active escrows, different outcomes
    // ─────────────────────────────────────────────────────────────────────
    function test_MultiDispute_DifferentOutcomes() public {
        vm.startPrank(agentAlpha);
        vault.approve(address(escrow), type(uint256).max);

        // Escrow A: Alpha buys digital goods from Beta
        uint256 escrowA = escrow.fundEscrow(
            agentBeta,
            _milestoneInvoice(1_000 ether, YieldEscrowV2.FulfillmentType.DIGITAL, 1, uint40(2 hours), uint40(3 days)),
            0
        );

        // Escrow B: Alpha buys physical goods from Beta
        uint256 escrowB = escrow.fundEscrow(
            agentBeta,
            _milestoneInvoice(2_000 ether, YieldEscrowV2.FulfillmentType.DELIVERY, 1, uint40(4 hours), uint40(5 days)),
            0
        );
        vm.stopPrank();

        // Beta fulfills both
        vm.prank(agentBeta);
        escrow.submitFulfillment(escrowA, YieldEscrowV2.FulfillmentType.DIGITAL, keccak256("digital-ok"));
        vm.prank(agentBeta);
        escrow.submitFulfillment(escrowB, YieldEscrowV2.FulfillmentType.DELIVERY, keccak256("package-delivered"));

        // Alpha disputes both for different reasons
        vm.prank(agentAlpha);
        escrow.dispute(escrowA, YieldEscrowV2.DisputeReason.NOT_AS_DESCRIBED, keccak256("wrong-digital-product"));
        vm.prank(agentAlpha);
        escrow.dispute(escrowB, YieldEscrowV2.DisputeReason.QUALITY, keccak256("damaged-in-transit"));

        // Arbiter resolves:
        //   Escrow A → RELEASE (digital product was actually correct)
        //   Escrow B → REFUND (physical goods were damaged)
        vm.startPrank(arbiter);
        escrow.resolveDispute(escrowA, YieldEscrowV2.DisputeResolution.RELEASE, keccak256("product-verified"));
        escrow.resolveDispute(escrowB, YieldEscrowV2.DisputeResolution.REFUND, keccak256("damage-confirmed"));
        vm.stopPrank();

        // Settle both
        vm.warp(block.timestamp + 1 hours);

        vm.prank(agentBeta);
        escrow.release(escrowA); // merchant gets paid

        vm.prank(agentAlpha);
        escrow.refund(escrowB); // buyer gets refund

        (YieldEscrowV2.Escrow memory eA,,,) = escrow.getEscrow(escrowA);
        (YieldEscrowV2.Escrow memory eB,,,) = escrow.getEscrow(escrowB);
        assertEq(uint256(eA.status), uint256(YieldEscrowV2.EscrowStatus.RELEASED));
        assertEq(uint256(eB.status), uint256(YieldEscrowV2.EscrowStatus.REFUNDED));
        assertEq(uint256(eA.settlementMode), uint256(YieldEscrowV2.SettlementMode.ARBITER_RELEASE));
        assertEq(uint256(eB.settlementMode), uint256(YieldEscrowV2.SettlementMode.ARBITER_REFUND));
    }
}
