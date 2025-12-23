// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title ThresholdKeyRegistry
 * @notice Manages threshold encryption keys for MEV-protected transactions
 * @dev Part of Set Chain's MEV protection strategy (Phase 2)
 *
 * This contract manages the lifecycle of threshold encryption keys:
 * 1. Key committee registration
 * 2. Distributed key generation (DKG) coordination
 * 3. Key rotation and revocation
 * 4. Epoch management for key validity
 *
 * The actual cryptographic operations happen off-chain via the keyper network.
 * This contract provides on-chain coordination and key availability proofs.
 */
contract ThresholdKeyRegistry is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // =========================================================================
    // Constants
    // =========================================================================

    /// @notice Minimum number of keypers required
    uint256 public constant MIN_KEYPERS = 3;

    /// @notice Maximum number of keypers
    uint256 public constant MAX_KEYPERS = 21;

    /// @notice Minimum threshold (t in t-of-n)
    uint256 public constant MIN_THRESHOLD = 2;

    /// @notice Epoch duration in blocks
    uint256 public constant EPOCH_DURATION = 50400; // ~1 week at 12s blocks

    // =========================================================================
    // Types
    // =========================================================================

    /// @notice Keyper node that participates in threshold encryption
    struct Keyper {
        address addr;               // Keyper's address
        bytes publicKey;            // BLS public key (48 bytes)
        string endpoint;            // RPC endpoint for key shares
        uint256 registeredAt;       // Block when registered
        bool active;                // Whether currently active
        uint256 slashCount;         // Number of times slashed
    }

    /// @notice Threshold key for an epoch
    struct ThresholdKey {
        uint256 epoch;              // Epoch number
        bytes aggregatedPubKey;     // Aggregated BLS public key (48 bytes)
        bytes32 keyCommitment;      // Commitment to key shares
        uint256 threshold;          // t in t-of-n
        uint256 keyperCount;        // n (number of keypers)
        uint256 activatedAt;        // Block when activated
        uint256 expiresAt;          // Block when expires
        bool revoked;               // Whether revoked early
    }

    /// @notice Key generation ceremony state
    struct DKGState {
        uint256 epoch;              // Epoch being generated
        uint256 phase;              // 0=inactive, 1=registration, 2=dealing, 3=finalized
        uint256 phaseDeadline;      // Block deadline for current phase
        address[] participants;     // Registered participants
        mapping(address => bytes32) dealings; // Encrypted dealings
        uint256 dealingsReceived;   // Count of dealings
    }

    // =========================================================================
    // State Variables
    // =========================================================================

    /// @notice Registered keypers
    mapping(address => Keyper) public keypers;

    /// @notice List of keyper addresses
    address[] public keyperList;

    /// @notice Active keyper count
    uint256 public activeKeyperCount;

    /// @notice Threshold keys by epoch
    mapping(uint256 => ThresholdKey) public epochKeys;

    /// @notice Current epoch
    uint256 public currentEpoch;

    /// @notice Current DKG state
    DKGState public dkgState;

    /// @notice Required threshold (t-of-n)
    uint256 public threshold;

    /// @notice Minimum stake to be a keyper
    uint256 public minStake;

    /// @notice Keyper stakes
    mapping(address => uint256) public stakes;

    // =========================================================================
    // Events
    // =========================================================================

    event KeyperRegistered(
        address indexed keyper,
        bytes publicKey,
        string endpoint
    );

    event KeyperDeactivated(address indexed keyper, string reason);

    event KeyperSlashed(address indexed keyper, uint256 amount, string reason);

    event DKGStarted(uint256 indexed epoch, uint256 deadline);

    event DKGDealingSubmitted(uint256 indexed epoch, address indexed keyper);

    event DKGFinalized(
        uint256 indexed epoch,
        bytes aggregatedPubKey,
        uint256 threshold,
        uint256 keyperCount
    );

    event EpochKeyActivated(uint256 indexed epoch, bytes aggregatedPubKey);

    event EpochKeyRevoked(uint256 indexed epoch, string reason);

    event ThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    // =========================================================================
    // Errors
    // =========================================================================

    error KeyperAlreadyRegistered();
    error KeyperNotRegistered();
    error InsufficientStake();
    error InvalidPublicKey();
    error InvalidThreshold();
    error TooManyKeypers();
    error NotEnoughKeypers();
    error DKGNotActive();
    error DKGAlreadyActive();
    error DKGPhaseIncorrect();
    error DKGDeadlinePassed();
    error DKGDeadlineNotPassed();
    error AlreadySubmittedDealing();
    error EpochNotActive();
    error EpochAlreadyExists();
    error KeyRevoked();

    // =========================================================================
    // Initialization
    // =========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the registry
     * @param _owner Owner address
     * @param _threshold Initial threshold (t in t-of-n)
     * @param _minStake Minimum stake for keypers
     */
    function initialize(
        address _owner,
        uint256 _threshold,
        uint256 _minStake
    ) public initializer {
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();

        if (_threshold < MIN_THRESHOLD) revert InvalidThreshold();

        threshold = _threshold;
        minStake = _minStake;
        currentEpoch = 1;
    }

    // =========================================================================
    // Keyper Management
    // =========================================================================

    /**
     * @notice Register as a keyper
     * @param _publicKey BLS public key (48 bytes)
     * @param _endpoint RPC endpoint for key shares
     */
    function registerKeyper(
        bytes calldata _publicKey,
        string calldata _endpoint
    ) external payable {
        if (keypers[msg.sender].addr != address(0)) {
            revert KeyperAlreadyRegistered();
        }
        if (msg.value < minStake) revert InsufficientStake();
        if (_publicKey.length != 48) revert InvalidPublicKey();
        if (keyperList.length >= MAX_KEYPERS) revert TooManyKeypers();

        keypers[msg.sender] = Keyper({
            addr: msg.sender,
            publicKey: _publicKey,
            endpoint: _endpoint,
            registeredAt: block.number,
            active: true,
            slashCount: 0
        });

        keyperList.push(msg.sender);
        stakes[msg.sender] = msg.value;
        activeKeyperCount++;

        emit KeyperRegistered(msg.sender, _publicKey, _endpoint);
    }

    /**
     * @notice Deactivate a keyper (self or admin)
     * @param _keyper Keyper address
     * @param _reason Reason for deactivation
     */
    function deactivateKeyper(
        address _keyper,
        string calldata _reason
    ) external {
        if (msg.sender != _keyper && msg.sender != owner()) {
            revert KeyperNotRegistered();
        }

        Keyper storage keyper = keypers[_keyper];
        if (keyper.addr == address(0)) revert KeyperNotRegistered();
        if (!keyper.active) revert KeyperNotRegistered();

        keyper.active = false;
        activeKeyperCount--;

        emit KeyperDeactivated(_keyper, _reason);
    }

    /**
     * @notice Slash a keyper for misbehavior
     * @param _keyper Keyper address
     * @param _amount Amount to slash
     * @param _reason Reason for slashing
     */
    function slashKeyper(
        address _keyper,
        uint256 _amount,
        string calldata _reason
    ) external onlyOwner {
        Keyper storage keyper = keypers[_keyper];
        if (keyper.addr == address(0)) revert KeyperNotRegistered();

        uint256 stake = stakes[_keyper];
        uint256 slashAmount = _amount > stake ? stake : _amount;

        stakes[_keyper] -= slashAmount;
        keyper.slashCount++;

        // Deactivate if stake falls below minimum
        if (stakes[_keyper] < minStake && keyper.active) {
            keyper.active = false;
            activeKeyperCount--;
        }

        emit KeyperSlashed(_keyper, slashAmount, _reason);
    }

    /**
     * @notice Withdraw stake (only for inactive keypers)
     */
    function withdrawStake() external {
        Keyper storage keyper = keypers[msg.sender];
        if (keyper.addr == address(0)) revert KeyperNotRegistered();
        if (keyper.active) revert KeyperNotRegistered(); // Must deactivate first

        uint256 amount = stakes[msg.sender];
        stakes[msg.sender] = 0;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
    }

    // =========================================================================
    // DKG Coordination
    // =========================================================================

    /**
     * @notice Start distributed key generation for next epoch
     */
    function startDKG() external onlyOwner {
        if (dkgState.phase != 0) revert DKGAlreadyActive();
        if (activeKeyperCount < threshold) revert NotEnoughKeypers();

        uint256 nextEpoch = currentEpoch + 1;

        dkgState.epoch = nextEpoch;
        dkgState.phase = 1; // Registration phase
        dkgState.phaseDeadline = block.number + 100; // ~20 minutes
        delete dkgState.participants;
        dkgState.dealingsReceived = 0;

        emit DKGStarted(nextEpoch, dkgState.phaseDeadline);
    }

    /**
     * @notice Register for DKG participation
     */
    function registerForDKG() external {
        if (dkgState.phase != 1) revert DKGPhaseIncorrect();
        if (block.number > dkgState.phaseDeadline) revert DKGDeadlinePassed();

        Keyper storage keyper = keypers[msg.sender];
        if (!keyper.active) revert KeyperNotRegistered();

        dkgState.participants.push(msg.sender);

        // Auto-advance to dealing phase if enough participants
        if (dkgState.participants.length >= threshold) {
            dkgState.phase = 2;
            dkgState.phaseDeadline = block.number + 200; // ~40 minutes
        }
    }

    /**
     * @notice Submit encrypted dealing for DKG
     * @param _dealingHash Hash of encrypted dealing (actual data sent off-chain)
     */
    function submitDealing(bytes32 _dealingHash) external {
        if (dkgState.phase != 2) revert DKGPhaseIncorrect();
        if (block.number > dkgState.phaseDeadline) revert DKGDeadlinePassed();
        if (dkgState.dealings[msg.sender] != bytes32(0)) {
            revert AlreadySubmittedDealing();
        }

        dkgState.dealings[msg.sender] = _dealingHash;
        dkgState.dealingsReceived++;

        emit DKGDealingSubmitted(dkgState.epoch, msg.sender);
    }

    /**
     * @notice Finalize DKG and activate new epoch key
     * @param _aggregatedPubKey Aggregated threshold public key
     * @param _keyCommitment Commitment to key shares
     */
    function finalizeDKG(
        bytes calldata _aggregatedPubKey,
        bytes32 _keyCommitment
    ) external onlyOwner {
        if (dkgState.phase != 2) revert DKGPhaseIncorrect();
        if (dkgState.dealingsReceived < threshold) revert NotEnoughKeypers();
        if (_aggregatedPubKey.length != 48) revert InvalidPublicKey();

        uint256 epoch = dkgState.epoch;

        epochKeys[epoch] = ThresholdKey({
            epoch: epoch,
            aggregatedPubKey: _aggregatedPubKey,
            keyCommitment: _keyCommitment,
            threshold: threshold,
            keyperCount: dkgState.participants.length,
            activatedAt: block.number,
            expiresAt: block.number + EPOCH_DURATION,
            revoked: false
        });

        // Reset DKG state
        dkgState.phase = 0;
        currentEpoch = epoch;

        emit DKGFinalized(
            epoch,
            _aggregatedPubKey,
            threshold,
            dkgState.participants.length
        );

        emit EpochKeyActivated(epoch, _aggregatedPubKey);
    }

    /**
     * @notice Revoke an epoch key (emergency)
     * @param _epoch Epoch to revoke
     * @param _reason Reason for revocation
     */
    function revokeEpochKey(
        uint256 _epoch,
        string calldata _reason
    ) external onlyOwner {
        ThresholdKey storage key = epochKeys[_epoch];
        if (key.epoch == 0) revert EpochNotActive();

        key.revoked = true;

        emit EpochKeyRevoked(_epoch, _reason);
    }

    // =========================================================================
    // Query Functions
    // =========================================================================

    /**
     * @notice Get current active threshold public key
     * @return pubKey The aggregated public key for encryption
     */
    function getCurrentPublicKey() external view returns (bytes memory pubKey) {
        ThresholdKey storage key = epochKeys[currentEpoch];
        if (key.revoked) revert KeyRevoked();
        if (block.number > key.expiresAt) revert EpochNotActive();

        return key.aggregatedPubKey;
    }

    /**
     * @notice Get threshold key for a specific epoch
     * @param _epoch Epoch number
     * @return key The threshold key data
     */
    function getEpochKey(
        uint256 _epoch
    ) external view returns (ThresholdKey memory key) {
        return epochKeys[_epoch];
    }

    /**
     * @notice Check if an epoch key is valid for encryption
     * @param _epoch Epoch number
     * @return valid True if key is valid
     */
    function isEpochKeyValid(uint256 _epoch) external view returns (bool valid) {
        ThresholdKey storage key = epochKeys[_epoch];
        return key.epoch != 0 &&
               !key.revoked &&
               block.number <= key.expiresAt;
    }

    /**
     * @notice Get all active keypers
     * @return activeKeypers List of active keyper addresses
     */
    function getActiveKeypers() external view returns (address[] memory activeKeypers) {
        activeKeypers = new address[](activeKeyperCount);
        uint256 index = 0;

        for (uint256 i = 0; i < keyperList.length; i++) {
            if (keypers[keyperList[i]].active) {
                activeKeypers[index] = keyperList[i];
                index++;
            }
        }

        return activeKeypers;
    }

    /**
     * @notice Get DKG participants for current ceremony
     * @return participants List of participant addresses
     */
    function getDKGParticipants() external view returns (address[] memory participants) {
        return dkgState.participants;
    }

    /**
     * @notice Get current DKG phase
     * @return phase Current phase (0=inactive, 1=registration, 2=dealing, 3=finalized)
     */
    function getDKGPhase() external view returns (uint256 phase) {
        return dkgState.phase;
    }

    // =========================================================================
    // Admin Functions
    // =========================================================================

    /**
     * @notice Update threshold requirement
     * @param _newThreshold New threshold value
     */
    function setThreshold(uint256 _newThreshold) external onlyOwner {
        if (_newThreshold < MIN_THRESHOLD) revert InvalidThreshold();
        if (_newThreshold > activeKeyperCount) revert InvalidThreshold();

        uint256 oldThreshold = threshold;
        threshold = _newThreshold;

        emit ThresholdUpdated(oldThreshold, _newThreshold);
    }

    /**
     * @notice Update minimum stake
     * @param _newMinStake New minimum stake
     */
    function setMinStake(uint256 _newMinStake) external onlyOwner {
        minStake = _newMinStake;
    }

    /**
     * @dev Authorize upgrade (owner only)
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /**
     * @notice Receive function to accept stake deposits
     */
    receive() external payable {}
}
