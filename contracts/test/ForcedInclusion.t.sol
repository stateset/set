// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../mev/ForcedInclusion.sol";

contract MockL2OutputOracle {
    mapping(uint256 => bytes32) public outputRoots;

    function setL2Output(uint256 blockNumber, bytes32 outputRoot) external {
        outputRoots[blockNumber] = outputRoot;
    }

    function getL2Output(uint256 _l2BlockNumber) external view returns (bytes32) {
        return outputRoots[_l2BlockNumber];
    }
}

contract MockTxRootOracle {
    mapping(uint256 => bytes32) public txRoots;

    function setTxRoot(uint256 blockNumber, bytes32 txRoot) external {
        txRoots[blockNumber] = txRoot;
    }

    function getTxRoot(uint256 blockNumber) external view returns (bytes32) {
        return txRoots[blockNumber];
    }
}

/**
 * @title ForcedInclusionTest
 * @notice Tests for L1 censorship resistance mechanism
 */
contract ForcedInclusionTest is Test {
    ForcedInclusion public forcedInclusion;
    MockL2OutputOracle public outputOracle;
    MockTxRootOracle public txRootOracle;

    address public owner = address(0x1);
    address public user = address(0x2);
    address public optimismPortal = address(0x4);

    // Test data
    address public target = address(0x100);
    bytes public txData = abi.encodeWithSignature("doSomething()");
    uint256 public gasLimit = 100_000;

    function setUp() public {
        vm.deal(user, 10 ether);

        outputOracle = new MockL2OutputOracle();
        txRootOracle = new MockTxRootOracle();

        forcedInclusion = new ForcedInclusion(
            owner,
            address(outputOracle),
            optimismPortal
        );

        vm.prank(owner);
        forcedInclusion.setTxRootOracle(address(txRootOracle));
    }

    // =========================================================================
    // Initialization Tests
    // =========================================================================

    function test_Initialization() public view {
        assertEq(forcedInclusion.owner(), owner);
        assertEq(forcedInclusion.l2OutputOracle(), address(outputOracle));
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
        bytes memory proof = _buildProof(user, target, txData, gasLimit, 100);
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
        bytes memory proof = _buildProof(user, target, txData, gasLimit, 100);

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

        bytes memory proof = _buildProof(user, target, txData, gasLimit, 100);
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
        bytes memory proof = _buildProof(user, target, txData, gasLimit, 100);
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
        bytes memory proof = _buildProof(user, target, txData, gasLimit, 100);
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

        vm.prank(user);
        vm.expectRevert();
        forcedInclusion.setTxRootOracle(address(0x777));
    }

    // =========================================================================
    // Input Validation Tests
    // =========================================================================

    function test_Constructor_RevertsZeroOwner() public {
        vm.expectRevert(ForcedInclusion.InvalidAddress.selector);
        new ForcedInclusion(
            address(0),
            address(outputOracle),
            optimismPortal
        );
    }

    function test_SetL2OutputOracle_RevertsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(ForcedInclusion.InvalidAddress.selector);
        forcedInclusion.setL2OutputOracle(address(0));
    }

    function test_SetOptimismPortal_RevertsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(ForcedInclusion.InvalidAddress.selector);
        forcedInclusion.setOptimismPortal(address(0));
    }

    function test_ForceTransaction_RevertsZeroTarget() public {
        vm.prank(user);
        vm.expectRevert(ForcedInclusion.InvalidTarget.selector);
        forcedInclusion.forceTransaction{value: 0.1 ether}(
            address(0),
            txData,
            gasLimit
        );
    }

    // =========================================================================
    // Event Tests
    // =========================================================================

    function test_SetL2OutputOracle_EmitsEvent() public {
        address newOracle = address(0x999);

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit ForcedInclusion.L2OutputOracleUpdated(address(outputOracle), newOracle);
        forcedInclusion.setL2OutputOracle(newOracle);
    }

    function test_SetOptimismPortal_EmitsEvent() public {
        address newPortal = address(0x888);

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit ForcedInclusion.OptimismPortalUpdated(optimismPortal, newPortal);
        forcedInclusion.setOptimismPortal(newPortal);
    }

    // =========================================================================
    // Monitoring Function Tests
    // =========================================================================

    function test_GetSystemStatus() public {
        // Initial state
        (
            uint256 pendingCount,
            uint256 totalForced,
            uint256 totalIncluded,
            uint256 totalExpired,
            uint256 bondsLocked,
            bool isPaused,
            uint256 circuitBreakerCapacity
        ) = forcedInclusion.getSystemStatus();

        assertEq(pendingCount, 0);
        assertEq(totalForced, 0);
        assertEq(totalIncluded, 0);
        assertEq(totalExpired, 0);
        assertEq(bondsLocked, 0);
        assertFalse(isPaused);
        assertEq(circuitBreakerCapacity, 1000); // Default maxPendingTxs

        // Add a transaction
        vm.prank(user);
        forcedInclusion.forceTransaction{value: 0.1 ether}(
            target,
            txData,
            gasLimit
        );

        (
            pendingCount,
            totalForced,
            ,
            ,
            bondsLocked,
            ,
            circuitBreakerCapacity
        ) = forcedInclusion.getSystemStatus();

        assertEq(pendingCount, 1);
        assertEq(totalForced, 1);
        assertEq(bondsLocked, 0.1 ether);
        assertEq(circuitBreakerCapacity, 999);
    }

    function test_GetTxDetails() public {
        vm.prank(user);
        bytes32 txId = forcedInclusion.forceTransaction{value: 0.1 ether}(
            target,
            txData,
            gasLimit
        );

        (
            address sender,
            address txTarget,
            uint256 bond,
            uint256 deadline,
            bool isResolved,
            bool isExpiredNow,
            uint256 timeRemaining
        ) = forcedInclusion.getTxDetails(txId);

        assertEq(sender, user);
        assertEq(txTarget, target);
        assertEq(bond, 0.1 ether);
        assertEq(deadline, block.timestamp + 24 hours);
        assertFalse(isResolved);
        assertFalse(isExpiredNow);
        assertEq(timeRemaining, 24 hours);
    }

    function test_GetTxDetails_Expired() public {
        vm.prank(user);
        bytes32 txId = forcedInclusion.forceTransaction{value: 0.1 ether}(
            target,
            txData,
            gasLimit
        );

        // Warp past deadline
        vm.warp(block.timestamp + 25 hours);

        (
            ,
            ,
            ,
            ,
            bool isResolved,
            bool isExpiredNow,
            uint256 timeRemaining
        ) = forcedInclusion.getTxDetails(txId);

        assertFalse(isResolved);
        assertTrue(isExpiredNow);
        assertEq(timeRemaining, 0);
    }

    function test_GetBatchTxStatuses() public {
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

        // Confirm one
        bytes memory proof = _buildProof(user, target, txData, gasLimit, 100);
        forcedInclusion.confirmInclusion(txId1, 100, proof);

        // Warp to expire the other
        vm.warp(block.timestamp + 25 hours);

        bytes32[] memory txIds = new bytes32[](2);
        txIds[0] = txId1;
        txIds[1] = txId2;

        (bool[] memory resolved, bool[] memory expired) = forcedInclusion.getBatchTxStatuses(txIds);

        assertEq(resolved.length, 2);
        assertEq(expired.length, 2);
        assertTrue(resolved[0]); // txId1 was confirmed
        assertFalse(resolved[1]); // txId2 not resolved
        assertFalse(expired[0]); // txId1 resolved, not expired
        assertTrue(expired[1]); // txId2 is expired
    }

    function test_GetInclusionRate() public {
        // Initially 100%
        assertEq(forcedInclusion.getInclusionRate(), 10000);

        // Force and confirm one transaction
        vm.prank(user);
        bytes32 txId1 = forcedInclusion.forceTransaction{value: 0.1 ether}(
            target,
            txData,
            gasLimit
        );

        bytes memory proof = _buildProof(user, target, txData, gasLimit, 100);
        forcedInclusion.confirmInclusion(txId1, 100, proof);

        // Still 100%
        assertEq(forcedInclusion.getInclusionRate(), 10000);

        // Force and let one expire
        vm.prank(user);
        bytes32 txId2 = forcedInclusion.forceTransaction{value: 0.1 ether}(
            address(0x200),
            txData,
            gasLimit
        );

        vm.warp(block.timestamp + 25 hours);
        forcedInclusion.claimExpired(txId2);

        // Now 50% = 5000 basis points
        assertEq(forcedInclusion.getInclusionRate(), 5000);
    }

    function test_GetUserSummary() public {
        vm.startPrank(user);

        forcedInclusion.forceTransaction{value: 0.1 ether}(
            target,
            txData,
            gasLimit
        );

        forcedInclusion.forceTransaction{value: 0.1 ether}(
            address(0x200),
            txData,
            gasLimit
        );

        vm.stopPrank();

        (
            uint256 totalSubmitted,
            uint256 pendingCount,
            uint256 currentRateUsed,
            bool canSubmitNow
        ) = forcedInclusion.getUserSummary(user);

        assertEq(totalSubmitted, 2);
        assertEq(pendingCount, 2);
        assertEq(currentRateUsed, 2);
        assertTrue(canSubmitNow); // Haven't hit rate limit yet
    }

    function test_GetUserSummary_RateLimited() public {
        // Set low rate limit for testing
        vm.prank(owner);
        forcedInclusion.setCircuitBreakerLimits(1000, 2);

        vm.startPrank(user);

        forcedInclusion.forceTransaction{value: 0.1 ether}(
            target,
            txData,
            gasLimit
        );

        forcedInclusion.forceTransaction{value: 0.1 ether}(
            address(0x200),
            txData,
            gasLimit
        );

        vm.stopPrank();

        (
            ,
            ,
            uint256 currentRateUsed,
            bool canSubmitNow
        ) = forcedInclusion.getUserSummary(user);

        assertEq(currentRateUsed, 2);
        assertFalse(canSubmitNow); // At rate limit
    }

    // =========================================================================
    // Circuit Breaker Tests
    // =========================================================================

    function test_CircuitBreaker_RevertsWhenTripped() public {
        // Set very low limit
        vm.prank(owner);
        forcedInclusion.setCircuitBreakerLimits(2, 100);

        vm.startPrank(user);

        // Submit 2 (should work)
        forcedInclusion.forceTransaction{value: 0.1 ether}(target, txData, gasLimit);
        forcedInclusion.forceTransaction{value: 0.1 ether}(address(0x200), txData, gasLimit);

        // 3rd should trip circuit breaker
        vm.expectRevert(ForcedInclusion.CircuitBreakerTripped.selector);
        forcedInclusion.forceTransaction{value: 0.1 ether}(address(0x300), txData, gasLimit);

        vm.stopPrank();
    }

    function test_RateLimit_RevertsWhenExceeded() public {
        // Set very low rate limit
        vm.prank(owner);
        forcedInclusion.setCircuitBreakerLimits(1000, 2);

        vm.startPrank(user);

        // Submit 2 (should work)
        forcedInclusion.forceTransaction{value: 0.1 ether}(target, txData, gasLimit);
        forcedInclusion.forceTransaction{value: 0.1 ether}(address(0x200), txData, gasLimit);

        // 3rd should hit rate limit
        vm.expectRevert(ForcedInclusion.RateLimitExceeded.selector);
        forcedInclusion.forceTransaction{value: 0.1 ether}(address(0x300), txData, gasLimit);

        vm.stopPrank();
    }

    function test_RateLimit_ResetsAfterHour() public {
        // Set very low rate limit
        vm.prank(owner);
        forcedInclusion.setCircuitBreakerLimits(1000, 1);

        vm.prank(user);
        forcedInclusion.forceTransaction{value: 0.1 ether}(target, txData, gasLimit);

        // Should fail immediately
        vm.prank(user);
        vm.expectRevert(ForcedInclusion.RateLimitExceeded.selector);
        forcedInclusion.forceTransaction{value: 0.1 ether}(address(0x200), txData, gasLimit);

        // Warp forward 1 hour
        vm.warp(block.timestamp + 1 hours);

        // Should work now
        vm.prank(user);
        bytes32 txId = forcedInclusion.forceTransaction{value: 0.1 ether}(address(0x200), txData, gasLimit);
        assertTrue(txId != bytes32(0));
    }

    function test_IsRateLimited() public {
        (bool limited, uint256 remaining) = forcedInclusion.isRateLimited(user);
        assertFalse(limited);
        assertEq(remaining, 10); // Default maxTxsPerUserPerHour

        // Submit one
        vm.prank(user);
        forcedInclusion.forceTransaction{value: 0.1 ether}(target, txData, gasLimit);

        (limited, remaining) = forcedInclusion.isRateLimited(user);
        assertFalse(limited);
        assertEq(remaining, 9);
    }

    function test_GetPendingCount() public {
        assertEq(forcedInclusion.getPendingCount(), 0);

        vm.prank(user);
        forcedInclusion.forceTransaction{value: 0.1 ether}(target, txData, gasLimit);

        assertEq(forcedInclusion.getPendingCount(), 1);
    }

    function _buildProof(
        address sender,
        address txTarget,
        bytes memory data,
        uint256 gasLimit_,
        uint256 l2BlockNumber
    ) internal returns (bytes memory) {
        bytes32 outputRoot = keccak256(abi.encodePacked("output", l2BlockNumber));
        outputOracle.setL2Output(l2BlockNumber, outputRoot);

        bytes32 txHash = keccak256(abi.encodePacked(sender, txTarget, data, gasLimit_));
        txRootOracle.setTxRoot(l2BlockNumber, txHash);

        bytes32[] memory proof = new bytes32[](0);
        return abi.encode(outputRoot, txHash, proof, uint256(0));
    }
}
