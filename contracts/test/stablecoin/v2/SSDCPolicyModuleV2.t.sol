// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SSDCPolicyModuleV2} from "../../../stablecoin/v2/SSDCPolicyModuleV2.sol";

contract SSDCPolicyModuleV2Test is Test {
    SSDCPolicyModuleV2 internal policy;

    address internal admin = address(0xA11CE);
    address internal consumer = address(0xC01A);
    address internal agent = address(0xA637);
    address internal merchant = address(0xBEEF);

    function setUp() public {
        vm.startPrank(admin);
        policy = new SSDCPolicyModuleV2(admin);
        policy.grantRole(policy.POLICY_CONSUMER_ROLE(), consumer);
        vm.stopPrank();
    }

    function test_CanSpendUsesRolledDailyWindow() public {
        vm.prank(admin);
        policy.setPolicy(agent, 0, 100 ether, 0, 0, false);

        vm.prank(consumer);
        policy.consumeSpend(agent, merchant, 100 ether);

        assertFalse(policy.canSpend(agent, merchant, 1));

        vm.warp(block.timestamp + 1 days + 1);

        assertTrue(policy.canSpend(agent, merchant, 1 ether));
    }

    function test_CanSpendRespectsMerchantAllowlist() public {
        vm.prank(admin);
        policy.setPolicy(agent, 100 ether, 100 ether, 0, 0, true);

        assertFalse(policy.canSpend(agent, merchant, 1 ether));

        vm.prank(admin);
        policy.setMerchantAllowed(agent, merchant, true);

        assertTrue(policy.canSpend(agent, merchant, 1 ether));
    }

    function test_CanSpendRespectsSessionExpiry() public {
        vm.prank(admin);
        policy.setPolicy(agent, 100 ether, 100 ether, 0, uint40(block.timestamp + 1 hours), false);

        assertTrue(policy.canSpend(agent, merchant, 1 ether));

        vm.warp(block.timestamp + 1 hours + 1);

        assertFalse(policy.canSpend(agent, merchant, 1 ether));
    }

    function test_CommittedSpendAdjustsEffectiveFloorAndCanRelease() public {
        vm.prank(admin);
        policy.setPolicy(agent, 100 ether, 100 ether, 50 ether, 0, false);

        assertEq(policy.getConfiguredMinAssetsFloor(agent), 50 ether);
        assertEq(policy.getCommittedAssets(agent), 0);
        assertEq(policy.getMinAssetsFloor(agent), 50 ether);

        vm.prank(consumer);
        policy.reserveCommittedSpend(agent, 20 ether);

        assertEq(policy.getConfiguredMinAssetsFloor(agent), 50 ether);
        assertEq(policy.getCommittedAssets(agent), 20 ether);
        assertEq(policy.getMinAssetsFloor(agent), 70 ether);

        vm.prank(consumer);
        policy.releaseCommittedSpend(agent, 5 ether);

        assertEq(policy.getCommittedAssets(agent), 15 ether);
        assertEq(policy.getMinAssetsFloor(agent), 65 ether);
    }

    function test_ReleaseCommittedSpendRevertsWhenAmountExceedsReserved() public {
        vm.prank(admin);
        policy.setPolicy(agent, 100 ether, 100 ether, 50 ether, 0, false);

        vm.prank(consumer);
        policy.reserveCommittedSpend(agent, 10 ether);

        vm.prank(consumer);
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_COMMITMENT.selector);
        policy.releaseCommittedSpend(agent, 11 ether);
    }

    function _unlimited() internal {
        vm.prank(admin);
        policy.setPolicy(agent, 0, 0, 0, 0, false);
    }

    function testFuzz_OversizedPolicyFieldsRejected(uint256 excess) public {
        uint256 amount = bound(excess, uint256(type(uint128).max) + 1, type(uint256).max);
        _unlimited();
        vm.startPrank(admin);
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_AMOUNT_OVERFLOW.selector);
        policy.setPolicy(agent, amount, 0, 0, 0, false);
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_AMOUNT_OVERFLOW.selector);
        policy.setPolicy(agent, 0, amount, 0, 0, false);
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_AMOUNT_OVERFLOW.selector);
        policy.setPolicy(agent, 0, 0, amount, 0, false);
        vm.stopPrank();
        assertEq(policy.getConfiguredMinAssetsFloor(agent), 0);
    }

    function testFuzz_OversizedSpendAndCommitmentsNeverTruncate(uint256 excess) public {
        uint256 amount = bound(excess, uint256(type(uint128).max) + 1, type(uint256).max);
        _unlimited();
        assertFalse(policy.canSpend(agent, merchant, amount));
        assertFalse(policy.canGasSpend(agent, amount));
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_AMOUNT_OVERFLOW.selector);
        policy.requireGasSpendAllowed(agent, amount);
        vm.startPrank(consumer);
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_AMOUNT_OVERFLOW.selector);
        policy.consumeSpend(agent, merchant, amount);
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_AMOUNT_OVERFLOW.selector);
        policy.consumeGasSpend(agent, amount);
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_AMOUNT_OVERFLOW.selector);
        policy.reserveCommittedSpend(agent, amount);
        vm.stopPrank();
        assertEq(policy.getCommittedAssets(agent), 0);
    }

    function test_FloorAndCommitmentSumUsesFullWidth() public {
        vm.prank(admin);
        policy.setPolicy(agent, type(uint128).max, type(uint128).max, type(uint128).max, 0, false);
        vm.prank(consumer);
        policy.reserveCommittedSpend(agent, type(uint128).max);
        assertEq(policy.getMinAssetsFloor(agent), 2 * uint256(type(uint128).max));
        vm.prank(consumer);
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_AMOUNT_OVERFLOW.selector);
        policy.reserveCommittedSpend(agent, 1);
    }

    function test_SpendAndGasShareCounterCapacityAndRollOver() public {
        _unlimited();
        vm.prank(consumer);
        policy.consumeSpend(agent, merchant, type(uint128).max - 1);
        vm.prank(consumer);
        policy.consumeGasSpend(agent, 1);
        assertFalse(policy.canSpend(agent, merchant, 1));
        assertFalse(policy.canGasSpend(agent, 1));
        vm.prank(consumer);
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_AMOUNT_OVERFLOW.selector);
        policy.consumeGasSpend(agent, 1);
        vm.warp(block.timestamp + 1 days);
        assertTrue(policy.canGasSpend(agent, 1));
        vm.prank(consumer);
        policy.consumeGasSpend(agent, 1);
    }

    function test_InterleavedPurchasesAndGasCannotExceedDailyBudget() public {
        vm.prank(admin);
        policy.setPolicy(agent, 100, 100, 0, 0, false);
        vm.startPrank(consumer);
        policy.consumeSpend(agent, merchant, 60);
        policy.consumeGasSpend(agent, 30);
        policy.consumeSpend(agent, merchant, 10);
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_DAILY_LIMIT.selector);
        policy.consumeSpend(agent, merchant, 1);
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_DAILY_LIMIT.selector);
        policy.consumeGasSpend(agent, 1);
        vm.stopPrank();
    }

    function test_RevocationBlocksNewSpendingButPreservesRefundCleanup() public {
        _unlimited();
        vm.startPrank(consumer);
        policy.consumeSpend(agent, merchant, 10);
        policy.reserveCommittedSpend(agent, 10);
        vm.stopPrank();
        vm.prank(admin);
        policy.setPolicyRevoked(agent, true);
        assertFalse(policy.canSpend(agent, merchant, 1));
        assertFalse(policy.canGasSpend(agent, 1));
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_REVOKED.selector);
        policy.requireGasSpendAllowed(agent, 1);
        vm.startPrank(consumer);
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_REVOKED.selector);
        policy.consumeSpend(agent, merchant, 1);
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_REVOKED.selector);
        policy.consumeGasSpend(agent, 1);
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_REVOKED.selector);
        policy.reserveCommittedSpend(agent, 1);
        policy.releaseCommittedSpend(agent, 10);
        vm.stopPrank();
        assertEq(policy.getCommittedAssets(agent), 0);
        vm.prank(admin);
        policy.setPolicy(agent, 100, 10, 0, 0, false);
        assertTrue(policy.policyRevoked(agent));
        vm.prank(admin);
        policy.setPolicyRevoked(agent, false);
        assertFalse(policy.canSpend(agent, merchant, 1)); // old usage survives reconfiguration
    }

    function test_ExpiredPolicyCannotReserveButCanReleaseCommitments() public {
        vm.prank(admin);
        policy.setPolicy(agent, 100, 100, 0, uint40(block.timestamp + 1), false);
        vm.prank(consumer);
        policy.reserveCommittedSpend(agent, 10);
        vm.warp(block.timestamp + 2);
        vm.startPrank(consumer);
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_SESSION_EXPIRED.selector);
        policy.reserveCommittedSpend(agent, 1);
        policy.releaseCommittedSpend(agent, 10);
        vm.stopPrank();
    }

    function test_UnauthorizedCallerCannotConsumeReserveOrRevoke() public {
        _unlimited();
        vm.startPrank(agent);
        vm.expectRevert();
        policy.consumeSpend(agent, merchant, 1);
        vm.expectRevert();
        policy.consumeGasSpend(agent, 1);
        vm.expectRevert();
        policy.reserveCommittedSpend(agent, 1);
        vm.expectRevert();
        policy.setPolicyRevoked(agent, false);
        vm.stopPrank();
    }
}
