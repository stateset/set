// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title SetTimelock
 * @notice Timelock controller for Set Chain governance
 * @dev Wraps OpenZeppelin's TimelockController with Set Chain specific defaults
 *
 * Key features:
 * - Minimum delay of 24 hours for security-critical operations
 * - Multisig as proposer/executor
 * - Admin role renounced after setup to prevent single-point-of-failure
 *
 * Recommended setup:
 * 1. Deploy with multisig as sole proposer and executor
 * 2. Transfer ownership of SetRegistry and SetPaymaster to this timelock
 * 3. Renounce admin role on this timelock
 */
contract SetTimelock is TimelockController {
    /// @notice Minimum delay for mainnet (24 hours)
    uint256 public constant MAINNET_MIN_DELAY = 24 hours;

    /// @notice Minimum delay for testnet (1 hour)
    uint256 public constant TESTNET_MIN_DELAY = 1 hours;

    /// @notice Minimum delay for devnet (5 minutes)
    uint256 public constant DEVNET_MIN_DELAY = 5 minutes;

    /**
     * @notice Deploy the timelock
     * @param minDelay Minimum delay between proposal and execution
     * @param proposers Addresses that can propose operations (should be multisig)
     * @param executors Addresses that can execute operations (should be multisig)
     * @param admin Optional admin for initial setup (should be renounced)
     */
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}

    /**
     * @notice Helper to check if caller can propose
     */
    function canPropose(address account) external view returns (bool) {
        return hasRole(PROPOSER_ROLE, account);
    }

    /**
     * @notice Helper to check if caller can execute
     */
    function canExecute(address account) external view returns (bool) {
        return hasRole(EXECUTOR_ROLE, account);
    }

    /**
     * @notice Helper to check if admin is renounced (no one has admin role)
     */
    function isAdminRenounced() external view returns (bool) {
        return getRoleMemberCount(DEFAULT_ADMIN_ROLE) == 0;
    }
}
