// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../governance/SetTimelock.sol";
import "../SetRegistry.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title SetTimelockTest
 * @notice Tests for governance timelock functionality
 */
contract SetTimelockTest is Test {
    SetTimelock public timelock;
    SetRegistry public registry;
    address public registryProxy;

    address public multisig = address(0x1234);
    address public deployer = address(0x5678);
    address public sequencer = address(0x9abc);

    uint256 public constant DELAY = 1 days;

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy timelock with multisig as proposer/executor
        address[] memory proposers = new address[](1);
        proposers[0] = multisig;
        address[] memory executors = new address[](1);
        executors[0] = multisig;

        timelock = new SetTimelock(DELAY, proposers, executors, deployer);

        // Deploy SetRegistry
        SetRegistry impl = new SetRegistry();
        bytes memory initData = abi.encodeCall(SetRegistry.initialize, (deployer, sequencer));
        registryProxy = address(new ERC1967Proxy(address(impl), initData));
        registry = SetRegistry(registryProxy);

        vm.stopPrank();
    }

    function test_TimelockDeployment() public view {
        assertEq(timelock.getMinDelay(), DELAY);
        assertTrue(timelock.canPropose(multisig));
        assertTrue(timelock.canExecute(multisig));
        assertFalse(timelock.canPropose(deployer));
        assertFalse(timelock.canExecute(deployer));
    }

    function test_TransferOwnershipToTimelock() public {
        vm.prank(deployer);
        registry.transferOwnership(address(timelock));

        assertEq(registry.owner(), address(timelock));
    }

    function test_TimelockCanExecuteAfterDelay() public {
        // Transfer ownership to timelock
        vm.prank(deployer);
        registry.transferOwnership(address(timelock));

        // Prepare operation to disable strict mode
        address target = registryProxy;
        uint256 value = 0;
        bytes memory data = abi.encodeCall(SetRegistry.setStrictMode, (false));
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("test-operation-1");

        // Schedule operation (as multisig)
        vm.prank(multisig);
        timelock.schedule(target, value, data, predecessor, salt, DELAY);

        bytes32 operationId = timelock.hashOperation(target, value, data, predecessor, salt);
        assertTrue(timelock.isOperationPending(operationId));

        // Try to execute before delay - should fail
        vm.prank(multisig);
        vm.expectRevert();
        timelock.execute(target, value, data, predecessor, salt);

        // Warp past delay
        vm.warp(block.timestamp + DELAY + 1);

        assertTrue(timelock.isOperationReady(operationId));

        // Execute operation
        vm.prank(multisig);
        timelock.execute(target, value, data, predecessor, salt);

        assertTrue(timelock.isOperationDone(operationId));
        assertFalse(registry.strictModeEnabled());
    }

    function test_NonProposerCannotSchedule() public {
        address target = registryProxy;
        bytes memory data = abi.encodeCall(SetRegistry.setStrictMode, (false));

        vm.prank(deployer);
        vm.expectRevert();
        timelock.schedule(target, 0, data, bytes32(0), bytes32(0), DELAY);
    }

    function test_NonExecutorCannotExecute() public {
        address target = registryProxy;
        bytes memory data = abi.encodeCall(SetRegistry.setStrictMode, (false));
        bytes32 salt = keccak256("test-2");

        vm.prank(multisig);
        timelock.schedule(target, 0, data, bytes32(0), salt, DELAY);

        vm.warp(block.timestamp + DELAY + 1);

        vm.prank(deployer);
        vm.expectRevert();
        timelock.execute(target, 0, data, bytes32(0), salt);
    }

    function test_RenounceAdmin() public {
        assertFalse(timelock.isAdminRenounced());

        vm.prank(deployer);
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        assertTrue(timelock.isAdminRenounced());
    }

    function test_CancelOperation() public {
        address target = registryProxy;
        bytes memory data = abi.encodeCall(SetRegistry.setStrictMode, (false));
        bytes32 salt = keccak256("test-cancel");

        vm.prank(multisig);
        timelock.schedule(target, 0, data, bytes32(0), salt, DELAY);

        bytes32 operationId = timelock.hashOperation(target, 0, data, bytes32(0), salt);
        assertTrue(timelock.isOperationPending(operationId));

        // Cancel as multisig (has CANCELLER_ROLE by default as proposer)
        vm.prank(multisig);
        timelock.cancel(operationId);

        assertFalse(timelock.isOperationPending(operationId));
    }

    function test_BatchOperations() public {
        vm.prank(deployer);
        registry.transferOwnership(address(timelock));

        // Prepare batch: authorize new sequencer + disable strict mode
        address[] memory targets = new address[](2);
        targets[0] = registryProxy;
        targets[1] = registryProxy;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory payloads = new bytes[](2);
        payloads[0] = abi.encodeCall(SetRegistry.setSequencerAuthorization, (address(0xdead), true));
        payloads[1] = abi.encodeCall(SetRegistry.setStrictMode, (false));

        bytes32 salt = keccak256("batch-test");

        vm.prank(multisig);
        timelock.scheduleBatch(targets, values, payloads, bytes32(0), salt, DELAY);

        vm.warp(block.timestamp + DELAY + 1);

        vm.prank(multisig);
        timelock.executeBatch(targets, values, payloads, bytes32(0), salt);

        assertTrue(registry.authorizedSequencers(address(0xdead)));
        assertFalse(registry.strictModeEnabled());
    }

    function test_MinDelayConstants() public pure {
        assertEq(SetTimelock(address(0)).MAINNET_MIN_DELAY(), 24 hours);
        assertEq(SetTimelock(address(0)).TESTNET_MIN_DELAY(), 1 hours);
        assertEq(SetTimelock(address(0)).DEVNET_MIN_DELAY(), 5 minutes);
    }
}
