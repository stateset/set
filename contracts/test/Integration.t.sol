// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../SetRegistry.sol";
import "../commerce/SetPaymaster.sol";
import "../governance/SetTimelock.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title IntegrationTest
 * @notice Integration tests across Set Chain contracts
 * @dev Tests cross-contract interactions and complete workflows
 */
contract IntegrationTest is Test {
    SetRegistry public registry;
    SetPaymaster public paymaster;
    SetTimelock public timelock;

    address public registryProxy;
    address public paymasterProxy;

    address public owner = address(0x1);
    address public sequencer = address(0x2);
    address public merchant = address(0x100);
    address public user = address(0x200);
    address public operator = address(0x300);

    // Proposers and executors for timelock
    address[] public proposers;
    address[] public executors;

    // Test data
    bytes32 public tenantId = keccak256("tenant1");
    bytes32 public storeId = keccak256("store1");
    bytes32 public batchId = keccak256("batch1");

    function setUp() public {
        vm.startPrank(owner);

        // Deploy SetRegistry
        SetRegistry registryImpl = new SetRegistry();
        bytes memory registryInitData = abi.encodeCall(
            SetRegistry.initialize,
            (owner)
        );
        registryProxy = address(new ERC1967Proxy(address(registryImpl), registryInitData));
        registry = SetRegistry(registryProxy);

        // Authorize sequencer
        registry.setSequencerAuthorization(sequencer, true);

        // Deploy SetPaymaster
        SetPaymaster paymasterImpl = new SetPaymaster();
        bytes memory paymasterInitData = abi.encodeCall(
            SetPaymaster.initialize,
            (owner)
        );
        paymasterProxy = address(new ERC1967Proxy(address(paymasterImpl), paymasterInitData));
        paymaster = SetPaymaster(payable(paymasterProxy));

        // Setup paymaster
        paymaster.setOperator(operator, true);

        // Deploy SetTimelock
        proposers.push(owner);
        executors.push(owner);
        timelock = new SetTimelock(5 minutes, proposers, executors, owner);

        vm.stopPrank();

        // Fund contracts
        vm.deal(paymasterProxy, 10 ether);
        vm.deal(merchant, 5 ether);
        vm.deal(user, 1 ether);
    }

    // =========================================================================
    // Complete Workflow Tests
    // =========================================================================

    /**
     * @notice Test complete merchant onboarding and sponsored transaction flow
     */
    function test_CompleteMerchantSponsorshipFlow() public {
        // Step 1: Merchant deposits to paymaster
        vm.prank(merchant);
        paymaster.deposit{value: 1 ether}();

        // Step 2: Operator sponsors merchant with Growth tier (tier 2)
        vm.prank(operator);
        paymaster.sponsorMerchant(merchant, 2);

        // Step 3: Verify merchant is active
        (bool active, uint256 tierId, , , ) = paymaster.getMerchantDetails(merchant);
        assertTrue(active);
        assertEq(tierId, 2);

        // Step 4: Execute multiple sponsorships for different operations
        vm.startPrank(operator);

        // Sponsor order creation
        paymaster.executeSponsorship(merchant, 0.001 ether, 0); // ORDER_CREATE

        // Sponsor payment processing
        paymaster.executeSponsorship(merchant, 0.0005 ether, 2); // PAYMENT_PROCESS

        // Sponsor commitment anchor
        paymaster.executeSponsorship(merchant, 0.002 ether, 5); // COMMITMENT_ANCHOR

        vm.stopPrank();

        // Step 5: Verify spending tracked correctly
        (, , uint256 spentToday, , uint256 totalSponsored) = paymaster.getMerchantDetails(merchant);
        assertEq(spentToday, 0.0035 ether);
        assertEq(totalSponsored, 0.0035 ether);
    }

    /**
     * @notice Test batch commitment with subsequent verification
     */
    function test_CompleteBatchCommitAndVerifyFlow() public {
        // Step 1: Build a batch with events
        bytes32[] memory events = new bytes32[](4);
        events[0] = keccak256("order_created_1");
        events[1] = keccak256("payment_processed_1");
        events[2] = keccak256("order_created_2");
        events[3] = keccak256("inventory_updated_1");

        // Step 2: Build merkle tree
        (bytes32 eventsRoot, bytes32[][] memory proofs) = _buildMerkleTree(events);

        // Step 3: Commit batch as sequencer
        bytes32 prevStateRoot = bytes32(0);
        bytes32 newStateRoot = keccak256("state_after_batch1");

        vm.prank(sequencer);
        registry.commitBatch(
            batchId,
            tenantId,
            storeId,
            eventsRoot,
            prevStateRoot,
            newStateRoot,
            1, // sequenceStart
            4, // sequenceEnd
            4  // eventCount
        );

        // Step 4: Verify state root updated
        assertEq(registry.getLatestStateRoot(tenantId, storeId), newStateRoot);
        assertEq(registry.getHeadSequence(tenantId, storeId), 4);

        // Step 5: Verify each event inclusion
        for (uint256 i = 0; i < events.length; i++) {
            bool valid = registry.verifyInclusion(batchId, events[i], proofs[i], i);
            assertTrue(valid, string(abi.encodePacked("Event ", i, " not verified")));
        }

        // Step 6: Verify non-included event fails
        bytes32 fakeEvent = keccak256("fake_event");
        bool fakeValid = registry.verifyInclusion(batchId, fakeEvent, proofs[0], 0);
        assertFalse(fakeValid);
    }

    /**
     * @notice Test multi-batch state chain continuity
     */
    function test_MultiTenantIsolation() public {
        bytes32 tenant1 = keccak256("tenant1");
        bytes32 tenant2 = keccak256("tenant2");
        bytes32 store = keccak256("store1");

        // Commit to tenant1
        vm.prank(sequencer);
        registry.commitBatch(
            keccak256("batch_t1"),
            tenant1,
            store,
            keccak256("events_t1"),
            bytes32(0),
            keccak256("state_t1"),
            1, 10, 10
        );

        // Commit to tenant2
        vm.prank(sequencer);
        registry.commitBatch(
            keccak256("batch_t2"),
            tenant2,
            store,
            keccak256("events_t2"),
            bytes32(0),
            keccak256("state_t2"),
            1, 5, 5
        );

        // Verify isolation - different state roots
        assertEq(registry.getLatestStateRoot(tenant1, store), keccak256("state_t1"));
        assertEq(registry.getLatestStateRoot(tenant2, store), keccak256("state_t2"));

        // Verify isolation - different sequences
        assertEq(registry.getHeadSequence(tenant1, store), 10);
        assertEq(registry.getHeadSequence(tenant2, store), 5);
    }

    /**
     * @notice Test sequential batches with state chain continuity
     */
    function test_StateChainContinuity() public {
        // Enable strict mode
        vm.prank(owner);
        registry.setStrictMode(true);

        bytes32 state0 = bytes32(0);
        bytes32 state1 = keccak256("state1");
        bytes32 state2 = keccak256("state2");
        bytes32 state3 = keccak256("state3");

        // Batch 1
        vm.prank(sequencer);
        registry.commitBatch(
            keccak256("batch1"),
            tenantId,
            storeId,
            keccak256("events1"),
            state0,
            state1,
            1, 10, 10
        );

        // Batch 2 - must reference state1
        vm.prank(sequencer);
        registry.commitBatch(
            keccak256("batch2"),
            tenantId,
            storeId,
            keccak256("events2"),
            state1,
            state2,
            11, 20, 10
        );

        // Batch 3 - must reference state2
        vm.prank(sequencer);
        registry.commitBatch(
            keccak256("batch3"),
            tenantId,
            storeId,
            keccak256("events3"),
            state2,
            state3,
            21, 30, 10
        );

        // Verify final state
        assertEq(registry.getLatestStateRoot(tenantId, storeId), state3);
        assertEq(registry.getHeadSequence(tenantId, storeId), 30);

        // Try invalid batch (wrong prev state) - should fail
        vm.prank(sequencer);
        vm.expectRevert(SetRegistry.InvalidPrevStateRoot.selector);
        registry.commitBatch(
            keccak256("batch_invalid"),
            tenantId,
            storeId,
            keccak256("events_invalid"),
            state1, // Should be state3!
            keccak256("state_invalid"),
            31, 40, 10
        );
    }

    /**
     * @notice Test governance timelock flow for parameter changes
     */
    function test_TimelockGovernanceFlow() public {
        // Step 1: Propose changing sequencer authorization
        address newSequencer = address(0x999);

        bytes memory callData = abi.encodeCall(
            SetRegistry.setSequencerAuthorization,
            (newSequencer, true)
        );

        bytes32 opId = timelock.hashOperation(
            registryProxy,
            0,
            callData,
            bytes32(0),
            keccak256("authorize_new_sequencer")
        );

        // Step 2: Schedule operation
        vm.prank(owner);
        timelock.schedule(
            registryProxy,
            0,
            callData,
            bytes32(0),
            keccak256("authorize_new_sequencer"),
            5 minutes
        );

        assertTrue(timelock.isOperationPending(opId));

        // Step 3: Cannot execute before delay
        vm.expectRevert();
        timelock.execute(
            registryProxy,
            0,
            callData,
            bytes32(0),
            keccak256("authorize_new_sequencer")
        );

        // Step 4: Warp past delay
        vm.warp(block.timestamp + 6 minutes);

        // Step 5: Execute
        vm.prank(owner);
        timelock.execute(
            registryProxy,
            0,
            callData,
            bytes32(0),
            keccak256("authorize_new_sequencer")
        );

        // Step 6: Verify change applied
        assertTrue(registry.authorizedSequencers(newSequencer));
        assertTrue(timelock.isOperationDone(opId));
    }

    /**
     * @notice Test spending limits across daily reset
     */
    function test_DailyLimitResetFlow() public {
        // Setup merchant
        vm.prank(operator);
        paymaster.sponsorMerchant(merchant, 1); // Starter tier: 0.1 ETH daily

        // Spend up to daily limit
        vm.startPrank(operator);

        // This should work (within limit)
        paymaster.executeSponsorship(merchant, 0.05 ether, 0);
        paymaster.executeSponsorship(merchant, 0.04 ether, 0);

        // This should fail (exceeds daily limit)
        vm.expectRevert(SetPaymaster.DailyLimitExceeded.selector);
        paymaster.executeSponsorship(merchant, 0.02 ether, 0);

        vm.stopPrank();

        // Warp to next day
        vm.warp(block.timestamp + 1 days);

        // Should work again after reset
        vm.prank(operator);
        paymaster.executeSponsorship(merchant, 0.05 ether, 0);

        (, , uint256 spentToday, , ) = paymaster.getMerchantDetails(merchant);
        assertEq(spentToday, 0.05 ether); // Reset to new day's spending
    }

    /**
     * @notice Test refund mechanism
     */
    function test_RefundMechanismFlow() public {
        // Setup merchant with deposit
        vm.prank(merchant);
        paymaster.deposit{value: 0.5 ether}();

        vm.prank(operator);
        paymaster.sponsorMerchant(merchant, 2);

        // Spend some
        vm.prank(operator);
        paymaster.executeSponsorship(merchant, 0.1 ether, 0);

        // Issue refund (simulating overcharge correction)
        vm.prank(operator);
        paymaster.refund(merchant, 0.02 ether);

        // Verify refund recorded
        (, , uint256 spentToday, , uint256 totalSponsored) = paymaster.getMerchantDetails(merchant);
        assertEq(spentToday, 0.08 ether);
        assertEq(totalSponsored, 0.08 ether);
    }

    // =========================================================================
    // Edge Case Integration Tests
    // =========================================================================

    /**
     * @notice Test merchant deactivation mid-flow
     */
    function test_MerchantDeactivationMidFlow() public {
        // Setup active merchant
        vm.prank(operator);
        paymaster.sponsorMerchant(merchant, 2);

        // Execute one sponsorship
        vm.prank(operator);
        paymaster.executeSponsorship(merchant, 0.01 ether, 0);

        // Deactivate merchant
        vm.prank(owner);
        paymaster.deactivateMerchant(merchant);

        // Further sponsorships should fail
        vm.prank(operator);
        vm.expectRevert(SetPaymaster.MerchantNotActive.selector);
        paymaster.executeSponsorship(merchant, 0.01 ether, 0);
    }

    /**
     * @notice Test concurrent batch commits to same tenant
     */
    function test_ConcurrentBatchCommits() public {
        // Two batches to same tenant but different stores
        bytes32 store1 = keccak256("store1");
        bytes32 store2 = keccak256("store2");

        vm.startPrank(sequencer);

        registry.commitBatch(
            keccak256("batch_s1"),
            tenantId,
            store1,
            keccak256("events_s1"),
            bytes32(0),
            keccak256("state_s1"),
            1, 10, 10
        );

        registry.commitBatch(
            keccak256("batch_s2"),
            tenantId,
            store2,
            keccak256("events_s2"),
            bytes32(0),
            keccak256("state_s2"),
            1, 5, 5
        );

        vm.stopPrank();

        // Both stores have independent state
        assertEq(registry.getLatestStateRoot(tenantId, store1), keccak256("state_s1"));
        assertEq(registry.getLatestStateRoot(tenantId, store2), keccak256("state_s2"));
    }

    /**
     * @notice Test multiple inclusion proofs in single call
     */
    function test_MultipleInclusionVerification() public {
        // Build batch
        bytes32[] memory events = new bytes32[](4);
        events[0] = keccak256("event0");
        events[1] = keccak256("event1");
        events[2] = keccak256("event2");
        events[3] = keccak256("event3");

        (bytes32 eventsRoot, bytes32[][] memory proofs) = _buildMerkleTree(events);

        vm.prank(sequencer);
        registry.commitBatch(
            batchId, tenantId, storeId, eventsRoot,
            bytes32(0), keccak256("state"), 1, 4, 4
        );

        // Verify multiple at once
        uint256[] memory indices = new uint256[](4);
        indices[0] = 0;
        indices[1] = 1;
        indices[2] = 2;
        indices[3] = 3;

        bool allValid = registry.verifyMultipleInclusions(batchId, events, proofs, indices);
        assertTrue(allValid);

        // Verify fails if one is wrong
        events[2] = keccak256("wrong_event");
        allValid = registry.verifyMultipleInclusions(batchId, events, proofs, indices);
        assertFalse(allValid);
    }

    // =========================================================================
    // Helper Functions
    // =========================================================================

    function _buildMerkleTree(
        bytes32[] memory leaves
    ) internal pure returns (bytes32 root, bytes32[][] memory proofs) {
        require(leaves.length == 4, "Only supports 4 leaves");

        // Level 1
        bytes32 h01 = keccak256(abi.encodePacked(leaves[0], leaves[1]));
        bytes32 h23 = keccak256(abi.encodePacked(leaves[2], leaves[3]));

        // Root
        root = keccak256(abi.encodePacked(h01, h23));

        // Build proofs
        proofs = new bytes32[][](4);

        proofs[0] = new bytes32[](2);
        proofs[0][0] = leaves[1];
        proofs[0][1] = h23;

        proofs[1] = new bytes32[](2);
        proofs[1][0] = leaves[0];
        proofs[1][1] = h23;

        proofs[2] = new bytes32[](2);
        proofs[2][0] = leaves[3];
        proofs[2][1] = h01;

        proofs[3] = new bytes32[](2);
        proofs[3][0] = leaves[2];
        proofs[3][1] = h01;
    }
}
