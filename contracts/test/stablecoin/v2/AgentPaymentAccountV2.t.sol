// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2TestBase} from "./SSDCV2TestBase.sol";
import {AgentPaymentAccountV2} from "../../../stablecoin/v2/AgentPaymentAccountV2.sol";
import {SSDCPolicyModuleV2} from "../../../stablecoin/v2/SSDCPolicyModuleV2.sol";

contract AgentPaymentAccountV2Test is SSDCV2TestBase {
    AgentPaymentAccountV2 internal account;
    SSDCPolicyModuleV2 internal policy;

    function setUp() public override {
        super.setUp();
        vm.startPrank(admin);
        policy = new SSDCPolicyModuleV2(admin);
        account = new AgentPaymentAccountV2(vault, policy, admin);
        policy.grantRole(policy.POLICY_CONSUMER_ROLE(), address(account));
        policy.setPolicy(address(account), 100 ether, 100 ether, 0, uint40(block.timestamp + 1 days), true);
        policy.setMerchantAllowed(address(account), user3, true);
        account.setSession(user1, user3, uint40(block.timestamp + 1 hours), 100 ether);
        account.setSession(user2, user3, uint40(block.timestamp + 1 hours), 100 ether);
        vm.stopPrank();
        _mintAndDeposit(address(account), 200 ether);
    }

    function _pay(address key, bytes32 order, uint256 epoch, uint256 nonce, uint256 amount) internal {
        vm.prank(key);
        account.pay(order, epoch, nonce, amount, type(uint256).max, uint40(block.timestamp + 10 minutes));
    }

    function test_PaymentConsumesBudgetAndTransfersToFixedMerchant() public {
        _pay(user1, bytes32(uint256(1)), 1, 0, 40 ether);
        assertEq(vault.balanceOf(user3), 40 ether);
        assertEq(account.nextNonce(), 1);
        assertTrue(account.paidOrders(bytes32(uint256(1))));
        (,, uint256 remaining,) = account.sessions(user1);
        assertEq(remaining, 60 ether);
        assertFalse(policy.canSpend(address(account), user3, 61 ether));
    }

    function test_CompetingSessionsCannotOverspendSharedDailyBudget() public {
        _pay(user1, bytes32(uint256(1)), 1, 0, 60 ether);
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_DAILY_LIMIT.selector);
        _pay(user2, bytes32(uint256(2)), 1, 1, 60 ether);
        assertEq(account.nextNonce(), 1);
        assertFalse(account.paidOrders(bytes32(uint256(2))));
        (,, uint256 remaining,) = account.sessions(user2);
        assertEq(remaining, 100 ether);
        assertEq(vault.balanceOf(user3), 60 ether);
    }

    function test_DuplicateOrderAndStaleNonceRejected() public {
        _pay(user1, bytes32(uint256(1)), 1, 0, 1 ether);
        vm.expectRevert(AgentPaymentAccountV2.AlreadyPaid.selector);
        _pay(user2, bytes32(uint256(1)), 1, 1, 1 ether);
        vm.expectRevert(AgentPaymentAccountV2.InvalidPayment.selector);
        _pay(user2, bytes32(uint256(2)), 1, 0, 1 ether);
    }

    function test_RevocationAndReplacementInvalidateOldEpoch() public {
        vm.prank(admin);
        account.revokeSession(user1);
        vm.expectRevert(AgentPaymentAccountV2.InvalidSession.selector);
        _pay(user1, bytes32(uint256(1)), 1, 0, 1 ether);
        vm.prank(admin);
        account.setSession(user1, user3, uint40(block.timestamp + 1 hours), 10 ether);
        vm.expectRevert(AgentPaymentAccountV2.InvalidSession.selector);
        _pay(user1, bytes32(uint256(1)), 1, 0, 1 ether);
        _pay(user1, bytes32(uint256(1)), 3, 0, 1 ether);
    }

    function test_PolicyRevocationRollsBackAllPaymentState() public {
        vm.prank(admin);
        policy.setPolicyRevoked(address(account), true);
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_REVOKED.selector);
        _pay(user1, bytes32(uint256(1)), 1, 0, 1 ether);
        assertEq(account.nextNonce(), 0);
        assertFalse(account.paidOrders(bytes32(uint256(1))));
        assertEq(vault.balanceOf(user3), 0);
    }

    function test_ExactSessionExpiryRejected() public {
        vm.warp(block.timestamp + 1 hours);
        vm.expectRevert(AgentPaymentAccountV2.InvalidSession.selector);
        _pay(user1, bytes32(uint256(1)), 1, 0, 1 ether);
    }

    function test_DeadlineAndSlippageRejected() public {
        vm.startPrank(user1);
        vm.expectRevert(AgentPaymentAccountV2.InvalidPayment.selector);
        account.pay(bytes32(uint256(1)), 1, 0, 1 ether, 1 ether, uint40(block.timestamp));
        vm.expectRevert(AgentPaymentAccountV2.InvalidPayment.selector);
        account.pay(bytes32(uint256(1)), 1, 0, 1 ether, 1, uint40(block.timestamp + 1));
        vm.stopPrank();
    }

    function test_SessionCannotWithdrawOrGrantPermissions() public {
        vm.startPrank(user1);
        vm.expectRevert();
        account.withdrawShares(user1, 1 ether);
        vm.expectRevert();
        account.setSession(user1, user1, uint40(block.timestamp + 1), 100 ether);
        vm.expectRevert();
        account.revokeSession(user2);
        vm.stopPrank();
        assertEq(vault.allowance(address(account), user1), 0);
    }

    function test_CommitmentsProtectedEvenDuringOwnerRecovery() public {
        vm.startPrank(admin);
        policy.reserveCommittedSpend(address(account), 180 ether);
        vm.expectRevert(AgentPaymentAccountV2.CollateralFloor.selector);
        account.withdrawShares(admin, 21 ether);
        vm.stopPrank();
        vm.expectRevert(AgentPaymentAccountV2.CollateralFloor.selector);
        _pay(user1, bytes32(uint256(1)), 1, 0, 21 ether);
        _pay(user1, bytes32(uint256(1)), 1, 0, 20 ether);
    }

    function testFuzz_SessionBudgetCannotBeExceeded(uint96 amount) public {
        uint256 spend = bound(uint256(amount), 1, 100 ether);
        vm.prank(admin);
        account.setSession(user1, user3, uint40(block.timestamp + 1 hours), spend);
        vm.expectRevert(AgentPaymentAccountV2.BudgetExceeded.selector);
        _pay(user1, bytes32(uint256(1)), 2, 0, spend + 1);
        _pay(user1, bytes32(uint256(1)), 2, 0, spend);
        assertEq(vault.balanceOf(user3), spend);
    }

    function test_TransferFailureRollsBackPolicyNonceAndOrder() public {
        vm.mockCallRevert(address(vault), abi.encodeWithSelector(vault.transfer.selector, user3, 1 ether), bytes("TRANSFER_FAILED"));
        vm.expectRevert(bytes("TRANSFER_FAILED"));
        _pay(user1, bytes32(uint256(1)), 1, 0, 1 ether);
        assertEq(account.nextNonce(), 0);
        assertFalse(account.paidOrders(bytes32(uint256(1))));
        assertTrue(policy.canSpend(address(account), user3, 100 ether));
        (,, uint256 remaining,) = account.sessions(user1);
        assertEq(remaining, 100 ether);
    }

    function test_RoundingChargesFullShareValue() public {
        vm.mockCall(address(vault), abi.encodeWithSelector(vault.currentNAVRay.selector), abi.encode(15e26));
        _pay(user1, bytes32(uint256(1)), 1, 0, 1);
        assertEq(vault.balanceOf(user3), 1);
        (,, uint256 remaining,) = account.sessions(user1);
        assertEq(remaining, 100 ether - 2);
    }

    function test_StaleNavFailsClosed() public {
        vm.prank(admin);
        account.setSession(user1, user3, uint40(block.timestamp + 4 days), 100 ether);
        vm.warp(block.timestamp + 3 days);
        vm.expectRevert();
        _pay(user1, bytes32(uint256(1)), 2, 0, 1 ether);
        assertEq(account.nextNonce(), 0);
    }

    function test_MerchantAllowlistAndConsumerRoleEnforced() public {
        vm.prank(admin);
        policy.setMerchantAllowed(address(account), user3, false);
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_ALLOWLIST.selector);
        _pay(user1, bytes32(uint256(1)), 1, 0, 1 ether);
        vm.startPrank(admin);
        policy.setMerchantAllowed(address(account), user3, true);
        policy.revokeRole(policy.POLICY_CONSUMER_ROLE(), address(account));
        vm.stopPrank();
        vm.expectRevert();
        _pay(user1, bytes32(uint256(1)), 1, 0, 1 ether);
        assertEq(account.nextNonce(), 0);
    }
}
