// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2TestBase, MockETHUSDOracle} from "./SSDCV2TestBase.sol";
import {GroundingRegistryV2} from "../../../stablecoin/v2/GroundingRegistryV2.sol";
import {SSDCClaimQueueV2} from "../../../stablecoin/v2/SSDCClaimQueueV2.sol";
import {SSDCPolicyModuleV2} from "../../../stablecoin/v2/SSDCPolicyModuleV2.sol";
import {SSDCVaultGatewayV2} from "../../../stablecoin/v2/SSDCVaultGatewayV2.sol";
import {YieldEscrowV2} from "../../../stablecoin/v2/YieldEscrowV2.sol";
import {YieldPaymasterV2} from "../../../stablecoin/v2/YieldPaymasterV2.sol";
import {IETHUSDOracleV2} from "../../../stablecoin/v2/interfaces/IETHUSDOracleV2.sol";

contract AgentCommerceFlowV2Test is SSDCV2TestBase {
    SSDCVaultGatewayV2 internal gateway;
    SSDCClaimQueueV2 internal queue;
    YieldEscrowV2 internal escrow;
    SSDCPolicyModuleV2 internal policy;
    GroundingRegistryV2 internal grounding;
    YieldPaymasterV2 internal paymaster;
    MockETHUSDOracle internal priceOracle;

    address internal merchant = address(0xBEEF);
    address internal protocolFeeCollector = address(0xFEE0);
    address internal entryPoint = address(0x4337);

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        gateway = new SSDCVaultGatewayV2(vault, admin);
        queue = new SSDCClaimQueueV2(vault, asset, admin);
        policy = new SSDCPolicyModuleV2(admin);
        grounding = new GroundingRegistryV2(policy, nav, vault, admin);
        escrow = new YieldEscrowV2(vault, nav, policy, grounding, admin, protocolFeeCollector);

        priceOracle = new MockETHUSDOracle();
        priceOracle.setPrice(3_000e18);

        paymaster = new YieldPaymasterV2(
            vault,
            nav,
            policy,
            grounding,
            IETHUSDOracleV2(address(priceOracle)),
            entryPoint,
            admin,
            protocolFeeCollector
        );

        vault.grantRole(vault.GATEWAY_ROLE(), address(gateway));
        vault.grantRole(vault.GATEWAY_ROLE(), address(queue));
        vault.grantRole(vault.QUEUE_ROLE(), address(queue));
        escrow.grantRole(escrow.FUNDER_ROLE(), address(gateway));
        policy.grantRole(policy.POLICY_CONSUMER_ROLE(), address(escrow));
        policy.grantRole(policy.POLICY_CONSUMER_ROLE(), address(paymaster));
        grounding.setCollateralProvider(address(paymaster), true);
        vault.setGatewayRequired(true);

        policy.setPolicy(
            user1,
            type(uint256).max,
            type(uint256).max,
            50 ether,
            uint40(block.timestamp + 7 days),
            false
        );

        vm.stopPrank();
    }

    function test_EndToEndAgentCommerceFlow() public {
        // 1) Buyer agent acquires shares
        asset.mint(user1, 1_400 ether);
        vm.startPrank(user1);
        asset.approve(address(gateway), type(uint256).max);
        gateway.deposit(1_000 ether, user1, 1_000 ether);
        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 400 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp + 12 hours),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 2,
            challengeWindow: uint40(6 hours),
            arbiterDeadline: uint40(7 days),
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.REFUND
        });
        // 2) Buyer funds invoice escrow from settlement assets through the gateway.
        (uint256 escrowId,,) = gateway.depositToEscrow(escrow, merchant, terms, 2_000, 400 ether);
        vm.stopPrank();
        assertEq(policy.getCommittedAssets(user1), 400 ether);

        // 3) NAV moves up smoothly (yield accrual period)
        uint64 nextEpoch = nav.navEpoch() + 1;
        vm.prank(oracle);
        nav.updateNAV(105e25, int256(0), nextEpoch); // 1.05, zero forward rate
        vm.warp(block.timestamp + 12 hours);
        priceOracle.setPrice(3_000e18);

        // 4) Merchant completes the invoice across two fulfillment milestones and finalizes after the buyer challenge window expires.
        vm.prank(merchant);
        escrow.submitFulfillment(escrowId, YieldEscrowV2.FulfillmentType.DELIVERY, keccak256("delivery-proof-1"));

        vm.warp(block.timestamp + 1 hours);
        vm.prank(merchant);
        escrow.submitFulfillment(escrowId, YieldEscrowV2.FulfillmentType.DELIVERY, keccak256("delivery-proof-2"));

        vm.warp(block.timestamp + 6 hours);
        vm.prank(merchant);
        escrow.release(escrowId);
        assertEq(policy.getCommittedAssets(user1), 0);
        assertGt(vault.balanceOf(merchant), 0);

        // 5) Merchant requests redemption via async queue
        vm.startPrank(merchant);
        vault.approve(address(queue), type(uint256).max);
        uint256 merchantShares = vault.balanceOf(merchant);
        uint256 requestShares = merchantShares / 2;
        uint256 claimId = queue.requestRedeem(requestShares, merchant);
        vm.stopPrank();

        // 6) Buffer refilled and queue processed to claimable
        asset.mint(admin, 1_000 ether);
        vm.startPrank(admin);
        asset.approve(address(queue), type(uint256).max);
        queue.refill(1_000 ether);
        queue.processQueue(10);
        vm.stopPrank();

        (, , uint256 assetsOwed, , SSDCClaimQueueV2.Status status) = queue.claims(claimId);
        assertEq(uint256(status), uint256(SSDCClaimQueueV2.Status.CLAIMABLE));
        assertGt(assetsOwed, 0);

        // 7) Merchant claims settlement asset
        uint256 beforeAssets = asset.balanceOf(merchant);
        vm.prank(merchant);
        queue.claim(claimId);
        assertEq(asset.balanceOf(merchant), beforeAssets + assetsOwed);

        // 8) Buyer tops up gas tank from remaining shares; entrypoint charges gas in shares
        priceOracle.setPrice(3_000e18);
        vm.startPrank(user1);
        vault.approve(address(paymaster), type(uint256).max);
        paymaster.topUpGasTank(100 ether);
        vm.stopPrank();

        uint256 feeBefore = vault.balanceOf(protocolFeeCollector);
        uint256 gasUsed = 200_000;
        uint256 gasPrice = 12 gwei;
        bytes32 opKey = keccak256("commerce-gas");

        vm.prank(entryPoint);
        uint256 previewShares = paymaster.validatePaymasterUserOp(opKey, user1, gasUsed * gasPrice);

        vm.prank(entryPoint);
        uint256 chargedShares = paymaster.postOp(opKey, user1, gasUsed, gasPrice);

        assertGt(chargedShares, 0);
        assertEq(chargedShares, previewShares);
        assertEq(vault.balanceOf(protocolFeeCollector), feeBefore + chargedShares);

        // 9) Grounding remains healthy above floor after charge
        assertFalse(grounding.isGroundedNow(user1));
    }
}
