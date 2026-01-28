// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../mev/SequencerAttestation.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title SequencerAttestationTest
 * @notice Tests for MEV protection ordering attestation
 */
contract SequencerAttestationTest is Test {
    SequencerAttestation public attestation;
    address public attestationProxy;

    address public owner = address(0x1);
    address public sequencer;
    uint256 public sequencerKey = 0x12345;

    // Test data
    bytes32 public blockHash = keccak256("block1");
    uint64 public blockNumber = 100;
    uint32 public txCount = 5;

    function setUp() public {
        sequencer = vm.addr(sequencerKey);

        vm.startPrank(owner);

        // Deploy implementation
        SequencerAttestation impl = new SequencerAttestation();

        // Deploy proxy
        bytes memory initData = abi.encodeCall(
            SequencerAttestation.initialize,
            (owner, sequencer)
        );
        attestationProxy = address(new ERC1967Proxy(address(impl), initData));
        attestation = SequencerAttestation(attestationProxy);

        vm.stopPrank();
    }

    // =========================================================================
    // Initialization Tests
    // =========================================================================

    function test_Initialization() public view {
        assertEq(attestation.owner(), owner);
        assertTrue(attestation.authorizedSequencers(sequencer));
        assertFalse(attestation.authorizedSequencers(address(0x999)));
    }

    function test_DomainSeparator() public view {
        bytes32 expected = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("SequencerAttestation"),
            keccak256("1"),
            block.chainid,
            attestationProxy
        ));
        assertEq(attestation.domainSeparator(), expected);
    }

    // =========================================================================
    // Authorization Tests
    // =========================================================================

    function test_SetSequencerAuthorization() public {
        address newSequencer = address(0x999);

        vm.prank(owner);
        attestation.setSequencerAuthorization(newSequencer, true);

        assertTrue(attestation.authorizedSequencers(newSequencer));

        vm.prank(owner);
        attestation.setSequencerAuthorization(newSequencer, false);

        assertFalse(attestation.authorizedSequencers(newSequencer));
    }

    function test_OnlyOwnerCanAuthorize() public {
        vm.prank(address(0x999));
        vm.expectRevert();
        attestation.setSequencerAuthorization(address(0x888), true);
    }

    // =========================================================================
    // Commitment Tests
    // =========================================================================

    function test_CommitOrdering() public {
        bytes32 txOrderingRoot = _buildOrderingRoot();

        bytes memory signature = _signCommitment(
            blockHash,
            blockNumber,
            txOrderingRoot,
            txCount
        );

        attestation.commitOrdering(
            blockHash,
            blockNumber,
            txOrderingRoot,
            txCount,
            signature
        );

        // Verify commitment stored
        assertTrue(attestation.hasCommitment(blockHash));

        SequencerAttestation.OrderingCommitment memory commitment =
            attestation.getCommitmentByBlockNumber(blockNumber);

        assertEq(commitment.blockHash, blockHash);
        assertEq(commitment.txOrderingRoot, txOrderingRoot);
        assertEq(commitment.blockNumber, blockNumber);
        assertEq(commitment.txCount, txCount);
        assertEq(commitment.sequencer, sequencer);
    }

    function test_CommitOrdering_UpdatesStats() public {
        bytes32 txOrderingRoot = _buildOrderingRoot();

        bytes memory signature = _signCommitment(
            blockHash,
            blockNumber,
            txOrderingRoot,
            txCount
        );

        attestation.commitOrdering(
            blockHash,
            blockNumber,
            txOrderingRoot,
            txCount,
            signature
        );

        SequencerAttestation.Stats memory stats = attestation.getStats();
        assertEq(stats.totalCommitments, 1);
        assertGt(stats.lastCommitmentTime, 0);
    }

    function test_CommitOrdering_RevertsDuplicate() public {
        bytes32 txOrderingRoot = _buildOrderingRoot();

        bytes memory signature = _signCommitment(
            blockHash,
            blockNumber,
            txOrderingRoot,
            txCount
        );

        attestation.commitOrdering(
            blockHash,
            blockNumber,
            txOrderingRoot,
            txCount,
            signature
        );

        // Try to commit again
        vm.expectRevert(SequencerAttestation.CommitmentAlreadyExists.selector);
        attestation.commitOrdering(
            blockHash,
            blockNumber,
            txOrderingRoot,
            txCount,
            signature
        );
    }

    function test_CommitOrdering_RevertsUnauthorized() public {
        bytes32 txOrderingRoot = _buildOrderingRoot();

        // Sign with unauthorized key
        uint256 unauthorizedKey = 0x99999;
        bytes memory signature = _signCommitmentWithKey(
            blockHash,
            blockNumber,
            txOrderingRoot,
            txCount,
            unauthorizedKey
        );

        vm.expectRevert(SequencerAttestation.NotAuthorizedSequencer.selector);
        attestation.commitOrdering(
            blockHash,
            blockNumber,
            txOrderingRoot,
            txCount,
            signature
        );
    }

    // =========================================================================
    // Verification Tests
    // =========================================================================

    function test_VerifyTxPosition() public {
        // Build a simple tree with 4 transactions
        bytes32[] memory txHashes = new bytes32[](4);
        txHashes[0] = keccak256("tx0");
        txHashes[1] = keccak256("tx1");
        txHashes[2] = keccak256("tx2");
        txHashes[3] = keccak256("tx3");

        (bytes32 root, bytes32[][] memory proofs) = _buildMerkleTree(txHashes);

        // Commit the ordering
        bytes memory signature = _signCommitment(
            blockHash,
            blockNumber,
            root,
            4
        );

        attestation.commitOrdering(
            blockHash,
            blockNumber,
            root,
            4,
            signature
        );

        // Verify each transaction position
        for (uint256 i = 0; i < txHashes.length; i++) {
            bool valid = attestation.verifyTxPositionView(
                blockHash,
                txHashes[i],
                i,
                proofs[i]
            );
            assertTrue(valid, string(abi.encodePacked("Failed for tx ", i)));
        }
    }

    function test_VerifyTxPosition_InvalidPosition() public {
        bytes32[] memory txHashes = new bytes32[](4);
        txHashes[0] = keccak256("tx0");
        txHashes[1] = keccak256("tx1");
        txHashes[2] = keccak256("tx2");
        txHashes[3] = keccak256("tx3");

        (bytes32 root, bytes32[][] memory proofs) = _buildMerkleTree(txHashes);

        bytes memory signature = _signCommitment(
            blockHash,
            blockNumber,
            root,
            4
        );

        attestation.commitOrdering(
            blockHash,
            blockNumber,
            root,
            4,
            signature
        );

        // Try to verify tx0 at position 1 (wrong position)
        bool valid = attestation.verifyTxPositionView(
            blockHash,
            txHashes[0],
            1, // Wrong position
            proofs[0]
        );
        assertFalse(valid);
    }

    function test_VerifyTxPosition_NonexistentCommitment() public {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(0);

        bool valid = attestation.verifyTxPositionView(
            keccak256("nonexistent"),
            keccak256("tx"),
            0,
            proof
        );
        assertFalse(valid);
    }

    function test_VerifyTxPosition_UpdatesStats() public {
        bytes32[] memory txHashes = new bytes32[](4);
        txHashes[0] = keccak256("tx0");
        txHashes[1] = keccak256("tx1");
        txHashes[2] = keccak256("tx2");
        txHashes[3] = keccak256("tx3");

        (bytes32 root, bytes32[][] memory proofs) = _buildMerkleTree(txHashes);

        bytes memory signature = _signCommitment(
            blockHash,
            blockNumber,
            root,
            4
        );

        attestation.commitOrdering(
            blockHash,
            blockNumber,
            root,
            4,
            signature
        );

        // Call the state-changing verify function
        attestation.verifyTxPosition(
            blockHash,
            txHashes[0],
            0,
            proofs[0]
        );

        SequencerAttestation.Stats memory stats = attestation.getStats();
        assertEq(stats.totalVerifications, 1);
        assertEq(stats.failedVerifications, 0);
    }

    // =========================================================================
    // Helper Functions
    // =========================================================================

    function _buildOrderingRoot() internal pure returns (bytes32) {
        // Simple root for testing
        return keccak256(abi.encodePacked(
            keccak256(abi.encodePacked(uint256(0), keccak256("tx0"))),
            keccak256(abi.encodePacked(uint256(1), keccak256("tx1")))
        ));
    }

    function _signCommitment(
        bytes32 _blockHash,
        uint64 _blockNumber,
        bytes32 _txOrderingRoot,
        uint32 _txCount
    ) internal view returns (bytes memory) {
        return _signCommitmentWithKey(
            _blockHash,
            _blockNumber,
            _txOrderingRoot,
            _txCount,
            sequencerKey
        );
    }

    function _signCommitmentWithKey(
        bytes32 _blockHash,
        uint64 _blockNumber,
        bytes32 _txOrderingRoot,
        uint32 _txCount,
        uint256 _privateKey
    ) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encodePacked(
            attestation.domainSeparator(),
            _blockHash,
            _blockNumber,
            _txOrderingRoot,
            _txCount
        ));

        bytes32 ethSignedHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            messageHash
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, ethSignedHash);
        return abi.encodePacked(r, s, v);
    }

    function _buildMerkleTree(
        bytes32[] memory txHashes
    ) internal pure returns (bytes32 root, bytes32[][] memory proofs) {
        require(txHashes.length == 4, "This helper only supports 4 txs");

        // Build leaves: hash(position, txHash)
        bytes32[] memory leaves = new bytes32[](4);
        for (uint256 i = 0; i < 4; i++) {
            leaves[i] = keccak256(abi.encodePacked(i, txHashes[i]));
        }

        // Build tree
        // Level 1: hash pairs
        bytes32 h01 = keccak256(abi.encodePacked(leaves[0], leaves[1]));
        bytes32 h23 = keccak256(abi.encodePacked(leaves[2], leaves[3]));

        // Root
        root = keccak256(abi.encodePacked(h01, h23));

        // Build proofs
        proofs = new bytes32[][](4);

        // Proof for leaf 0: [leaf1, h23]
        proofs[0] = new bytes32[](2);
        proofs[0][0] = leaves[1];
        proofs[0][1] = h23;

        // Proof for leaf 1: [leaf0, h23]
        proofs[1] = new bytes32[](2);
        proofs[1][0] = leaves[0];
        proofs[1][1] = h23;

        // Proof for leaf 2: [leaf3, h01]
        proofs[2] = new bytes32[](2);
        proofs[2][0] = leaves[3];
        proofs[2][1] = h01;

        // Proof for leaf 3: [leaf2, h01]
        proofs[3] = new bytes32[](2);
        proofs[3][0] = leaves[2];
        proofs[3][1] = h01;

        return (root, proofs);
    }
}
