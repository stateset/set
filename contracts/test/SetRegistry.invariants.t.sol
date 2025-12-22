// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../SetRegistry.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SetRegistryHandler is Test {
    SetRegistry private registry;
    address private sequencer;
    uint256 private committedCount;

    struct TenantState {
        bytes32 lastBatchId;
        bytes32 lastStateRoot;
        uint64 lastSequence;
        bool initialized;
    }

    struct CommitmentExpectation {
        bytes32 eventsRoot;
        bytes32 prevStateRoot;
        bytes32 newStateRoot;
        uint64 sequenceStart;
        uint64 sequenceEnd;
        uint32 eventCount;
        address submitter;
    }

    mapping(bytes32 => TenantState) private tenantState;
    bytes32[] private tenantKeys;

    mapping(bytes32 => CommitmentExpectation) private expectations;
    bytes32[] private batchIds;

    constructor(SetRegistry _registry, address _sequencer) {
        registry = _registry;
        sequencer = _sequencer;
    }

    function commitBatch(
        uint256 tenantSeed,
        uint256 storeSeed,
        bytes32 eventsSeed,
        bytes32 stateSeed,
        uint32 eventCountSeed
    ) public {
        bytes32 tenantId = bytes32(uint256(tenantSeed % 8) + 1);
        bytes32 storeId = bytes32(uint256(storeSeed % 8) + 100);
        bytes32 tenantStoreKey = keccak256(abi.encodePacked(tenantId, storeId));

        TenantState storage state = tenantState[tenantStoreKey];
        bool isNew = !state.initialized;
        if (isNew) {
            tenantKeys.push(tenantStoreKey);
            state.initialized = true;
        }

        uint32 eventCount = uint32(bound(eventCountSeed, 1, 100));
        uint64 sequenceStart = isNew ? 1 : state.lastSequence + 1;
        uint64 sequenceEnd = sequenceStart + uint64(eventCount) - 1;

        bytes32 eventsRoot = keccak256(
            abi.encodePacked(eventsSeed, tenantStoreKey, committedCount)
        );
        if (eventsRoot == bytes32(0)) {
            eventsRoot = bytes32(uint256(1));
        }

        bytes32 prevStateRoot = isNew ? bytes32(0) : state.lastStateRoot;
        bytes32 newStateRoot = keccak256(
            abi.encodePacked(stateSeed, tenantStoreKey, sequenceEnd)
        );
        if (newStateRoot == bytes32(0)) {
            newStateRoot = bytes32(uint256(2));
        }

        bytes32 batchId = keccak256(
            abi.encodePacked(tenantStoreKey, committedCount, eventsRoot)
        );

        vm.prank(sequencer);
        registry.commitBatch(
            batchId,
            tenantId,
            storeId,
            eventsRoot,
            prevStateRoot,
            newStateRoot,
            sequenceStart,
            sequenceEnd,
            eventCount
        );

        state.lastBatchId = batchId;
        state.lastStateRoot = newStateRoot;
        state.lastSequence = sequenceEnd;

        expectations[batchId] = CommitmentExpectation({
            eventsRoot: eventsRoot,
            prevStateRoot: prevStateRoot,
            newStateRoot: newStateRoot,
            sequenceStart: sequenceStart,
            sequenceEnd: sequenceEnd,
            eventCount: eventCount,
            submitter: sequencer
        });
        batchIds.push(batchId);
        committedCount += 1;
    }

    function totalCommitted() external view returns (uint256) {
        return committedCount;
    }

    function tenantKeyCount() external view returns (uint256) {
        return tenantKeys.length;
    }

    function tenantKeyAt(uint256 index) external view returns (bytes32) {
        return tenantKeys[index];
    }

    function batchIdCount() external view returns (uint256) {
        return batchIds.length;
    }

    function batchIdAt(uint256 index) external view returns (bytes32) {
        return batchIds[index];
    }

    function tenantStateSummary(
        bytes32 tenantStoreKey
    )
        external
        view
        returns (bytes32 lastBatchId, bytes32 lastStateRoot, uint64 lastSequence)
    {
        TenantState storage state = tenantState[tenantStoreKey];
        return (state.lastBatchId, state.lastStateRoot, state.lastSequence);
    }

    function commitmentExpectation(
        bytes32 batchId
    )
        external
        view
        returns (
            bytes32 eventsRoot,
            bytes32 prevStateRoot,
            bytes32 newStateRoot,
            uint64 sequenceStart,
            uint64 sequenceEnd,
            uint32 eventCount,
            address submitter
        )
    {
        CommitmentExpectation storage expected = expectations[batchId];
        return (
            expected.eventsRoot,
            expected.prevStateRoot,
            expected.newStateRoot,
            expected.sequenceStart,
            expected.sequenceEnd,
            expected.eventCount,
            expected.submitter
        );
    }
}

contract SetRegistryInvariants is StdInvariant, Test {
    SetRegistry private registry;
    SetRegistryHandler private handler;

    address private owner = address(0x1);
    address private sequencer = address(0x2);

    function setUp() public {
        SetRegistry impl = new SetRegistry();
        bytes memory initData = abi.encodeCall(
            SetRegistry.initialize,
            (owner, sequencer)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        registry = SetRegistry(address(proxy));

        handler = new SetRegistryHandler(registry, sequencer);
        targetContract(address(handler));
    }

    function invariant_totalCommitments_matchesHandler() public view {
        assertEq(registry.totalCommitments(), handler.totalCommitted());
    }

    function invariant_latestCommitments_matchHandler() public view {
        uint256 count = handler.tenantKeyCount();
        for (uint256 i = 0; i < count; i++) {
            bytes32 tenantStoreKey = handler.tenantKeyAt(i);
            (bytes32 lastBatchId, bytes32 lastStateRoot, uint64 lastSequence) =
                handler.tenantStateSummary(tenantStoreKey);

            assertEq(registry.latestCommitment(tenantStoreKey), lastBatchId);
            assertEq(registry.headSequence(tenantStoreKey), lastSequence);

            if (lastBatchId != bytes32(0)) {
                (
                    ,
                    ,
                    bytes32 newStateRoot,
                    ,
                    uint64 sequenceEnd,
                    ,
                    ,
                    address _storedSubmitter
                ) = registry.commitments(lastBatchId);
                assertEq(newStateRoot, lastStateRoot);
                assertEq(sequenceEnd, lastSequence);
            }
        }
    }

    function invariant_commitments_matchExpectations() public view {
        uint256 count = handler.batchIdCount();
        for (uint256 i = 0; i < count; i++) {
            bytes32 batchId = handler.batchIdAt(i);
            (
                bytes32 expectedEventsRoot,
                bytes32 expectedPrevStateRoot,
                bytes32 expectedNewStateRoot,
                uint64 expectedSequenceStart,
                uint64 expectedSequenceEnd,
                uint32 expectedEventCount,
                address expectedSubmitter
            ) = handler.commitmentExpectation(batchId);

            (
                bytes32 storedEventsRoot,
                bytes32 storedPrevStateRoot,
                bytes32 storedNewStateRoot,
                uint64 storedSequenceStart,
                uint64 storedSequenceEnd,
                uint32 storedEventCount,
                ,
                address storedSubmitter
            ) = registry.commitments(batchId);

            assertEq(storedEventsRoot, expectedEventsRoot);
            assertEq(storedPrevStateRoot, expectedPrevStateRoot);
            assertEq(storedNewStateRoot, expectedNewStateRoot);
            assertEq(storedSequenceStart, expectedSequenceStart);
            assertEq(storedSequenceEnd, expectedSequenceEnd);
            assertEq(storedEventCount, expectedEventCount);
            assertEq(storedSubmitter, expectedSubmitter);
        }
    }
}
