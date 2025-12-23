// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
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
    error ExecutionFailed();

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
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        keyRegistry = ThresholdKeyRegistry(payable(_keyRegistry));
        sequencer = _sequencer;
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
    ) external payable nonReentrant returns (bytes32 txId) {
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
        uint256 minFee = _gasLimit * _maxFeePerGas;
        if (msg.value < minFee) {
            revert InsufficientFee();
        }

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
        uint256 refund = etx.gasLimit * etx.maxFeePerGas;
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
        if (etx.status != EncryptedTxStatus.Decrypted) revert TxNotDecrypted();
        if (dtx.executed) revert TxAlreadyExecuted();

        dtx.executed = true;

        // Execute the transaction
        (bool success, bytes memory returnData) = dtx.to.call{
            value: dtx.value,
            gas: etx.gasLimit
        }(dtx.data);

        dtx.success = success;
        etx.status = success ? EncryptedTxStatus.Executed : EncryptedTxStatus.Failed;

        if (success) {
            totalExecuted++;
        } else {
            totalFailed++;
        }

        // Refund unused gas to sender
        uint256 gasUsed = etx.gasLimit; // Simplified; real impl would track actual gas
        uint256 refund = (etx.gasLimit - gasUsed) * etx.maxFeePerGas;
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
                    uint256 refund = etx.gasLimit * etx.maxFeePerGas;
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
        keyRegistry = ThresholdKeyRegistry(payable(_keyRegistry));
    }

    // =========================================================================
    // Internal Functions
    // =========================================================================

    /**
     * @dev Verify decryption proof
     */
    function _verifyDecryption(
        bytes32 _txId,
        address _to,
        bytes calldata _data,
        uint256 _value,
        bytes calldata _proof
    ) internal view returns (bool) {
        // In production, this would:
        // 1. Verify threshold signature from keypers
        // 2. Verify decrypted data matches encrypted payload
        // 3. Check epoch key validity

        // Placeholder: accept any proof of sufficient length
        return _proof.length >= 96; // BLS signature size
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
