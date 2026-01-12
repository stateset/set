// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../mev/ThresholdKeyRegistry.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title ThresholdKeyRegistryTest
 * @notice Tests for threshold encryption key management
 */
contract ThresholdKeyRegistryTest is Test {
    ThresholdKeyRegistry public registry;
    address public registryProxy;

    address public owner = address(0x1);
    address public keyper1 = address(0x10);
    address public keyper2 = address(0x20);
    address public keyper3 = address(0x30);

    uint256 public minStake = 1 ether;
    uint256 public initialThreshold = 2;

    // Valid 48-byte BLS public key (placeholder)
    bytes public validPubKey = hex"a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4";

    function setUp() public {
        vm.startPrank(owner);

        // Deploy implementation
        ThresholdKeyRegistry impl = new ThresholdKeyRegistry();

        // Deploy proxy
        bytes memory initData = abi.encodeCall(
            ThresholdKeyRegistry.initialize,
            (owner, initialThreshold, minStake)
        );
        registryProxy = address(new ERC1967Proxy(address(impl), initData));
        registry = ThresholdKeyRegistry(payable(registryProxy));

        vm.stopPrank();
    }

    // =========================================================================
    // Initialization Tests
    // =========================================================================

    function test_Initialization() public view {
        assertEq(registry.owner(), owner);
        assertEq(registry.threshold(), initialThreshold);
        assertEq(registry.minStake(), minStake);
        assertEq(registry.currentEpoch(), 1);
        assertEq(registry.activeKeyperCount(), 0);
    }

    function test_Initialize_RevertsInvalidThreshold() public {
        ThresholdKeyRegistry impl = new ThresholdKeyRegistry();

        bytes memory initData = abi.encodeCall(
            ThresholdKeyRegistry.initialize,
            (owner, 1, minStake) // threshold < MIN_THRESHOLD
        );

        vm.expectRevert(ThresholdKeyRegistry.InvalidThreshold.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    // =========================================================================
    // Keyper Registration Tests
    // =========================================================================

    function test_RegisterKeyper() public {
        vm.deal(keyper1, 2 ether);
        vm.prank(keyper1);
        registry.registerKeyper{value: 1 ether}(validPubKey, "http://keyper1:8080");

        (
            address addr,
            bytes memory pubKey,
            string memory endpoint,
            uint256 registeredAt,
            bool active,
            uint256 slashCount
        ) = registry.keypers(keyper1);

        assertEq(addr, keyper1);
        assertEq(pubKey, validPubKey);
        assertEq(endpoint, "http://keyper1:8080");
        assertEq(registeredAt, block.number);
        assertTrue(active);
        assertEq(slashCount, 0);
        assertEq(registry.activeKeyperCount(), 1);
        assertEq(registry.stakes(keyper1), 1 ether);
    }

    function test_RegisterKeyper_RevertsInsufficientStake() public {
        vm.deal(keyper1, 0.5 ether);
        vm.prank(keyper1);

        vm.expectRevert(ThresholdKeyRegistry.InsufficientStake.selector);
        registry.registerKeyper{value: 0.5 ether}(validPubKey, "http://keyper1:8080");
    }

    function test_RegisterKeyper_RevertsInvalidPublicKey() public {
        vm.deal(keyper1, 2 ether);
        vm.prank(keyper1);

        bytes memory invalidPubKey = hex"a1b2c3"; // Only 3 bytes, not 48

        vm.expectRevert(ThresholdKeyRegistry.InvalidPublicKey.selector);
        registry.registerKeyper{value: 1 ether}(invalidPubKey, "http://keyper1:8080");
    }

    function test_RegisterKeyper_RevertsAlreadyRegistered() public {
        vm.deal(keyper1, 3 ether);

        vm.prank(keyper1);
        registry.registerKeyper{value: 1 ether}(validPubKey, "http://keyper1:8080");

        vm.prank(keyper1);
        vm.expectRevert(ThresholdKeyRegistry.KeyperAlreadyRegistered.selector);
        registry.registerKeyper{value: 1 ether}(validPubKey, "http://keyper1:8080");
    }

    function test_RegisterKeyper_RevertsTooManyKeypers() public {
        // Register MAX_KEYPERS (21)
        for (uint256 i = 0; i < 21; i++) {
            address keyper = address(uint160(100 + i));
            vm.deal(keyper, 2 ether);
            vm.prank(keyper);
            registry.registerKeyper{value: 1 ether}(validPubKey, "http://keyper:8080");
        }

        // Try to register one more
        address extraKeyper = address(0x999);
        vm.deal(extraKeyper, 2 ether);
        vm.prank(extraKeyper);

        vm.expectRevert(ThresholdKeyRegistry.TooManyKeypers.selector);
        registry.registerKeyper{value: 1 ether}(validPubKey, "http://extra:8080");
    }

    // =========================================================================
    // Keyper Deactivation Tests
    // =========================================================================

    function test_DeactivateKeyper_Self() public {
        _registerKeyper(keyper1);

        vm.prank(keyper1);
        registry.deactivateKeyper(keyper1, "Retiring");

        (, , , , bool active, ) = registry.keypers(keyper1);
        assertFalse(active);
        assertEq(registry.activeKeyperCount(), 0);
    }

    function test_DeactivateKeyper_ByOwner() public {
        _registerKeyper(keyper1);

        vm.prank(owner);
        registry.deactivateKeyper(keyper1, "Misbehavior");

        (, , , , bool active, ) = registry.keypers(keyper1);
        assertFalse(active);
    }

    function test_DeactivateKeyper_RevertsUnauthorized() public {
        _registerKeyper(keyper1);

        vm.prank(keyper2);
        vm.expectRevert(ThresholdKeyRegistry.KeyperNotRegistered.selector);
        registry.deactivateKeyper(keyper1, "Unauthorized");
    }

    // =========================================================================
    // Slashing Tests
    // =========================================================================

    function test_SlashKeyper() public {
        _registerKeyper(keyper1);

        vm.prank(owner);
        registry.slashKeyper(keyper1, 0.3 ether, "Missed decryption");

        assertEq(registry.stakes(keyper1), 0.7 ether);
        (, , , , , uint256 slashCount) = registry.keypers(keyper1);
        assertEq(slashCount, 1);
    }

    function test_SlashKeyper_DeactivatesIfBelowMinimum() public {
        _registerKeyper(keyper1);

        vm.prank(owner);
        registry.slashKeyper(keyper1, 0.5 ether, "Major violation");

        // Still has 0.5 ether, but minStake is 1 ether
        (, , , , bool active, ) = registry.keypers(keyper1);
        assertFalse(active);
        assertEq(registry.activeKeyperCount(), 0);
    }

    function test_SlashKeyper_CapsAtStake() public {
        _registerKeyper(keyper1);

        vm.prank(owner);
        registry.slashKeyper(keyper1, 5 ether, "Maximum penalty"); // More than stake

        assertEq(registry.stakes(keyper1), 0);
    }

    function test_SlashKeyper_RevertsOnlyOwner() public {
        _registerKeyper(keyper1);

        vm.prank(keyper2);
        vm.expectRevert();
        registry.slashKeyper(keyper1, 0.3 ether, "Unauthorized slash");
    }

    // =========================================================================
    // Withdraw Stake Tests
    // =========================================================================

    function test_WithdrawStake() public {
        _registerKeyper(keyper1);

        vm.prank(keyper1);
        registry.deactivateKeyper(keyper1, "Leaving");

        uint256 balanceBefore = keyper1.balance;

        vm.prank(keyper1);
        registry.withdrawStake();

        assertEq(keyper1.balance, balanceBefore + 1 ether);
        assertEq(registry.stakes(keyper1), 0);
    }

    function test_WithdrawStake_RevertsIfActive() public {
        _registerKeyper(keyper1);

        vm.prank(keyper1);
        vm.expectRevert(ThresholdKeyRegistry.KeyperNotRegistered.selector);
        registry.withdrawStake();
    }

    // =========================================================================
    // DKG Tests
    // =========================================================================

    function test_StartDKG() public {
        _registerKeypers(3);

        vm.prank(owner);
        registry.startDKG();

        assertEq(registry.getDKGPhase(), 1); // Registration phase
    }

    function test_StartDKG_RevertsNotEnoughKeypers() public {
        _registerKeyper(keyper1); // Only 1 keyper, threshold is 2

        vm.prank(owner);
        vm.expectRevert(ThresholdKeyRegistry.NotEnoughKeypers.selector);
        registry.startDKG();
    }

    function test_StartDKG_RevertsAlreadyActive() public {
        _registerKeypers(3);

        vm.prank(owner);
        registry.startDKG();

        vm.prank(owner);
        vm.expectRevert(ThresholdKeyRegistry.DKGAlreadyActive.selector);
        registry.startDKG();
    }

    function test_RegisterForDKG() public {
        _registerKeypers(3);

        vm.prank(owner);
        registry.startDKG();

        vm.prank(keyper1);
        registry.registerForDKG();

        address[] memory participants = registry.getDKGParticipants();
        assertEq(participants.length, 1);
        assertEq(participants[0], keyper1);
    }

    function test_RegisterForDKG_AdvancesPhase() public {
        _registerKeypers(3);

        vm.prank(owner);
        registry.startDKG();

        // Register threshold number of keypers to advance to dealing phase
        vm.prank(keyper1);
        registry.registerForDKG();

        vm.prank(keyper2);
        registry.registerForDKG();

        assertEq(registry.getDKGPhase(), 2); // Dealing phase
    }

    function test_SubmitDealing() public {
        _startDKGAndRegister();

        bytes32 dealingHash = keccak256("encrypted_dealing_1");

        vm.prank(keyper1);
        registry.submitDealing(dealingHash);
    }

    function test_SubmitDealing_RevertsDuplicate() public {
        _startDKGAndRegister();

        bytes32 dealingHash = keccak256("encrypted_dealing_1");

        vm.prank(keyper1);
        registry.submitDealing(dealingHash);

        vm.prank(keyper1);
        vm.expectRevert(ThresholdKeyRegistry.AlreadySubmittedDealing.selector);
        registry.submitDealing(dealingHash);
    }

    function test_SubmitDealing_RevertsNotRegisteredForDKG() public {
        _registerKeypers(3);

        vm.prank(owner);
        registry.startDKG();

        vm.prank(keyper1);
        registry.registerForDKG();
        vm.prank(keyper2);
        registry.registerForDKG(); // Advance to dealing phase

        vm.prank(keyper3);
        vm.expectRevert(ThresholdKeyRegistry.NotRegisteredForDKG.selector);
        registry.submitDealing(keccak256("dealing_unregistered"));
    }

    function test_FinalizeDKG() public {
        _startDKGAndRegister();

        // Submit dealings
        vm.prank(keyper1);
        registry.submitDealing(keccak256("dealing1"));

        vm.prank(keyper2);
        registry.submitDealing(keccak256("dealing2"));

        // Finalize
        bytes32 keyCommitment = keccak256("key_shares_commitment");

        vm.prank(owner);
        registry.finalizeDKG(validPubKey, keyCommitment);

        assertEq(registry.getDKGPhase(), 0); // Inactive
        assertEq(registry.currentEpoch(), 2);

        ThresholdKeyRegistry.ThresholdKey memory key = registry.getEpochKey(2);
        assertEq(key.epoch, 2);
        assertEq(key.aggregatedPubKey, validPubKey);
        assertEq(key.keyCommitment, keyCommitment);
        assertEq(key.threshold, 2);
        assertFalse(key.revoked);
    }

    function test_FinalizeDKG_RevertsNotEnoughDealings() public {
        _startDKGAndRegister();

        // Only one dealing (threshold is 2)
        vm.prank(keyper1);
        registry.submitDealing(keccak256("dealing1"));

        vm.prank(owner);
        vm.expectRevert(ThresholdKeyRegistry.NotEnoughKeypers.selector);
        registry.finalizeDKG(validPubKey, keccak256("commitment"));
    }

    // =========================================================================
    // Epoch Key Tests
    // =========================================================================

    function test_GetCurrentPublicKey() public {
        _completeDKG();

        bytes memory pubKey = registry.getCurrentPublicKey();
        assertEq(pubKey, validPubKey);
    }

    function test_IsEpochKeyValid() public {
        _completeDKG();

        assertTrue(registry.isEpochKeyValid(2));
        assertFalse(registry.isEpochKeyValid(1)); // Epoch 1 never had a key
        assertFalse(registry.isEpochKeyValid(999)); // Future epoch
    }

    function test_RevokeEpochKey() public {
        _completeDKG();

        vm.prank(owner);
        registry.revokeEpochKey(2, "Compromised key");

        ThresholdKeyRegistry.ThresholdKey memory key = registry.getEpochKey(2);
        assertTrue(key.revoked);
        assertFalse(registry.isEpochKeyValid(2));
    }

    function test_GetCurrentPublicKey_RevertsIfRevoked() public {
        _completeDKG();

        vm.prank(owner);
        registry.revokeEpochKey(2, "Emergency");

        vm.expectRevert(ThresholdKeyRegistry.KeyRevoked.selector);
        registry.getCurrentPublicKey();
    }

    // =========================================================================
    // Admin Tests
    // =========================================================================

    function test_SetThreshold() public {
        _registerKeypers(5);

        vm.prank(owner);
        registry.setThreshold(3);

        assertEq(registry.threshold(), 3);
    }

    function test_SetThreshold_RevertsBelowMinimum() public {
        vm.prank(owner);
        vm.expectRevert(ThresholdKeyRegistry.InvalidThreshold.selector);
        registry.setThreshold(1);
    }

    function test_SetThreshold_RevertsAboveKeyperCount() public {
        _registerKeypers(3);

        vm.prank(owner);
        vm.expectRevert(ThresholdKeyRegistry.InvalidThreshold.selector);
        registry.setThreshold(5); // Only 3 keypers
    }

    function test_SetMinStake() public {
        vm.prank(owner);
        registry.setMinStake(2 ether);

        assertEq(registry.minStake(), 2 ether);
    }

    function test_GetActiveKeypers() public {
        _registerKeypers(3);

        address[] memory activeKeypers = registry.getActiveKeypers();
        assertEq(activeKeypers.length, 3);
        assertEq(activeKeypers[0], keyper1);
        assertEq(activeKeypers[1], keyper2);
        assertEq(activeKeypers[2], keyper3);
    }

    // =========================================================================
    // Pause Tests
    // =========================================================================

    function test_Pause() public {
        vm.prank(owner);
        registry.pause();

        assertTrue(registry.paused());
    }

    function test_Unpause() public {
        vm.prank(owner);
        registry.pause();

        vm.prank(owner);
        registry.unpause();

        assertFalse(registry.paused());
    }

    function test_RegisterKeyper_RevertsWhenPaused() public {
        vm.prank(owner);
        registry.pause();

        vm.deal(keyper1, 2 ether);
        vm.prank(keyper1);

        vm.expectRevert();
        registry.registerKeyper{value: 1 ether}(validPubKey, "http://keyper1:8080");
    }

    // =========================================================================
    // Monitoring Function Tests
    // =========================================================================

    function test_GetRegistryStatus() public {
        _registerKeypers(3);

        (
            uint256 totalKeypers,
            uint256 activeCount,
            uint256 currentThreshold,
            uint256 epoch,
            uint256 dkgPhase,
            bool isPaused
        ) = registry.getRegistryStatus();

        assertEq(totalKeypers, 3);
        assertEq(activeCount, 3);
        assertEq(currentThreshold, 2);
        assertEq(epoch, 1);
        assertEq(dkgPhase, 0);
        assertFalse(isPaused);
    }

    function test_GetKeyperDetails() public {
        _registerKeyper(keyper1);

        (
            ThresholdKeyRegistry.Keyper memory keyperData,
            uint256 stakedAmount,
            bool isActive
        ) = registry.getKeyperDetails(keyper1);

        assertEq(keyperData.addr, keyper1);
        assertEq(stakedAmount, 1 ether);
        assertTrue(isActive);
    }

    function test_GetCurrentKeyStatus() public {
        _completeDKG();

        (
            bool valid,
            uint256 blocksRemaining,
            uint256 keyperCount,
            uint256 epochThreshold
        ) = registry.getCurrentKeyStatus();

        assertTrue(valid);
        assertTrue(blocksRemaining > 0);
        assertEq(keyperCount, 2);
        assertEq(epochThreshold, 2);
    }

    function test_GetDKGStatus() public {
        _registerKeypers(3);

        vm.prank(owner);
        registry.startDKG();

        (
            uint256 epoch,
            uint256 phase,
            uint256 deadline,
            uint256 participantCount,
            uint256 dealingsCount,
            uint256 blocksUntilDeadline
        ) = registry.getDKGStatus();

        assertEq(epoch, 2);
        assertEq(phase, 1);
        assertTrue(deadline > block.number);
        assertEq(participantCount, 0);
        assertEq(dealingsCount, 0);
        assertTrue(blocksUntilDeadline > 0);
    }

    function test_IsRegisteredForDKG() public {
        _registerKeypers(3);

        vm.prank(owner);
        registry.startDKG();

        assertFalse(registry.isRegisteredForDKG(keyper1));

        vm.prank(keyper1);
        registry.registerForDKG();

        assertTrue(registry.isRegisteredForDKG(keyper1));
    }

    function test_GetTotalStaked() public {
        _registerKeypers(3);

        uint256 totalStaked = registry.getTotalStaked();
        assertEq(totalStaked, 3 ether);
    }

    function test_GetAllKeypers() public {
        _registerKeypers(3);

        address[] memory allKeypers = registry.getAllKeypers();
        assertEq(allKeypers.length, 3);
    }

    function test_AbortDKG() public {
        _registerKeypers(3);

        vm.prank(owner);
        registry.startDKG();

        vm.prank(keyper1);
        registry.registerForDKG();

        vm.prank(owner);
        registry.abortDKG("Test abort");

        assertEq(registry.getDKGPhase(), 0);
    }

    function test_SetMinStake_RevertsZero() public {
        vm.prank(owner);
        vm.expectRevert(ThresholdKeyRegistry.InsufficientStake.selector);
        registry.setMinStake(0);
    }

    function test_WithdrawStake_RevertsZeroBalance() public {
        _registerKeyper(keyper1);

        vm.prank(keyper1);
        registry.deactivateKeyper(keyper1, "Leaving");

        vm.prank(keyper1);
        registry.withdrawStake();

        // Try to withdraw again with 0 balance
        vm.prank(keyper1);
        vm.expectRevert(ThresholdKeyRegistry.InsufficientStake.selector);
        registry.withdrawStake();
    }

    // =========================================================================
    // Helper Functions
    // =========================================================================

    function _registerKeyper(address keyper) internal {
        vm.deal(keyper, 2 ether);
        vm.prank(keyper);
        registry.registerKeyper{value: 1 ether}(validPubKey, "http://keyper:8080");
    }

    function _registerKeypers(uint256 count) internal {
        address[3] memory keyperAddrs = [keyper1, keyper2, keyper3];
        for (uint256 i = 0; i < count && i < 3; i++) {
            _registerKeyper(keyperAddrs[i]);
        }
    }

    function _startDKGAndRegister() internal {
        _registerKeypers(3);

        vm.prank(owner);
        registry.startDKG();

        vm.prank(keyper1);
        registry.registerForDKG();

        vm.prank(keyper2);
        registry.registerForDKG();

        // Now in dealing phase (phase 2)
    }

    function _completeDKG() internal {
        _startDKGAndRegister();

        vm.prank(keyper1);
        registry.submitDealing(keccak256("dealing1"));

        vm.prank(keyper2);
        registry.submitDealing(keccak256("dealing2"));

        vm.prank(owner);
        registry.finalizeDKG(validPubKey, keccak256("commitment"));
    }
}
