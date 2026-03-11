// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2TestBase, MockETHUSDOracle} from "./SSDCV2TestBase.sol";
import {GroundingRegistryV2} from "../../../stablecoin/v2/GroundingRegistryV2.sol";
import {SSDCPolicyModuleV2} from "../../../stablecoin/v2/SSDCPolicyModuleV2.sol";
import {YieldPaymasterV2} from "../../../stablecoin/v2/YieldPaymasterV2.sol";
import {IETHUSDOracleV2} from "../../../stablecoin/v2/interfaces/IETHUSDOracleV2.sol";

contract YieldPaymasterV2Test is SSDCV2TestBase {
    SSDCPolicyModuleV2 internal policy;
    GroundingRegistryV2 internal grounding;
    MockETHUSDOracle internal priceOracle;
    YieldPaymasterV2 internal paymaster;
    address internal entryPoint = address(0x4337);

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
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
            user3
        );

        policy.grantRole(policy.POLICY_CONSUMER_ROLE(), address(paymaster));
        grounding.setCollateralProvider(address(paymaster), true);

        policy.setPolicy(
            user1,
            type(uint256).max,
            type(uint256).max,
            100 ether,
            uint40(block.timestamp + 1 days),
            false
        );

        vm.stopPrank();

        _mintAndDeposit(user1, 120 ether);

        vm.startPrank(user1);
        vault.approve(address(paymaster), type(uint256).max);
        paymaster.topUpGasTank(30 ether);
        vm.stopPrank();
    }

    function test_ValidateRevertsWhenPriceStale() public {
        vm.warp(3 hours);
        priceOracle.setStalePrice(3_000e18, block.timestamp - 2 hours);

        vm.prank(entryPoint);
        vm.expectRevert(YieldPaymasterV2.PRICE_STALE.selector);
        paymaster.validatePaymasterUserOp(keccak256("stale"), user1, 0.001 ether);
    }

    function test_ValidateRevertsWhenGrounded() public {
        vm.prank(admin);
        policy.setPolicy(
            user1,
            type(uint256).max,
            type(uint256).max,
            1_000 ether,
            uint40(block.timestamp + 1 days),
            false
        );

        vm.prank(entryPoint);
        vm.expectRevert(YieldPaymasterV2.GROUNDED.selector);
        paymaster.validatePaymasterUserOp(keccak256("grounded"), user1, 0.001 ether);
    }

    function test_PaymasterFloorDefense() public {
        vm.prank(entryPoint);
        vm.expectRevert(YieldPaymasterV2.FLOOR.selector);
        paymaster.validatePaymasterUserOp(keccak256("floor"), user1, 0.01 ether);
    }

    function test_PaymasterFloorDefenseIncludesCommittedInvoiceHeadroom() public {
        vm.prank(admin);
        policy.setPolicy(
            user1,
            type(uint256).max,
            type(uint256).max,
            80 ether,
            uint40(block.timestamp + 1 days),
            false
        );

        vm.prank(admin);
        policy.reserveCommittedSpend(user1, 20 ether);

        vm.prank(entryPoint);
        vm.expectRevert(YieldPaymasterV2.FLOOR.selector);
        paymaster.validatePaymasterUserOp(keccak256("floor+commit"), user1, 0.01 ether);
    }

    function test_ValidateRevertsWhenGasTankInsufficient() public {
        vm.prank(entryPoint);
        vm.expectRevert(YieldPaymasterV2.INSUFFICIENT_SHARES.selector);
        paymaster.validatePaymasterUserOp(keccak256("tank"), user1, 0.02 ether);
    }

    function test_PostOpHonorsFloorWhenValid() public {
        vm.startPrank(user1);
        paymaster.topUpGasTank(30 ether);
        vm.stopPrank();

        vm.prank(admin);
        policy.setPolicy(
            user1,
            type(uint256).max,
            type(uint256).max,
            80 ether,
            uint40(block.timestamp + 1 days),
            false
        );

        vm.prank(entryPoint);
        bytes32 opKey = keccak256("valid");
        uint256 previewShares = paymaster.validatePaymasterUserOp(opKey, user1, 100_000 * 10 gwei);

        vm.prank(entryPoint);
        uint256 chargedShares = paymaster.postOp(opKey, user1, 100_000, 10 gwei);

        uint256 remainingShares = paymaster.gasTankShares(user1) + vault.balanceOf(user1);
        uint256 remainingAssets = vault.convertToAssets(remainingShares);

        assertGt(chargedShares, 0);
        assertEq(chargedShares, previewShares);
        assertGe(remainingAssets, 80 ether);
    }

    function test_PostOpRequiresPreparedValidation() public {
        vm.prank(entryPoint);
        vm.expectRevert(YieldPaymasterV2.VALIDATION_MISSING.selector);
        paymaster.postOp(keccak256("missing"), user1, 100_000, 10 gwei);
    }

    function test_RevertsWhenCallerNotEntryPoint() public {
        vm.expectRevert(YieldPaymasterV2.NOT_ENTRYPOINT.selector);
        paymaster.validatePaymasterUserOp(keccak256("not-entry-validate"), user1, 0.001 ether);

        vm.expectRevert(YieldPaymasterV2.NOT_ENTRYPOINT.selector);
        paymaster.postOp(keccak256("not-entry-post"), user1, 100_000, 10 gwei);
    }

    function test_SetEntryPoint() public {
        address newEntryPoint = address(0x4555);
        vm.prank(admin);
        paymaster.setEntryPoint(newEntryPoint);
        assertEq(paymaster.entryPoint(), newEntryPoint);
    }
}
