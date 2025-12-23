// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../mev/ForcedInclusion.sol";

/**
 * @title ForcedInclusionTest
 * @notice Tests for L1 censorship resistance mechanism
 */
contract ForcedInclusionTest is Test {
    ForcedInclusion public forcedInclusion;

    address public owner = address(0x1);
    address public user = address(0x2);
    address public l2OutputOracle = address(0x3);
    address public optimismPortal = address(0x4);

    // Test data
    address public target = address(0x100);
    bytes public txData = abi.encodeWithSignature("doSomething()");
    uint256 public gasLimit = 100_000;

    function setUp() public {
        vm.deal(user, 10 ether);

        forcedInclusion = new ForcedInclusion(
            owner,
            l2OutputOracle,
            optimismPortal
        );
    }

    // =========================================================================
    // Initialization Tests
    // =========================================================================

    function test_Initialization() public view {
        assertEq(forcedInclusion.owner(), owner);
        assertEq(forcedInclusion.l2OutputOracle(), l2OutputOracle);
        assertEq(forcedInclusion.optimismPortal(), optimismPortal);
    }

    function test_Constants() public view {
        assertEq(forcedInclusion.INCLUSION_DEADLINE(), 24 hours);
        assertEq(forcedInclusion.MIN_BOND(), 0.01 ether);
        assertEq(forcedInclusion.MAX_GAS_LIMIT(), 10_000_000);
    }

    // =========================================================================
    // Force Transaction Tests
    // =========================================================================

    function test_ForceTransaction() public {
        vm.prank(user);
        bytes32 txId = forcedInclusion.forceTransaction{value: 0.1 ether}(
            target,
            txData,
            gasLimit
        );

        assertTrue(txId != bytes32(0));
        assertTrue(forcedInclusion.isPending(txId));

        (
            address sender,
            address txTarget,
            ,
            ,
            uint256 txGasLimit,
            uint256 bond,
            uint256 deadline,
            ,
            bool resolved
        ) = forcedInclusion.forcedTransactions(txId);

        assertEq(sender, user);
        assertEq(txTarget, target);
        assertEq(txGasLimit, gasLimit);
        assertEq(bond, 0.1 ether);
        assertEq(deadline, block.timestamp + 24 hours);
        assertFalse(resolved);
    }

    function test_ForceTransaction_UpdatesStats() public {
        vm.prank(user);
        forcedInclusion.forceTransaction{value: 0.1 ether}(
            target,
            txData,
            gasLimit
        );

        ForcedInclusion.Stats memory stats = forcedInclusion.getStats();
        assertEq(stats.totalForced, 1);
        assertEq(stats.totalBondsLocked, 0.1 ether);
    }

    function test_ForceTransaction_RevertsInsufficientBond() public {
        vm.prank(user);
        vm.expectRevert(ForcedInclusion.InsufficientBond.selector);
        forcedInclusion.forceTransaction{value: 0.001 ether}(
            target,
            txData,
            gasLimit
        );
    }

    function test_ForceTransaction_RevertsGasLimitTooHigh() public {
        vm.prank(user);
        vm.expectRevert(ForcedInclusion.GasLimitTooHigh.selector);
        forcedInclusion.forceTransaction{value: 0.1 ether}(
            target,
            txData,
            20_000_000 // Over MAX_GAS_LIMIT
        );
    }

    function test_ForceTransaction_MultipleTxs() public {
        vm.startPrank(user);

        bytes32 txId1 = forcedInclusion.forceTransaction{value: 0.1 ether}(
            target,
            txData,
            gasLimit
        );

        bytes32 txId2 = forcedInclusion.forceTransaction{value: 0.1 ether}(
            address(0x200),
            abi.encodeWithSignature("other()"),
            200_000
        );

        vm.stopPrank();

        assertTrue(txId1 != txId2);

        bytes32[] memory pending = forcedInclusion.getUserPendingTxs(user);
        assertEq(pending.length, 2);
    }

    // =========================================================================
    // Confirm Inclusion Tests
    // =========================================================================

    function test_ConfirmInclusion() public {
        vm.prank(user);
        bytes32 txId = forcedInclusion.forceTransaction{value: 0.1 ether}(
            target,
            txData,
            gasLimit
        );

        uint256 userBalanceBefore = user.balance;

        // Confirm inclusion with proof
        bytes memory proof = abi.encodePacked(bytes32(uint256(1)));
        forcedInclusion.confirmInclusion(txId, 100, proof);

        // Verify bond returned
        assertEq(user.balance, userBalanceBefore + 0.1 ether);

        // Verify resolved
        assertFalse(forcedInclusion.isPending(txId));

        ForcedInclusion.Stats memory stats = forcedInclusion.getStats();
        assertEq(stats.totalIncluded, 1);
        assertEq(stats.totalBondsLocked, 0);
    }

    function test_ConfirmInclusion_RevertsNotFound() public {
        bytes memory proof = abi.encodePacked(bytes32(uint256(1)));

        vm.expectRevert(ForcedInclusion.TransactionNotFound.selector);
        forcedInclusion.confirmInclusion(bytes32(uint256(999)), 100, proof);
    }

    function test_ConfirmInclusion_RevertsAlreadyResolved() public {
        vm.prank(user);
        bytes32 txId = forcedInclusion.forceTransaction{value: 0.1 ether}(
            target,
            txData,
            gasLimit
        );

        bytes memory proof = abi.encodePacked(bytes32(uint256(1)));
        forcedInclusion.confirmInclusion(txId, 100, proof);

        // Try again
        vm.expectRevert(ForcedInclusion.TransactionAlreadyResolved.selector);
        forcedInclusion.confirmInclusion(txId, 100, proof);
    }

    function test_ConfirmInclusion_RevertsInvalidProof() public {
        vm.prank(user);
        bytes32 txId = forcedInclusion.forceTransaction{value: 0.1 ether}(
            target,
            txData,
            gasLimit
        );

        // Empty proof should fail
        bytes memory emptyProof = "";

        vm.expectRevert(ForcedInclusion.InvalidInclusionProof.selector);
        forcedInclusion.confirmInclusion(txId, 100, emptyProof);
    }

    // =========================================================================
    // Claim Expired Tests
    // =========================================================================

    function test_ClaimExpired() public {
        vm.prank(user);
        bytes32 txId = forcedInclusion.forceTransaction{value: 0.1 ether}(
            target,
            txData,
            gasLimit
        );

        // Warp past deadline
        vm.warp(block.timestamp + 25 hours);

        assertTrue(forcedInclusion.isExpired(txId));

        uint256 userBalanceBefore = user.balance;

        forcedInclusion.claimExpired(txId);

        // Verify bond returned
        assertEq(user.balance, userBalanceBefore + 0.1 ether);

        // Verify resolved
        assertFalse(forcedInclusion.isPending(txId));

        ForcedInclusion.Stats memory stats = forcedInclusion.getStats();
        assertEq(stats.totalExpired, 1);
        assertEq(stats.totalBondsLocked, 0);
    }

    function test_ClaimExpired_RevertsBeforeDeadline() public {
        vm.prank(user);
        bytes32 txId = forcedInclusion.forceTransaction{value: 0.1 ether}(
            target,
            txData,
            gasLimit
        );

        // Only 1 hour passed
        vm.warp(block.timestamp + 1 hours);

        assertFalse(forcedInclusion.isExpired(txId));

        vm.expectRevert(ForcedInclusion.DeadlineNotReached.selector);
        forcedInclusion.claimExpired(txId);
    }

    function test_ClaimExpired_RevertsNotFound() public {
        vm.expectRevert(ForcedInclusion.TransactionNotFound.selector);
        forcedInclusion.claimExpired(bytes32(uint256(999)));
    }

    function test_ClaimExpired_RevertsAlreadyResolved() public {
        vm.prank(user);
        bytes32 txId = forcedInclusion.forceTransaction{value: 0.1 ether}(
            target,
            txData,
            gasLimit
        );

        vm.warp(block.timestamp + 25 hours);
        forcedInclusion.claimExpired(txId);

        // Try again
        vm.expectRevert(ForcedInclusion.TransactionAlreadyResolved.selector);
        forcedInclusion.claimExpired(txId);
    }

    // =========================================================================
    // Query Tests
    // =========================================================================

    function test_GetUserPendingTxs() public {
        vm.startPrank(user);

        bytes32 txId1 = forcedInclusion.forceTransaction{value: 0.1 ether}(
            target,
            txData,
            gasLimit
        );

        bytes32 txId2 = forcedInclusion.forceTransaction{value: 0.1 ether}(
            address(0x200),
            txData,
            gasLimit
        );

        vm.stopPrank();

        bytes32[] memory pending = forcedInclusion.getUserPendingTxs(user);
        assertEq(pending.length, 2);
        assertEq(pending[0], txId1);
        assertEq(pending[1], txId2);

        // Confirm one
        bytes memory proof = abi.encodePacked(bytes32(uint256(1)));
        forcedInclusion.confirmInclusion(txId1, 100, proof);

        pending = forcedInclusion.getUserPendingTxs(user);
        assertEq(pending.length, 1);
        assertEq(pending[0], txId2);
    }

    function test_IsPending() public {
        vm.prank(user);
        bytes32 txId = forcedInclusion.forceTransaction{value: 0.1 ether}(
            target,
            txData,
            gasLimit
        );

        assertTrue(forcedInclusion.isPending(txId));

        // Confirm
        bytes memory proof = abi.encodePacked(bytes32(uint256(1)));
        forcedInclusion.confirmInclusion(txId, 100, proof);

        assertFalse(forcedInclusion.isPending(txId));
    }

    function test_IsExpired() public {
        vm.prank(user);
        bytes32 txId = forcedInclusion.forceTransaction{value: 0.1 ether}(
            target,
            txData,
            gasLimit
        );

        assertFalse(forcedInclusion.isExpired(txId));

        vm.warp(block.timestamp + 25 hours);

        assertTrue(forcedInclusion.isExpired(txId));
    }

    // =========================================================================
    // Admin Tests
    // =========================================================================

    function test_SetL2OutputOracle() public {
        address newOracle = address(0x999);

        vm.prank(owner);
        forcedInclusion.setL2OutputOracle(newOracle);

        assertEq(forcedInclusion.l2OutputOracle(), newOracle);
    }

    function test_SetOptimismPortal() public {
        address newPortal = address(0x888);

        vm.prank(owner);
        forcedInclusion.setOptimismPortal(newPortal);

        assertEq(forcedInclusion.optimismPortal(), newPortal);
    }

    function test_OnlyOwnerCanSetAddresses() public {
        vm.prank(user);
        vm.expectRevert();
        forcedInclusion.setL2OutputOracle(address(0x999));

        vm.prank(user);
        vm.expectRevert();
        forcedInclusion.setOptimismPortal(address(0x888));
    }
}
