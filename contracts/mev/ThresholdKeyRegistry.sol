// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

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
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
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
        mapping(address => bool) hasRegistered; // Track who has registered for this DKG (prevents duplicates)
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

    /// @notice Current DKG state (contains mappings; cannot be public)
    DKGState private dkgState;

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

    event DKGAborted(string reason);

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
    error AlreadyRegisteredForDKG();
    error NotRegisteredForDKG();
    error EpochNotActive();
    error EpochAlreadyExists();
    error KeyRevoked();
    error InvalidAddress();
    error EmptyArray();

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
        __Pausable_init();
        __ReentrancyGuard_init();
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
    ) external payable whenNotPaused {
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
    function withdrawStake() external nonReentrant {
        Keyper storage keyper = keypers[msg.sender];
        if (keyper.addr == address(0)) revert KeyperNotRegistered();
        if (keyper.active) revert KeyperNotRegistered(); // Must deactivate first

        uint256 amount = stakes[msg.sender];
        if (amount == 0) revert InsufficientStake();
        stakes[msg.sender] = 0;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
    }

    // =========================================================================
    // DKG Coordination
    // =========================================================================

    /**
     * @notice Start distributed key generation for next epoch
     *
     * SECURITY FIX: Properly clears all DKG state from previous ceremonies
     * including the hasRegistered and dealings mappings to prevent:
     * 1. Stale registration data affecting new ceremonies
     * 2. Old dealings being counted in new ceremonies
     * 3. Keypers being unable to participate in new ceremonies
     */
    function startDKG() external onlyOwner {
        if (dkgState.phase != 0) revert DKGAlreadyActive();
        if (activeKeyperCount < threshold) revert NotEnoughKeypers();

        // SECURITY FIX: Clear previous ceremony's state before starting new one
        // Clear the hasRegistered mapping for all previous participants
        for (uint256 i = 0; i < dkgState.participants.length; i++) {
            address participant = dkgState.participants[i];
            delete dkgState.hasRegistered[participant];
            delete dkgState.dealings[participant];
        }

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
     *
     * SECURITY FIX: Prevents duplicate registration in the same DKG ceremony.
     * A keyper can only register once per ceremony.
     */
    function registerForDKG() external {
        if (dkgState.phase != 1) revert DKGPhaseIncorrect();
        if (block.number > dkgState.phaseDeadline) revert DKGDeadlinePassed();

        Keyper storage keyper = keypers[msg.sender];
        if (!keyper.active) revert KeyperNotRegistered();

        // SECURITY FIX: Prevent duplicate registration
        if (dkgState.hasRegistered[msg.sender]) revert AlreadyRegisteredForDKG();

        dkgState.hasRegistered[msg.sender] = true;
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
        if (!dkgState.hasRegistered[msg.sender]) revert NotRegisteredForDKG();
        if (!keypers[msg.sender].active) revert KeyperNotRegistered();
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
     *
     * SECURITY FIX: After finalization, DKG state is cleared to prevent
     * any stale state from affecting future ceremonies.
     */
    function finalizeDKG(
        bytes calldata _aggregatedPubKey,
        bytes32 _keyCommitment
    ) external onlyOwner {
        if (dkgState.phase != 2) revert DKGPhaseIncorrect();
        if (dkgState.dealingsReceived < threshold) revert NotEnoughKeypers();
        if (_aggregatedPubKey.length != 48) revert InvalidPublicKey();

        uint256 epoch = dkgState.epoch;
        uint256 participantCount = dkgState.participants.length;

        epochKeys[epoch] = ThresholdKey({
            epoch: epoch,
            aggregatedPubKey: _aggregatedPubKey,
            keyCommitment: _keyCommitment,
            threshold: threshold,
            keyperCount: participantCount,
            activatedAt: block.number,
            expiresAt: block.number + EPOCH_DURATION,
            revoked: false
        });

        // Reset DKG state - phase 0 means inactive
        // Note: hasRegistered and dealings will be cleared in next startDKG call
        dkgState.phase = 0;
        currentEpoch = epoch;

        emit DKGFinalized(
            epoch,
            _aggregatedPubKey,
            threshold,
            participantCount
        );

        emit EpochKeyActivated(epoch, _aggregatedPubKey);
    }

    /**
     * @notice Abort a DKG ceremony that has failed or stalled
     * @param _reason Reason for aborting
     *
     * SECURITY FIX: Allows admin to abort a failed DKG and clear state
     * so a new ceremony can be started.
     */
    function abortDKG(string calldata _reason) external onlyOwner {
        if (dkgState.phase == 0) revert DKGNotActive();

        // Clear all DKG state
        for (uint256 i = 0; i < dkgState.participants.length; i++) {
            address participant = dkgState.participants[i];
            delete dkgState.hasRegistered[participant];
            delete dkgState.dealings[participant];
        }

        delete dkgState.participants;
        dkgState.epoch = 0;
        dkgState.phase = 0;
        dkgState.phaseDeadline = 0;
        dkgState.dealingsReceived = 0;

        emit DKGAborted(_reason);
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
     * @notice Check if a keyper is currently active
     * @param keyper Keyper address
     * @return active True if active
     */
    function isKeyperActive(address keyper) external view returns (bool active) {
        return keypers[keyper].active;
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
     * @param _newMinStake New minimum stake (must be > 0)
     */
    function setMinStake(uint256 _newMinStake) external onlyOwner {
        if (_newMinStake == 0) revert InsufficientStake();
        minStake = _newMinStake;
    }

    /**
     * @notice Pause all keyper operations
     * @dev Emergency stop mechanism
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause keyper operations
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // =========================================================================
    // Monitoring Functions
    // =========================================================================

    /**
     * @notice Get comprehensive registry status
     * @return totalKeypers Total registered keypers
     * @return activeCount Number of active keypers
     * @return currentThreshold Current threshold (t)
     * @return epoch Current epoch number
     * @return dkgPhase Current DKG phase
     * @return isPaused Whether contract is paused
     */
    function getRegistryStatus() external view returns (
        uint256 totalKeypers,
        uint256 activeCount,
        uint256 currentThreshold,
        uint256 epoch,
        uint256 dkgPhase,
        bool isPaused
    ) {
        return (
            keyperList.length,
            activeKeyperCount,
            threshold,
            currentEpoch,
            dkgState.phase,
            paused()
        );
    }

    /**
     * @notice Get full keyper details
     * @param _keyper Keyper address
     * @return keyperData Full keyper struct
     * @return stakedAmount Amount staked
     * @return isActive Whether currently active
     */
    function getKeyperDetails(address _keyper) external view returns (
        Keyper memory keyperData,
        uint256 stakedAmount,
        bool isActive
    ) {
        Keyper storage k = keypers[_keyper];
        return (k, stakes[_keyper], k.active);
    }

    /**
     * @notice Get current epoch key status
     * @return valid Whether current key is valid
     * @return blocksRemaining Blocks until expiration (0 if expired)
     * @return keyperCount Number of keypers in current epoch
     * @return epochThreshold Threshold for current epoch
     */
    function getCurrentKeyStatus() external view returns (
        bool valid,
        uint256 blocksRemaining,
        uint256 keyperCount,
        uint256 epochThreshold
    ) {
        ThresholdKey storage key = epochKeys[currentEpoch];
        bool isValid = key.epoch != 0 && !key.revoked && block.number <= key.expiresAt;
        uint256 remaining = 0;
        if (isValid && block.number < key.expiresAt) {
            remaining = key.expiresAt - block.number;
        }
        return (isValid, remaining, key.keyperCount, key.threshold);
    }

    /**
     * @notice Get DKG ceremony status
     * @return epoch Epoch being generated
     * @return phase Current phase
     * @return deadline Phase deadline block
     * @return participantCount Number of registered participants
     * @return dealingsCount Number of dealings received
     * @return blocksUntilDeadline Blocks until deadline (0 if passed)
     */
    function getDKGStatus() external view returns (
        uint256 epoch,
        uint256 phase,
        uint256 deadline,
        uint256 participantCount,
        uint256 dealingsCount,
        uint256 blocksUntilDeadline
    ) {
        uint256 remaining = 0;
        if (block.number < dkgState.phaseDeadline) {
            remaining = dkgState.phaseDeadline - block.number;
        }
        return (
            dkgState.epoch,
            dkgState.phase,
            dkgState.phaseDeadline,
            dkgState.participants.length,
            dkgState.dealingsReceived,
            remaining
        );
    }

    /**
     * @notice Check if a keyper has registered for current DKG
     * @param _keyper Keyper address
     * @return registered True if registered
     */
    function isRegisteredForDKG(address _keyper) external view returns (bool registered) {
        return dkgState.hasRegistered[_keyper];
    }

    /**
     * @notice Get total staked value in the registry
     * @return totalStaked Sum of all keyper stakes
     */
    function getTotalStaked() external view returns (uint256 totalStaked) {
        for (uint256 i = 0; i < keyperList.length; i++) {
            totalStaked += stakes[keyperList[i]];
        }
        return totalStaked;
    }

    /**
     * @notice Get the list of all keyper addresses
     * @return allKeypers Array of keyper addresses
     */
    function getAllKeypers() external view returns (address[] memory allKeypers) {
        return keyperList;
    }

    // =========================================================================
    // Batch Query Functions
    // =========================================================================

    /**
     * @notice Get active status for multiple keypers
     * @param _keypers Array of keyper addresses
     * @return active Array of active statuses
     */
    function batchIsKeyperActive(
        address[] calldata _keypers
    ) external view returns (bool[] memory active) {
        active = new bool[](_keypers.length);
        for (uint256 i = 0; i < _keypers.length; i++) {
            active[i] = keypers[_keypers[i]].active;
        }
        return active;
    }

    /**
     * @notice Get stakes for multiple keypers
     * @param _keypers Array of keyper addresses
     * @return stakedAmounts Array of staked amounts
     */
    function batchGetStakes(
        address[] calldata _keypers
    ) external view returns (uint256[] memory stakedAmounts) {
        stakedAmounts = new uint256[](_keypers.length);
        for (uint256 i = 0; i < _keypers.length; i++) {
            stakedAmounts[i] = stakes[_keypers[i]];
        }
        return stakedAmounts;
    }

    /**
     * @notice Check DKG registration status for multiple keypers
     * @param _keypers Array of keyper addresses
     * @return registered Array of registration statuses
     */
    function batchIsRegisteredForDKG(
        address[] calldata _keypers
    ) external view returns (bool[] memory registered) {
        registered = new bool[](_keypers.length);
        for (uint256 i = 0; i < _keypers.length; i++) {
            registered[i] = dkgState.hasRegistered[_keypers[i]];
        }
        return registered;
    }

    /**
     * @notice Check if multiple epochs have valid keys
     * @param _epochs Array of epoch numbers
     * @return valid Array of validity statuses
     */
    function batchIsEpochKeyValid(
        uint256[] calldata _epochs
    ) external view returns (bool[] memory valid) {
        valid = new bool[](_epochs.length);
        for (uint256 i = 0; i < _epochs.length; i++) {
            ThresholdKey storage key = epochKeys[_epochs[i]];
            valid[i] = key.epoch != 0 && !key.revoked && block.number <= key.expiresAt;
        }
        return valid;
    }

    /**
     * @notice Get comprehensive keyper summaries
     * @param _keypers Array of keyper addresses
     * @return active_ Array of active statuses
     * @return stakes_ Array of stake amounts
     * @return slashCounts Array of slash counts
     * @return registeredForDKG Array of DKG registration statuses
     */
    function batchGetKeyperSummary(
        address[] calldata _keypers
    ) external view returns (
        bool[] memory active_,
        uint256[] memory stakes_,
        uint256[] memory slashCounts,
        bool[] memory registeredForDKG
    ) {
        uint256 len = _keypers.length;
        active_ = new bool[](len);
        stakes_ = new uint256[](len);
        slashCounts = new uint256[](len);
        registeredForDKG = new bool[](len);

        for (uint256 i = 0; i < len; i++) {
            Keyper storage k = keypers[_keypers[i]];
            active_[i] = k.active;
            stakes_[i] = stakes[_keypers[i]];
            slashCounts[i] = k.slashCount;
            registeredForDKG[i] = dkgState.hasRegistered[_keypers[i]];
        }

        return (active_, stakes_, slashCounts, registeredForDKG);
    }

    // =========================================================================
    // Extended Monitoring
    // =========================================================================

    /**
     * @notice Get keyper network health metrics
     * @return totalKeypers_ Total registered keypers
     * @return activeCount_ Active keyper count
     * @return avgStake Average stake per active keyper
     * @return totalSlashed Total slash count across all keypers
     * @return networkSecure Whether network meets minimum security (active >= threshold)
     */
    function getNetworkHealth() external view returns (
        uint256 totalKeypers_,
        uint256 activeCount_,
        uint256 avgStake,
        uint256 totalSlashed,
        bool networkSecure
    ) {
        totalKeypers_ = keyperList.length;
        activeCount_ = activeKeyperCount;

        uint256 totalStake = 0;
        for (uint256 i = 0; i < keyperList.length; i++) {
            address k = keyperList[i];
            totalStake += stakes[k];
            totalSlashed += keypers[k].slashCount;
        }

        if (activeCount_ > 0) {
            avgStake = totalStake / activeCount_;
        }

        networkSecure = activeCount_ >= threshold;

        return (totalKeypers_, activeCount_, avgStake, totalSlashed, networkSecure);
    }

    /**
     * @notice Get epoch history summary
     * @param _epochStart Starting epoch
     * @param _epochEnd Ending epoch
     * @return epochs_ Array of epoch numbers
     * @return valid Array of validity statuses
     * @return revoked Array of revocation statuses
     * @return thresholds_ Array of thresholds used
     */
    function getEpochHistory(
        uint256 _epochStart,
        uint256 _epochEnd
    ) external view returns (
        uint256[] memory epochs_,
        bool[] memory valid,
        bool[] memory revoked,
        uint256[] memory thresholds_
    ) {
        if (_epochEnd < _epochStart) {
            return (epochs_, valid, revoked, thresholds_);
        }

        uint256 count = _epochEnd - _epochStart + 1;
        epochs_ = new uint256[](count);
        valid = new bool[](count);
        revoked = new bool[](count);
        thresholds_ = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 epoch = _epochStart + i;
            ThresholdKey storage key = epochKeys[epoch];

            epochs_[i] = epoch;
            revoked[i] = key.revoked;
            thresholds_[i] = key.threshold;
            valid[i] = key.epoch != 0 && !key.revoked && block.number <= key.expiresAt;
        }

        return (epochs_, valid, revoked, thresholds_);
    }

    /**
     * @notice Calculate time until current key expires
     * @return blocksRemaining Blocks until expiration
     * @return secondsRemaining Approximate seconds (assuming 12s blocks)
     * @return percentRemaining Percentage of epoch remaining (basis points)
     */
    function getKeyExpirationInfo() external view returns (
        uint256 blocksRemaining,
        uint256 secondsRemaining,
        uint256 percentRemaining
    ) {
        ThresholdKey storage key = epochKeys[currentEpoch];

        if (key.epoch == 0 || key.revoked || block.number > key.expiresAt) {
            return (0, 0, 0);
        }

        blocksRemaining = key.expiresAt - block.number;
        secondsRemaining = blocksRemaining * 12; // Assuming 12 second blocks

        uint256 totalDuration = key.expiresAt - key.activatedAt;
        if (totalDuration > 0) {
            percentRemaining = (blocksRemaining * 10000) / totalDuration;
        }

        return (blocksRemaining, secondsRemaining, percentRemaining);
    }

    /**
     * @notice Get keypers sorted by stake (descending)
     * @param _limit Maximum number to return
     * @return topKeypers Array of keyper addresses
     * @return topStakes Array of stake amounts
     */
    function getTopKeypersByStake(
        uint256 _limit
    ) external view returns (
        address[] memory topKeypers,
        uint256[] memory topStakes
    ) {
        uint256 count = keyperList.length;
        if (_limit > 0 && _limit < count) {
            count = _limit;
        }

        // Create temporary arrays
        address[] memory tempAddrs = new address[](keyperList.length);
        uint256[] memory tempStakes = new uint256[](keyperList.length);

        for (uint256 i = 0; i < keyperList.length; i++) {
            tempAddrs[i] = keyperList[i];
            tempStakes[i] = stakes[keyperList[i]];
        }

        // Simple bubble sort (fine for small arrays)
        for (uint256 i = 0; i < keyperList.length; i++) {
            for (uint256 j = i + 1; j < keyperList.length; j++) {
                if (tempStakes[j] > tempStakes[i]) {
                    // Swap
                    (tempStakes[i], tempStakes[j]) = (tempStakes[j], tempStakes[i]);
                    (tempAddrs[i], tempAddrs[j]) = (tempAddrs[j], tempAddrs[i]);
                }
            }
        }

        // Return top N
        topKeypers = new address[](count);
        topStakes = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            topKeypers[i] = tempAddrs[i];
            topStakes[i] = tempStakes[i];
        }

        return (topKeypers, topStakes);
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
