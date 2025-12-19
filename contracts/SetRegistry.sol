// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title SetRegistry
 * @notice Merkle Root Anchoring for Commerce Events on Set Chain
 * @dev Stores batch commitments from the stateset-sequencer for verifiable commerce
 *
 * Key features:
 * - Multi-sequencer authorization
 * - State chain continuity verification
 * - Inclusion proof verification
 * - Tenant/store isolation
 */
contract SetRegistry is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    // =========================================================================
    // Types
    // =========================================================================

    /// @notice Batch commitment containing state and event roots
    struct BatchCommitment {
        bytes32 eventsRoot;      // Merkle root of events in this batch
        bytes32 prevStateRoot;   // State root before applying this batch
        bytes32 newStateRoot;    // State root after applying this batch
        uint64 sequenceStart;    // First sequence number in batch
        uint64 sequenceEnd;      // Last sequence number in batch
        uint32 eventCount;       // Number of events in batch
        uint64 timestamp;        // Block timestamp when committed
        address submitter;       // Address that submitted this commitment
    }

    // =========================================================================
    // State Variables
    // =========================================================================

    /// @notice Authorized sequencers who can submit commitments
    mapping(address => bool) public authorizedSequencers;

    /// @notice Batch commitments by batch ID
    mapping(bytes32 => BatchCommitment) public commitments;

    /// @notice Latest commitment per tenant/store (tenant_store_key => batch_id)
    mapping(bytes32 => bytes32) public latestCommitment;

    /// @notice Head sequence per tenant/store
    mapping(bytes32 => uint64) public headSequence;

    /// @notice Total commitments count
    uint256 public totalCommitments;

    /// @notice Whether strict state chain verification is enabled
    bool public strictModeEnabled;

    // =========================================================================
    // Events
    // =========================================================================

    event SequencerAuthorized(address indexed sequencer, bool authorized);

    event BatchCommitted(
        bytes32 indexed batchId,
        bytes32 indexed tenantStoreKey,
        bytes32 eventsRoot,
        bytes32 newStateRoot,
        uint64 sequenceStart,
        uint64 sequenceEnd,
        uint32 eventCount
    );

    event StrictModeUpdated(bool enabled);

    // =========================================================================
    // Errors
    // =========================================================================

    error NotAuthorizedSequencer();
    error InvalidSequenceRange();
    error EmptyEventsRoot();
    error BatchAlreadyCommitted();
    error StateRootMismatch(bytes32 expected, bytes32 provided);
    error SequenceGap(uint64 expected, uint64 provided);
    error InvalidProof();

    // =========================================================================
    // Initialization
    // =========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the registry
     * @param _owner Owner address for admin functions
     * @param _initialSequencer First authorized sequencer
     */
    function initialize(
        address _owner,
        address _initialSequencer
    ) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        if (_initialSequencer != address(0)) {
            authorizedSequencers[_initialSequencer] = true;
            emit SequencerAuthorized(_initialSequencer, true);
        }

        strictModeEnabled = true;
    }

    // =========================================================================
    // Admin Functions
    // =========================================================================

    /**
     * @notice Authorize or revoke a sequencer
     * @param _sequencer Address to authorize/revoke
     * @param _authorized Whether to authorize or revoke
     */
    function setSequencerAuthorization(
        address _sequencer,
        bool _authorized
    ) external onlyOwner {
        authorizedSequencers[_sequencer] = _authorized;
        emit SequencerAuthorized(_sequencer, _authorized);
    }

    /**
     * @notice Enable or disable strict state chain verification
     * @param _enabled Whether strict mode is enabled
     */
    function setStrictMode(bool _enabled) external onlyOwner {
        strictModeEnabled = _enabled;
        emit StrictModeUpdated(_enabled);
    }

    // =========================================================================
    // Core Functions
    // =========================================================================

    /**
     * @notice Commit a batch of events
     * @param _batchId Unique identifier for this batch
     * @param _tenantId Tenant identifier
     * @param _storeId Store identifier
     * @param _eventsRoot Merkle root of events
     * @param _prevStateRoot State root before this batch
     * @param _newStateRoot State root after this batch
     * @param _sequenceStart First sequence number
     * @param _sequenceEnd Last sequence number
     * @param _eventCount Number of events in batch
     */
    function commitBatch(
        bytes32 _batchId,
        bytes32 _tenantId,
        bytes32 _storeId,
        bytes32 _eventsRoot,
        bytes32 _prevStateRoot,
        bytes32 _newStateRoot,
        uint64 _sequenceStart,
        uint64 _sequenceEnd,
        uint32 _eventCount
    ) external nonReentrant {
        // Authorization check
        if (!authorizedSequencers[msg.sender]) {
            revert NotAuthorizedSequencer();
        }

        // Basic validation
        if (_sequenceEnd < _sequenceStart) {
            revert InvalidSequenceRange();
        }
        if (_eventsRoot == bytes32(0)) {
            revert EmptyEventsRoot();
        }
        if (commitments[_batchId].timestamp != 0) {
            revert BatchAlreadyCommitted();
        }

        // Tenant/store key
        bytes32 tenantStoreKey = keccak256(abi.encodePacked(_tenantId, _storeId));

        // State chain verification (if strict mode enabled)
        if (strictModeEnabled) {
            bytes32 lastBatchId = latestCommitment[tenantStoreKey];

            if (lastBatchId != bytes32(0)) {
                BatchCommitment storage lastBatch = commitments[lastBatchId];

                // Verify state root continuity
                if (lastBatch.newStateRoot != _prevStateRoot) {
                    revert StateRootMismatch(lastBatch.newStateRoot, _prevStateRoot);
                }

                // Verify sequence continuity
                if (lastBatch.sequenceEnd + 1 != _sequenceStart) {
                    revert SequenceGap(lastBatch.sequenceEnd + 1, _sequenceStart);
                }
            }
        }

        // Store commitment
        commitments[_batchId] = BatchCommitment({
            eventsRoot: _eventsRoot,
            prevStateRoot: _prevStateRoot,
            newStateRoot: _newStateRoot,
            sequenceStart: _sequenceStart,
            sequenceEnd: _sequenceEnd,
            eventCount: _eventCount,
            timestamp: uint64(block.timestamp),
            submitter: msg.sender
        });

        // Update latest commitment and head sequence
        latestCommitment[tenantStoreKey] = _batchId;
        headSequence[tenantStoreKey] = _sequenceEnd;
        totalCommitments++;

        emit BatchCommitted(
            _batchId,
            tenantStoreKey,
            _eventsRoot,
            _newStateRoot,
            _sequenceStart,
            _sequenceEnd,
            _eventCount
        );
    }

    // =========================================================================
    // Verification Functions
    // =========================================================================

    /**
     * @notice Verify a Merkle inclusion proof for an event
     * @param _batchId Batch containing the event
     * @param _leaf Hash of the event (payload_hash + metadata)
     * @param _proof Merkle proof path
     * @param _index Index of the leaf in the tree
     * @return valid True if proof is valid
     */
    function verifyInclusion(
        bytes32 _batchId,
        bytes32 _leaf,
        bytes32[] calldata _proof,
        uint256 _index
    ) external view returns (bool valid) {
        BatchCommitment storage commitment = commitments[_batchId];

        // Batch must exist
        if (commitment.timestamp == 0) {
            return false;
        }

        // Compute root from proof
        bytes32 computedRoot = _computeMerkleRoot(_leaf, _proof, _index);

        return computedRoot == commitment.eventsRoot;
    }

    /**
     * @notice Verify multiple events in a single call
     * @param _batchId Batch containing the events
     * @param _leaves Array of event hashes
     * @param _proofs Array of Merkle proofs
     * @param _indices Array of leaf indices
     * @return allValid True if all proofs are valid
     */
    function verifyMultipleInclusions(
        bytes32 _batchId,
        bytes32[] calldata _leaves,
        bytes32[][] calldata _proofs,
        uint256[] calldata _indices
    ) external view returns (bool allValid) {
        if (_leaves.length != _proofs.length || _leaves.length != _indices.length) {
            return false;
        }

        BatchCommitment storage commitment = commitments[_batchId];
        if (commitment.timestamp == 0) {
            return false;
        }

        for (uint256 i = 0; i < _leaves.length; i++) {
            bytes32 computedRoot = _computeMerkleRoot(_leaves[i], _proofs[i], _indices[i]);
            if (computedRoot != commitment.eventsRoot) {
                return false;
            }
        }

        return true;
    }

    /**
     * @notice Get the latest state root for a tenant/store
     * @param _tenantId Tenant identifier
     * @param _storeId Store identifier
     * @return stateRoot Current state root
     */
    function getLatestStateRoot(
        bytes32 _tenantId,
        bytes32 _storeId
    ) external view returns (bytes32 stateRoot) {
        bytes32 tenantStoreKey = keccak256(abi.encodePacked(_tenantId, _storeId));
        bytes32 batchId = latestCommitment[tenantStoreKey];

        if (batchId == bytes32(0)) {
            return bytes32(0);
        }

        return commitments[batchId].newStateRoot;
    }

    /**
     * @notice Get the head sequence for a tenant/store
     * @param _tenantId Tenant identifier
     * @param _storeId Store identifier
     * @return sequence Current head sequence number
     */
    function getHeadSequence(
        bytes32 _tenantId,
        bytes32 _storeId
    ) external view returns (uint64 sequence) {
        bytes32 tenantStoreKey = keccak256(abi.encodePacked(_tenantId, _storeId));
        return headSequence[tenantStoreKey];
    }

    // =========================================================================
    // Internal Functions
    // =========================================================================

    /**
     * @dev Compute Merkle root from leaf and proof
     */
    function _computeMerkleRoot(
        bytes32 _leaf,
        bytes32[] calldata _proof,
        uint256 _index
    ) internal pure returns (bytes32) {
        bytes32 computedHash = _leaf;

        for (uint256 i = 0; i < _proof.length; i++) {
            bytes32 proofElement = _proof[i];

            if (_index % 2 == 0) {
                // Current node is left child
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                // Current node is right child
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }

            _index = _index / 2;
        }

        return computedHash;
    }

    /**
     * @dev Authorize upgrade (owner only)
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // =========================================================================
    // Legacy Compatibility
    // =========================================================================

    /**
     * @notice Legacy function for backward compatibility
     * @dev Maps to new commitBatch function with default tenant/store
     */
    function registerBatchRoot(
        uint256 _startSequence,
        uint256 _endSequence,
        bytes32 _root
    ) external {
        // Generate a batch ID from sequence range
        bytes32 batchId = keccak256(abi.encodePacked(_startSequence, _endSequence, block.timestamp));

        // Use default tenant/store (zeros)
        commitBatch(
            batchId,
            bytes32(0),
            bytes32(0),
            _root,
            bytes32(0),
            bytes32(0),
            uint64(_startSequence),
            uint64(_endSequence),
            uint32(_endSequence - _startSequence + 1)
        );
    }

    /**
     * @notice Legacy function for backward compatibility
     */
    function getBatchRoot(
        uint256 _startSequence,
        uint256 _endSequence
    ) external view returns (bytes32) {
        // This is a simplified lookup - in practice you'd need to search
        // For true backward compatibility, maintain a separate mapping
        bytes32 tenantStoreKey = keccak256(abi.encodePacked(bytes32(0), bytes32(0)));
        bytes32 batchId = latestCommitment[tenantStoreKey];

        if (batchId == bytes32(0)) {
            return bytes32(0);
        }

        BatchCommitment storage commitment = commitments[batchId];
        if (commitment.sequenceStart == _startSequence &&
            commitment.sequenceEnd == _endSequence) {
            return commitment.eventsRoot;
        }

        return bytes32(0);
    }
}
