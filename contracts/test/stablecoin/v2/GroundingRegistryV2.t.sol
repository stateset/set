// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2TestBase, MockETHUSDOracle} from "./SSDCV2TestBase.sol";
import {GroundingRegistryV2} from "../../../stablecoin/v2/GroundingRegistryV2.sol";
import {NAVControllerV2} from "../../../stablecoin/v2/NAVControllerV2.sol";
import {SSDCPolicyModuleV2} from "../../../stablecoin/v2/SSDCPolicyModuleV2.sol";
import {YieldPaymasterV2} from "../../../stablecoin/v2/YieldPaymasterV2.sol";
import {IETHUSDOracleV2} from "../../../stablecoin/v2/interfaces/IETHUSDOracleV2.sol";
import {wSSDCVaultV2} from "../../../stablecoin/v2/wSSDCVaultV2.sol";

contract GroundingRegistryV2Test is SSDCV2TestBase {
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
        vm.stopPrank();

        _mintAndDeposit(user1, 100 ether);

        vm.startPrank(user1);
        vault.approve(address(paymaster), type(uint256).max);
        paymaster.topUpGasTank(100 ether);
        vm.stopPrank();
    }

    function test_ConstructorRejectsZeroDependencies() public {
        vm.expectRevert(GroundingRegistryV2.ZeroAddress.selector);
        new GroundingRegistryV2(SSDCPolicyModuleV2(address(0)), nav, vault, admin);

        vm.expectRevert(GroundingRegistryV2.ZeroAddress.selector);
        new GroundingRegistryV2(policy, NAVControllerV2(address(0)), vault, admin);

        vm.expectRevert(GroundingRegistryV2.ZeroAddress.selector);
        new GroundingRegistryV2(policy, nav, wSSDCVaultV2(address(0)), admin);
    }

    function test_CurrentAssetsIncludesRegisteredGasTankShares() public {
        vm.prank(admin);
        policy.setPolicy(user1, 0, 0, 50 ether, 0, false);

        (uint256 assetsNow, uint256 floor, uint256 navRay) = grounding.currentAssets(user1);

        assertEq(vault.balanceOf(user1), 0);
        assertEq(paymaster.gasTankShares(user1), 100 ether);
        assertEq(assetsNow, 100 ether);
        assertEq(floor, 50 ether);
        assertEq(navRay, RAY);
        assertFalse(grounding.isGroundedNow(user1));
    }

    function test_PokeCachesProviderAwareGrounding() public {
        vm.prank(admin);
        policy.setPolicy(user1, 0, 0, 120 ether, 0, false);

        grounding.poke(user1);

        assertTrue(grounding.isGroundedNow(user1));
        assertTrue(grounding.isGrounded(user1));
    }

    function test_CurrentAssetsUsesEffectiveFloorIncludingCommitments() public {
        vm.prank(admin);
        policy.setPolicy(user1, 0, 0, 50 ether, 0, false);

        vm.prank(admin);
        policy.reserveCommittedSpend(user1, 30 ether);

        (uint256 assetsNow, uint256 floor, uint256 navRay) = grounding.currentAssets(user1);

        assertEq(assetsNow, 100 ether);
        assertEq(floor, 80 ether);
        assertEq(navRay, RAY);
        assertFalse(grounding.isGroundedNow(user1));

        vm.prank(admin);
        policy.reserveCommittedSpend(user1, 30 ether);

        (assetsNow, floor, navRay) = grounding.currentAssets(user1);

        assertEq(assetsNow, 100 ether);
        assertEq(floor, 110 ether);
        assertEq(navRay, RAY);
        assertTrue(grounding.isGroundedNow(user1));
    }
}
