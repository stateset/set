// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title SequencerAttestation
 * @notice Provides verifiable FCFS ordering commitments from the sequencer
 * @dev Part of Set Chain's MEV protection strategy (Phase 1)
 *
 * The sequencer signs ordering commitments for each block, allowing users to:
 * 1. Verify their transaction was included in the correct order
 * 2. Detect ordering violations (out-of-order transactions)
 * 3. Build trust in fair transaction ordering
 *
 * Flow:
 * 1. Sequencer builds block with FCFS ordering
 * 2. Sequencer computes Merkle root of (position, txHash) pairs
 * 3. Sequencer signs and submits commitment
 * 4. Users can verify their tx position using Merkle proofs
 */
contract SequencerAttestation is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // =========================================================================
    // Types
    // =========================================================================

    /// @notice Ordering commitment for a block
    struct OrderingCommitment {
        bytes32 blockHash;          // L2 block hash
        bytes32 txOrderingRoot;     // Merkle root of ordered transactions
        uint64 blockNumber;         // L2 block number
        uint64 timestamp;           // Commitment timestamp
        uint32 txCount;             // Number of transactions in block
        address sequencer;          // Sequencer that signed
    }

    /// @notice Statistics for monitoring
    struct Stats {
        uint256 totalCommitments;
        uint256 totalVerifications;
        uint256 failedVerifications;
        uint64 lastCommitmentTime;
    }

    // =========================================================================
    // State Variables
    // =========================================================================

    /// @notice Authorized sequencers who can submit commitments
    mapping(address => bool) public authorizedSequencers;

    /// @notice Ordering commitments by block hash
    mapping(bytes32 => OrderingCommitment) public commitments;

    /// @notice Ordering commitments by block number (for easier lookup)
    mapping(uint256 => bytes32) public blockNumberToHash;

    /// @notice Statistics
    Stats public stats;

    /// @notice Domain separator for signatures (EIP-712 style)
    bytes32 public domainSeparator;

    // =========================================================================
    // Events
    // =========================================================================

    event SequencerAuthorized(address indexed sequencer, bool authorized);

    event OrderingCommitted(
        bytes32 indexed blockHash,
        uint64 indexed blockNumber,
        bytes32 txOrderingRoot,
        uint32 txCount,
        address sequencer
    );

    event OrderingVerified(
        bytes32 indexed blockHash,
        bytes32 indexed txHash,
        uint256 position,
        bool valid
    );

    // =========================================================================
    // Errors
    // =========================================================================

    error NotAuthorizedSequencer();
    error CommitmentAlreadyExists();
    error CommitmentNotFound();
    error InvalidSignature();
    error InvalidProof();
    error BlockNumberMismatch();

    // =========================================================================
    // Initialization
    // =========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param _owner Owner address
     * @param _initialSequencer First authorized sequencer
     */
    function initialize(
        address _owner,
        address _initialSequencer
    ) public initializer {
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();

        // Set domain separator for signature verification
        domainSeparator = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("SequencerAttestation"),
            keccak256("1"),
            block.chainid,
            address(this)
        ));

        if (_initialSequencer != address(0)) {
            authorizedSequencers[_initialSequencer] = true;
            emit SequencerAuthorized(_initialSequencer, true);
        }
    }

    // =========================================================================
    // Admin Functions
    // =========================================================================

    /**
     * @notice Authorize or revoke a sequencer
     * @param _sequencer Sequencer address
     * @param _authorized Whether to authorize
     */
    function setSequencerAuthorization(
        address _sequencer,
        bool _authorized
    ) external onlyOwner {
        authorizedSequencers[_sequencer] = _authorized;
        emit SequencerAuthorized(_sequencer, _authorized);
    }

    // =========================================================================
    // Core Functions
    // =========================================================================

    /**
     * @notice Submit an ordering commitment for a block
     * @param _blockHash L2 block hash
     * @param _blockNumber L2 block number
     * @param _txOrderingRoot Merkle root of (position, txHash) pairs
     * @param _txCount Number of transactions in block
     * @param _signature Sequencer's signature over the commitment
     */
    function commitOrdering(
        bytes32 _blockHash,
        uint64 _blockNumber,
        bytes32 _txOrderingRoot,
        uint32 _txCount,
        bytes calldata _signature
    ) external {
        // Check if commitment already exists
        if (commitments[_blockHash].timestamp != 0) {
            revert CommitmentAlreadyExists();
        }

        // Verify signature
        bytes32 messageHash = keccak256(abi.encodePacked(
            domainSeparator,
            _blockHash,
            _blockNumber,
            _txOrderingRoot,
            _txCount
        ));

        address signer = messageHash.toEthSignedMessageHash().recover(_signature);

        if (!authorizedSequencers[signer]) {
            revert NotAuthorizedSequencer();
        }

        // Store commitment
        commitments[_blockHash] = OrderingCommitment({
            blockHash: _blockHash,
            txOrderingRoot: _txOrderingRoot,
            blockNumber: _blockNumber,
            timestamp: uint64(block.timestamp),
            txCount: _txCount,
            sequencer: signer
        });

        blockNumberToHash[_blockNumber] = _blockHash;

        // Update stats
        stats.totalCommitments++;
        stats.lastCommitmentTime = uint64(block.timestamp);

        emit OrderingCommitted(
            _blockHash,
            _blockNumber,
            _txOrderingRoot,
            _txCount,
            signer
        );
    }

    /**
     * @notice Verify a transaction's position in a block's ordering
     * @param _blockHash Block containing the transaction
     * @param _txHash Transaction hash
     * @param _position Expected position (0-indexed)
     * @param _proof Merkle proof
     * @return valid True if the proof is valid
     */
    function verifyTxPosition(
        bytes32 _blockHash,
        bytes32 _txHash,
        uint256 _position,
        bytes32[] calldata _proof
    ) external returns (bool valid) {
        OrderingCommitment storage commitment = commitments[_blockHash];

        if (commitment.timestamp == 0) {
            revert CommitmentNotFound();
        }

        // Leaf is hash of (position, txHash)
        bytes32 leaf = keccak256(abi.encodePacked(_position, _txHash));

        valid = _verifyMerkleProof(_proof, commitment.txOrderingRoot, leaf, _position);

        // Update stats
        stats.totalVerifications++;
        if (!valid) {
            stats.failedVerifications++;
        }

        emit OrderingVerified(_blockHash, _txHash, _position, valid);

        return valid;
    }

    /**
     * @notice Verify ordering without modifying state (view function)
     * @param _blockHash Block containing the transaction
     * @param _txHash Transaction hash
     * @param _position Expected position (0-indexed)
     * @param _proof Merkle proof
     * @return valid True if the proof is valid
     */
    function verifyTxPositionView(
        bytes32 _blockHash,
        bytes32 _txHash,
        uint256 _position,
        bytes32[] calldata _proof
    ) external view returns (bool valid) {
        OrderingCommitment storage commitment = commitments[_blockHash];

        if (commitment.timestamp == 0) {
            return false;
        }

        bytes32 leaf = keccak256(abi.encodePacked(_position, _txHash));
        return _verifyMerkleProof(_proof, commitment.txOrderingRoot, leaf, _position);
    }

    /**
     * @notice Batch verify multiple transactions
     * @param _blockHash Block containing the transactions
     * @param _txHashes Transaction hashes
     * @param _positions Expected positions
     * @param _proofs Merkle proofs (flattened, same length per proof)
     * @param _proofLength Length of each individual proof
     * @return results Verification results for each transaction
     */
    function batchVerify(
        bytes32 _blockHash,
        bytes32[] calldata _txHashes,
        uint256[] calldata _positions,
        bytes32[] calldata _proofs,
        uint256 _proofLength
    ) external view returns (bool[] memory results) {
        require(_txHashes.length == _positions.length, "Length mismatch");
        require(_proofs.length == _txHashes.length * _proofLength, "Invalid proofs length");

        OrderingCommitment storage commitment = commitments[_blockHash];
        if (commitment.timestamp == 0) {
            results = new bool[](_txHashes.length);
            return results;
        }

        results = new bool[](_txHashes.length);

        for (uint256 i = 0; i < _txHashes.length; i++) {
            bytes32 leaf = keccak256(abi.encodePacked(_positions[i], _txHashes[i]));

            // Extract individual proof
            bytes32[] memory proof = new bytes32[](_proofLength);
            for (uint256 j = 0; j < _proofLength; j++) {
                proof[j] = _proofs[i * _proofLength + j];
            }

            results[i] = _verifyMerkleProofMemory(proof, commitment.txOrderingRoot, leaf, _positions[i]);
        }

        return results;
    }

    // =========================================================================
    // Query Functions
    // =========================================================================

    /**
     * @notice Get commitment by block number
     * @param _blockNumber L2 block number
     * @return commitment The ordering commitment
     */
    function getCommitmentByBlockNumber(
        uint256 _blockNumber
    ) external view returns (OrderingCommitment memory commitment) {
        bytes32 blockHash = blockNumberToHash[_blockNumber];
        return commitments[blockHash];
    }

    /**
     * @notice Check if a commitment exists for a block
     * @param _blockHash Block hash
     * @return exists True if commitment exists
     */
    function hasCommitment(bytes32 _blockHash) external view returns (bool exists) {
        return commitments[_blockHash].timestamp != 0;
    }

    /**
     * @notice Get current statistics
     * @return stats_ Current stats
     */
    function getStats() external view returns (Stats memory stats_) {
        return stats;
    }

    // =========================================================================
    // Internal Functions
    // =========================================================================

    /**
     * @dev Verify a Merkle proof (calldata version)
     */
    function _verifyMerkleProof(
        bytes32[] calldata _proof,
        bytes32 _root,
        bytes32 _leaf,
        uint256 _index
    ) internal pure returns (bool) {
        bytes32 computedHash = _leaf;

        for (uint256 i = 0; i < _proof.length; i++) {
            bytes32 proofElement = _proof[i];

            if (_index % 2 == 0) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }

            _index = _index / 2;
        }

        return computedHash == _root;
    }

    /**
     * @dev Verify a Merkle proof (memory version for batch operations)
     */
    function _verifyMerkleProofMemory(
        bytes32[] memory _proof,
        bytes32 _root,
        bytes32 _leaf,
        uint256 _index
    ) internal pure returns (bool) {
        bytes32 computedHash = _leaf;

        for (uint256 i = 0; i < _proof.length; i++) {
            bytes32 proofElement = _proof[i];

            if (_index % 2 == 0) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }

            _index = _index / 2;
        }

        return computedHash == _root;
    }

    /**
     * @dev Authorize upgrade (owner only)
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
