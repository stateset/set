// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2TestBase} from "./SSDCV2TestBase.sol";
import {GroundingRegistryV2} from "../../../stablecoin/v2/GroundingRegistryV2.sol";
import {NAVControllerV2} from "../../../stablecoin/v2/NAVControllerV2.sol";
import {SSDCPolicyModuleV2} from "../../../stablecoin/v2/SSDCPolicyModuleV2.sol";
import {YieldEscrowV2} from "../../../stablecoin/v2/YieldEscrowV2.sol";
import {wSSDCVaultV2} from "../../../stablecoin/v2/wSSDCVaultV2.sol";

contract YieldEscrowV2Test is SSDCV2TestBase {
    YieldEscrowV2 internal escrow;
    SSDCPolicyModuleV2 internal policy;
    GroundingRegistryV2 internal grounding;

    struct EscrowView {
        address buyer;
        address merchant;
        address refundRecipient;
        uint256 sharesHeld;
        uint256 principalAssetsSnapshot;
        uint256 committedAssets;
        uint40 releaseAfter;
        uint16 buyerBps;
        YieldEscrowV2.EscrowStatus status;
        bool requiresFulfillment;
        YieldEscrowV2.FulfillmentType fulfillmentType;
        bool disputed;
        YieldEscrowV2.DisputeReason disputeReason;
        uint40 fulfilledAt;
        bytes32 fulfillmentEvidence;
        YieldEscrowV2.DisputeResolution resolution;
        uint40 resolvedAt;
        bytes32 resolutionEvidence;
        uint40 challengeWindow;
        uint40 arbiterDeadline;
        YieldEscrowV2.DisputeResolution timeoutResolution;
        uint40 disputedAt;
        YieldEscrowV2.SettlementMode settlementMode;
        uint40 settledAt;
    }

    function setUp() public override {
        super.setUp();
        vm.startPrank(admin);
        policy = new SSDCPolicyModuleV2(admin);
        grounding = new GroundingRegistryV2(policy, nav, vault, admin);
        escrow = new YieldEscrowV2(vault, nav, policy, grounding, admin, user3);
        policy.grantRole(policy.POLICY_CONSUMER_ROLE(), address(escrow));
        escrow.grantRole(escrow.FUNDER_ROLE(), user2);
        policy.setPolicy(
            user1,
            type(uint256).max,
            type(uint256).max,
            0,
            uint40(block.timestamp + 7 days),
            false
        );
        vm.stopPrank();
    }

    function test_ConstructorRejectsZeroDependencies() public {
        vm.expectRevert(YieldEscrowV2.ZeroAddress.selector);
        new YieldEscrowV2(wSSDCVaultV2(address(0)), nav, policy, grounding, admin, user3);

        vm.expectRevert(YieldEscrowV2.ZeroAddress.selector);
        new YieldEscrowV2(vault, NAVControllerV2(address(0)), policy, grounding, admin, user3);
    }

    function _readEscrow(uint256 escrowId) internal view returns (EscrowView memory escrowView) {
        (
            address buyer,
            address merchant,
            address refundRecipient,
            uint256 sharesHeld,
            uint256 principalAssetsSnapshot,
            uint256 committedAssets,
            uint40 releaseAfter,
            uint16 buyerBps,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
        ) = escrow.escrows(escrowId);
        escrowView.buyer = buyer;
        escrowView.merchant = merchant;
        escrowView.refundRecipient = refundRecipient;
        escrowView.sharesHeld = sharesHeld;
        escrowView.principalAssetsSnapshot = principalAssetsSnapshot;
        escrowView.committedAssets = committedAssets;
        escrowView.releaseAfter = releaseAfter;
        escrowView.buyerBps = buyerBps;
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            YieldEscrowV2.EscrowStatus status,
            bool requiresFulfillment,
            YieldEscrowV2.FulfillmentType fulfillmentType,
            bool disputed,
            YieldEscrowV2.DisputeReason disputeReason,
            uint40 fulfilledAt,
            bytes32 fulfillmentEvidence,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
        ) = escrow.escrows(escrowId);
        escrowView.status = status;
        escrowView.requiresFulfillment = requiresFulfillment;
        escrowView.fulfillmentType = fulfillmentType;
        escrowView.disputed = disputed;
        escrowView.disputeReason = disputeReason;
        escrowView.fulfilledAt = fulfilledAt;
        escrowView.fulfillmentEvidence = fulfillmentEvidence;
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            YieldEscrowV2.DisputeResolution resolution,
            uint40 resolvedAt,
            bytes32 resolutionEvidence,
            uint40 challengeWindow,
            uint40 arbiterDeadline,
            YieldEscrowV2.DisputeResolution timeoutResolution,
            uint40 disputedAt,
            YieldEscrowV2.SettlementMode settlementMode,
            uint40 settledAt
        ) = escrow.escrows(escrowId);
        escrowView.resolution = resolution;
        escrowView.resolvedAt = resolvedAt;
        escrowView.resolutionEvidence = resolutionEvidence;
        escrowView.challengeWindow = challengeWindow;
        escrowView.arbiterDeadline = arbiterDeadline;
        escrowView.timeoutResolution = timeoutResolution;
        escrowView.disputedAt = disputedAt;
        escrowView.settlementMode = settlementMode;
        escrowView.settledAt = settledAt;
    }

    function test_FundEscrowForUsesBuyerPolicyAndStoresBuyer() public {
        _mintAndDeposit(user1, 100 ether);
        _mintAndDeposit(user2, 100 ether);

        vm.prank(admin);
        policy.setPolicy(user1, type(uint256).max, type(uint256).max, 0, uint40(block.timestamp + 7 days), false);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: 0,
            arbiterDeadline: 0,
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user2);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrowFor(user1, user2, user3, terms, 1_500);
        vm.stopPrank();

        EscrowView memory stored = _readEscrow(escrowId);
        assertEq(stored.buyer, user1);
        assertEq(stored.merchant, user3);
        assertEq(stored.refundRecipient, user2);
        assertEq(stored.sharesHeld, 40 ether);
        assertEq(stored.committedAssets, 40 ether);
        assertEq(stored.releaseAfter, block.timestamp);
        assertEq(stored.buyerBps, 1_500);
        assertEq(uint8(stored.status), uint8(YieldEscrowV2.EscrowStatus.FUNDED));
        assertFalse(stored.requiresFulfillment);
        assertEq(uint8(stored.fulfillmentType), uint8(YieldEscrowV2.FulfillmentType.NONE));
        assertFalse(stored.disputed);
        assertEq(uint8(stored.disputeReason), uint8(YieldEscrowV2.DisputeReason.NONE));
        assertEq(stored.fulfilledAt, 0);
        assertEq(stored.fulfillmentEvidence, bytes32(0));
        assertEq(uint8(stored.resolution), uint8(YieldEscrowV2.DisputeResolution.NONE));
        assertEq(stored.resolvedAt, 0);
        assertEq(stored.resolutionEvidence, bytes32(0));
        assertEq(stored.challengeWindow, 0);
        assertEq(stored.arbiterDeadline, 0);
        assertEq(uint8(stored.timeoutResolution), uint8(YieldEscrowV2.DisputeResolution.NONE));
        assertEq(stored.disputedAt, 0);
        assertEq(uint8(stored.settlementMode), uint8(YieldEscrowV2.SettlementMode.NONE));
        assertEq(stored.settledAt, 0);
        assertEq(policy.getCommittedAssets(user1), 40 ether);
    }

    function test_FundEscrowRevertsWhenMerchantZero() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 10 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: 0,
            arbiterDeadline: 0,
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        vm.expectRevert(YieldEscrowV2.INVALID_MERCHANT.selector);
        escrow.fundEscrow(address(0), terms, 0);
        vm.stopPrank();
    }

    function test_FundEscrowForRevertsWhenRefundRecipientZero() public {
        _mintAndDeposit(user2, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 10 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: 0,
            arbiterDeadline: 0,
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user2);
        vault.approve(address(escrow), type(uint256).max);
        vm.expectRevert(YieldEscrowV2.INVALID_REFUND_RECIPIENT.selector);
        escrow.fundEscrowFor(user1, address(0), user3, terms, 0);
        vm.stopPrank();
    }

    function test_FundEscrowRevertsWhenPolicyBlocksSpend() public {
        _mintAndDeposit(user1, 100 ether);

        vm.prank(admin);
        policy.setPolicy(user1, 50 ether, type(uint256).max, 0, uint40(block.timestamp + 7 days), false);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 100 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: 0,
            arbiterDeadline: 0,
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_LIMIT.selector);
        escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();
    }

    function test_FundEscrowRevertsWhenSelfFundingBreaksFloor() public {
        _mintAndDeposit(user1, 100 ether);

        vm.prank(admin);
        policy.setPolicy(user1, type(uint256).max, type(uint256).max, 60 ether, uint40(block.timestamp + 7 days), false);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 50 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: 0,
            arbiterDeadline: 0,
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        vm.expectRevert(YieldEscrowV2.FLOOR.selector);
        escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();
    }

    function test_FundEscrowForSponsoredFundingReservesCommittedFloor() public {
        _mintAndDeposit(user1, 100 ether);
        _mintAndDeposit(user2, 100 ether);

        vm.prank(admin);
        policy.setPolicy(user1, type(uint256).max, type(uint256).max, 40 ether, uint40(block.timestamp + 7 days), false);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 50 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: 0,
            arbiterDeadline: 0,
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user2);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrowFor(user1, user2, user3, terms, 0);
        vm.stopPrank();

        EscrowView memory stored = _readEscrow(escrowId);
        assertEq(stored.refundRecipient, user2);
        assertEq(stored.sharesHeld, 50 ether);
        assertEq(stored.committedAssets, 50 ether);
        assertEq(stored.releaseAfter, terms.releaseAfter);
        assertEq(uint8(stored.status), uint8(YieldEscrowV2.EscrowStatus.FUNDED));
        assertFalse(stored.requiresFulfillment);
        assertEq(uint8(stored.fulfillmentType), uint8(YieldEscrowV2.FulfillmentType.NONE));
        assertFalse(stored.disputed);
        assertEq(uint8(stored.disputeReason), uint8(YieldEscrowV2.DisputeReason.NONE));
        assertEq(stored.fulfilledAt, 0);
        assertEq(stored.fulfillmentEvidence, bytes32(0));
        assertEq(uint8(stored.resolution), uint8(YieldEscrowV2.DisputeResolution.NONE));
        assertEq(stored.resolvedAt, 0);
        assertEq(stored.resolutionEvidence, bytes32(0));
        assertEq(stored.challengeWindow, 0);
        assertEq(stored.arbiterDeadline, 0);
        assertEq(stored.disputedAt, 0);
        assertEq(uint8(stored.settlementMode), uint8(YieldEscrowV2.SettlementMode.NONE));
        assertEq(stored.settledAt, 0);
        assertEq(policy.getCommittedAssets(user1), 50 ether);

        (, uint256 floor, ) = grounding.currentAssets(user1);
        assertEq(floor, 90 ether);
        assertFalse(grounding.isGroundedNow(user1));
    }

    function test_FundEscrowForSponsoredFundingRevertsWhenCommitmentBreaksFloor() public {
        _mintAndDeposit(user1, 100 ether);
        _mintAndDeposit(user2, 100 ether);

        vm.prank(admin);
        policy.setPolicy(user1, type(uint256).max, type(uint256).max, 60 ether, uint40(block.timestamp + 7 days), false);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 50 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: 0,
            arbiterDeadline: 0,
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user2);
        vault.approve(address(escrow), type(uint256).max);
        vm.expectRevert(YieldEscrowV2.FLOOR.selector);
        escrow.fundEscrowFor(user1, user2, user3, terms, 0);
        vm.stopPrank();
    }

    function test_ReleaseReserveTakesFirstSliceBeforeFeeAndBuyerYield() public {
        _mintAndDeposit(user1, 2_000 ether);

        vm.startPrank(admin);
        escrow.setProtocolFee(1_000, user3);
        escrow.setReserveConfig(2_500, admin);
        vm.stopPrank();

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 1_000 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: 0,
            arbiterDeadline: 0,
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 2_000);
        vm.stopPrank();

        uint64 nextEpoch = nav.navEpoch() + 1;
        vm.prank(admin);
        nav.relayNAV(12e26, uint40(block.timestamp), 0, nextEpoch);

        YieldEscrowV2.ReleaseSplit memory split = escrow.previewReleaseSplit(escrowId);

        uint256 expectedPrincipal = vault.convertToSharesInvoiceOrWithdraw(1_000 ether);
        if (expectedPrincipal > 1_000 ether) {
            expectedPrincipal = 1_000 ether;
        }
        uint256 expectedGrossYield = 1_000 ether - expectedPrincipal;
        uint256 expectedReserve = (expectedGrossYield * 2_500) / 10_000;
        uint256 expectedAfterReserve = expectedGrossYield - expectedReserve;
        uint256 expectedFee = (expectedAfterReserve * 1_000) / 10_000;
        uint256 expectedNetYield = expectedAfterReserve - expectedFee;
        uint256 expectedBuyerYield = (expectedNetYield * 2_000) / 10_000;
        uint256 expectedMerchantYield = expectedNetYield - expectedBuyerYield;

        assertEq(split.totalShares, 1_000 ether);
        assertEq(split.principalShares, expectedPrincipal);
        assertEq(split.grossYieldShares, expectedGrossYield);
        assertEq(split.reserveShares, expectedReserve);
        assertEq(split.feeShares, expectedFee);
        assertEq(split.buyerYieldShares, expectedBuyerYield);
        assertEq(split.merchantYieldShares, expectedMerchantYield);

        uint256 buyerBefore = vault.balanceOf(user1);
        uint256 merchantBefore = vault.balanceOf(user2);
        uint256 reserveBefore = vault.balanceOf(admin);
        uint256 feeBefore = vault.balanceOf(user3);

        vm.prank(user1);
        escrow.release(escrowId);

        assertEq(vault.balanceOf(user1) - buyerBefore, split.buyerYieldShares);
        assertEq(vault.balanceOf(user2) - merchantBefore, split.principalShares + split.merchantYieldShares);
        assertEq(vault.balanceOf(admin) - reserveBefore, split.reserveShares);
        assertEq(vault.balanceOf(user3) - feeBefore, split.feeShares);
    }

    function test_PreviewSettlementShowsFulfillmentChallengeFlow() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 1,
            challengeWindow: uint40(6 hours),
            arbiterDeadline: uint40(7 days),
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.REFUND
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();

        YieldEscrowV2.SettlementPreview memory preview = escrow.previewSettlement(escrowId);
        assertEq(uint8(preview.status), uint8(YieldEscrowV2.EscrowStatus.FUNDED));
        assertTrue(preview.releaseAfterPassed);
        assertFalse(preview.fulfillmentSubmitted);
        assertFalse(preview.fulfillmentComplete);
        assertFalse(preview.disputeActive);
        assertFalse(preview.disputeResolved);
        assertFalse(preview.disputeTimedOut);
        assertFalse(preview.requiresArbiterResolution);
        assertFalse(preview.canBuyerRelease);
        assertFalse(preview.canMerchantRelease);
        assertTrue(preview.canArbiterRelease);
        assertTrue(preview.canBuyerRefund);
        assertTrue(preview.canArbiterRefund);
        assertFalse(preview.canArbiterResolve);
        assertEq(uint8(preview.arbiterReleaseMode), uint8(YieldEscrowV2.SettlementMode.ARBITER_RELEASE));
        assertEq(uint8(preview.buyerRefundMode), uint8(YieldEscrowV2.SettlementMode.BUYER_REFUND));
        assertEq(uint8(preview.arbiterRefundMode), uint8(YieldEscrowV2.SettlementMode.ARBITER_REFUND));
        assertEq(preview.requiredMilestones, 1);
        assertEq(preview.completedMilestones, 0);
        assertEq(preview.nextMilestoneNumber, 1);
        assertEq(preview.disputedMilestone, 0);
        assertEq(preview.challengeWindowEndsAt, 0);
        assertEq(preview.disputeWindowEndsAt, 0);

        vm.prank(user2);
        escrow.submitFulfillment(escrowId, YieldEscrowV2.FulfillmentType.DELIVERY, keccak256("delivery-proof"));

        preview = escrow.previewSettlement(escrowId);
        assertTrue(preview.fulfillmentSubmitted);
        assertTrue(preview.fulfillmentComplete);
        assertTrue(preview.canBuyerRelease);
        assertFalse(preview.canMerchantRelease);
        assertTrue(preview.canArbiterRelease);
        assertFalse(preview.canBuyerRefund);
        assertTrue(preview.canArbiterRefund);
        assertEq(uint8(preview.buyerReleaseMode), uint8(YieldEscrowV2.SettlementMode.BUYER_RELEASE));
        assertEq(uint8(preview.arbiterReleaseMode), uint8(YieldEscrowV2.SettlementMode.ARBITER_RELEASE));
        assertEq(uint8(preview.arbiterRefundMode), uint8(YieldEscrowV2.SettlementMode.ARBITER_REFUND));
        assertEq(preview.requiredMilestones, 1);
        assertEq(preview.completedMilestones, 1);
        assertEq(preview.nextMilestoneNumber, 0);
        assertEq(preview.disputedMilestone, 0);
        assertEq(preview.challengeWindowEndsAt, uint40(block.timestamp + 6 hours));
        assertEq(preview.disputeWindowEndsAt, 0);

        vm.warp(block.timestamp + 6 hours);

        preview = escrow.previewSettlement(escrowId);
        assertTrue(preview.canMerchantRelease);
        assertEq(uint8(preview.merchantReleaseMode), uint8(YieldEscrowV2.SettlementMode.MERCHANT_TIMEOUT_RELEASE));
        assertEq(preview.challengeWindowEndsAt, uint40(block.timestamp));
    }

    function test_PreviewSettlementTracksMilestoneProgressBeforeFinalFulfillment() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 2,
            challengeWindow: uint40(6 hours),
            arbiterDeadline: uint40(7 days),
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.REFUND
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();

        vm.prank(user2);
        escrow.submitFulfillment(escrowId, YieldEscrowV2.FulfillmentType.DELIVERY, keccak256("delivery-proof-1"));

        YieldEscrowV2.SettlementPreview memory preview = escrow.previewSettlement(escrowId);
        assertTrue(preview.fulfillmentSubmitted);
        assertFalse(preview.fulfillmentComplete);
        assertEq(preview.requiredMilestones, 2);
        assertEq(preview.completedMilestones, 1);
        assertEq(preview.nextMilestoneNumber, 2);
        assertEq(preview.disputedMilestone, 0);
        assertFalse(preview.canBuyerRelease);
        assertTrue(preview.canBuyerRefund);
        assertEq(preview.challengeWindowEndsAt, 0);
        assertEq(escrow.escrowCompletedMilestones(escrowId), 1);

        vm.prank(user1);
        vm.expectRevert(YieldEscrowV2.FULFILLMENT_PENDING.selector);
        escrow.release(escrowId);

        vm.warp(block.timestamp + 1 hours);
        vm.prank(user2);
        escrow.submitFulfillment(escrowId, YieldEscrowV2.FulfillmentType.DELIVERY, keccak256("delivery-proof-2"));

        preview = escrow.previewSettlement(escrowId);
        assertTrue(preview.fulfillmentComplete);
        assertEq(preview.requiredMilestones, 2);
        assertEq(preview.completedMilestones, 2);
        assertEq(preview.nextMilestoneNumber, 0);
        assertEq(preview.disputedMilestone, 0);
        assertTrue(preview.canBuyerRelease);
        assertFalse(preview.canBuyerRefund);
        assertEq(preview.challengeWindowEndsAt, uint40(block.timestamp + 6 hours));
        assertEq(escrow.escrowRequiredMilestones(escrowId), 2);
        assertEq(escrow.escrowCompletedMilestones(escrowId), 2);

        EscrowView memory stored = _readEscrow(escrowId);
        assertEq(stored.fulfilledAt, block.timestamp);
    }

    function test_PreviewSettlementShowsPendingAndTimedOutDisputeRefundPath() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: uint40(6 hours),
            arbiterDeadline: uint40(7 days),
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.REFUND
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();

        vm.prank(user1);
        escrow.dispute(escrowId, YieldEscrowV2.DisputeReason.FRAUD_OR_CANCELLED, keccak256("cancelled-order"));

        YieldEscrowV2.SettlementPreview memory preview = escrow.previewSettlement(escrowId);
        assertTrue(preview.disputeActive);
        assertFalse(preview.disputeResolved);
        assertFalse(preview.disputeTimedOut);
        assertTrue(preview.requiresArbiterResolution);
        assertFalse(preview.canBuyerRelease);
        assertFalse(preview.canMerchantRelease);
        assertFalse(preview.canArbiterRelease);
        assertFalse(preview.canBuyerRefund);
        assertFalse(preview.canArbiterRefund);
        assertTrue(preview.canArbiterResolve);
        assertEq(preview.requiredMilestones, 0);
        assertEq(preview.completedMilestones, 0);
        assertEq(preview.nextMilestoneNumber, 0);
        assertEq(preview.disputedMilestone, 0);
        assertEq(preview.challengeWindowEndsAt, 0);
        assertEq(preview.disputeWindowEndsAt, uint40(block.timestamp + 7 days));

        vm.warp(block.timestamp + 7 days);

        preview = escrow.previewSettlement(escrowId);
        assertTrue(preview.disputeTimedOut);
        assertFalse(preview.requiresArbiterResolution);
        assertFalse(preview.canBuyerRelease);
        assertFalse(preview.canMerchantRelease);
        assertFalse(preview.canArbiterRelease);
        assertTrue(preview.canBuyerRefund);
        assertTrue(preview.canArbiterRefund);
        assertFalse(preview.canArbiterResolve);
        assertEq(preview.requiredMilestones, 0);
        assertEq(preview.completedMilestones, 0);
        assertEq(preview.nextMilestoneNumber, 0);
        assertEq(preview.disputedMilestone, 0);
        assertEq(uint8(preview.buyerRefundMode), uint8(YieldEscrowV2.SettlementMode.DISPUTE_TIMEOUT_REFUND));
        assertEq(uint8(preview.arbiterRefundMode), uint8(YieldEscrowV2.SettlementMode.DISPUTE_TIMEOUT_REFUND));
        assertEq(preview.disputeWindowEndsAt, uint40(block.timestamp));
    }

    function test_PreviewSettlementShowsTimedOutDisputeReleasePath() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: uint40(6 hours),
            arbiterDeadline: uint40(7 days),
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.RELEASE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();

        vm.prank(user1);
        escrow.dispute(escrowId, YieldEscrowV2.DisputeReason.OTHER, keccak256("merchant-fulfilled-offchain"));

        vm.warp(block.timestamp + 7 days);

        YieldEscrowV2.SettlementPreview memory preview = escrow.previewSettlement(escrowId);
        assertTrue(preview.disputeTimedOut);
        assertFalse(preview.requiresArbiterResolution);
        assertTrue(preview.canBuyerRelease);
        assertTrue(preview.canMerchantRelease);
        assertTrue(preview.canArbiterRelease);
        assertFalse(preview.canBuyerRefund);
        assertFalse(preview.canArbiterRefund);
        assertFalse(preview.canArbiterResolve);
        assertEq(preview.requiredMilestones, 0);
        assertEq(preview.completedMilestones, 0);
        assertEq(preview.nextMilestoneNumber, 0);
        assertEq(preview.disputedMilestone, 0);
        assertEq(uint8(preview.buyerReleaseMode), uint8(YieldEscrowV2.SettlementMode.DISPUTE_TIMEOUT_RELEASE));
        assertEq(uint8(preview.merchantReleaseMode), uint8(YieldEscrowV2.SettlementMode.DISPUTE_TIMEOUT_RELEASE));
        assertEq(uint8(preview.arbiterReleaseMode), uint8(YieldEscrowV2.SettlementMode.DISPUTE_TIMEOUT_RELEASE));
        assertEq(preview.disputeWindowEndsAt, uint40(block.timestamp));
    }

    function test_ResolveDisputeRevertsAfterArbiterDeadlineExpires() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: uint40(6 hours),
            arbiterDeadline: uint40(7 days),
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.REFUND
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();

        vm.prank(user1);
        escrow.dispute(escrowId, YieldEscrowV2.DisputeReason.QUALITY, keccak256("quality-issue"));

        vm.warp(block.timestamp + 7 days);

        YieldEscrowV2.SettlementPreview memory preview = escrow.previewSettlement(escrowId);
        assertFalse(preview.canArbiterResolve);

        vm.prank(admin);
        vm.expectRevert(YieldEscrowV2.ARBITER_DEADLINE_EXPIRED.selector);
        escrow.resolveDispute(escrowId, YieldEscrowV2.DisputeResolution.RELEASE, keccak256("late-arbiter"));
    }

    function test_EscrowPauseBlocksDisputeResolutionAndTimeoutFlows() public {
        _mintAndDeposit(user1, 200 ether);

        YieldEscrowV2.InvoiceTerms memory disputeTerms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: uint40(6 hours),
            arbiterDeadline: uint40(7 days),
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.REFUND
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 pausedDisputeEscrowId = escrow.fundEscrow(user2, disputeTerms, 0);
        uint256 pausedTimeoutEscrowId = escrow.fundEscrow(user2, disputeTerms, 0);
        vm.stopPrank();

        vm.prank(admin);
        escrow.setEscrowOpsPaused(true);

        vm.prank(user1);
        vm.expectRevert(YieldEscrowV2.ESCROW_OPS_PAUSED.selector);
        escrow.dispute(pausedDisputeEscrowId, YieldEscrowV2.DisputeReason.OTHER, keccak256("paused-dispute"));

        vm.prank(admin);
        vm.expectRevert(YieldEscrowV2.ESCROW_OPS_PAUSED.selector);
        escrow.resolveDispute(pausedDisputeEscrowId, YieldEscrowV2.DisputeResolution.REFUND, keccak256("paused-resolve"));

        vm.prank(admin);
        escrow.setEscrowOpsPaused(false);

        vm.prank(user1);
        escrow.dispute(pausedTimeoutEscrowId, YieldEscrowV2.DisputeReason.OTHER, keccak256("timeout-ready"));

        vm.warp(block.timestamp + 7 days);

        vm.prank(admin);
        escrow.setEscrowOpsPaused(true);

        vm.expectRevert(YieldEscrowV2.ESCROW_OPS_PAUSED.selector);
        escrow.executeTimeout(pausedTimeoutEscrowId);
    }

    function test_EscrowPauseBlocksFulfillmentSubmission() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 1,
            challengeWindow: uint40(6 hours),
            arbiterDeadline: uint40(7 days),
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.REFUND
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();

        vm.prank(admin);
        escrow.setEscrowOpsPaused(true);

        vm.prank(user2);
        vm.expectRevert(YieldEscrowV2.ESCROW_OPS_PAUSED.selector);
        escrow.submitFulfillment(escrowId, YieldEscrowV2.FulfillmentType.DELIVERY, keccak256("paused-fulfillment"));
    }

    function testFuzz_EscrowDustConservation(
        uint256 assetsDue,
        uint16 protocolFeeBps,
        uint16 reserveBps,
        uint16 buyerBps,
        uint256 navBps
    ) public {
        assetsDue = bound(assetsDue, 1e12, 1_000_000 ether);
        protocolFeeBps = uint16(bound(protocolFeeBps, 0, 10_000));
        reserveBps = uint16(bound(reserveBps, 0, 10_000));
        buyerBps = uint16(bound(buyerBps, 0, 10_000));
        navBps = bound(navBps, 9_000, 12_000);

        _mintAndDeposit(user1, assetsDue * 2);

        vm.startPrank(admin);
        escrow.setProtocolFee(protocolFeeBps, user3);
        escrow.setReserveConfig(reserveBps, admin);
        vm.stopPrank();

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: assetsDue,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: 0,
            arbiterDeadline: 0,
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, buyerBps);
        vm.stopPrank();

        uint256 totalShares = _readEscrow(escrowId).sharesHeld;

        uint256 navRay = (RAY * navBps) / 10_000;
        uint64 nextEpoch = nav.navEpoch() + 1;
        vm.prank(admin);
        nav.relayNAV(navRay, uint40(block.timestamp), 0, nextEpoch);

        uint256 buyerBefore = vault.balanceOf(user1);
        uint256 merchantBefore = vault.balanceOf(user2);
        uint256 reserveBefore = vault.balanceOf(admin);
        uint256 feeBefore = vault.balanceOf(user3);

        vm.prank(user1);
        escrow.release(escrowId);

        uint256 buyerDelta = vault.balanceOf(user1) - buyerBefore;
        uint256 merchantDelta = vault.balanceOf(user2) - merchantBefore;
        uint256 reserveDelta = vault.balanceOf(admin) - reserveBefore;
        uint256 feeDelta = vault.balanceOf(user3) - feeBefore;

        assertEq(merchantDelta + buyerDelta + reserveDelta + feeDelta, totalShares);
    }

    function test_FundEscrowRevertsOnShareSlippage() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 100 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: 50 ether,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: 0,
            arbiterDeadline: 0,
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        vm.expectRevert(YieldEscrowV2.SHARES_SLIPPAGE.selector);
        escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();
    }

    function test_ReleaseRevertsWhenCallerLacksSettlementAuthority() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: 0,
            arbiterDeadline: 0,
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();

        vm.prank(user3);
        vm.expectRevert(YieldEscrowV2.SETTLEMENT_AUTH.selector);
        escrow.release(escrowId);
    }

    function test_BuyerCanRefundSponsoredEscrowToRefundRecipient() public {
        _mintAndDeposit(user1, 100 ether);
        _mintAndDeposit(user2, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp + 1 days),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: 0,
            arbiterDeadline: 0,
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user2);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrowFor(user1, user2, user3, terms, 0);
        vm.stopPrank();

        uint256 sponsorBefore = vault.balanceOf(user2);

        vm.prank(user1);
        escrow.refund(escrowId);

        uint256 sponsorAfter = vault.balanceOf(user2);
        assertEq(sponsorAfter - sponsorBefore, 40 ether);

        EscrowView memory stored = _readEscrow(escrowId);
        assertEq(stored.refundRecipient, user2);
        assertEq(stored.sharesHeld, 0);
        assertEq(stored.committedAssets, 0);
        assertEq(stored.releaseAfter, terms.releaseAfter);
        assertEq(uint8(stored.status), uint8(YieldEscrowV2.EscrowStatus.REFUNDED));
        assertFalse(stored.requiresFulfillment);
        assertEq(uint8(stored.fulfillmentType), uint8(YieldEscrowV2.FulfillmentType.NONE));
        assertFalse(stored.disputed);
        assertEq(uint8(stored.disputeReason), uint8(YieldEscrowV2.DisputeReason.NONE));
        assertEq(stored.fulfilledAt, 0);
        assertEq(stored.fulfillmentEvidence, bytes32(0));
        assertEq(uint8(stored.resolution), uint8(YieldEscrowV2.DisputeResolution.NONE));
        assertEq(stored.resolvedAt, 0);
        assertEq(stored.resolutionEvidence, bytes32(0));
        assertEq(stored.challengeWindow, 0);
        assertEq(stored.arbiterDeadline, 0);
        assertEq(stored.disputedAt, 0);
        assertEq(uint8(stored.settlementMode), uint8(YieldEscrowV2.SettlementMode.BUYER_REFUND));
        assertEq(stored.settledAt, block.timestamp);
        assertEq(policy.getCommittedAssets(user1), 0);
    }

    function test_ReleaseRevertsBeforeReleaseAfterAndSucceedsAfter() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp + 1 days),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: 0,
            arbiterDeadline: 0,
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert(YieldEscrowV2.RELEASE_LOCKED.selector);
        escrow.release(escrowId);

        vm.warp(block.timestamp + 1 days);
        vm.prank(user1);
        escrow.release(escrowId);

        EscrowView memory stored = _readEscrow(escrowId);
        assertEq(stored.sharesHeld, 0);
        assertEq(stored.committedAssets, 0);
        assertEq(stored.releaseAfter, terms.releaseAfter);
        assertEq(uint8(stored.status), uint8(YieldEscrowV2.EscrowStatus.RELEASED));
        assertFalse(stored.requiresFulfillment);
        assertEq(uint8(stored.fulfillmentType), uint8(YieldEscrowV2.FulfillmentType.NONE));
        assertFalse(stored.disputed);
        assertEq(uint8(stored.disputeReason), uint8(YieldEscrowV2.DisputeReason.NONE));
        assertEq(stored.fulfilledAt, 0);
        assertEq(stored.fulfillmentEvidence, bytes32(0));
        assertEq(uint8(stored.resolution), uint8(YieldEscrowV2.DisputeResolution.NONE));
        assertEq(stored.resolvedAt, 0);
        assertEq(stored.resolutionEvidence, bytes32(0));
        assertEq(stored.challengeWindow, 0);
        assertEq(stored.arbiterDeadline, 0);
        assertEq(stored.disputedAt, 0);
        assertEq(uint8(stored.settlementMode), uint8(YieldEscrowV2.SettlementMode.BUYER_RELEASE));
        assertEq(stored.settledAt, block.timestamp);
    }

    function test_ReleaseRevertsWhenFulfillmentRequiredButNotSubmitted() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 1,
            challengeWindow: 0,
            arbiterDeadline: 0,
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.expectRevert(YieldEscrowV2.FULFILLMENT_PENDING.selector);
        escrow.release(escrowId);
        vm.stopPrank();
    }

    function test_MerchantCanSubmitFulfillmentAndBuyerCanRelease() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 1,
            challengeWindow: 0,
            arbiterDeadline: 0,
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 2_500);
        vm.stopPrank();

        bytes32 proof = keccak256("delivery-proof");

        vm.prank(user2);
        escrow.submitFulfillment(escrowId, YieldEscrowV2.FulfillmentType.DELIVERY, proof);

        EscrowView memory stored = _readEscrow(escrowId);
        assertEq(uint8(stored.status), uint8(YieldEscrowV2.EscrowStatus.FUNDED));
        assertTrue(stored.requiresFulfillment);
        assertEq(uint8(stored.fulfillmentType), uint8(YieldEscrowV2.FulfillmentType.DELIVERY));
        assertFalse(stored.disputed);
        assertEq(uint8(stored.disputeReason), uint8(YieldEscrowV2.DisputeReason.NONE));
        assertEq(stored.fulfilledAt, block.timestamp);
        assertEq(stored.fulfillmentEvidence, proof);
        assertEq(uint8(stored.settlementMode), uint8(YieldEscrowV2.SettlementMode.NONE));
        assertEq(stored.settledAt, 0);

        vm.prank(user1);
        escrow.release(escrowId);

        assertGt(vault.balanceOf(user2), 0);
        assertEq(policy.getCommittedAssets(user1), 0);
    }

    function test_BuyerCannotRefundAfterFulfillmentSubmitted() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp + 1 days),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 1,
            challengeWindow: 0,
            arbiterDeadline: 0,
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();

        vm.prank(user2);
        escrow.submitFulfillment(escrowId, YieldEscrowV2.FulfillmentType.DELIVERY, keccak256("proof"));

        vm.prank(user1);
        vm.expectRevert(YieldEscrowV2.FULFILLMENT_SUBMITTED.selector);
        escrow.refund(escrowId);
    }

    function test_FundEscrowAllowsDisputeWindowWithoutFulfillmentRequirement() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: uint40(6 hours),
            arbiterDeadline: uint40(7 days),
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.REFUND
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();

        EscrowView memory stored = _readEscrow(escrowId);
        assertFalse(stored.requiresFulfillment);
        assertEq(uint8(stored.fulfillmentType), uint8(YieldEscrowV2.FulfillmentType.NONE));
        assertEq(stored.challengeWindow, uint40(6 hours));
        assertEq(stored.arbiterDeadline, uint40(7 days));
        assertEq(uint8(stored.timeoutResolution), uint8(YieldEscrowV2.DisputeResolution.REFUND));
    }

    function test_FundEscrowRevertsWhenFulfillmentRequiredWithoutType() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 1,
            challengeWindow: 0,
            arbiterDeadline: 0,
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        vm.expectRevert(YieldEscrowV2.INVALID_FULFILLMENT_TYPE.selector);
        escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();
    }

    function test_FundEscrowRevertsWhenFulfillmentRequiredWithoutMilestones() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 0,
            challengeWindow: 0,
            arbiterDeadline: 0,
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        vm.expectRevert(YieldEscrowV2.INVALID_MILESTONE_COUNT.selector);
        escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();
    }

    function test_FundEscrowRevertsWhenFulfillmentTypeSetWithoutRequirement() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 0,
            challengeWindow: 0,
            arbiterDeadline: 0,
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        vm.expectRevert(YieldEscrowV2.INVALID_FULFILLMENT_TYPE.selector);
        escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();
    }

    function test_FundEscrowRevertsWhenMilestonesSetWithoutFulfillmentRequirement() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 1,
            challengeWindow: 0,
            arbiterDeadline: 0,
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        vm.expectRevert(YieldEscrowV2.INVALID_MILESTONE_COUNT.selector);
        escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();
    }

    function test_FundEscrowRevertsWhenDisputeWindowLacksTimeoutResolution() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 1,
            challengeWindow: uint40(6 hours),
            arbiterDeadline: uint40(7 days),
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        vm.expectRevert(YieldEscrowV2.INVALID_TIMEOUT_RESOLUTION.selector);
        escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();
    }

    function test_FundEscrowRevertsWhenTimeoutResolutionSetWithoutDisputeWindow() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 1,
            challengeWindow: 0,
            arbiterDeadline: 0,
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.REFUND
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        vm.expectRevert(YieldEscrowV2.INVALID_TIMEOUT_RESOLUTION.selector);
        escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();
    }

    function test_MerchantReleaseRevertsBeforeDisputeWindowExpires() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 1,
            challengeWindow: uint40(6 hours),
            arbiterDeadline: uint40(7 days),
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.REFUND
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();

        vm.prank(user2);
        escrow.submitFulfillment(escrowId, YieldEscrowV2.FulfillmentType.DELIVERY, keccak256("delivery-proof"));

        vm.warp(block.timestamp + 5 hours);
        vm.prank(user2);
        vm.expectRevert(YieldEscrowV2.MERCHANT_RELEASE_LOCKED.selector);
        escrow.release(escrowId);
    }

    function test_MerchantCanReleaseAfterDisputeWindowExpires() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 1,
            challengeWindow: uint40(6 hours),
            arbiterDeadline: uint40(7 days),
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.REFUND
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 1_500);
        vm.stopPrank();

        vm.prank(user2);
        escrow.submitFulfillment(escrowId, YieldEscrowV2.FulfillmentType.DELIVERY, keccak256("delivery-proof"));

        vm.warp(block.timestamp + 6 hours);
        vm.prank(user2);
        escrow.release(escrowId);

        assertGt(vault.balanceOf(user2), 0);
        assertEq(policy.getCommittedAssets(user1), 0);

        EscrowView memory stored = _readEscrow(escrowId);
        assertEq(uint8(stored.status), uint8(YieldEscrowV2.EscrowStatus.RELEASED));
        assertTrue(stored.requiresFulfillment);
        assertEq(uint8(stored.fulfillmentType), uint8(YieldEscrowV2.FulfillmentType.DELIVERY));
        assertFalse(stored.disputed);
        assertEq(uint8(stored.disputeReason), uint8(YieldEscrowV2.DisputeReason.NONE));
        assertEq(stored.fulfilledAt, block.timestamp - 6 hours);
        assertEq(stored.challengeWindow, uint40(6 hours));
        assertEq(stored.arbiterDeadline, uint40(7 days));
        assertEq(uint8(stored.timeoutResolution), uint8(YieldEscrowV2.DisputeResolution.REFUND));
        assertEq(stored.disputedAt, 0);
        assertEq(uint8(stored.settlementMode), uint8(YieldEscrowV2.SettlementMode.MERCHANT_TIMEOUT_RELEASE));
        assertEq(stored.settledAt, block.timestamp);
    }

    function test_DisputeDefaultsToLatestCompletedMilestone() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 2,
            challengeWindow: uint40(6 hours),
            arbiterDeadline: uint40(7 days),
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.REFUND
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();

        vm.prank(user2);
        escrow.submitFulfillment(escrowId, YieldEscrowV2.FulfillmentType.DELIVERY, keccak256("delivery-proof-1"));

        vm.prank(user1);
        escrow.dispute(escrowId, YieldEscrowV2.DisputeReason.QUALITY, keccak256("quality-issue"));

        YieldEscrowV2.SettlementPreview memory preview = escrow.previewSettlement(escrowId);
        assertTrue(preview.disputeActive);
        assertEq(preview.disputedMilestone, 1);
        assertEq(preview.completedMilestones, 1);
        assertEq(preview.nextMilestoneNumber, 2);
    }

    function test_DisputeMilestoneStoresExplicitTarget() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 2,
            challengeWindow: uint40(6 hours),
            arbiterDeadline: uint40(7 days),
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.REFUND
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();

        vm.prank(user2);
        escrow.submitFulfillment(escrowId, YieldEscrowV2.FulfillmentType.DELIVERY, keccak256("delivery-proof-1"));

        vm.prank(user1);
        escrow.disputeMilestone(escrowId, YieldEscrowV2.DisputeReason.NOT_AS_DESCRIBED, 1, keccak256("wrong-stage"));

        YieldEscrowV2.SettlementPreview memory preview = escrow.previewSettlement(escrowId);
        assertTrue(preview.disputeActive);
        assertEq(preview.disputedMilestone, 1);
        assertTrue(preview.requiresArbiterResolution);
    }

    function test_DisputeMilestoneRevertsWhenTargetExceedsCompletedProgress() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 2,
            challengeWindow: uint40(6 hours),
            arbiterDeadline: uint40(7 days),
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.REFUND
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();

        vm.prank(user2);
        escrow.submitFulfillment(escrowId, YieldEscrowV2.FulfillmentType.DELIVERY, keccak256("delivery-proof-1"));

        vm.prank(user1);
        vm.expectRevert(YieldEscrowV2.INVALID_MILESTONE_TARGET.selector);
        escrow.disputeMilestone(escrowId, YieldEscrowV2.DisputeReason.QUALITY, 2, keccak256("future-stage"));
    }

    function test_BuyerCanRefundAfterDisputeWindowExpiresWithoutResolution() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 1,
            challengeWindow: uint40(6 hours),
            arbiterDeadline: uint40(7 days),
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.REFUND
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();

        vm.prank(user2);
        escrow.submitFulfillment(escrowId, YieldEscrowV2.FulfillmentType.DELIVERY, keccak256("delivery-proof"));

        vm.prank(user1);
        escrow.dispute(escrowId, YieldEscrowV2.DisputeReason.QUALITY, keccak256("quality-issue"));

        vm.warp(block.timestamp + 6 days);
        vm.prank(user1);
        vm.expectRevert(YieldEscrowV2.DISPUTE_PENDING.selector);
        escrow.refund(escrowId);

        vm.warp(block.timestamp + 1 days);
        uint256 buyerBefore = vault.balanceOf(user1);

        vm.prank(user1);
        escrow.refund(escrowId);

        assertEq(vault.balanceOf(user1), buyerBefore + 40 ether);
        assertEq(policy.getCommittedAssets(user1), 0);

        EscrowView memory stored = _readEscrow(escrowId);
        assertEq(stored.sharesHeld, 0);
        assertEq(stored.committedAssets, 0);
        assertEq(uint8(stored.status), uint8(YieldEscrowV2.EscrowStatus.REFUNDED));
        assertEq(uint8(stored.fulfillmentType), uint8(YieldEscrowV2.FulfillmentType.DELIVERY));
        assertTrue(stored.disputed);
        assertEq(uint8(stored.disputeReason), uint8(YieldEscrowV2.DisputeReason.QUALITY));
        assertEq(stored.fulfilledAt, block.timestamp - 7 days);
        assertEq(stored.challengeWindow, uint40(6 hours));
        assertEq(stored.arbiterDeadline, uint40(7 days));
        assertEq(uint8(stored.timeoutResolution), uint8(YieldEscrowV2.DisputeResolution.REFUND));
        assertEq(stored.disputedAt, block.timestamp - 7 days);
        assertEq(uint8(stored.settlementMode), uint8(YieldEscrowV2.SettlementMode.DISPUTE_TIMEOUT_REFUND));
        assertEq(stored.settledAt, block.timestamp);
    }

    function test_BuyerCanRefundNonFulfillmentEscrowAfterDisputeWindowExpires() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: uint40(6 hours),
            arbiterDeadline: uint40(7 days),
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.REFUND
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();

        vm.prank(user1);
        escrow.dispute(escrowId, YieldEscrowV2.DisputeReason.FRAUD_OR_CANCELLED, keccak256("cancelled-order"));

        vm.warp(block.timestamp + 6 days);
        vm.prank(user1);
        vm.expectRevert(YieldEscrowV2.DISPUTE_PENDING.selector);
        escrow.refund(escrowId);

        uint256 buyerBefore = vault.balanceOf(user1);

        vm.warp(block.timestamp + 1 days);
        vm.prank(user1);
        escrow.refund(escrowId);

        assertEq(vault.balanceOf(user1), buyerBefore + 40 ether);

        EscrowView memory stored = _readEscrow(escrowId);
        assertFalse(stored.requiresFulfillment);
        assertTrue(stored.disputed);
        assertEq(uint8(stored.disputeReason), uint8(YieldEscrowV2.DisputeReason.FRAUD_OR_CANCELLED));
        assertEq(stored.challengeWindow, uint40(6 hours));
        assertEq(stored.arbiterDeadline, uint40(7 days));
        assertEq(uint8(stored.timeoutResolution), uint8(YieldEscrowV2.DisputeResolution.REFUND));
        assertEq(uint8(stored.settlementMode), uint8(YieldEscrowV2.SettlementMode.DISPUTE_TIMEOUT_REFUND));
        assertEq(stored.settledAt, block.timestamp);
    }

    function test_BuyerCannotRefundAfterDisputeWindowExpiresWhenTimeoutResolvesRelease() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 1,
            challengeWindow: uint40(6 hours),
            arbiterDeadline: uint40(7 days),
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.RELEASE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();

        vm.prank(user2);
        escrow.submitFulfillment(escrowId, YieldEscrowV2.FulfillmentType.DELIVERY, keccak256("delivery-proof"));

        vm.prank(user1);
        escrow.dispute(escrowId, YieldEscrowV2.DisputeReason.QUALITY, keccak256("quality-issue"));

        vm.warp(block.timestamp + 7 days);
        vm.prank(user1);
        vm.expectRevert(YieldEscrowV2.RESOLUTION_MISMATCH.selector);
        escrow.refund(escrowId);
    }

    function test_MerchantCanReleaseAfterDisputeWindowExpiresWhenTimeoutResolvesRelease() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 1,
            challengeWindow: uint40(6 hours),
            arbiterDeadline: uint40(7 days),
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.RELEASE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();

        vm.prank(user2);
        escrow.submitFulfillment(escrowId, YieldEscrowV2.FulfillmentType.DELIVERY, keccak256("delivery-proof"));

        vm.prank(user1);
        escrow.dispute(escrowId, YieldEscrowV2.DisputeReason.QUALITY, keccak256("quality-issue"));

        vm.warp(block.timestamp + 7 days);
        _updateNav(RAY, nav.navEpoch() + 1);

        vm.prank(user2);
        escrow.release(escrowId);

        EscrowView memory stored = _readEscrow(escrowId);
        assertEq(uint8(stored.status), uint8(YieldEscrowV2.EscrowStatus.RELEASED));
        assertEq(uint8(stored.disputeReason), uint8(YieldEscrowV2.DisputeReason.QUALITY));
        assertEq(uint8(stored.timeoutResolution), uint8(YieldEscrowV2.DisputeResolution.RELEASE));
        assertEq(uint8(stored.settlementMode), uint8(YieldEscrowV2.SettlementMode.DISPUTE_TIMEOUT_RELEASE));
        assertEq(stored.settledAt, block.timestamp);
    }

    function test_MerchantCanReleaseNonFulfillmentEscrowAfterDisputeWindowExpiresWhenTimeoutResolvesRelease() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: uint40(6 hours),
            arbiterDeadline: uint40(7 days),
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.RELEASE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();

        vm.prank(user1);
        escrow.dispute(escrowId, YieldEscrowV2.DisputeReason.OTHER, keccak256("merchant-fulfilled-offchain"));

        vm.warp(block.timestamp + 7 days);
        _updateNav(RAY, nav.navEpoch() + 1);

        vm.prank(user2);
        escrow.release(escrowId);

        EscrowView memory stored = _readEscrow(escrowId);
        assertEq(uint8(stored.status), uint8(YieldEscrowV2.EscrowStatus.RELEASED));
        assertFalse(stored.requiresFulfillment);
        assertTrue(stored.disputed);
        assertEq(uint8(stored.disputeReason), uint8(YieldEscrowV2.DisputeReason.OTHER));
        assertEq(uint8(stored.timeoutResolution), uint8(YieldEscrowV2.DisputeResolution.RELEASE));
        assertEq(uint8(stored.settlementMode), uint8(YieldEscrowV2.SettlementMode.DISPUTE_TIMEOUT_RELEASE));
        assertEq(stored.settledAt, block.timestamp);
    }

    function test_ResolveDisputeRevertsWhenCallerLacksArbiterRole() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 1,
            challengeWindow: 0,
            arbiterDeadline: 0,
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();

        vm.prank(user1);
        escrow.dispute(escrowId, YieldEscrowV2.DisputeReason.QUALITY, keccak256("damaged-goods"));

        vm.prank(user1);
        vm.expectRevert();
        escrow.resolveDispute(escrowId, YieldEscrowV2.DisputeResolution.REFUND, keccak256("buyer-resolution"));
    }

    function test_ArbiterResolvedReleaseLetsBuyerSettleDisputedEscrow() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 1,
            challengeWindow: 0,
            arbiterDeadline: 0,
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();

        vm.prank(user1);
        escrow.dispute(escrowId, YieldEscrowV2.DisputeReason.OTHER, keccak256("inspection-required"));

        vm.prank(user1);
        vm.expectRevert(YieldEscrowV2.DISPUTE_PENDING.selector);
        escrow.release(escrowId);

        bytes32 resolutionEvidence = keccak256("arbiter-approve-release");

        vm.prank(admin);
        escrow.resolveDispute(escrowId, YieldEscrowV2.DisputeResolution.RELEASE, resolutionEvidence);

        vm.prank(user1);
        escrow.release(escrowId);

        assertGt(vault.balanceOf(user2), 0);
        assertEq(policy.getCommittedAssets(user1), 0);

        EscrowView memory stored = _readEscrow(escrowId);
        assertEq(uint8(stored.status), uint8(YieldEscrowV2.EscrowStatus.RELEASED));
        assertEq(uint8(stored.fulfillmentType), uint8(YieldEscrowV2.FulfillmentType.DELIVERY));
        assertTrue(stored.disputed);
        assertEq(uint8(stored.disputeReason), uint8(YieldEscrowV2.DisputeReason.OTHER));
        assertEq(uint8(stored.resolution), uint8(YieldEscrowV2.DisputeResolution.RELEASE));
        assertEq(uint8(stored.settlementMode), uint8(YieldEscrowV2.SettlementMode.ARBITER_RELEASE));
        assertEq(stored.settledAt, block.timestamp);
    }

    function test_DisputeBlocksBuyerSettlementUntilArbiterResolvesRefund() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 1,
            challengeWindow: 0,
            arbiterDeadline: 0,
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();

        vm.prank(user2);
        escrow.submitFulfillment(escrowId, YieldEscrowV2.FulfillmentType.DELIVERY, keccak256("delivery-proof"));

        vm.prank(user1);
        escrow.dispute(escrowId, YieldEscrowV2.DisputeReason.QUALITY, keccak256("damaged-goods"));

        vm.prank(user1);
        vm.expectRevert(YieldEscrowV2.DISPUTE_PENDING.selector);
        escrow.refund(escrowId);

        bytes32 resolutionEvidence = keccak256("arbiter-refund");
        uint256 buyerBefore = vault.balanceOf(user1);

        vm.prank(admin);
        escrow.resolveDispute(escrowId, YieldEscrowV2.DisputeResolution.REFUND, resolutionEvidence);

        vm.prank(user1);
        escrow.refund(escrowId);

        assertEq(vault.balanceOf(user1), buyerBefore + 40 ether);
        assertEq(policy.getCommittedAssets(user1), 0);

        EscrowView memory stored = _readEscrow(escrowId);
        assertEq(uint8(stored.status), uint8(YieldEscrowV2.EscrowStatus.REFUNDED));
        assertEq(uint8(stored.fulfillmentType), uint8(YieldEscrowV2.FulfillmentType.DELIVERY));
        assertTrue(stored.disputed);
        assertEq(uint8(stored.disputeReason), uint8(YieldEscrowV2.DisputeReason.QUALITY));
        assertEq(uint8(stored.resolution), uint8(YieldEscrowV2.DisputeResolution.REFUND));
        assertEq(uint8(stored.settlementMode), uint8(YieldEscrowV2.SettlementMode.ARBITER_REFUND));
        assertEq(stored.settledAt, block.timestamp);
    }

    function test_SubmitFulfillmentRevertsWhenTypeMismatchesTerms() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 40 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.SERVICE,
            requiredMilestones: 1,
            challengeWindow: 0,
            arbiterDeadline: 0,
        disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();

        vm.prank(user2);
        vm.expectRevert(YieldEscrowV2.INVALID_FULFILLMENT_TYPE.selector);
        escrow.submitFulfillment(escrowId, YieldEscrowV2.FulfillmentType.DELIVERY, keccak256("wrong-proof-type"));
    }
}
