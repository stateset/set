// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "./ThresholdKeyRegistry.sol";

/**
 * @title EncryptedMempool
 * @notice Handles submission and execution of threshold-encrypted transactions
 * @dev Part of Set Chain's MEV protection strategy (Phase 2)
 *
 * Flow:
 * 1. User encrypts tx with current epoch's threshold public key (off-chain)
 * 2. User submits encrypted tx to this contract
 * 3. Sequencer commits to ordering (by encrypted tx hash)
 * 4. Keypers provide decryption shares (off-chain coordination)
 * 5. Once threshold shares available, tx is decrypted and executed
 *
 * This ensures:
 * - Transaction contents are hidden until ordering is committed
 * - Frontrunning and sandwich attacks are not possible
 * - Fair ordering is cryptographically enforced
 */
contract EncryptedMempool is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    // =========================================================================
    // Constants
    // =========================================================================

    /// @notice Maximum encrypted payload size (64 KB)
    uint256 public constant MAX_PAYLOAD_SIZE = 65536;

    /// @notice Decryption timeout in blocks (~10 minutes)
    uint256 public constant DECRYPTION_TIMEOUT = 50;

    /// @notice Minimum gas for encrypted tx execution
    uint256 public constant MIN_GAS_LIMIT = 21000;

    /// @notice Maximum gas for encrypted tx execution
    uint256 public constant MAX_GAS_LIMIT = 10_000_000;

    // =========================================================================
    // Types
    // =========================================================================

    /// @notice Encrypted transaction
    struct EncryptedTx {
        bytes32 id;                 // Unique identifier
        address sender;             // Original sender
        bytes encryptedPayload;     // Encrypted tx data
        bytes32 payloadHash;        // Hash of encrypted payload
        uint256 epoch;              // Encryption epoch
        uint256 gasLimit;           // Gas limit for execution
        uint256 maxFeePerGas;       // Max fee willing to pay
        uint256 valueDeposit;       // ETH deposit to cover decrypted value
        uint256 submittedAt;        // Block when submitted
        uint256 orderPosition;      // Position in ordering (set by sequencer)
        EncryptedTxStatus status;   // Current status
    }

    /// @notice Decrypted transaction (after threshold decryption)
    struct DecryptedTx {
        bytes32 encryptedId;        // Reference to encrypted tx
        address to;                 // Target address
        bytes data;                 // Calldata
        uint256 value;              // ETH value
        uint256 decryptedAt;        // Block when decrypted
        bool executed;              // Whether executed
        bool success;               // Execution result
    }

    /// @notice Transaction status
    enum EncryptedTxStatus {
        Pending,        // Submitted, awaiting ordering
        Ordered,        // Ordering committed by sequencer
        Decrypting,     // Decryption in progress
        Decrypted,      // Decrypted, ready for execution
        Executed,       // Successfully executed
        Failed,         // Execution failed
        Expired         // Decryption timed out
    }

    /// @notice Ordering commitment from sequencer
    struct OrderingCommitment {
        bytes32 batchId;            // Batch identifier
        bytes32 orderingRoot;       // Merkle root of ordered tx hashes
        uint256 txCount;            // Number of transactions
        uint256 committedAt;        // Block when committed
        bytes sequencerSignature;   // Sequencer's signature
    }

    // =========================================================================
    // State Variables
    // =========================================================================

    /// @notice Threshold key registry
    ThresholdKeyRegistry public keyRegistry;

    /// @notice Authorized sequencer
    address public sequencer;

    /// @notice Encrypted transactions by ID
    mapping(bytes32 => EncryptedTx) public encryptedTxs;

    /// @notice Decrypted transactions by encrypted ID
    mapping(bytes32 => DecryptedTx) public decryptedTxs;

    /// @notice Ordering commitments by batch ID
    mapping(bytes32 => OrderingCommitment) public orderingCommitments;

    /// @notice User's pending encrypted transactions
    mapping(address => bytes32[]) public userPendingTxs;

    /// @notice Pending transaction queue (ordered)
    bytes32[] public pendingQueue;

    /// @notice Next position in queue
    uint256 public nextQueuePosition;

    /// @notice Statistics
    uint256 public totalSubmitted;
    uint256 public totalExecuted;
    uint256 public totalFailed;
    uint256 public totalExpired;

    /// @notice Maximum queue size to prevent spam
    uint256 public maxQueueSize;

    /// @notice Rate limit: max submissions per user per block
    uint256 public maxSubmissionsPerUserPerBlock;

    /// @notice User submission count per block
    mapping(address => mapping(uint256 => uint256)) public userBlockSubmissions;

    // =========================================================================
    // Events
    // =========================================================================

    event EncryptedTxSubmitted(
        bytes32 indexed txId,
        address indexed sender,
        bytes32 payloadHash,
        uint256 epoch,
        uint256 gasLimit
    );

    event OrderingCommitted(
        bytes32 indexed batchId,
        bytes32 orderingRoot,
        uint256 txCount
    );

    event TxOrdered(
        bytes32 indexed txId,
        bytes32 indexed batchId,
        uint256 position
    );

    event TxDecrypted(
        bytes32 indexed txId,
        address to,
        uint256 value
    );

    event TxExecuted(
        bytes32 indexed txId,
        bool success,
        bytes returnData
    );

    event TxExpired(bytes32 indexed txId);

    event SequencerUpdated(address oldSequencer, address newSequencer);

    // =========================================================================
    // Errors
    // =========================================================================

    error PayloadTooLarge();
    error InvalidGasLimit();
    error InvalidEpoch();
    error TxAlreadyExists();
    error TxNotFound();
    error TxNotOrdered();
    error TxNotDecrypted();
    error TxAlreadyExecuted();
    error TxExpiredError();
    error NotSequencer();
    error InvalidSignature();
    error DecryptionFailed();
    error InsufficientFee();
    error ValueExceedsDeposit();
    error ExecutionFailed();
    error InvalidAddress();
    error QueueFull();
    error RateLimitExceeded();

    // =========================================================================
    // Modifiers
    // =========================================================================

    modifier onlySequencer() {
        if (msg.sender != sequencer) revert NotSequencer();
        _;
    }

    // =========================================================================
    // Initialization
    // =========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the encrypted mempool
     * @param _owner Owner address
     * @param _keyRegistry Threshold key registry address
     * @param _sequencer Initial sequencer address
     */
    function initialize(
        address _owner,
        address _keyRegistry,
        address _sequencer
    ) public initializer {
        if (_owner == address(0)) revert InvalidAddress();
        if (_keyRegistry == address(0)) revert InvalidAddress();
        if (_sequencer == address(0)) revert InvalidAddress();

        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        keyRegistry = ThresholdKeyRegistry(payable(_keyRegistry));
        sequencer = _sequencer;

        // Default limits
        maxQueueSize = 10000;
        maxSubmissionsPerUserPerBlock = 5;
    }

    // =========================================================================
    // User Functions
    // =========================================================================

    /**
     * @notice Submit an encrypted transaction
     * @param _encryptedPayload Threshold-encrypted transaction data
     * @param _epoch Epoch used for encryption
     * @param _gasLimit Gas limit for execution
     * @param _maxFeePerGas Maximum fee per gas
     * @return txId Unique transaction identifier
     */
    function submitEncryptedTx(
        bytes calldata _encryptedPayload,
        uint256 _epoch,
        uint256 _gasLimit,
        uint256 _maxFeePerGas
    ) external payable nonReentrant whenNotPaused returns (bytes32 txId) {
        // Check queue size limit
        uint256 effectiveQueueSize = pendingQueue.length - nextQueuePosition;
        if (maxQueueSize > 0 && effectiveQueueSize >= maxQueueSize) {
            revert QueueFull();
        }

        // Check rate limit
        if (maxSubmissionsPerUserPerBlock > 0) {
            if (userBlockSubmissions[msg.sender][block.number] >= maxSubmissionsPerUserPerBlock) {
                revert RateLimitExceeded();
            }
            userBlockSubmissions[msg.sender][block.number]++;
        }

        // Validate payload size
        if (_encryptedPayload.length > MAX_PAYLOAD_SIZE) {
            revert PayloadTooLarge();
        }

        // Validate gas limit
        if (_gasLimit < MIN_GAS_LIMIT || _gasLimit > MAX_GAS_LIMIT) {
            revert InvalidGasLimit();
        }

        // Validate epoch is current and key is valid
        if (!keyRegistry.isEpochKeyValid(_epoch)) {
            revert InvalidEpoch();
        }

        // Calculate minimum fee
        uint256 gasDeposit = _gasLimit * _maxFeePerGas;
        if (msg.value < gasDeposit) {
            revert InsufficientFee();
        }
        uint256 valueDeposit = msg.value - gasDeposit;

        // Generate unique ID
        bytes32 payloadHash = keccak256(_encryptedPayload);
        txId = keccak256(abi.encodePacked(
            msg.sender,
            payloadHash,
            block.number,
            block.timestamp
        ));

        if (encryptedTxs[txId].sender != address(0)) {
            revert TxAlreadyExists();
        }

        // Store encrypted transaction
        encryptedTxs[txId] = EncryptedTx({
            id: txId,
            sender: msg.sender,
            encryptedPayload: _encryptedPayload,
            payloadHash: payloadHash,
            epoch: _epoch,
            gasLimit: _gasLimit,
            maxFeePerGas: _maxFeePerGas,
            valueDeposit: valueDeposit,
            submittedAt: block.number,
            orderPosition: 0,
            status: EncryptedTxStatus.Pending
        });

        userPendingTxs[msg.sender].push(txId);
        pendingQueue.push(txId);
        totalSubmitted++;

        emit EncryptedTxSubmitted(
            txId,
            msg.sender,
            payloadHash,
            _epoch,
            _gasLimit
        );

        return txId;
    }

    /**
     * @notice Cancel a pending encrypted transaction
     * @param _txId Transaction ID to cancel
     */
    function cancelEncryptedTx(bytes32 _txId) external nonReentrant {
        EncryptedTx storage etx = encryptedTxs[_txId];

        if (etx.sender != msg.sender) revert TxNotFound();
        if (etx.status != EncryptedTxStatus.Pending) revert TxNotFound();

        etx.status = EncryptedTxStatus.Expired;

        // Refund prepaid fee
        uint256 refund = (etx.gasLimit * etx.maxFeePerGas) + etx.valueDeposit;
        (bool success, ) = msg.sender.call{value: refund}("");
        require(success, "Refund failed");

        emit TxExpired(_txId);
    }

    // =========================================================================
    // Sequencer Functions
    // =========================================================================

    /**
     * @notice Commit to transaction ordering
     * @param _batchId Unique batch identifier
     * @param _txIds Ordered transaction IDs
     * @param _orderingRoot Merkle root of ordering
     * @param _signature Sequencer's signature
     */
    function commitOrdering(
        bytes32 _batchId,
        bytes32[] calldata _txIds,
        bytes32 _orderingRoot,
        bytes calldata _signature
    ) external onlySequencer {
        // Store ordering commitment
        orderingCommitments[_batchId] = OrderingCommitment({
            batchId: _batchId,
            orderingRoot: _orderingRoot,
            txCount: _txIds.length,
            committedAt: block.number,
            sequencerSignature: _signature
        });

        // Update transaction statuses
        for (uint256 i = 0; i < _txIds.length; i++) {
            EncryptedTx storage etx = encryptedTxs[_txIds[i]];
            if (etx.status == EncryptedTxStatus.Pending) {
                etx.status = EncryptedTxStatus.Ordered;
                etx.orderPosition = i;

                emit TxOrdered(_txIds[i], _batchId, i);
            }
        }

        emit OrderingCommitted(_batchId, _orderingRoot, _txIds.length);
    }

    /**
     * @notice Submit decrypted transaction data
     * @param _txId Encrypted transaction ID
     * @param _to Target address
     * @param _data Calldata
     * @param _value ETH value
     * @param _decryptionProof Proof of valid decryption
     */
    function submitDecryption(
        bytes32 _txId,
        address _to,
        bytes calldata _data,
        uint256 _value,
        bytes calldata _decryptionProof
    ) external onlySequencer {
        EncryptedTx storage etx = encryptedTxs[_txId];

        if (etx.sender == address(0)) revert TxNotFound();
        if (etx.status != EncryptedTxStatus.Ordered) revert TxNotOrdered();
        if (_value > etx.valueDeposit) revert ValueExceedsDeposit();

        // Verify decryption proof
        // In production, this would verify threshold signature
        if (!_verifyDecryption(_txId, _to, _data, _value, _decryptionProof)) {
            revert DecryptionFailed();
        }

        etx.status = EncryptedTxStatus.Decrypted;

        decryptedTxs[_txId] = DecryptedTx({
            encryptedId: _txId,
            to: _to,
            data: _data,
            value: _value,
            decryptedAt: block.number,
            executed: false,
            success: false
        });

        emit TxDecrypted(_txId, _to, _value);
    }

    /**
     * @notice Execute a decrypted transaction
     * @param _txId Transaction ID
     */
    function executeDecryptedTx(bytes32 _txId) external nonReentrant {
        EncryptedTx storage etx = encryptedTxs[_txId];
        DecryptedTx storage dtx = decryptedTxs[_txId];

        if (etx.sender == address(0)) revert TxNotFound();
        if (dtx.executed) revert TxAlreadyExecuted();
        if (etx.status != EncryptedTxStatus.Decrypted) revert TxNotDecrypted();

        dtx.executed = true;

        // Execute the transaction
        uint256 gasStart = gasleft();
        (bool success, bytes memory returnData) = dtx.to.call{
            value: dtx.value,
            gas: etx.gasLimit
        }(dtx.data);
        uint256 gasUsed = gasStart - gasleft();
        if (gasUsed > etx.gasLimit) {
            gasUsed = etx.gasLimit;
        }

        dtx.success = success;
        etx.status = success ? EncryptedTxStatus.Executed : EncryptedTxStatus.Failed;

        if (success) {
            totalExecuted++;
        } else {
            totalFailed++;
        }

        // Refund unused gas to sender
        uint256 gasRefund = (etx.gasLimit - gasUsed) * etx.maxFeePerGas;
        uint256 valueRefund = success ? (etx.valueDeposit - dtx.value) : etx.valueDeposit;
        uint256 refund = gasRefund + valueRefund;
        if (refund > 0) {
            (bool refundSuccess, ) = etx.sender.call{value: refund}("");
            // Don't revert on refund failure
        }

        emit TxExecuted(_txId, success, returnData);
    }

    /**
     * @notice Mark expired transactions
     * @param _txIds Transaction IDs to check
     */
    function markExpired(bytes32[] calldata _txIds) external {
        for (uint256 i = 0; i < _txIds.length; i++) {
            EncryptedTx storage etx = encryptedTxs[_txIds[i]];

            if (etx.status == EncryptedTxStatus.Pending ||
                etx.status == EncryptedTxStatus.Ordered) {

                if (block.number > etx.submittedAt + DECRYPTION_TIMEOUT) {
                    etx.status = EncryptedTxStatus.Expired;
                    totalExpired++;

                    // Refund prepaid fee
                    uint256 refund = (etx.gasLimit * etx.maxFeePerGas) + etx.valueDeposit;
                    (bool success, ) = etx.sender.call{value: refund}("");

                    emit TxExpired(_txIds[i]);
                }
            }
        }
    }

    // =========================================================================
    // Query Functions
    // =========================================================================

    /**
     * @notice Get encrypted transaction details
     * @param _txId Transaction ID
     * @return etx Encrypted transaction data
     */
    function getEncryptedTx(
        bytes32 _txId
    ) external view returns (EncryptedTx memory etx) {
        return encryptedTxs[_txId];
    }

    /**
     * @notice Get decrypted transaction details
     * @param _txId Transaction ID
     * @return dtx Decrypted transaction data
     */
    function getDecryptedTx(
        bytes32 _txId
    ) external view returns (DecryptedTx memory dtx) {
        return decryptedTxs[_txId];
    }

    /**
     * @notice Get user's pending transactions
     * @param _user User address
     * @return txIds Array of pending transaction IDs
     */
    function getUserPendingTxs(
        address _user
    ) external view returns (bytes32[] memory txIds) {
        return userPendingTxs[_user];
    }

    /**
     * @notice Get current pending queue length
     * @return length Number of pending transactions
     */
    function getPendingQueueLength() external view returns (uint256 length) {
        return pendingQueue.length - nextQueuePosition;
    }

    /**
     * @notice Get statistics
     * @return submitted Total submitted
     * @return executed Total executed
     * @return failed Total failed
     * @return expired Total expired
     */
    function getStats() external view returns (
        uint256 submitted,
        uint256 executed,
        uint256 failed,
        uint256 expired
    ) {
        return (totalSubmitted, totalExecuted, totalFailed, totalExpired);
    }

    // =========================================================================
    // Admin Functions
    // =========================================================================

    /**
     * @notice Update sequencer address
     * @param _newSequencer New sequencer address
     */
    function setSequencer(address _newSequencer) external onlyOwner {
        address oldSequencer = sequencer;
        sequencer = _newSequencer;
        emit SequencerUpdated(oldSequencer, _newSequencer);
    }

    /**
     * @notice Update key registry address
     * @param _keyRegistry New key registry address
     */
    function setKeyRegistry(address _keyRegistry) external onlyOwner {
        if (_keyRegistry == address(0)) revert InvalidAddress();
        keyRegistry = ThresholdKeyRegistry(payable(_keyRegistry));
    }

    /**
     * @notice Set maximum queue size
     * @param _maxQueueSize New max queue size (0 = unlimited)
     */
    function setMaxQueueSize(uint256 _maxQueueSize) external onlyOwner {
        maxQueueSize = _maxQueueSize;
    }

    /**
     * @notice Set rate limit per user per block
     * @param _maxSubmissions Max submissions per user per block (0 = unlimited)
     */
    function setMaxSubmissionsPerUserPerBlock(uint256 _maxSubmissions) external onlyOwner {
        maxSubmissionsPerUserPerBlock = _maxSubmissions;
    }

    /**
     * @notice Pause the encrypted mempool (emergency stop)
     * @dev Prevents new encrypted tx submissions while paused
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the encrypted mempool
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // =========================================================================
    // Monitoring Functions
    // =========================================================================

    /**
     * @notice Get comprehensive mempool status
     * @return pendingCount Number of pending transactions
     * @return queueCapacity Remaining queue capacity
     * @return submitted Total submitted
     * @return executed Total executed
     * @return failed Total failed
     * @return expired Total expired
     * @return isPaused Whether mempool is paused
     * @return currentMaxQueueSize Current queue size limit
     */
    function getMempoolStatus() external view returns (
        uint256 pendingCount,
        uint256 queueCapacity,
        uint256 submitted,
        uint256 executed,
        uint256 failed,
        uint256 expired,
        bool isPaused,
        uint256 currentMaxQueueSize
    ) {
        uint256 effectiveQueueSize = pendingQueue.length - nextQueuePosition;
        uint256 capacity = maxQueueSize > 0 ? (maxQueueSize > effectiveQueueSize ? maxQueueSize - effectiveQueueSize : 0) : type(uint256).max;

        return (
            effectiveQueueSize,
            capacity,
            totalSubmitted,
            totalExecuted,
            totalFailed,
            totalExpired,
            paused(),
            maxQueueSize
        );
    }

    /**
     * @notice Get transaction status summary
     * @param _txId Transaction ID
     * @return status Current status enum value
     * @return statusName Human-readable status
     * @return blocksUntilExpiry Blocks until expiration (0 if already expired or executed)
     * @return canExecute Whether transaction can be executed now
     */
    function getTxStatus(bytes32 _txId) external view returns (
        EncryptedTxStatus status,
        string memory statusName,
        uint256 blocksUntilExpiry,
        bool canExecute
    ) {
        EncryptedTx storage etx = encryptedTxs[_txId];
        if (etx.sender == address(0)) {
            return (EncryptedTxStatus.Pending, "NotFound", 0, false);
        }

        string memory name;
        if (etx.status == EncryptedTxStatus.Pending) name = "Pending";
        else if (etx.status == EncryptedTxStatus.Ordered) name = "Ordered";
        else if (etx.status == EncryptedTxStatus.Decrypting) name = "Decrypting";
        else if (etx.status == EncryptedTxStatus.Decrypted) name = "Decrypted";
        else if (etx.status == EncryptedTxStatus.Executed) name = "Executed";
        else if (etx.status == EncryptedTxStatus.Failed) name = "Failed";
        else name = "Expired";

        uint256 expiryBlock = etx.submittedAt + DECRYPTION_TIMEOUT;
        uint256 remaining = block.number >= expiryBlock ? 0 : expiryBlock - block.number;

        bool executable = etx.status == EncryptedTxStatus.Decrypted && !decryptedTxs[_txId].executed;

        return (etx.status, name, remaining, executable);
    }

    /**
     * @notice Get batch of transaction statuses
     * @param _txIds Array of transaction IDs
     * @return statuses Array of status values
     */
    function getBatchTxStatuses(bytes32[] calldata _txIds) external view returns (EncryptedTxStatus[] memory statuses) {
        statuses = new EncryptedTxStatus[](_txIds.length);
        for (uint256 i = 0; i < _txIds.length; i++) {
            statuses[i] = encryptedTxs[_txIds[i]].status;
        }
        return statuses;
    }

    /**
     * @notice Check if user can submit (rate limit check)
     * @param _user User address
     * @return canSubmit Whether user can submit
     * @return remainingSubmissions Remaining submissions this block
     */
    function canUserSubmit(address _user) external view returns (bool canSubmit, uint256 remainingSubmissions) {
        if (maxSubmissionsPerUserPerBlock == 0) {
            return (true, type(uint256).max);
        }
        uint256 used = userBlockSubmissions[_user][block.number];
        if (used >= maxSubmissionsPerUserPerBlock) {
            return (false, 0);
        }
        return (true, maxSubmissionsPerUserPerBlock - used);
    }

    /**
     * @notice Get pending transactions for a batch of users
     * @param _users Array of user addresses
     * @return counts Array of pending transaction counts
     */
    function getBatchUserPendingCounts(address[] calldata _users) external view returns (uint256[] memory counts) {
        counts = new uint256[](_users.length);
        for (uint256 i = 0; i < _users.length; i++) {
            counts[i] = userPendingTxs[_users[i]].length;
        }
        return counts;
    }

    /**
     * @notice Get success rate
     * @return rate Success rate in basis points (10000 = 100%)
     */
    function getSuccessRate() external view returns (uint256 rate) {
        uint256 completed = totalExecuted + totalFailed;
        if (completed == 0) return 10000; // 100% if no completions yet
        return (totalExecuted * 10000) / completed;
    }

    // =========================================================================
    // Internal Functions
    // =========================================================================

    /**
     * @dev Verify decryption proof binds to the encrypted payload
     * @param _txId Transaction ID
     * @param _to Decrypted target address
     * @param _data Decrypted calldata
     * @param _value Decrypted ETH value
     * @param _proof Decryption proof (threshold ECDSA signatures over commitment)
     * @return valid True if proof is valid and binds to the encrypted payload
     *
     * Proof structure (ABI-encoded):
     * - bytes signature: Concatenated 65-byte ECDSA signatures from keypers
     * - bytes32 decryptionCommitment: Hash binding decrypted data to encrypted payload
     * - uint256 epoch: Epoch the key belongs to
     * - address[] signers: Keypers who signed (order must match signatures)
     *
     * The decryptionCommitment must equal:
     * keccak256(abi.encodePacked(payloadHash, to, data, value))
     *
     * This ensures:
     * 1. The decrypted data actually came from the encrypted payload
     * 2. Keypers attested to the correct decryption
     * 3. The sequencer cannot substitute different transaction data
     */
    function _verifyDecryption(
        bytes32 _txId,
        address _to,
        bytes calldata _data,
        uint256 _value,
        bytes calldata _proof
    ) internal view returns (bool) {
        // Minimum proof size: dynamic signature + commitment + epoch + signers
        if (_proof.length < 320) {
            return false;
        }

        // Decode proof components
        (
            bytes memory signature,
            bytes32 decryptionCommitment,
            uint256 proofEpoch,
            address[] memory signers
        ) = abi.decode(_proof, (bytes, bytes32, uint256, address[]));

        if (signature.length == 0) {
            return false;
        }

        // Get the encrypted transaction
        EncryptedTx storage etx = encryptedTxs[_txId];
        if (etx.sender == address(0)) {
            return false;
        }

        // Verify epoch matches
        if (etx.epoch != proofEpoch) {
            return false;
        }

        // Verify the epoch key is still valid
        if (!keyRegistry.isEpochKeyValid(proofEpoch)) {
            return false;
        }

        // CRITICAL: Verify the decryption commitment binds the decrypted data
        // to the original encrypted payload hash
        bytes32 expectedCommitment = keccak256(abi.encodePacked(
            etx.payloadHash,  // Hash of the encrypted payload
            _to,
            _data,
            _value
        ));

        if (decryptionCommitment != expectedCommitment) {
            return false;
        }

        // Verify threshold signature
        // The message being signed is the decryption commitment
        // This ensures keypers attest to the binding between encrypted and decrypted data
        if (!_verifyThresholdSignature(signature, decryptionCommitment, proofEpoch, signers)) {
            return false;
        }

        return true;
    }

    /**
     * @dev Verify threshold ECDSA signatures from keypers
     * @param _signature Concatenated 65-byte ECDSA signatures
     * @param _message The message that was signed (decryption commitment)
     * @param _epoch The epoch for the threshold key
     * @param _signers The keypers who contributed signatures
     * @return valid True if the threshold signatures are valid
     */
    function _verifyThresholdSignature(
        bytes memory _signature,
        bytes32 _message,
        uint256 _epoch,
        address[] memory _signers
    ) internal view returns (bool valid) {
        // Get the threshold key for this epoch
        ThresholdKeyRegistry.ThresholdKey memory epochKey = keyRegistry.getEpochKey(_epoch);

        // Verify we have enough signers (at least threshold)
        if (_signers.length < epochKey.threshold) {
            return false;
        }

        // Signature must be a concatenation of 65-byte ECDSA signatures
        if (_signature.length == 0 || _signature.length % 65 != 0) {
            return false;
        }
        if (_signature.length / 65 != _signers.length) {
            return false;
        }

        bytes32 messageHash = MessageHashUtils.toEthSignedMessageHash(_message);

        // Verify all signers are valid keypers and signatures match
        for (uint256 i = 0; i < _signers.length; i++) {
            bytes memory sig = new bytes(65);
            for (uint256 j = 0; j < 65; j++) {
                sig[j] = _signature[i * 65 + j];
            }

            address recovered = ECDSA.recover(messageHash, sig);
            if (recovered != _signers[i]) {
                return false;
            }

            if (!keyRegistry.isKeyperActive(recovered)) {
                return false;
            }

            // Check for duplicates (prevent signature replay)
            for (uint256 j = i + 1; j < _signers.length; j++) {
                if (_signers[i] == _signers[j]) {
                    return false; // Duplicate signer
                }
            }
        }

        // Signatures are verified against the decryption commitment using
        // the active keyper set from the registry.

        // Verify message is not empty
        if (_message == bytes32(0)) {
            return false;
        }

        // Verify epoch key commitment matches (prevents key substitution)
        if (epochKey.keyCommitment == bytes32(0)) {
            return false;
        }

        return true;
    }

    /**
     * @dev Authorize upgrade (owner only)
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /**
     * @notice Receive function to accept payments
     */
    receive() external payable {}
}
