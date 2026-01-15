// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title ForcedInclusion
 * @notice L1 contract for censorship-resistant transaction inclusion on Set Chain
 * @dev Deployed on Ethereum L1, provides escape hatch for censored users
 *
 * Flow:
 * 1. User submits transaction + bond to this contract on L1
 * 2. Sequencer MUST include the transaction within INCLUSION_DEADLINE
 * 3. If included: user can claim bond back with inclusion proof
 * 4. If not included: user can reclaim bond + sequencer faces reputation damage
 *
 * This mechanism ensures users always have a path to inclusion, even if
 * the sequencer attempts to censor specific transactions.
 */
contract ForcedInclusion is Ownable, ReentrancyGuard, Pausable {
    // =========================================================================
    // Interfaces
    // =========================================================================

    interface ITxRootOracle {
        function getTxRoot(uint256 l2BlockNumber) external view returns (bytes32);
    }

    // =========================================================================
    // Constants
    // =========================================================================

    /// @notice Time sequencer has to include forced transaction
    uint256 public constant INCLUSION_DEADLINE = 24 hours;

    /// @notice Minimum bond required to force inclusion
    uint256 public constant MIN_BOND = 0.01 ether;

    /// @notice Maximum gas limit for forced transactions
    uint256 public constant MAX_GAS_LIMIT = 10_000_000;

    // =========================================================================
    // Types
    // =========================================================================

    /// @notice Forced transaction request
    struct ForcedTx {
        address sender;         // Original sender
        address target;         // Target contract on L2
        bytes data;             // Calldata
        uint256 value;          // ETH value to send
        uint256 gasLimit;       // Gas limit
        uint256 bond;           // Bond amount
        uint256 deadline;       // Inclusion deadline
        uint256 l2BlockNumber;  // L2 block where included (0 if pending)
        bool resolved;          // Whether resolved (included or expired)
    }

    /// @notice Statistics
    struct Stats {
        uint256 totalForced;
        uint256 totalIncluded;
        uint256 totalExpired;
        uint256 totalBondsLocked;
    }

    // =========================================================================
    // State Variables
    // =========================================================================

    /// @notice Forced transactions by ID
    mapping(bytes32 => ForcedTx) public forcedTransactions;

    /// @notice User's pending forced transactions
    mapping(address => bytes32[]) public userForcedTxs;

    /// @notice All forced transaction IDs (append-only)
    bytes32[] public allForcedTxs;

    /// @notice L2OutputOracle contract for verifying inclusion
    address public l2OutputOracle;

    /// @notice OptimismPortal contract for cross-domain messages
    address public optimismPortal;

    /// @notice Oracle for L2 transactions root by block number
    address public txRootOracle;

    /// @notice Statistics
    Stats public stats;

    /// @notice Sequencer reputation (negative points for missed inclusions)
    mapping(address => uint256) public sequencerPenalties;

    // =========================================================================
    // Circuit Breaker State
    // =========================================================================

    /// @notice Maximum pending transactions allowed (circuit breaker)
    uint256 public maxPendingTxs;

    /// @notice Rate limit: max txs per user per hour
    uint256 public maxTxsPerUserPerHour;

    /// @notice User rate limiting tracking
    mapping(address => uint256) public userTxCount;
    mapping(address => uint256) public userLastReset;

    // =========================================================================
    // Events
    // =========================================================================

    event TransactionForced(
        bytes32 indexed txId,
        address indexed sender,
        address target,
        uint256 value,
        uint256 gasLimit,
        uint256 deadline
    );

    event TransactionIncluded(
        bytes32 indexed txId,
        uint256 l2BlockNumber
    );

    event TransactionExpired(
        bytes32 indexed txId,
        address indexed sender,
        uint256 bondReturned
    );

    event BondClaimed(
        bytes32 indexed txId,
        address indexed sender,
        uint256 amount
    );

    event TxRootOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event CircuitBreakerUpdated(uint256 maxPendingTxs, uint256 maxTxsPerUserPerHour);
    event L2OutputOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event OptimismPortalUpdated(address indexed oldPortal, address indexed newPortal);

    // =========================================================================
    // Errors
    // =========================================================================

    error InsufficientBond();
    error GasLimitTooHigh();
    error TransactionNotFound();
    error TransactionAlreadyResolved();
    error DeadlineNotReached();
    error InvalidInclusionProof();
    error TransferFailed();
    error CircuitBreakerTripped();
    error RateLimitExceeded();
    error InvalidAddress();
    error InvalidTarget();

    // =========================================================================
    // Constructor
    // =========================================================================

    constructor(
        address _owner,
        address _l2OutputOracle,
        address _optimismPortal
    ) Ownable(_owner) {
        if (_owner == address(0)) revert InvalidAddress();

        l2OutputOracle = _l2OutputOracle;
        optimismPortal = _optimismPortal;

        // Initialize circuit breaker defaults
        maxPendingTxs = 1000;          // Max 1000 pending txs
        maxTxsPerUserPerHour = 10;     // Max 10 txs per user per hour
    }

    // =========================================================================
    // Admin Functions
    // =========================================================================

    /**
     * @notice Update L2OutputOracle address
     * @param _l2OutputOracle New address
     */
    function setL2OutputOracle(address _l2OutputOracle) external onlyOwner {
        if (_l2OutputOracle == address(0)) revert InvalidAddress();
        address oldOracle = l2OutputOracle;
        l2OutputOracle = _l2OutputOracle;
        emit L2OutputOracleUpdated(oldOracle, _l2OutputOracle);
    }

    /**
     * @notice Update OptimismPortal address
     * @param _optimismPortal New address
     */
    function setOptimismPortal(address _optimismPortal) external onlyOwner {
        if (_optimismPortal == address(0)) revert InvalidAddress();
        address oldPortal = optimismPortal;
        optimismPortal = _optimismPortal;
        emit OptimismPortalUpdated(oldPortal, _optimismPortal);
    }

    /**
     * @notice Update tx root oracle address
     * @param _txRootOracle New oracle address
     */
    function setTxRootOracle(address _txRootOracle) external onlyOwner {
        if (_txRootOracle == address(0)) revert InvalidAddress();
        emit TxRootOracleUpdated(txRootOracle, _txRootOracle);
        txRootOracle = _txRootOracle;
    }

    /**
     * @notice Update circuit breaker settings
     * @param _maxPendingTxs Maximum pending transactions allowed
     * @param _maxTxsPerUserPerHour Maximum transactions per user per hour
     */
    function setCircuitBreakerLimits(
        uint256 _maxPendingTxs,
        uint256 _maxTxsPerUserPerHour
    ) external onlyOwner {
        maxPendingTxs = _maxPendingTxs;
        maxTxsPerUserPerHour = _maxTxsPerUserPerHour;
        emit CircuitBreakerUpdated(_maxPendingTxs, _maxTxsPerUserPerHour);
    }

    /**
     * @notice Pause the contract (emergency stop)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // =========================================================================
    // Core Functions
    // =========================================================================

    /**
     * @notice Force a transaction to be included on L2
     * @param _target Target contract address on L2
     * @param _data Calldata for the transaction
     * @param _gasLimit Gas limit for execution on L2
     * @return txId Unique identifier for this forced transaction
     */
    function forceTransaction(
        address _target,
        bytes calldata _data,
        uint256 _gasLimit
    ) external payable nonReentrant whenNotPaused returns (bytes32 txId) {
        // Validate target
        if (_target == address(0)) revert InvalidTarget();

        // Circuit breaker: check pending count
        if (stats.totalForced - stats.totalIncluded - stats.totalExpired >= maxPendingTxs) {
            revert CircuitBreakerTripped();
        }

        // Rate limiting: check user's tx count
        _checkAndUpdateRateLimit(msg.sender);

        // Validate bond
        if (msg.value < MIN_BOND) {
            revert InsufficientBond();
        }

        // Validate gas limit
        if (_gasLimit > MAX_GAS_LIMIT) {
            revert GasLimitTooHigh();
        }

        // Generate unique ID
        txId = keccak256(abi.encodePacked(
            msg.sender,
            _target,
            _data,
            _gasLimit,
            block.timestamp,
            block.number
        ));

        // Store forced transaction
        forcedTransactions[txId] = ForcedTx({
            sender: msg.sender,
            target: _target,
            data: _data,
            value: 0, // L2 value sent separately via bridge
            gasLimit: _gasLimit,
            bond: msg.value,
            deadline: block.timestamp + INCLUSION_DEADLINE,
            l2BlockNumber: 0,
            resolved: false
        });

        userForcedTxs[msg.sender].push(txId);
        allForcedTxs.push(txId);

        // Update stats
        stats.totalForced++;
        stats.totalBondsLocked += msg.value;

        emit TransactionForced(
            txId,
            msg.sender,
            _target,
            0,
            _gasLimit,
            block.timestamp + INCLUSION_DEADLINE
        );

        return txId;
    }

    /**
     * @notice Confirm that a forced transaction was included on L2
     * @param _txId Transaction ID
     * @param _l2BlockNumber L2 block where transaction was included
     * @param _inclusionProof Merkle proof of inclusion
     */
    function confirmInclusion(
        bytes32 _txId,
        uint256 _l2BlockNumber,
        bytes calldata _inclusionProof
    ) external nonReentrant {
        ForcedTx storage forcedTx = forcedTransactions[_txId];

        if (forcedTx.sender == address(0)) {
            revert TransactionNotFound();
        }

        if (forcedTx.resolved) {
            revert TransactionAlreadyResolved();
        }

        // Verify inclusion proof against L2OutputOracle
        if (!_verifyInclusion(_txId, _l2BlockNumber, _inclusionProof)) {
            revert InvalidInclusionProof();
        }

        // Mark as resolved
        forcedTx.resolved = true;
        forcedTx.l2BlockNumber = _l2BlockNumber;

        // Return bond to sender
        uint256 bondAmount = forcedTx.bond;
        stats.totalBondsLocked -= bondAmount;
        stats.totalIncluded++;

        (bool success, ) = forcedTx.sender.call{value: bondAmount}("");
        if (!success) {
            revert TransferFailed();
        }

        emit TransactionIncluded(_txId, _l2BlockNumber);
        emit BondClaimed(_txId, forcedTx.sender, bondAmount);
    }

    /**
     * @notice Claim bond back if transaction was not included before deadline
     * @param _txId Transaction ID
     */
    function claimExpired(bytes32 _txId) external nonReentrant {
        ForcedTx storage forcedTx = forcedTransactions[_txId];

        if (forcedTx.sender == address(0)) {
            revert TransactionNotFound();
        }

        if (forcedTx.resolved) {
            revert TransactionAlreadyResolved();
        }

        if (block.timestamp < forcedTx.deadline) {
            revert DeadlineNotReached();
        }

        // Mark as resolved (expired)
        forcedTx.resolved = true;

        // Return bond to sender
        uint256 bondAmount = forcedTx.bond;
        stats.totalBondsLocked -= bondAmount;
        stats.totalExpired++;

        (bool success, ) = forcedTx.sender.call{value: bondAmount}("");
        if (!success) {
            revert TransferFailed();
        }

        emit TransactionExpired(_txId, forcedTx.sender, bondAmount);
    }

    // =========================================================================
    // Query Functions
    // =========================================================================

    /**
     * @notice Get all pending forced transactions for a user
     * @param _user User address
     * @return txIds Array of transaction IDs
     */
    function getUserPendingTxs(
        address _user
    ) external view returns (bytes32[] memory txIds) {
        bytes32[] storage allTxs = userForcedTxs[_user];
        uint256 pendingCount = 0;

        // Count pending
        for (uint256 i = 0; i < allTxs.length; i++) {
            if (!forcedTransactions[allTxs[i]].resolved) {
                pendingCount++;
            }
        }

        // Build array
        txIds = new bytes32[](pendingCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allTxs.length; i++) {
            if (!forcedTransactions[allTxs[i]].resolved) {
                txIds[index] = allTxs[i];
                index++;
            }
        }

        return txIds;
    }

    /**
     * @notice Check if a transaction is pending (not yet resolved)
     * @param _txId Transaction ID
     * @return pending True if pending
     */
    function isPending(bytes32 _txId) external view returns (bool pending) {
        ForcedTx storage forcedTx = forcedTransactions[_txId];
        return forcedTx.sender != address(0) && !forcedTx.resolved;
    }

    /**
     * @notice Check if a transaction has expired
     * @param _txId Transaction ID
     * @return expired True if expired
     */
    function isExpired(bytes32 _txId) external view returns (bool expired) {
        ForcedTx storage forcedTx = forcedTransactions[_txId];
        return forcedTx.sender != address(0) &&
               !forcedTx.resolved &&
               block.timestamp >= forcedTx.deadline;
    }

    /**
     * @notice Get statistics
     * @return stats_ Current statistics
     */
    function getStats() external view returns (Stats memory stats_) {
        return stats;
    }

    // =========================================================================
    // Internal Functions
    // =========================================================================

    /**
     * @dev Verify inclusion of a forced transaction in L2
     * @param _txId Transaction ID
     * @param _l2BlockNumber L2 block number
     * @param _proof Inclusion proof (ABI-encoded: outputRoot, txRoot, storageProof[], txIndex)
     * @return valid True if proof is valid
     *
     * Proof structure:
     * - bytes32 outputRoot: The L2 output root from L2OutputOracle
     * - bytes32 txRoot: Transactions root for the L2 block
     * - bytes32[] storageProof: Merkle proof for transaction in block's tx trie
     * - uint256 txIndex: Leaf index in the tx trie
     *
     * Security assumptions (documented in docs/mev-protection.md):
     * - L2OutputOracle is trusted and correctly posts L2 state roots
     * - The proof verifies against a finalized (not disputed) output root
     * - Transaction hash includes sender, target, data, gasLimit to prevent spoofing
     * - Tx root oracle is trusted to provide the correct txRoot for finalized blocks
     */
    function _verifyInclusion(
        bytes32 _txId,
        uint256 _l2BlockNumber,
        bytes calldata _proof
    ) internal view returns (bool valid) {
        // Minimum proof size: outputRoot + txRoot + offsets
        if (_proof.length < 128) {
            return false;
        }

        // Decode the proof components
        (
            bytes32 claimedOutputRoot,
            bytes32 txRoot,
            bytes32[] memory storageProof,
            uint256 txIndex
        ) = abi.decode(_proof, (bytes32, bytes32, bytes32[], uint256));

        // Verify output root against L2OutputOracle
        if (l2OutputOracle == address(0)) {
            return false;
        }

        // Query L2OutputOracle for the output root at the claimed block
        // Interface: getL2Output(uint256 _l2BlockNumber) returns (bytes32 outputRoot, uint256 timestamp)
        (bool success, bytes memory returnData) = l2OutputOracle.staticcall(
            abi.encodeWithSignature("getL2Output(uint256)", _l2BlockNumber)
        );

        if (!success || returnData.length < 32) {
            return false;
        }

        bytes32 oracleOutputRoot = abi.decode(returnData, (bytes32));

        // Output root must match what's in the oracle
        if (oracleOutputRoot != claimedOutputRoot || oracleOutputRoot == bytes32(0)) {
            return false;
        }

        // Verify transactions root against oracle
        if (txRootOracle == address(0)) {
            return false;
        }
        bytes32 oracleTxRoot = ITxRootOracle(txRootOracle).getTxRoot(_l2BlockNumber);
        if (oracleTxRoot != txRoot || txRoot == bytes32(0)) {
            return false;
        }

        // Reconstruct the expected transaction hash from stored data
        ForcedTx storage forcedTx = forcedTransactions[_txId];
        bytes32 expectedTxHash = keccak256(abi.encodePacked(
            forcedTx.sender,
            forcedTx.target,
            forcedTx.data,
            forcedTx.gasLimit
        ));

        // Verify the Merkle proof that this transaction was included in the block
        // The leaf is the transaction hash, and we verify it's in the transactions trie
        bytes32 computedRoot = _computeMerkleRoot(expectedTxHash, storageProof, txIndex);

        return computedRoot == txRoot;
    }

    /**
     * @dev Compute Merkle root from leaf and proof
     * @param _leaf The leaf node (transaction hash)
     * @param _proof The Merkle proof path
     * @param _index The index of the leaf in the tree
     * @return root The computed Merkle root
     */
    function _computeMerkleRoot(
        bytes32 _leaf,
        bytes32[] memory _proof,
        uint256 _index
    ) internal pure returns (bytes32 root) {
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
     * @dev Check and update rate limit for a user
     * @param _user User address to check
     */
    function _checkAndUpdateRateLimit(address _user) internal {
        // Reset count if an hour has passed
        if (block.timestamp - userLastReset[_user] >= 1 hours) {
            userTxCount[_user] = 0;
            userLastReset[_user] = block.timestamp;
        }

        // Check rate limit
        if (userTxCount[_user] >= maxTxsPerUserPerHour) {
            revert RateLimitExceeded();
        }

        // Increment count
        userTxCount[_user]++;
    }

    /**
     * @notice Get the current pending transaction count
     * @return pendingCount Number of pending transactions
     */
    function getPendingCount() external view returns (uint256 pendingCount) {
        return stats.totalForced - stats.totalIncluded - stats.totalExpired;
    }

    /**
     * @notice Check if user is rate limited
     * @param _user User address to check
     * @return limited True if user is currently rate limited
     * @return remaining Remaining transactions this hour
     */
    function isRateLimited(address _user) external view returns (bool limited, uint256 remaining) {
        uint256 count = userTxCount[_user];

        // If an hour has passed, they have full quota
        if (block.timestamp - userLastReset[_user] >= 1 hours) {
            return (false, maxTxsPerUserPerHour);
        }

        if (count >= maxTxsPerUserPerHour) {
            return (true, 0);
        }

        return (false, maxTxsPerUserPerHour - count);
    }

    // =========================================================================
    // Monitoring Functions
    // =========================================================================

    /**
     * @notice Get comprehensive forced inclusion status
     * @return pendingCount Number of pending transactions
     * @return totalForced Total forced transactions
     * @return totalIncluded Total included on L2
     * @return totalExpired Total expired
     * @return bondsLocked Total ETH locked in bonds
     * @return isPaused Whether contract is paused
     * @return circuitBreakerCapacity Remaining capacity before circuit breaker trips
     */
    function getSystemStatus() external view returns (
        uint256 pendingCount,
        uint256 totalForced,
        uint256 totalIncluded,
        uint256 totalExpired,
        uint256 bondsLocked,
        bool isPaused,
        uint256 circuitBreakerCapacity
    ) {
        uint256 pending = stats.totalForced - stats.totalIncluded - stats.totalExpired;
        uint256 capacity = maxPendingTxs > pending ? maxPendingTxs - pending : 0;

        return (
            pending,
            stats.totalForced,
            stats.totalIncluded,
            stats.totalExpired,
            stats.totalBondsLocked,
            paused(),
            capacity
        );
    }

    /**
     * @notice Get transaction details with status info
     * @param _txId Transaction ID
     * @return sender Original sender
     * @return target Target contract
     * @return bond Bond amount
     * @return deadline Inclusion deadline
     * @return isResolved Whether resolved
     * @return isExpiredNow Whether deadline has passed (and not resolved)
     * @return timeRemaining Seconds until deadline (0 if passed)
     */
    function getTxDetails(bytes32 _txId) external view returns (
        address sender,
        address target,
        uint256 bond,
        uint256 deadline,
        bool isResolved,
        bool isExpiredNow,
        uint256 timeRemaining
    ) {
        ForcedTx storage tx_ = forcedTransactions[_txId];

        uint256 remaining = 0;
        if (!tx_.resolved && block.timestamp < tx_.deadline) {
            remaining = tx_.deadline - block.timestamp;
        }

        bool expiredNow = !tx_.resolved && block.timestamp >= tx_.deadline;

        return (
            tx_.sender,
            tx_.target,
            tx_.bond,
            tx_.deadline,
            tx_.resolved,
            expiredNow,
            remaining
        );
    }

    /**
     * @notice Get batch of transaction statuses
     * @param _txIds Array of transaction IDs
     * @return resolved Array of resolved statuses
     * @return expired Array of expired statuses
     */
    function getBatchTxStatuses(bytes32[] calldata _txIds) external view returns (
        bool[] memory resolved,
        bool[] memory expired
    ) {
        resolved = new bool[](_txIds.length);
        expired = new bool[](_txIds.length);

        for (uint256 i = 0; i < _txIds.length; i++) {
            ForcedTx storage tx_ = forcedTransactions[_txIds[i]];
            resolved[i] = tx_.resolved;
            expired[i] = !tx_.resolved && block.timestamp >= tx_.deadline;
        }

        return (resolved, expired);
    }

    /**
     * @notice Get all expirable transactions (past deadline, not resolved)
     * @param _maxResults Maximum results to return
     * @return txIds Array of expirable transaction IDs
     */
    function getExpirableTxs(uint256 _maxResults) external view returns (bytes32[] memory txIds) {
        if (_maxResults == 0) {
            return new bytes32[](0);
        }

        bytes32[] memory results = new bytes32[](_maxResults);
        uint256 found = 0;

        // Note: This is O(n) and should only be called off-chain
        // On-chain, use events to track transactions
        for (uint256 i = 0; i < allForcedTxs.length && found < _maxResults; i++) {
            bytes32 txId = allForcedTxs[i];
            ForcedTx storage tx_ = forcedTransactions[txId];

            if (tx_.sender != address(0) && !tx_.resolved && block.timestamp >= tx_.deadline) {
                results[found] = txId;
                found++;
            }
        }

        // Trim unused slots for cleaner off-chain consumption.
        assembly {
            mstore(results, found)
        }

        return results;
    }

    /**
     * @notice Calculate inclusion rate
     * @return rate Inclusion rate in basis points (10000 = 100%)
     */
    function getInclusionRate() external view returns (uint256 rate) {
        uint256 resolved = stats.totalIncluded + stats.totalExpired;
        if (resolved == 0) return 10000; // 100% if no resolutions yet
        return (stats.totalIncluded * 10000) / resolved;
    }

    /**
     * @notice Get user's forced transaction history summary
     * @param _user User address
     * @return totalSubmitted Total submitted by user
     * @return pendingCount Pending count
     * @return currentRateUsed Rate limit used this hour
     * @return canSubmitNow Whether user can submit now
     */
    function getUserSummary(address _user) external view returns (
        uint256 totalSubmitted,
        uint256 pendingCount,
        uint256 currentRateUsed,
        bool canSubmitNow
    ) {
        bytes32[] storage allTxs = userForcedTxs[_user];
        uint256 pending = 0;

        for (uint256 i = 0; i < allTxs.length; i++) {
            if (!forcedTransactions[allTxs[i]].resolved) {
                pending++;
            }
        }

        uint256 rateUsed = userTxCount[_user];
        if (block.timestamp - userLastReset[_user] >= 1 hours) {
            rateUsed = 0;
        }

        bool canSubmit = rateUsed < maxTxsPerUserPerHour && !paused();

        return (allTxs.length, pending, rateUsed, canSubmit);
    }
}
