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
     * @return canSponsor Whether sponsorship is possible
     * @return reason Reason if cannot sponsor
     */
    function canSponsor(
        address _merchant,
        uint256 _amount
    ) external view returns (bool canSponsor, string memory reason) {
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
    // Receive
    // =========================================================================

    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }
}
