// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../SetRegistry.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SetRegistryAccountingTest is Test {
    SetRegistry private registry;
    address private constant OWNER = address(0xA11CE);
    address private constant SEQUENCER = address(0x5E0);

    function setUp() public {
        SetRegistry implementation = new SetRegistry();
        bytes memory initialization = abi.encodeCall(SetRegistry.initialize, (OWNER, SEQUENCER));
        registry = SetRegistry(address(new ERC1967Proxy(address(implementation), initialization)));
    }

    function test_commitBatch_incrementsTotalCommitments() public {
        vm.prank(SEQUENCER);
        registry.commitBatch(
            keccak256("batch-1"),
            bytes32(uint256(1)),
            bytes32(uint256(2)),
            keccak256("events-1"),
            bytes32(0),
            keccak256("state-1"),
            1,
            10,
            10
        );

        assertEq(registry.totalCommitments(), 1);
        (uint256 count,,,) = registry.getRegistryStats();
        assertEq(count, 1);
    }

    function test_commitBatchWithStarkProof_countsExactlyOnce() public {
        vm.prank(SEQUENCER);
        registry.commitBatchWithStarkProof(
            keccak256("batch-with-proof"),
            bytes32(uint256(1)),
            bytes32(uint256(2)),
            keccak256("events-with-proof"),
            bytes32(0),
            keccak256("state-with-proof"),
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

        assertEq(registry.totalCommitments(), 1);
        assertEq(registry.totalStarkProofs(), 1);
    }
}
