// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2TestBase} from "./SSDCV2TestBase.sol";
import {GroundingRegistryV2} from "../../../stablecoin/v2/GroundingRegistryV2.sol";
import {MockETHUSDOracle} from "./SSDCV2TestBase.sol";
import {SSDCPolicyModuleV2} from "../../../stablecoin/v2/SSDCPolicyModuleV2.sol";
import {SSDCVaultGatewayV2} from "../../../stablecoin/v2/SSDCVaultGatewayV2.sol";
import {YieldEscrowV2} from "../../../stablecoin/v2/YieldEscrowV2.sol";
import {YieldPaymasterV2} from "../../../stablecoin/v2/YieldPaymasterV2.sol";
import {IETHUSDOracleV2} from "../../../stablecoin/v2/interfaces/IETHUSDOracleV2.sol";
import {wSSDCVaultV2} from "../../../stablecoin/v2/wSSDCVaultV2.sol";

contract SSDCVaultGatewayV2Test is SSDCV2TestBase {
    SSDCVaultGatewayV2 internal gateway;
    SSDCPolicyModuleV2 internal policy;
    GroundingRegistryV2 internal grounding;
    MockETHUSDOracle internal priceOracle;
    YieldPaymasterV2 internal paymaster;
    YieldEscrowV2 internal escrow;

    address internal entryPoint = address(0x4337);
    address internal merchant = address(0xBEEF);

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        gateway = new SSDCVaultGatewayV2(vault, admin);
        policy = new SSDCPolicyModuleV2(admin);
        grounding = new GroundingRegistryV2(policy, nav, vault, admin);
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
            admin
        );
        escrow = new YieldEscrowV2(vault, nav, policy, grounding, admin, admin);
        vault.grantRole(vault.GATEWAY_ROLE(), address(gateway));
        vault.setGatewayRequired(true);
        escrow.grantRole(escrow.FUNDER_ROLE(), address(gateway));
        policy.grantRole(policy.POLICY_CONSUMER_ROLE(), address(escrow));
        policy.grantRole(policy.POLICY_CONSUMER_ROLE(), address(paymaster));
        grounding.setCollateralProvider(address(paymaster), true);
        vm.stopPrank();
    }

    function test_GatewayDepositWorksWhenGatewayRequired() public {
        asset.mint(user1, 100 ether);

        vm.startPrank(user1);
        asset.approve(address(vault), type(uint256).max);
        vm.expectRevert(wSSDCVaultV2.GATEWAY_ONLY.selector);
        vault.deposit(100 ether, user1);

        asset.approve(address(gateway), type(uint256).max);
        uint256 sharesOut = gateway.deposit(100 ether, user1, 100 ether);
        vm.stopPrank();

        assertEq(sharesOut, 100 ether);
        assertEq(vault.balanceOf(user1), 100 ether);
    }

    function test_GatewayWithdrawWorksWhenGatewayRequired() public {
        asset.mint(user1, 100 ether);

        vm.startPrank(user1);
        asset.approve(address(gateway), type(uint256).max);
        gateway.deposit(100 ether, user1, 100 ether);

        vault.approve(address(gateway), type(uint256).max);
        uint256 sharesBurned = gateway.withdraw(40 ether, user2, user1, 40 ether);
        vm.stopPrank();

        assertEq(sharesBurned, 40 ether);
        assertEq(asset.balanceOf(user2), 40 ether);
        assertEq(vault.balanceOf(user1), 60 ether);
    }

    function test_GatewayMintAndRedeemRespectBounds() public {
        asset.mint(user1, 200 ether);

        vm.startPrank(user1);
        asset.approve(address(gateway), type(uint256).max);

        vm.expectRevert(SSDCVaultGatewayV2.MAX_ASSETS_IN.selector);
        gateway.mint(100 ether, user1, 99 ether);

        uint256 assetsIn = gateway.mint(100 ether, user1, 100 ether);
        assertEq(assetsIn, 100 ether);

        vault.approve(address(gateway), type(uint256).max);

        vm.expectRevert(SSDCVaultGatewayV2.MIN_ASSETS_OUT.selector);
        gateway.redeem(10 ether, user1, user1, 11 ether);

        uint256 assetsOut = gateway.redeem(10 ether, user1, user1, 10 ether);
        vm.stopPrank();

        assertEq(assetsOut, 10 ether);
        assertEq(vault.balanceOf(user1), 90 ether);
    }

    function test_GatewayWithdrawSlippageGuard() public {
        asset.mint(user1, 100 ether);

        vm.startPrank(user1);
        asset.approve(address(gateway), type(uint256).max);
        gateway.deposit(100 ether, user1, 100 ether);

        uint64 nextEpoch = nav.navEpoch() + 1;
        vm.stopPrank();

        vm.prank(admin);
        nav.relayNAV(11e26, uint40(block.timestamp), 0, nextEpoch);

        vm.startPrank(user1);
        vault.approve(address(gateway), type(uint256).max);

        vm.expectRevert(SSDCVaultGatewayV2.MAX_SHARES_BURNED.selector);
        gateway.withdraw(10 ether, user1, user1, 9 ether);

        vm.stopPrank();
    }

    function test_GatewayCanTopUpGasTankFromSettlementAssets() public {
        vm.prank(admin);
        policy.setPolicy(
            user1,
            type(uint256).max,
            type(uint256).max,
            0,
            uint40(block.timestamp + 1 days),
            false
        );

        asset.mint(user1, 50 ether);

        vm.startPrank(user1);
        asset.approve(address(gateway), type(uint256).max);
        uint256 sharesOut = gateway.depositToGasTank(paymaster, 50 ether, user1, 50 ether);
        vm.stopPrank();

        assertEq(sharesOut, 50 ether);
        assertEq(paymaster.gasTankShares(user1), 50 ether);
        assertEq(vault.balanceOf(address(paymaster)), 50 ether);
    }

    function test_GatewayCanFundEscrowFromSettlementAssets() public {
        vm.prank(admin);
        policy.setPolicy(
            user1,
            type(uint256).max,
            type(uint256).max,
            0,
            uint40(block.timestamp + 1 days),
            false
        );

        asset.mint(user1, 175 ether);

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
        asset.approve(address(gateway), type(uint256).max);
        gateway.deposit(100 ether, user1, 100 ether);
        (uint256 escrowId, uint256 assetsIn, uint256 sharesOut) =
            gateway.depositToEscrow(escrow, merchant, terms, 2_000, 50 ether);
        vm.stopPrank();

        (YieldEscrowV2.Escrow memory e,,,) = escrow.getEscrow(escrowId);

        assertEq(assetsIn, 50 ether);
        assertEq(sharesOut, 50 ether);
        assertEq(e.buyer, user1);
        assertEq(e.merchant, merchant);
        assertEq(e.refundRecipient, user1);
        assertEq(e.sharesHeld, 50 ether);
        assertEq(e.committedAssets, 50 ether);
        assertEq(e.releaseAfter, block.timestamp);
        assertEq(e.buyerBps, 2_000);
        assertEq(uint8(e.status), uint8(YieldEscrowV2.EscrowStatus.FUNDED));
        assertFalse(e.requiresFulfillment);
        assertEq(uint8(e.fulfillmentType), uint8(YieldEscrowV2.FulfillmentType.NONE));
        assertFalse(e.disputed);
        assertEq(uint8(e.disputeReason), uint8(YieldEscrowV2.DisputeReason.NONE));
        assertEq(e.fulfilledAt, 0);
        assertEq(uint8(e.resolution), uint8(YieldEscrowV2.DisputeResolution.NONE));
        assertEq(e.resolvedAt, 0);
        assertEq(e.challengeWindow, 0);
        assertEq(e.arbiterDeadline, 0);
        assertEq(uint8(e.timeoutResolution), uint8(YieldEscrowV2.DisputeResolution.NONE));
        assertEq(e.disputedAt, 0);
        assertEq(uint8(e.settlementMode), uint8(YieldEscrowV2.SettlementMode.NONE));
        assertEq(e.settledAt, 0);
        assertEq(policy.getCommittedAssets(user1), 50 ether);
    }

    function test_GatewayEscrowRefundRoutesSharesBackToBuyer() public {
        vm.prank(admin);
        policy.setPolicy(
            user1,
            type(uint256).max,
            type(uint256).max,
            0,
            uint40(block.timestamp + 1 days),
            false
        );

        asset.mint(user1, 175 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 50 ether,
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
        asset.approve(address(gateway), type(uint256).max);
        gateway.deposit(100 ether, user1, 100 ether);
        (uint256 escrowId, , uint256 sharesOut) = gateway.depositToEscrow(escrow, merchant, terms, 2_000, 50 ether);
        vm.stopPrank();

        vm.prank(user1);
        escrow.refund(escrowId);

        assertEq(vault.balanceOf(user1), 100 ether + sharesOut);
        assertEq(vault.balanceOf(address(gateway)), 0);
        assertEq(policy.getCommittedAssets(user1), 0);
    }
}
