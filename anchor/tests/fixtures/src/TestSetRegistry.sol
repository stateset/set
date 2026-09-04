// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal, source-auditable SetRegistry double for Rust/Anvil integration tests.
/// @dev It deliberately implements only the behavior consumed by the anchor service.
contract TestSetRegistry {
    mapping(address => bool) public authorizedSequencers;
    mapping(bytes32 => bool) public committedBatches;
    uint256 public totalCommitments;
    bool public strictModeEnabled;
    bool private initialized;

    error AlreadyInitialized();
    error NotAuthorizedSequencer();
    error BatchAlreadyCommitted();

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

    function initialize(address, address initialSequencer) external {
        if (initialized) revert AlreadyInitialized();
        initialized = true;
        strictModeEnabled = true;
        authorizedSequencers[initialSequencer] = true;
        emit SequencerAuthorized(initialSequencer, true);
    }

    function commitBatch(
        bytes32 batchId,
        bytes32 tenantId,
        bytes32 storeId,
        bytes32 eventsRoot,
        bytes32,
        bytes32 newStateRoot,
        uint64 sequenceStart,
        uint64 sequenceEnd,
        uint32 eventCount
    ) external {
        if (!authorizedSequencers[msg.sender]) revert NotAuthorizedSequencer();
        if (committedBatches[batchId]) revert BatchAlreadyCommitted();

        committedBatches[batchId] = true;
        totalCommitments++;
        emit BatchCommitted(
            batchId,
            keccak256(abi.encodePacked(tenantId, storeId)),
            eventsRoot,
            newStateRoot,
            sequenceStart,
            sequenceEnd,
            eventCount
        );
    }
}
