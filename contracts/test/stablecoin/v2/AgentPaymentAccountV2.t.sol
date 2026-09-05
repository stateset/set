// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2TestBase} from "./SSDCV2TestBase.sol";
import {AgentPaymentAccountV2} from "../../../stablecoin/v2/AgentPaymentAccountV2.sol";
import {SSDCPolicyModuleV2} from "../../../stablecoin/v2/SSDCPolicyModuleV2.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

contract InvoiceMerchant1271 is IERC1271 {
    bytes32 public approved;
    bool public reverts;
    function configure(bytes32 digest, bool reverts_) external { approved = digest; reverts = reverts_; }
    function isValidSignature(bytes32 digest, bytes memory) external view returns (bytes4) {
        require(!reverts, "MERCHANT_UNAVAILABLE");
        return digest == approved ? IERC1271.isValidSignature.selector : bytes4(0xffffffff);
    }
}

contract AgentPaymentAccountV2Test is SSDCV2TestBase {
    AgentPaymentAccountV2 internal account;
    SSDCPolicyModuleV2 internal policy;
    uint256 internal constant MERCHANT_KEY = 0xBEEF;

    function setUp() public override {
        super.setUp();
        user3 = vm.addr(MERCHANT_KEY);
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
        uint40 deadline = uint40(block.timestamp + 10 minutes);
        bytes memory signature = _sign(address(account), block.chainid, user3, address(vault), order, amount, deadline);
        vm.prank(key);
        account.pay(order, epoch, nonce, amount, type(uint256).max, deadline, signature);
    }

    function _sign(address target, uint256 chainId, address merchant, address token, bytes32 order, uint256 amount, uint40 deadline)
        internal returns (bytes memory)
    {
        bytes32 domain = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("AgentPaymentAccountV2"), keccak256("1"), chainId, target
        ));
        bytes32 invoice = keccak256(abi.encode(
            keccak256("Invoice(bytes32 orderId,address merchant,address vault,uint256 assets,uint40 deadline)"),
            order, merchant, token, amount, deadline
        ));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(MERCHANT_KEY, keccak256(abi.encodePacked(hex"1901", domain, invoice)));
        return abi.encodePacked(r, s, v);
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
        bytes memory signature = _sign(address(account), block.chainid, user3, address(vault), bytes32(uint256(1)), 1 ether, uint40(block.timestamp + 1));
        vm.startPrank(user1);
        vm.expectRevert(AgentPaymentAccountV2.InvalidPayment.selector);
        account.pay(bytes32(uint256(1)), 1, 0, 1 ether, 1 ether, uint40(block.timestamp), signature);
        vm.expectRevert(AgentPaymentAccountV2.InvalidPayment.selector);
        account.pay(bytes32(uint256(1)), 1, 0, 1 ether, 1, uint40(block.timestamp + 1), signature);
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

    function test_UnsignedAndLegacyPaymentsRejected() public {
        vm.startPrank(user1);
        vm.expectRevert(AgentPaymentAccountV2.InvalidInvoiceSignature.selector);
        account.pay(bytes32(uint256(1)), 1, 0, 1 ether, 1 ether, uint40(block.timestamp + 1), "");
        (bool ok,) = address(account).call(abi.encodeWithSignature(
            "pay(bytes32,uint256,uint256,uint256,uint256,uint40)", bytes32(uint256(1)), 1, 0, 1 ether, 1 ether, uint40(block.timestamp + 1)
        ));
        assertFalse(ok);
        vm.stopPrank();
        assertEq(account.nextNonce(), 0);
        assertEq(vault.balanceOf(user3), 0);
    }

    function testFuzz_InvoiceTamperingRejected(uint8 field) public {
        field = uint8(bound(field, 0, 6));
        bytes32 order = bytes32(uint256(1));
        uint40 deadline = uint40(block.timestamp + 10 minutes);
        bytes memory signature = _sign(
            field == 0 ? address(0x1234) : address(account),
            field == 1 ? block.chainid + 1 : block.chainid,
            field == 2 ? user2 : user3,
            field == 3 ? address(asset) : address(vault),
            field == 4 ? bytes32(uint256(2)) : order,
            field == 5 ? 2 ether : 1 ether,
            field == 6 ? deadline + 1 : deadline
        );
        vm.prank(user1);
        vm.expectRevert(AgentPaymentAccountV2.InvalidInvoiceSignature.selector);
        account.pay(order, 1, 0, 1 ether, 1 ether, deadline, signature);
        assertEq(account.nextNonce(), 0);
        assertFalse(account.paidOrders(order));
        assertTrue(policy.canSpend(address(account), user3, 100 ether));
    }

    function test_ERC1271MerchantValidatesAndCanRevokeInvoice() public {
        InvoiceMerchant1271 merchant = new InvoiceMerchant1271();
        vm.startPrank(admin);
        policy.setMerchantAllowed(address(account), address(merchant), true);
        account.setSession(user1, address(merchant), uint40(block.timestamp + 1 hours), 100 ether);
        vm.stopPrank();
        uint40 deadline = uint40(block.timestamp + 10 minutes);
        bytes32 order = bytes32(uint256(1));
        bytes32 digest = account.invoiceDigest(order, address(merchant), 1 ether, deadline);
        merchant.configure(digest, false);
        vm.prank(user1);
        account.pay(order, 2, 0, 1 ether, 1 ether, deadline, "");
        assertEq(vault.balanceOf(address(merchant)), 1 ether);

        order = bytes32(uint256(2));
        digest = account.invoiceDigest(order, address(merchant), 1 ether, deadline);
        merchant.configure(digest, false);
        merchant.configure(bytes32(0), false);
        vm.prank(user1);
        vm.expectRevert(AgentPaymentAccountV2.InvalidInvoiceSignature.selector);
        account.pay(order, 2, 1, 1 ether, 1 ether, deadline, "");
        merchant.configure(digest, true);
        vm.prank(user1);
        vm.expectRevert(AgentPaymentAccountV2.InvalidInvoiceSignature.selector);
        account.pay(order, 2, 1, 1 ether, 1 ether, deadline, "");
        assertEq(account.nextNonce(), 1);
    }
}
