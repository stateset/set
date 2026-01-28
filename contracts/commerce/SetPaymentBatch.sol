// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SetPaymentBatch
 * @notice x402 Payment Batching and Settlement for Set Chain L2
 * @dev Enables gas-efficient batch settlement of x402 payment intents
 *
 * Key features:
 * - Batch settlement of multiple payments in single transaction
 * - Merkle proof verification for payment inclusion
 * - Multi-asset support (USDC, ssUSD, USDT)
 * - Authorized sequencer submission
 * - Merchant auto-withdrawal
 *
 * ## x402 Protocol Flow
 *
 * 1. AI Agent creates signed PaymentIntent off-chain
 * 2. Intent is sequenced by stateset-sequencer
 * 3. Multiple intents are batched with Merkle root
 * 4. This contract settles the batch on-chain
 * 5. Tokens are transferred from payers to payees
 *
 * ## Security Model
 *
 * - Only authorized sequencers can submit batches
 * - Payment signatures are verified off-chain by sequencer
 * - Merkle proofs allow independent verification
 * - Reentrancy protection on all transfers
 */
contract SetPaymentBatch is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    // =========================================================================
    // Types
    // =========================================================================

    /// @notice Payment intent for batch settlement
    struct PaymentIntent {
        bytes32 intentId;           // Unique intent ID (UUID as bytes32)
        address payer;              // Sender wallet address
        address payee;              // Recipient wallet address
        uint256 amount;             // Payment amount in smallest unit
        address token;              // Token contract address (0x0 for native)
        uint64 nonce;               // Replay protection nonce
        uint64 validUntil;          // Expiry timestamp
        bytes32 signingHash;        // Hash that was signed
    }

    /// @notice Batch commitment for settlement
    struct BatchSettlement {
        bytes32 batchId;            // Unique batch ID
        bytes32 merkleRoot;         // Merkle root of payment intents
        bytes32 tenantStoreKey;     // Tenant/store identifier
        uint64 sequenceStart;       // First sequence number
        uint64 sequenceEnd;         // Last sequence number
        uint32 paymentCount;        // Number of payments
        uint256 totalAmount;        // Total amount across all payments
        address token;              // Primary token for this batch
        uint64 settledAt;           // Settlement timestamp
        address submitter;          // Sequencer that submitted
        bool executed;              // Whether batch is executed
    }

    /// @notice Asset configuration
    struct AssetConfig {
        bool enabled;               // Whether asset is accepted
        uint256 minAmount;          // Minimum payment amount
        uint256 maxAmount;          // Maximum payment amount
        uint256 dailyLimit;         // Daily volume limit
        uint256 dailyVolume;        // Current daily volume
        uint256 lastDayReset;       // Last daily reset timestamp
    }

    // =========================================================================
    // State Variables
    // =========================================================================

    /// @notice Authorized sequencers
    mapping(address => bool) public authorizedSequencers;

    /// @notice Number of authorized sequencers
    uint256 public sequencerCount;

    /// @notice Batch settlements by batch ID
    mapping(bytes32 => BatchSettlement) public batches;

    /// @notice Asset configurations by token address
    mapping(address => AssetConfig) public assetConfigs;

    /// @notice Used nonces per payer (payer => nonce => used)
    mapping(address => mapping(uint64 => bool)) public usedNonces;

    /// @notice Settled intents (intentId => settled)
    mapping(bytes32 => bool) public settledIntents;

    /// @notice Total payments settled
    uint256 public totalPaymentsSettled;

    /// @notice Total volume settled (in USD equivalent, 6 decimals)
    uint256 public totalVolumeSettled;

    /// @notice Total batches settled
    uint256 public totalBatchesSettled;

    /// @notice USDC token address
    address public usdcToken;

    /// @notice ssUSD token address
    address public ssUsdToken;

    /// @notice Registry contract for Merkle verification
    address public registry;

    // =========================================================================
    // Events
    // =========================================================================

    event SequencerAuthorized(address indexed sequencer, bool authorized);

    event AssetConfigured(
        address indexed token,
        bool enabled,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 dailyLimit
    );

    event BatchSubmitted(
        bytes32 indexed batchId,
        bytes32 merkleRoot,
        uint32 paymentCount,
        uint256 totalAmount,
        address indexed token
    );

    event BatchSettled(
        bytes32 indexed batchId,
        uint32 paymentsSettled,
        uint256 totalAmount,
        uint256 gasUsed
    );

    event PaymentSettled(
        bytes32 indexed batchId,
        bytes32 indexed intentId,
        address indexed payer,
        address payee,
        uint256 amount,
        address token
    );

    event PaymentFailed(
        bytes32 indexed batchId,
        bytes32 indexed intentId,
        address indexed payer,
        string reason
    );

    // =========================================================================
    // Errors
    // =========================================================================

    error NotAuthorizedSequencer();
    error BatchAlreadySettled();
    error BatchNotFound();
    error InvalidMerkleRoot();
    error InvalidPaymentCount();
    error AssetNotEnabled();
    error AmountBelowMinimum();
    error AmountAboveMaximum();
    error DailyLimitExceeded();
    error PaymentExpired();
    error NonceAlreadyUsed();
    error IntentAlreadySettled();
    error InvalidProof();
    error TransferFailed();
    error InvalidAddress();
    error ArrayLengthMismatch();
    error EmptyBatch();

    // =========================================================================
    // Modifiers
    // =========================================================================

    modifier onlySequencer() {
        if (!authorizedSequencers[msg.sender]) revert NotAuthorizedSequencer();
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
     * @notice Initialize the contract
     * @param _owner Owner address
     * @param _sequencer Initial authorized sequencer
     * @param _usdcToken USDC token address
     * @param _ssUsdToken ssUSD token address
     * @param _registry SetRegistry address for Merkle verification
     */
    function initialize(
        address _owner,
        address _sequencer,
        address _usdcToken,
        address _ssUsdToken,
        address _registry
    ) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        if (_sequencer != address(0)) {
            authorizedSequencers[_sequencer] = true;
            sequencerCount = 1;
            emit SequencerAuthorized(_sequencer, true);
        }

        usdcToken = _usdcToken;
        ssUsdToken = _ssUsdToken;
        registry = _registry;

        // Configure default assets
        if (_usdcToken != address(0)) {
            assetConfigs[_usdcToken] = AssetConfig({
                enabled: true,
                minAmount: 1e4,           // 0.01 USDC
                maxAmount: 1e12,          // 1M USDC
                dailyLimit: 1e14,         // 100M USDC/day
                dailyVolume: 0,
                lastDayReset: block.timestamp
            });
            emit AssetConfigured(_usdcToken, true, 1e4, 1e12, 1e14);
        }

        if (_ssUsdToken != address(0)) {
            assetConfigs[_ssUsdToken] = AssetConfig({
                enabled: true,
                minAmount: 1e4,           // 0.01 ssUSD
                maxAmount: 1e12,          // 1M ssUSD
                dailyLimit: 1e14,         // 100M ssUSD/day
                dailyVolume: 0,
                lastDayReset: block.timestamp
            });
            emit AssetConfigured(_ssUsdToken, true, 1e4, 1e12, 1e14);
        }
    }

    // =========================================================================
    // Admin Functions
    // =========================================================================

    /**
     * @notice Authorize or revoke a sequencer
     * @param _sequencer Sequencer address
     * @param _authorized Whether to authorize
     */
    function setSequencerAuthorization(
        address _sequencer,
        bool _authorized
    ) external onlyOwner {
        if (_sequencer == address(0)) revert InvalidAddress();

        bool wasAuthorized = authorizedSequencers[_sequencer];
        authorizedSequencers[_sequencer] = _authorized;

        if (_authorized && !wasAuthorized) {
            unchecked { ++sequencerCount; }
        } else if (!_authorized && wasAuthorized) {
            unchecked { --sequencerCount; }
        }

        emit SequencerAuthorized(_sequencer, _authorized);
    }

    /**
     * @notice Configure an asset for payments
     * @param _token Token address
     * @param _enabled Whether asset is enabled
     * @param _minAmount Minimum payment amount
     * @param _maxAmount Maximum payment amount
     * @param _dailyLimit Daily volume limit
     */
    function configureAsset(
        address _token,
        bool _enabled,
        uint256 _minAmount,
        uint256 _maxAmount,
        uint256 _dailyLimit
    ) external onlyOwner {
        assetConfigs[_token] = AssetConfig({
            enabled: _enabled,
            minAmount: _minAmount,
            maxAmount: _maxAmount,
            dailyLimit: _dailyLimit,
            dailyVolume: assetConfigs[_token].dailyVolume,
            lastDayReset: assetConfigs[_token].lastDayReset
        });

        emit AssetConfigured(_token, _enabled, _minAmount, _maxAmount, _dailyLimit);
    }

    /**
     * @notice Update the registry address
     * @param _registry New registry address
     */
    function setRegistry(address _registry) external onlyOwner {
        registry = _registry;
    }

    /**
     * @notice Pause the contract
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
    // Settlement Functions
    // =========================================================================

    /**
     * @notice Submit and settle a batch of payments
     * @param _batchId Unique batch ID
     * @param _merkleRoot Merkle root of payment intents
     * @param _tenantStoreKey Tenant/store identifier
     * @param _sequenceStart First sequence number
     * @param _sequenceEnd Last sequence number
     * @param _payments Array of payment intents to settle
     */
    function settleBatch(
        bytes32 _batchId,
        bytes32 _merkleRoot,
        bytes32 _tenantStoreKey,
        uint64 _sequenceStart,
        uint64 _sequenceEnd,
        PaymentIntent[] calldata _payments
    ) external onlySequencer nonReentrant whenNotPaused {
        if (_payments.length == 0) revert EmptyBatch();
        if (batches[_batchId].executed) revert BatchAlreadySettled();
        if (_merkleRoot == bytes32(0)) revert InvalidMerkleRoot();

        uint256 gasStart = gasleft();

        // Determine primary token from first payment
        address primaryToken = _payments[0].token;
        uint256 totalAmount = 0;
        uint32 successCount = 0;

        // Process each payment
        for (uint256 i = 0; i < _payments.length; i++) {
            PaymentIntent calldata payment = _payments[i];

            // Validate and settle individual payment
            (bool success, string memory reason) = _settlePayment(_batchId, payment);

            if (success) {
                totalAmount += payment.amount;
                unchecked { ++successCount; }

                emit PaymentSettled(
                    _batchId,
                    payment.intentId,
                    payment.payer,
                    payment.payee,
                    payment.amount,
                    payment.token
                );
            } else {
                emit PaymentFailed(_batchId, payment.intentId, payment.payer, reason);
            }
        }

        // Record batch settlement
        batches[_batchId] = BatchSettlement({
            batchId: _batchId,
            merkleRoot: _merkleRoot,
            tenantStoreKey: _tenantStoreKey,
            sequenceStart: _sequenceStart,
            sequenceEnd: _sequenceEnd,
            paymentCount: successCount,
            totalAmount: totalAmount,
            token: primaryToken,
            settledAt: uint64(block.timestamp),
            submitter: msg.sender,
            executed: true
        });

        // Update statistics
        totalPaymentsSettled += successCount;
        totalVolumeSettled += totalAmount;
        unchecked { ++totalBatchesSettled; }

        uint256 gasUsed = gasStart - gasleft();

        emit BatchSubmitted(_batchId, _merkleRoot, successCount, totalAmount, primaryToken);
        emit BatchSettled(_batchId, successCount, totalAmount, gasUsed);
    }

    /**
     * @notice Settle a single payment (internal)
     * @param _batchId Batch ID for logging
     * @param _payment Payment intent to settle
     * @return success Whether settlement succeeded
     * @return reason Failure reason if failed
     */
    function _settlePayment(
        bytes32 _batchId,
        PaymentIntent calldata _payment
    ) internal returns (bool success, string memory reason) {
        // Check if already settled
        if (settledIntents[_payment.intentId]) {
            return (false, "Already settled");
        }

        // Check expiry
        if (block.timestamp > _payment.validUntil) {
            return (false, "Payment expired");
        }

        // Check nonce
        if (usedNonces[_payment.payer][_payment.nonce]) {
            return (false, "Nonce already used");
        }

        // Check asset config
        AssetConfig storage config = assetConfigs[_payment.token];
        if (!config.enabled) {
            return (false, "Asset not enabled");
        }

        if (_payment.amount < config.minAmount) {
            return (false, "Amount below minimum");
        }

        if (_payment.amount > config.maxAmount) {
            return (false, "Amount above maximum");
        }

        // Check daily limit (reset if new day)
        if (block.timestamp >= config.lastDayReset + 1 days) {
            config.dailyVolume = 0;
            config.lastDayReset = block.timestamp;
        }

        if (config.dailyVolume + _payment.amount > config.dailyLimit) {
            return (false, "Daily limit exceeded");
        }

        // Execute transfer
        IERC20 token = IERC20(_payment.token);

        // Check payer balance and allowance
        if (token.balanceOf(_payment.payer) < _payment.amount) {
            return (false, "Insufficient balance");
        }

        if (token.allowance(_payment.payer, address(this)) < _payment.amount) {
            return (false, "Insufficient allowance");
        }

        // Transfer tokens
        try token.transferFrom(_payment.payer, _payment.payee, _payment.amount) {
            // Mark as settled
            settledIntents[_payment.intentId] = true;
            usedNonces[_payment.payer][_payment.nonce] = true;

            // Update daily volume
            config.dailyVolume += _payment.amount;

            return (true, "");
        } catch {
            return (false, "Transfer failed");
        }
    }

    // =========================================================================
    // View Functions
    // =========================================================================

    /**
     * @notice Get batch settlement details
     * @param _batchId Batch ID to query
     */
    function getBatch(bytes32 _batchId) external view returns (BatchSettlement memory) {
        return batches[_batchId];
    }

    /**
     * @notice Check if an intent has been settled
     * @param _intentId Intent ID to check
     */
    function isIntentSettled(bytes32 _intentId) external view returns (bool) {
        return settledIntents[_intentId];
    }

    /**
     * @notice Check if a nonce has been used for a payer
     * @param _payer Payer address
     * @param _nonce Nonce to check
     */
    function isNonceUsed(address _payer, uint64 _nonce) external view returns (bool) {
        return usedNonces[_payer][_nonce];
    }

    /**
     * @notice Get asset configuration
     * @param _token Token address
     */
    function getAssetConfig(address _token) external view returns (AssetConfig memory) {
        return assetConfigs[_token];
    }

    /**
     * @notice Get settlement statistics
     */
    function getStats() external view returns (
        uint256 _totalPayments,
        uint256 _totalVolume,
        uint256 _totalBatches,
        uint256 _sequencers
    ) {
        return (totalPaymentsSettled, totalVolumeSettled, totalBatchesSettled, sequencerCount);
    }

    // =========================================================================
    // Merkle Proof Verification
    // =========================================================================

    /**
     * @notice Verify a payment was included in a batch via Merkle proof
     * @param _batchId Batch ID
     * @param _intentId Intent ID to verify
     * @param _proof Merkle proof (array of sibling hashes)
     * @param _index Leaf index in the tree
     */
    function verifyPaymentInclusion(
        bytes32 _batchId,
        bytes32 _intentId,
        bytes32[] calldata _proof,
        uint256 _index
    ) external view returns (bool) {
        BatchSettlement storage batch = batches[_batchId];
        if (!batch.executed) return false;

        bytes32 computedHash = _intentId;

        for (uint256 i = 0; i < _proof.length; i++) {
            bytes32 proofElement = _proof[i];

            if (_index % 2 == 0) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }

            _index = _index / 2;
        }

        return computedHash == batch.merkleRoot;
    }

    // =========================================================================
    // Upgrade Authorization
    // =========================================================================

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
