// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title SetPaymaster
 * @notice Gas abstraction for commerce transactions on Set Chain
 * @dev Sponsors gas costs for authorized merchants, enabling frictionless commerce
 *
 * Key features:
 * - Merchant sponsorship with spend limits
 * - Per-transaction and daily limits
 * - Category-based sponsorship tiers
 * - Automatic refund of unused gas
 */
contract SetPaymaster is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    // =========================================================================
    // Types
    // =========================================================================

    /// @notice Sponsorship tier with limits
    struct SponsorshipTier {
        string name;
        uint256 maxPerTransaction;  // Max gas sponsorship per tx (wei)
        uint256 maxPerDay;          // Max gas sponsorship per day (wei)
        uint256 maxPerMonth;        // Max gas sponsorship per month (wei)
        bool active;
    }

    /// @notice Merchant sponsorship record
    struct MerchantSponsorship {
        bool active;
        uint256 tierId;
        uint256 spentToday;
        uint256 spentThisMonth;
        uint256 lastDayReset;
        uint256 lastMonthReset;
        uint256 totalSponsored;
    }

    /// @notice Commerce operation types that can be sponsored
    enum OperationType {
        ORDER_CREATE,
        ORDER_UPDATE,
        PAYMENT_PROCESS,
        INVENTORY_UPDATE,
        RETURN_PROCESS,
        COMMITMENT_ANCHOR,
        OTHER
    }

    // =========================================================================
    // State Variables
    // =========================================================================

    /// @notice Sponsorship tiers
    mapping(uint256 => SponsorshipTier) public tiers;

    /// @notice Next tier ID
    uint256 public nextTierId;

    /// @notice Merchant sponsorships
    mapping(address => MerchantSponsorship) public merchantSponsorship;

    /// @notice Total gas sponsored
    uint256 public totalGasSponsored;

    /// @notice Treasury address for deposits
    address public treasury;

    /// @notice Minimum deposit to sponsor
    uint256 public minDeposit;

    /// @notice Operator addresses that can execute sponsorships
    mapping(address => bool) public operators;

    // =========================================================================
    // Events
    // =========================================================================

    event TierCreated(uint256 indexed tierId, string name, uint256 maxPerTx, uint256 maxPerDay);
    event TierUpdated(uint256 indexed tierId, uint256 maxPerTx, uint256 maxPerDay);
    event MerchantSponsored(address indexed merchant, uint256 tierId);
    event MerchantRevoked(address indexed merchant);
    event GasSponsored(address indexed merchant, uint256 amount, OperationType operationType);
    event Deposited(address indexed from, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);
    event OperatorUpdated(address indexed operator, bool authorized);
    event BatchSponsorshipCompleted(uint256 processed, uint256 succeeded, uint256 failed);
    event BatchSponsorshipFailed(address indexed merchant, string reason);

    // =========================================================================
    // Constants
    // =========================================================================

    /// @notice Maximum merchants per batch operation
    uint256 public constant MAX_BATCH_SIZE = 100;

    // =========================================================================
    // Errors
    // =========================================================================

    error NotSponsored();
    error TierNotActive();
    error ExceedsTransactionLimit(uint256 requested, uint256 max);
    error ExceedsDailyLimit(uint256 requested, uint256 remaining);
    error ExceedsMonthlyLimit(uint256 requested, uint256 remaining);
    error InsufficientBalance();
    error NotOperator();
    error InvalidTier();
    error InvalidAddress();
    error ArrayLengthMismatch();
    error BatchTooLarge();
    error EmptyArray();

    // =========================================================================
    // Modifiers
    // =========================================================================

    modifier onlyOperator() {
        if (!operators[msg.sender] && msg.sender != owner()) {
            revert NotOperator();
        }
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
     * @notice Initialize the paymaster
     * @param _owner Owner address
     * @param _treasury Treasury address for deposits
     */
    function initialize(
        address _owner,
        address _treasury
    ) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        treasury = _treasury;
        minDeposit = 0.01 ether;

        // Create default tiers
        _createDefaultTiers();
    }

    // =========================================================================
    // Admin Functions
    // =========================================================================

    /**
     * @notice Create a new sponsorship tier
     * @param _name Tier name
     * @param _maxPerTx Max per transaction
     * @param _maxPerDay Max per day
     * @param _maxPerMonth Max per month
     */
    function createTier(
        string calldata _name,
        uint256 _maxPerTx,
        uint256 _maxPerDay,
        uint256 _maxPerMonth
    ) external onlyOwner returns (uint256 tierId) {
        tierId = nextTierId++;

        tiers[tierId] = SponsorshipTier({
            name: _name,
            maxPerTransaction: _maxPerTx,
            maxPerDay: _maxPerDay,
            maxPerMonth: _maxPerMonth,
            active: true
        });

        emit TierCreated(tierId, _name, _maxPerTx, _maxPerDay);
    }

    /**
     * @notice Update an existing tier
     * @param _tierId Tier ID
     * @param _maxPerTx Max per transaction
     * @param _maxPerDay Max per day
     * @param _maxPerMonth Max per month
     */
    function updateTier(
        uint256 _tierId,
        uint256 _maxPerTx,
        uint256 _maxPerDay,
        uint256 _maxPerMonth
    ) external onlyOwner {
        SponsorshipTier storage tier = tiers[_tierId];
        tier.maxPerTransaction = _maxPerTx;
        tier.maxPerDay = _maxPerDay;
        tier.maxPerMonth = _maxPerMonth;

        emit TierUpdated(_tierId, _maxPerTx, _maxPerDay);
    }

    /**
     * @notice Set operator authorization
     * @param _operator Operator address
     * @param _authorized Whether authorized
     */
    function setOperator(address _operator, bool _authorized) external onlyOwner {
        operators[_operator] = _authorized;
        emit OperatorUpdated(_operator, _authorized);
    }

    /**
     * @notice Update treasury address
     * @param _treasury New treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    // =========================================================================
    // Merchant Functions
    // =========================================================================

    /**
     * @notice Sponsor a merchant
     * @param _merchant Merchant address
     * @param _tierId Sponsorship tier ID
     */
    function sponsorMerchant(
        address _merchant,
        uint256 _tierId
    ) external onlyOwner {
        if (!tiers[_tierId].active) {
            revert InvalidTier();
        }

        merchantSponsorship[_merchant] = MerchantSponsorship({
            active: true,
            tierId: _tierId,
            spentToday: 0,
            spentThisMonth: 0,
            lastDayReset: block.timestamp,
            lastMonthReset: block.timestamp,
            totalSponsored: 0
        });

        emit MerchantSponsored(_merchant, _tierId);
    }

    /**
     * @notice Revoke merchant sponsorship
     * @param _merchant Merchant address
     */
    function revokeMerchant(address _merchant) external onlyOwner {
        merchantSponsorship[_merchant].active = false;
        emit MerchantRevoked(_merchant);
    }

    /**
     * @notice Check if a merchant can be sponsored for an amount
     * @param _merchant Merchant address
     * @param _amount Gas amount requested
     * @return sponsorable Whether sponsorship is possible
     * @return reason Reason if cannot sponsor
     */
    function canSponsor(
        address _merchant,
        uint256 _amount
    ) external view returns (bool sponsorable, string memory reason) {
        MerchantSponsorship storage sponsorship = merchantSponsorship[_merchant];

        if (!sponsorship.active) {
            return (false, "Not sponsored");
        }

        SponsorshipTier storage tier = tiers[sponsorship.tierId];

        if (!tier.active) {
            return (false, "Tier not active");
        }

        if (_amount > tier.maxPerTransaction) {
            return (false, "Exceeds transaction limit");
        }

        uint256 todaySpent = _getTodaySpent(sponsorship);
        if (todaySpent + _amount > tier.maxPerDay) {
            return (false, "Exceeds daily limit");
        }

        uint256 monthSpent = _getMonthSpent(sponsorship);
        if (monthSpent + _amount > tier.maxPerMonth) {
            return (false, "Exceeds monthly limit");
        }

        if (address(this).balance < _amount) {
            return (false, "Insufficient paymaster balance");
        }

        return (true, "");
    }

    // =========================================================================
    // Sponsorship Execution
    // =========================================================================

    /**
     * @notice Execute gas sponsorship for a merchant
     * @param _merchant Merchant address
     * @param _amount Gas amount to sponsor
     * @param _operationType Type of commerce operation
     */
    function executeSponsorship(
        address _merchant,
        uint256 _amount,
        OperationType _operationType
    ) external onlyOperator nonReentrant {
        MerchantSponsorship storage sponsorship = merchantSponsorship[_merchant];

        if (!sponsorship.active) {
            revert NotSponsored();
        }

        SponsorshipTier storage tier = tiers[sponsorship.tierId];
        if (!tier.active) {
            revert TierNotActive();
        }

        // Check transaction limit
        if (_amount > tier.maxPerTransaction) {
            revert ExceedsTransactionLimit(_amount, tier.maxPerTransaction);
        }

        // Reset and check daily limit
        _resetDailyIfNeeded(sponsorship);
        if (sponsorship.spentToday + _amount > tier.maxPerDay) {
            revert ExceedsDailyLimit(_amount, tier.maxPerDay - sponsorship.spentToday);
        }

        // Reset and check monthly limit
        _resetMonthlyIfNeeded(sponsorship);
        if (sponsorship.spentThisMonth + _amount > tier.maxPerMonth) {
            revert ExceedsMonthlyLimit(_amount, tier.maxPerMonth - sponsorship.spentThisMonth);
        }

        // Check balance
        if (address(this).balance < _amount) {
            revert InsufficientBalance();
        }

        // Update spending
        sponsorship.spentToday += _amount;
        sponsorship.spentThisMonth += _amount;
        sponsorship.totalSponsored += _amount;
        totalGasSponsored += _amount;

        // Transfer gas to merchant
        (bool success, ) = _merchant.call{value: _amount}("");
        require(success, "Transfer failed");

        emit GasSponsored(_merchant, _amount, _operationType);
    }

    /**
     * @notice Refund unused gas sponsorship
     * @param _merchant Merchant address
     * @param _refundAmount Amount to refund
     */
    function refundUnusedGas(
        address _merchant,
        uint256 _refundAmount
    ) external onlyOperator {
        MerchantSponsorship storage sponsorship = merchantSponsorship[_merchant];

        // Reduce spent amounts (but not below 0)
        if (_refundAmount <= sponsorship.spentToday) {
            sponsorship.spentToday -= _refundAmount;
        } else {
            sponsorship.spentToday = 0;
        }

        if (_refundAmount <= sponsorship.spentThisMonth) {
            sponsorship.spentThisMonth -= _refundAmount;
        } else {
            sponsorship.spentThisMonth = 0;
        }

        if (_refundAmount <= sponsorship.totalSponsored) {
            sponsorship.totalSponsored -= _refundAmount;
        }

        if (_refundAmount <= totalGasSponsored) {
            totalGasSponsored -= _refundAmount;
        }
    }

    // =========================================================================
    // Deposit / Withdraw
    // =========================================================================

    /**
     * @notice Deposit ETH to fund sponsorships
     */
    function deposit() external payable {
        require(msg.value >= minDeposit, "Below minimum deposit");
        emit Deposited(msg.sender, msg.value);
    }

    /**
     * @notice Withdraw ETH from paymaster
     * @param _amount Amount to withdraw
     */
    function withdraw(uint256 _amount) external onlyOwner {
        require(address(this).balance >= _amount, "Insufficient balance");

        (bool success, ) = treasury.call{value: _amount}("");
        require(success, "Withdraw failed");

        emit Withdrawn(treasury, _amount);
    }

    /**
     * @notice Get paymaster balance
     */
    function balance() external view returns (uint256) {
        return address(this).balance;
    }

    // =========================================================================
    // View Functions
    // =========================================================================

    /**
     * @notice Get merchant's remaining daily allowance
     * @param _merchant Merchant address
     */
    function getRemainingDailyAllowance(
        address _merchant
    ) external view returns (uint256) {
        MerchantSponsorship storage sponsorship = merchantSponsorship[_merchant];

        if (!sponsorship.active) {
            return 0;
        }

        SponsorshipTier storage tier = tiers[sponsorship.tierId];
        uint256 spent = _getTodaySpent(sponsorship);

        if (spent >= tier.maxPerDay) {
            return 0;
        }

        return tier.maxPerDay - spent;
    }

    /**
     * @notice Get merchant's sponsorship details
     * @param _merchant Merchant address
     */
    function getMerchantDetails(
        address _merchant
    ) external view returns (
        bool active,
        uint256 tierId,
        uint256 spentToday,
        uint256 spentThisMonth,
        uint256 totalSponsored
    ) {
        MerchantSponsorship storage s = merchantSponsorship[_merchant];
        return (
            s.active,
            s.tierId,
            _getTodaySpent(s),
            _getMonthSpent(s),
            s.totalSponsored
        );
    }

    // =========================================================================
    // Internal Functions
    // =========================================================================

    function _createDefaultTiers() internal {
        // Tier 0: Starter (free tier)
        tiers[0] = SponsorshipTier({
            name: "Starter",
            maxPerTransaction: 0.001 ether,
            maxPerDay: 0.01 ether,
            maxPerMonth: 0.1 ether,
            active: true
        });

        // Tier 1: Growth
        tiers[1] = SponsorshipTier({
            name: "Growth",
            maxPerTransaction: 0.005 ether,
            maxPerDay: 0.05 ether,
            maxPerMonth: 0.5 ether,
            active: true
        });

        // Tier 2: Enterprise
        tiers[2] = SponsorshipTier({
            name: "Enterprise",
            maxPerTransaction: 0.01 ether,
            maxPerDay: 0.1 ether,
            maxPerMonth: 1 ether,
            active: true
        });

        nextTierId = 3;
    }

    function _resetDailyIfNeeded(MerchantSponsorship storage s) internal {
        if (block.timestamp - s.lastDayReset >= 1 days) {
            s.spentToday = 0;
            s.lastDayReset = block.timestamp;
        }
    }

    function _resetMonthlyIfNeeded(MerchantSponsorship storage s) internal {
        if (block.timestamp - s.lastMonthReset >= 30 days) {
            s.spentThisMonth = 0;
            s.lastMonthReset = block.timestamp;
        }
    }

    function _getTodaySpent(
        MerchantSponsorship storage s
    ) internal view returns (uint256) {
        if (block.timestamp - s.lastDayReset >= 1 days) {
            return 0;
        }
        return s.spentToday;
    }

    function _getMonthSpent(
        MerchantSponsorship storage s
    ) internal view returns (uint256) {
        if (block.timestamp - s.lastMonthReset >= 30 days) {
            return 0;
        }
        return s.spentThisMonth;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // =========================================================================
    // Batch Operations
    // =========================================================================

    /**
     * @notice Sponsor multiple merchants in a single transaction
     * @param _merchants Array of merchant addresses
     * @param _tierIds Array of tier IDs for each merchant
     */
    function batchSponsorMerchants(
        address[] calldata _merchants,
        uint256[] calldata _tierIds
    ) external onlyOwner {
        if (_merchants.length == 0) revert EmptyArray();
        if (_merchants.length != _tierIds.length) revert ArrayLengthMismatch();
        if (_merchants.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        for (uint256 i = 0; i < _merchants.length; i++) {
            if (_merchants[i] == address(0)) revert InvalidAddress();
            if (!tiers[_tierIds[i]].active) {
                revert InvalidTier();
            }

            merchantSponsorship[_merchants[i]] = MerchantSponsorship({
                active: true,
                tierId: _tierIds[i],
                spentToday: 0,
                spentThisMonth: 0,
                lastDayReset: block.timestamp,
                lastMonthReset: block.timestamp,
                totalSponsored: 0
            });

            emit MerchantSponsored(_merchants[i], _tierIds[i]);
        }
    }

    /**
     * @notice Revoke sponsorship for multiple merchants
     * @param _merchants Array of merchant addresses
     */
    function batchRevokeMerchants(address[] calldata _merchants) external onlyOwner {
        if (_merchants.length == 0) revert EmptyArray();
        if (_merchants.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        for (uint256 i = 0; i < _merchants.length; i++) {
            merchantSponsorship[_merchants[i]].active = false;
            emit MerchantRevoked(_merchants[i]);
        }
    }

    /**
     * @notice Execute sponsorship for multiple merchants in a single transaction
     * @param _merchants Array of merchant addresses
     * @param _amounts Array of amounts to sponsor
     * @param _operationTypes Array of operation types
     * @return succeeded Count of successful sponsorships
     * @return failed Count of failed sponsorships
     * @dev Skips merchants that fail validation rather than reverting
     */
    function batchExecuteSponsorship(
        address[] calldata _merchants,
        uint256[] calldata _amounts,
        OperationType[] calldata _operationTypes
    ) external onlyOperator nonReentrant returns (uint256 succeeded, uint256 failed) {
        if (_merchants.length == 0) revert EmptyArray();
        if (_merchants.length != _amounts.length || _amounts.length != _operationTypes.length) {
            revert ArrayLengthMismatch();
        }
        if (_merchants.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        for (uint256 i = 0; i < _merchants.length; i++) {
            MerchantSponsorship storage sponsorship = merchantSponsorship[_merchants[i]];

            // Skip inactive merchants
            if (!sponsorship.active) {
                emit BatchSponsorshipFailed(_merchants[i], "Not sponsored");
                failed++;
                continue;
            }

            SponsorshipTier storage tier = tiers[sponsorship.tierId];
            if (!tier.active) {
                emit BatchSponsorshipFailed(_merchants[i], "Tier not active");
                failed++;
                continue;
            }

            // Skip if exceeds transaction limit
            if (_amounts[i] > tier.maxPerTransaction) {
                emit BatchSponsorshipFailed(_merchants[i], "Exceeds tx limit");
                failed++;
                continue;
            }

            // Reset and check daily limit
            _resetDailyIfNeeded(sponsorship);
            if (sponsorship.spentToday + _amounts[i] > tier.maxPerDay) {
                emit BatchSponsorshipFailed(_merchants[i], "Exceeds daily limit");
                failed++;
                continue;
            }

            // Reset and check monthly limit
            _resetMonthlyIfNeeded(sponsorship);
            if (sponsorship.spentThisMonth + _amounts[i] > tier.maxPerMonth) {
                emit BatchSponsorshipFailed(_merchants[i], "Exceeds monthly limit");
                failed++;
                continue;
            }

            // Check balance
            if (address(this).balance < _amounts[i]) {
                emit BatchSponsorshipFailed(_merchants[i], "Insufficient balance");
                failed++;
                continue;
            }

            // Update spending
            sponsorship.spentToday += _amounts[i];
            sponsorship.spentThisMonth += _amounts[i];
            sponsorship.totalSponsored += _amounts[i];
            totalGasSponsored += _amounts[i];

            // Transfer gas to merchant
            (bool success, ) = _merchants[i].call{value: _amounts[i]}("");
            if (success) {
                emit GasSponsored(_merchants[i], _amounts[i], _operationTypes[i]);
                succeeded++;
            } else {
                // Rollback spending updates on failed transfer
                sponsorship.spentToday -= _amounts[i];
                sponsorship.spentThisMonth -= _amounts[i];
                sponsorship.totalSponsored -= _amounts[i];
                totalGasSponsored -= _amounts[i];
                emit BatchSponsorshipFailed(_merchants[i], "Transfer failed");
                failed++;
            }
        }

        emit BatchSponsorshipCompleted(_merchants.length, succeeded, failed);
        return (succeeded, failed);
    }

    /**
     * @notice Batch refund unused gas for multiple merchants
     * @param _merchants Array of merchant addresses
     * @param _refundAmounts Array of refund amounts
     */
    function batchRefundUnusedGas(
        address[] calldata _merchants,
        uint256[] calldata _refundAmounts
    ) external onlyOperator {
        if (_merchants.length == 0) revert EmptyArray();
        if (_merchants.length != _refundAmounts.length) revert ArrayLengthMismatch();
        if (_merchants.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        for (uint256 i = 0; i < _merchants.length; i++) {
            MerchantSponsorship storage sponsorship = merchantSponsorship[_merchants[i]];
            uint256 refundAmount = _refundAmounts[i];

            // Reduce spent amounts (but not below 0)
            if (refundAmount <= sponsorship.spentToday) {
                sponsorship.spentToday -= refundAmount;
            } else {
                sponsorship.spentToday = 0;
            }

            if (refundAmount <= sponsorship.spentThisMonth) {
                sponsorship.spentThisMonth -= refundAmount;
            } else {
                sponsorship.spentThisMonth = 0;
            }

            if (refundAmount <= sponsorship.totalSponsored) {
                sponsorship.totalSponsored -= refundAmount;
            }

            if (refundAmount <= totalGasSponsored) {
                totalGasSponsored -= refundAmount;
            }
        }
    }

    /**
     * @notice Get sponsorship status for multiple merchants
     * @param _merchants Array of merchant addresses
     * @return statuses Array of active status for each merchant
     * @return tiers_ Array of tier IDs for each merchant
     */
    function batchGetMerchantStatus(
        address[] calldata _merchants
    ) external view returns (bool[] memory statuses, uint256[] memory tiers_) {
        statuses = new bool[](_merchants.length);
        tiers_ = new uint256[](_merchants.length);

        for (uint256 i = 0; i < _merchants.length; i++) {
            MerchantSponsorship storage s = merchantSponsorship[_merchants[i]];
            statuses[i] = s.active;
            tiers_[i] = s.tierId;
        }

        return (statuses, tiers_);
    }

    /**
     * @notice Check if multiple merchants can be sponsored for given amounts
     * @param _merchants Array of merchant addresses
     * @param _amounts Array of requested amounts
     * @return canSponsor_ Array of booleans indicating sponsorability
     * @return reasons Array of rejection reasons (empty if sponsorable)
     */
    function batchCanSponsor(
        address[] calldata _merchants,
        uint256[] calldata _amounts
    ) external view returns (bool[] memory canSponsor_, string[] memory reasons) {
        if (_merchants.length != _amounts.length) revert ArrayLengthMismatch();

        canSponsor_ = new bool[](_merchants.length);
        reasons = new string[](_merchants.length);

        for (uint256 i = 0; i < _merchants.length; i++) {
            (canSponsor_[i], reasons[i]) = this.canSponsor(_merchants[i], _amounts[i]);
        }

        return (canSponsor_, reasons);
    }

    /**
     * @notice Get remaining daily allowances for multiple merchants
     * @param _merchants Array of merchant addresses
     * @return allowances Array of remaining daily allowances
     */
    function batchGetRemainingDailyAllowance(
        address[] calldata _merchants
    ) external view returns (uint256[] memory allowances) {
        allowances = new uint256[](_merchants.length);

        for (uint256 i = 0; i < _merchants.length; i++) {
            allowances[i] = this.getRemainingDailyAllowance(_merchants[i]);
        }

        return allowances;
    }

    /**
     * @notice Get comprehensive details for multiple merchants
     * @param _merchants Array of merchant addresses
     * @return details Packed merchant details (active, tierId, spentToday, spentThisMonth, totalSponsored)
     */
    function batchGetMerchantDetails(
        address[] calldata _merchants
    ) external view returns (
        bool[] memory active,
        uint256[] memory tierIds,
        uint256[] memory spentToday,
        uint256[] memory spentThisMonth,
        uint256[] memory totalSponsored
    ) {
        active = new bool[](_merchants.length);
        tierIds = new uint256[](_merchants.length);
        spentToday = new uint256[](_merchants.length);
        spentThisMonth = new uint256[](_merchants.length);
        totalSponsored = new uint256[](_merchants.length);

        for (uint256 i = 0; i < _merchants.length; i++) {
            (
                active[i],
                tierIds[i],
                spentToday[i],
                spentThisMonth[i],
                totalSponsored[i]
            ) = this.getMerchantDetails(_merchants[i]);
        }

        return (active, tierIds, spentToday, spentThisMonth, totalSponsored);
    }

    /**
     * @notice Update tier for multiple merchants
     * @param _merchants Array of merchant addresses
     * @param _newTierId New tier ID to assign
     */
    function batchUpdateMerchantTier(
        address[] calldata _merchants,
        uint256 _newTierId
    ) external onlyOwner {
        if (_merchants.length == 0) revert EmptyArray();
        if (_merchants.length > MAX_BATCH_SIZE) revert BatchTooLarge();
        if (!tiers[_newTierId].active) revert InvalidTier();

        for (uint256 i = 0; i < _merchants.length; i++) {
            MerchantSponsorship storage s = merchantSponsorship[_merchants[i]];
            if (s.active) {
                s.tierId = _newTierId;
                emit MerchantSponsored(_merchants[i], _newTierId);
            }
        }
    }

    // =========================================================================
    // Monitoring Functions
    // =========================================================================

    /**
     * @notice Get comprehensive paymaster status
     * @return paymasterBalance Current contract balance
     * @return totalSponsored_ Total gas ever sponsored
     * @return tierCount Number of tiers
     * @return treasuryAddr Treasury address
     */
    function getPaymasterStatus() external view returns (
        uint256 paymasterBalance,
        uint256 totalSponsored_,
        uint256 tierCount,
        address treasuryAddr
    ) {
        return (
            address(this).balance,
            totalGasSponsored,
            nextTierId,
            treasury
        );
    }

    /**
     * @notice Get all active tier details
     * @return tierIds Array of tier IDs
     * @return names Array of tier names
     * @return maxPerTx Array of max per transaction limits
     * @return maxPerDay_ Array of max per day limits
     * @return maxPerMonth_ Array of max per month limits
     */
    function getAllTiers() external view returns (
        uint256[] memory tierIds,
        string[] memory names,
        uint256[] memory maxPerTx,
        uint256[] memory maxPerDay_,
        uint256[] memory maxPerMonth_
    ) {
        // Count active tiers
        uint256 activeCount = 0;
        for (uint256 i = 0; i < nextTierId; i++) {
            if (tiers[i].active) activeCount++;
        }

        tierIds = new uint256[](activeCount);
        names = new string[](activeCount);
        maxPerTx = new uint256[](activeCount);
        maxPerDay_ = new uint256[](activeCount);
        maxPerMonth_ = new uint256[](activeCount);

        uint256 index = 0;
        for (uint256 i = 0; i < nextTierId; i++) {
            if (tiers[i].active) {
                tierIds[index] = i;
                names[index] = tiers[i].name;
                maxPerTx[index] = tiers[i].maxPerTransaction;
                maxPerDay_[index] = tiers[i].maxPerDay;
                maxPerMonth_[index] = tiers[i].maxPerMonth;
                index++;
            }
        }

        return (tierIds, names, maxPerTx, maxPerDay_, maxPerMonth_);
    }

    // =========================================================================
    // Receive
    // =========================================================================

    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }
}
