// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../SetRegistry.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice Tests for the optimistic STARK-proof finalization layer: challenge window, challenges,
///         resolution, and the isProofFinalized() finality signal.
contract SetRegistryProofFinalizationTest is Test {
    SetRegistry public registry;

    address public owner = address(0x1);
    address public sequencer = address(0x2);
    address public challenger = address(0x4);
    address public stranger = address(0x5);

    bytes32 public tenantId = bytes32(uint256(1));
    bytes32 public storeId = bytes32(uint256(100));
    bytes32 public constant BATCH = keccak256("batch-fin");

    uint64 public constant WINDOW = 1 hours;

    function setUp() public {
        SetRegistry impl = new SetRegistry();
        bytes memory initData = abi.encodeCall(SetRegistry.initialize, (owner, sequencer));
        registry = SetRegistry(address(new ERC1967Proxy(address(impl), initData)));

        vm.prank(owner);
        registry.setAuthorizedChallenger(challenger, true);
    }

    function _commitWithProof(bytes32 batchId) internal {
        vm.prank(sequencer);
        registry.commitBatchWithStarkProof(
            batchId,
            tenantId,
            storeId,
            keccak256("events"),
            bytes32(0),
            keccak256(abi.encode(batchId, "state")),
            1,
            10,
            10,
            keccak256("proof"),
            keccak256("policy"),
            100,
            true,
            1024,
            500
        );
    }

    // --- Finality timing ----------------------------------------------------

    function test_DefaultWindowZero_InstantFinality() public {
        // Window defaults to 0 -> proof is final the moment it is committed.
        _commitWithProof(BATCH);
        assertEq(registry.proofChallengeWindow(), 0);
        assertTrue(registry.isProofFinalized(BATCH));
    }

    function test_WindowOpen_NotFinalUntilElapsed() public {
        vm.prank(owner);
        registry.setProofChallengeWindow(WINDOW);

        _commitWithProof(BATCH);
        assertFalse(registry.isProofFinalized(BATCH)); // still inside window

        vm.warp(block.timestamp + WINDOW);
        assertTrue(registry.isProofFinalized(BATCH)); // window elapsed undisputed
    }

    function test_UnknownBatch_NotFinalized() public view {
        assertFalse(registry.isProofFinalized(keccak256("nope")));
    }

    // --- Challenges ---------------------------------------------------------

    function test_Challenge_BlocksFinalization() public {
        vm.prank(owner);
        registry.setProofChallengeWindow(WINDOW);
        _commitWithProof(BATCH);

        vm.prank(challenger);
        registry.challengeStarkProof(BATCH, keccak256("evidence"));

        (bool disputed,, address who,) = registry.getProofChallenge(BATCH);
        assertTrue(disputed);
        assertEq(who, challenger);

        // Even after the window elapses, a disputed proof never finalizes.
        vm.warp(block.timestamp + WINDOW + 1);
        assertFalse(registry.isProofFinalized(BATCH));
    }

    function test_Challenge_RevertsAfterWindow() public {
        vm.prank(owner);
        registry.setProofChallengeWindow(WINDOW);
        _commitWithProof(BATCH);

        vm.warp(block.timestamp + WINDOW);
        vm.prank(challenger);
        vm.expectRevert(SetRegistry.ChallengeWindowClosed.selector);
        registry.challengeStarkProof(BATCH, keccak256("evidence"));
    }

    function test_Challenge_OnlyAuthorized() public {
        vm.prank(owner);
        registry.setProofChallengeWindow(WINDOW);
        _commitWithProof(BATCH);

        vm.prank(stranger);
        vm.expectRevert(SetRegistry.NotAuthorizedChallenger.selector);
        registry.challengeStarkProof(BATCH, bytes32(0));
    }

    function test_Challenge_RevertsOnMissingProof() public {
        vm.prank(owner);
        registry.setProofChallengeWindow(WINDOW);
        vm.prank(challenger);
        vm.expectRevert(SetRegistry.NoStarkProof.selector);
        registry.challengeStarkProof(keccak256("absent"), bytes32(0));
    }

    function test_Challenge_NoDoubleDispute() public {
        vm.prank(owner);
        registry.setProofChallengeWindow(WINDOW);
        _commitWithProof(BATCH);

        vm.prank(challenger);
        registry.challengeStarkProof(BATCH, bytes32(0));
        vm.prank(challenger);
        vm.expectRevert(SetRegistry.ProofAlreadyDisputed.selector);
        registry.challengeStarkProof(BATCH, bytes32(0));
    }

    // --- Resolution ---------------------------------------------------------

    function test_ResolveUpheld_InvalidatesProof() public {
        vm.prank(owner);
        registry.setProofChallengeWindow(WINDOW);
        _commitWithProof(BATCH);

        vm.prank(challenger);
        registry.challengeStarkProof(BATCH, bytes32(0));

        vm.prank(owner);
        registry.resolveChallenge(BATCH, true); // proof was bad

        assertFalse(registry.hasStarkProof(BATCH));
        assertFalse(registry.isProofFinalized(BATCH));
        assertEq(registry.totalStarkProofs(), 1, "submission count is cumulative");
        (bool disputed,,,) = registry.getProofChallenge(BATCH);
        assertFalse(disputed);
    }

    function test_ResolveRejected_ProofStands() public {
        vm.prank(owner);
        registry.setProofChallengeWindow(WINDOW);
        _commitWithProof(BATCH);

        vm.prank(challenger);
        registry.challengeStarkProof(BATCH, bytes32(0));

        vm.prank(owner);
        registry.resolveChallenge(BATCH, false); // challenge rejected

        assertTrue(registry.hasStarkProof(BATCH));
        (bool disputed,,,) = registry.getProofChallenge(BATCH);
        assertFalse(disputed);

        vm.warp(block.timestamp + WINDOW);
        assertTrue(registry.isProofFinalized(BATCH));
    }

    function test_Resolve_RevertsWhenNotDisputed() public {
        _commitWithProof(BATCH);
        vm.prank(owner);
        vm.expectRevert(SetRegistry.ProofNotDisputed.selector);
        registry.resolveChallenge(BATCH, true);
    }

    // --- Access control -----------------------------------------------------

    function test_OnlyOwnerSetsWindow() public {
        vm.prank(stranger);
        vm.expectRevert();
        registry.setProofChallengeWindow(WINDOW);
    }

    function test_ChallengerManagement() public {
        assertEq(registry.authorizedChallengerCount(), 1); // challenger from setUp

        vm.prank(owner);
        registry.setAuthorizedChallenger(stranger, true);
        assertTrue(registry.authorizedChallengers(stranger));
        assertEq(registry.authorizedChallengerCount(), 2);

        // Idempotent: re-authorizing does not double-count.
        vm.prank(owner);
        registry.setAuthorizedChallenger(stranger, true);
        assertEq(registry.authorizedChallengerCount(), 2);

        vm.prank(owner);
        registry.setAuthorizedChallenger(stranger, false);
        assertFalse(registry.authorizedChallengers(stranger));
        assertEq(registry.authorizedChallengerCount(), 1);
    }
}
