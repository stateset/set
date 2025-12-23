// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

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
contract ForcedInclusion is Ownable, ReentrancyGuard {
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

    // =========================================================================
    // Constructor
    // =========================================================================

    constructor(
        address _owner,
        address _l2OutputOracle,
        address _optimismPortal
    ) Ownable(_owner) {
        l2OutputOracle = _l2OutputOracle;
        optimismPortal = _optimismPortal;
    }

    // =========================================================================
    // Admin Functions
    // =========================================================================

    /**
     * @notice Update L2OutputOracle address
     * @param _l2OutputOracle New address
     */
    function setL2OutputOracle(address _l2OutputOracle) external onlyOwner {
        l2OutputOracle = _l2OutputOracle;
    }

    /**
     * @notice Update OptimismPortal address
     * @param _optimismPortal New address
     */
    function setOptimismPortal(address _optimismPortal) external onlyOwner {
        optimismPortal = _optimismPortal;
    }

    /**
     * @notice Update tx root oracle address
     * @param _txRootOracle New oracle address
     */
    function setTxRootOracle(address _txRootOracle) external onlyOwner {
        emit TxRootOracleUpdated(txRootOracle, _txRootOracle);
        txRootOracle = _txRootOracle;
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
    ) external payable nonReentrant returns (bytes32 txId) {
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
}
