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
    // =========================================================================
    // Constants
    // =========================================================================

    /// @notice Minimum delay for mainnet (24 hours)
    uint256 public constant MAINNET_MIN_DELAY = 24 hours;

    /// @notice Minimum delay for testnet (1 hour)
    uint256 public constant TESTNET_MIN_DELAY = 1 hours;

    /// @notice Minimum delay for devnet (5 minutes)
    uint256 public constant DEVNET_MIN_DELAY = 5 minutes;

    /// @notice Maximum allowed delay (30 days) to prevent lock-up attacks
    uint256 public constant MAX_DELAY = 30 days;

    // =========================================================================
    // Errors
    // =========================================================================

    error NoProposersProvided();
    error NoExecutorsProvided();
    error DelayTooLong();
    error ZeroAddressProposer();
    error ZeroAddressExecutor();
    error ArrayLengthMismatch();
    error EmptyArray();

    // =========================================================================
    // Events
    // =========================================================================

    event TimelockDeployed(
        uint256 minDelay,
        uint256 proposerCount,
        uint256 executorCount,
        address indexed admin
    );

    // =========================================================================
    // Constructor
    // =========================================================================

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
    ) TimelockController(minDelay, proposers, executors, admin) {
        // Input validation
        if (proposers.length == 0) revert NoProposersProvided();
        if (executors.length == 0) revert NoExecutorsProvided();
        if (minDelay > MAX_DELAY) revert DelayTooLong();

        // Validate no zero addresses in proposers
        for (uint256 i = 0; i < proposers.length; i++) {
            if (proposers[i] == address(0)) revert ZeroAddressProposer();
        }

        // Validate no zero addresses in executors
        for (uint256 i = 0; i < executors.length; i++) {
            if (executors[i] == address(0)) revert ZeroAddressExecutor();
        }

        emit TimelockDeployed(minDelay, proposers.length, executors.length, admin);
    }

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
     * @notice Helper to check if a specific address has renounced admin
     * @param account The address to check
     * @dev Since AccessControl doesn't enumerate members, check specific addresses
     */
    function hasAdminRole(address account) external view returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, account);
    }

    // =========================================================================
    // Monitoring Functions
    // =========================================================================

    /**
     * @notice Get comprehensive timelock status
     * @return delay Current minimum delay
     * @return maxDelay Maximum allowed delay
     * @return isMainnetDelay Whether using mainnet delay
     * @return isTestnetDelay Whether using testnet delay
     * @return isDevnetDelay Whether using devnet delay
     */
    function getTimelockStatus() external view returns (
        uint256 delay,
        uint256 maxDelay,
        bool isMainnetDelay,
        bool isTestnetDelay,
        bool isDevnetDelay
    ) {
        uint256 currentDelay = getMinDelay();
        return (
            currentDelay,
            MAX_DELAY,
            currentDelay >= MAINNET_MIN_DELAY,
            currentDelay >= TESTNET_MIN_DELAY && currentDelay < MAINNET_MIN_DELAY,
            currentDelay < TESTNET_MIN_DELAY
        );
    }

    /**
     * @notice Check the status of a scheduled operation
     * @param id Operation id (hash)
     * @return isPending Whether operation is pending
     * @return isReady Whether operation is ready to execute
     * @return isDone Whether operation has been executed
     * @return timestamp When the operation can be executed (0 if not scheduled)
     */
    function getOperationStatus(bytes32 id) external view returns (
        bool isPending,
        bool isReady,
        bool isDone,
        uint256 timestamp
    ) {
        return (
            isOperationPending(id),
            isOperationReady(id),
            isOperationDone(id),
            getTimestamp(id)
        );
    }

    /**
     * @notice Calculate time remaining until an operation can be executed
     * @param id Operation id (hash)
     * @return remaining Seconds until ready (0 if already ready or not scheduled)
     */
    function getTimeRemaining(bytes32 id) external view returns (uint256 remaining) {
        uint256 timestamp = getTimestamp(id);
        if (timestamp == 0 || timestamp == 1) {
            return 0; // Not scheduled or already done
        }
        if (block.timestamp >= timestamp) {
            return 0; // Already ready
        }
        return timestamp - block.timestamp;
    }

    /**
     * @notice Check roles for an account
     * @param account Address to check
     * @return isProposer Has proposer role
     * @return isExecutor Has executor role
     * @return isCanceller Has canceller role
     * @return isAdmin Has admin role
     */
    function getRoles(address account) external view returns (
        bool isProposer,
        bool isExecutor,
        bool isCanceller,
        bool isAdmin
    ) {
        return (
            hasRole(PROPOSER_ROLE, account),
            hasRole(EXECUTOR_ROLE, account),
            hasRole(CANCELLER_ROLE, account),
            hasRole(DEFAULT_ADMIN_ROLE, account)
        );
    }

    /**
     * @notice Calculate the operation id for a single call
     * @param target Target address
     * @param value ETH value
     * @param data Call data
     * @param predecessor Predecessor operation
     * @param salt Unique salt
     * @return id The operation id
     */
    function computeOperationId(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) external pure returns (bytes32 id) {
        return hashOperation(target, value, data, predecessor, salt);
    }

    /**
     * @notice Calculate the operation id for a batch call
     * @param targets Target addresses
     * @param values ETH values
     * @param payloads Call data array
     * @param predecessor Predecessor operation
     * @param salt Unique salt
     * @return id The operation id
     */
    function computeBatchOperationId(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt
    ) external pure returns (bytes32 id) {
        return hashOperationBatch(targets, values, payloads, predecessor, salt);
    }

    /**
     * @notice Get recommended delay for a given environment
     * @param environment 0=devnet, 1=testnet, 2=mainnet
     * @return recommendedDelay The recommended minimum delay
     */
    function getRecommendedDelay(uint8 environment) external pure returns (uint256 recommendedDelay) {
        if (environment == 0) return DEVNET_MIN_DELAY;
        if (environment == 1) return TESTNET_MIN_DELAY;
        return MAINNET_MIN_DELAY;
    }

    // =========================================================================
    // Batch Query Functions
    // =========================================================================

    /**
     * @notice Check roles for multiple accounts
     * @param accounts Array of addresses to check
     * @return isProposer_ Array of proposer statuses
     * @return isExecutor_ Array of executor statuses
     * @return isCanceller_ Array of canceller statuses
     * @return isAdmin_ Array of admin statuses
     */
    function batchGetRoles(
        address[] calldata accounts
    ) external view returns (
        bool[] memory isProposer_,
        bool[] memory isExecutor_,
        bool[] memory isCanceller_,
        bool[] memory isAdmin_
    ) {
        if (accounts.length == 0) revert EmptyArray();

        uint256 len = accounts.length;
        isProposer_ = new bool[](len);
        isExecutor_ = new bool[](len);
        isCanceller_ = new bool[](len);
        isAdmin_ = new bool[](len);

        for (uint256 i = 0; i < len; i++) {
            isProposer_[i] = hasRole(PROPOSER_ROLE, accounts[i]);
            isExecutor_[i] = hasRole(EXECUTOR_ROLE, accounts[i]);
            isCanceller_[i] = hasRole(CANCELLER_ROLE, accounts[i]);
            isAdmin_[i] = hasRole(DEFAULT_ADMIN_ROLE, accounts[i]);
        }

        return (isProposer_, isExecutor_, isCanceller_, isAdmin_);
    }

    /**
     * @notice Check operation status for multiple operations
     * @param ids Array of operation IDs
     * @return isPending_ Array of pending statuses
     * @return isReady_ Array of ready statuses
     * @return isDone_ Array of done statuses
     * @return timestamps_ Array of execution timestamps
     */
    function batchGetOperationStatus(
        bytes32[] calldata ids
    ) external view returns (
        bool[] memory isPending_,
        bool[] memory isReady_,
        bool[] memory isDone_,
        uint256[] memory timestamps_
    ) {
        if (ids.length == 0) revert EmptyArray();

        uint256 len = ids.length;
        isPending_ = new bool[](len);
        isReady_ = new bool[](len);
        isDone_ = new bool[](len);
        timestamps_ = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            isPending_[i] = isOperationPending(ids[i]);
            isReady_[i] = isOperationReady(ids[i]);
            isDone_[i] = isOperationDone(ids[i]);
            timestamps_[i] = getTimestamp(ids[i]);
        }

        return (isPending_, isReady_, isDone_, timestamps_);
    }

    /**
     * @notice Get time remaining for multiple operations
     * @param ids Array of operation IDs
     * @return remaining Array of seconds remaining
     */
    function batchGetTimeRemaining(
        bytes32[] calldata ids
    ) external view returns (uint256[] memory remaining) {
        if (ids.length == 0) revert EmptyArray();

        remaining = new uint256[](ids.length);

        for (uint256 i = 0; i < ids.length; i++) {
            uint256 timestamp = getTimestamp(ids[i]);
            if (timestamp == 0 || timestamp == 1 || block.timestamp >= timestamp) {
                remaining[i] = 0;
            } else {
                remaining[i] = timestamp - block.timestamp;
            }
        }

        return remaining;
    }

    /**
     * @notice Check if accounts can propose
     * @param accounts Array of addresses
     * @return canPropose_ Array of proposer statuses
     */
    function batchCanPropose(
        address[] calldata accounts
    ) external view returns (bool[] memory canPropose_) {
        if (accounts.length == 0) revert EmptyArray();

        canPropose_ = new bool[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            canPropose_[i] = hasRole(PROPOSER_ROLE, accounts[i]);
        }
        return canPropose_;
    }

    /**
     * @notice Check if accounts can execute
     * @param accounts Array of addresses
     * @return canExecute_ Array of executor statuses
     */
    function batchCanExecute(
        address[] calldata accounts
    ) external view returns (bool[] memory canExecute_) {
        if (accounts.length == 0) revert EmptyArray();

        canExecute_ = new bool[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            canExecute_[i] = hasRole(EXECUTOR_ROLE, accounts[i]);
        }
        return canExecute_;
    }

    // =========================================================================
    // Extended Monitoring
    // =========================================================================

    /**
     * @notice Get extended timelock configuration
     * @return minDelay_ Current minimum delay
     * @return maxDelay_ Maximum allowed delay
     * @return mainnetDelay_ Mainnet recommended delay
     * @return testnetDelay_ Testnet recommended delay
     * @return devnetDelay_ Devnet recommended delay
     * @return currentEnvironment_ Current environment based on delay (0=dev, 1=test, 2=main)
     */
    function getExtendedConfig() external view returns (
        uint256 minDelay_,
        uint256 maxDelay_,
        uint256 mainnetDelay_,
        uint256 testnetDelay_,
        uint256 devnetDelay_,
        uint8 currentEnvironment_
    ) {
        uint256 currentDelay = getMinDelay();

        uint8 env;
        if (currentDelay >= MAINNET_MIN_DELAY) {
            env = 2; // Mainnet
        } else if (currentDelay >= TESTNET_MIN_DELAY) {
            env = 1; // Testnet
        } else {
            env = 0; // Devnet
        }

        return (
            currentDelay,
            MAX_DELAY,
            MAINNET_MIN_DELAY,
            TESTNET_MIN_DELAY,
            DEVNET_MIN_DELAY,
            env
        );
    }

    /**
     * @notice Check if an operation exists and is actionable
     * @param id Operation ID
     * @return exists Whether the operation exists (was scheduled)
     * @return actionable Whether it can be executed now
     * @return secondsToActionable Seconds until it becomes actionable (0 if ready or doesn't exist)
     * @return executed Whether it has been executed
     */
    function getOperationActionability(bytes32 id) external view returns (
        bool exists,
        bool actionable,
        uint256 secondsToActionable,
        bool executed
    ) {
        uint256 timestamp = getTimestamp(id);

        // Check if operation exists
        exists = timestamp > 0;

        // Check if executed (timestamp == 1 means done)
        executed = timestamp == 1;

        // Check if ready to execute
        actionable = isOperationReady(id);

        // Calculate time to actionable
        if (!exists || executed || actionable) {
            secondsToActionable = 0;
        } else {
            secondsToActionable = timestamp > block.timestamp ? timestamp - block.timestamp : 0;
        }

        return (exists, actionable, secondsToActionable, executed);
    }

    /**
     * @notice Helper to verify roles before scheduling
     * @param proposer Address that will propose
     * @param executor Address that will execute
     * @return canSchedule Whether proposer can schedule
     * @return canRun Whether executor can execute
     * @return delay Current delay that will apply
     */
    function verifyRolesForOperation(
        address proposer,
        address executor
    ) external view returns (
        bool canSchedule,
        bool canRun,
        uint256 delay
    ) {
        return (
            hasRole(PROPOSER_ROLE, proposer),
            hasRole(EXECUTOR_ROLE, executor),
            getMinDelay()
        );
    }

    /**
     * @notice Calculate when an operation would become executable if scheduled now
     * @return executeableAt Timestamp when operation would be executable
     * @return currentTime Current block timestamp
     * @return delaySeconds Delay in seconds
     */
    function getExecutionTimeline() external view returns (
        uint256 executeableAt,
        uint256 currentTime,
        uint256 delaySeconds
    ) {
        uint256 delay = getMinDelay();
        return (
            block.timestamp + delay,
            block.timestamp,
            delay
        );
    }
}
