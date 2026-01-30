// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/ISSDC.sol";

/**
 * @title wSSDC (Wrapped StateSet Dollar Coin)
 * @notice Non-rebasing wrapper for SSDC using ERC4626 vault standard
 * @dev
 * - SSDC rebases (balance changes with yield)
 * - wSSDC does NOT rebase (balance stable, value accrues)
 *
 * This makes wSSDC compatible with DeFi protocols that don't handle rebasing tokens:
 * - AMMs (Uniswap, etc.)
 * - Lending protocols (Aave, Compound)
 * - Yield aggregators
 *
 * Mechanics:
 * - Deposit SSDC → Receive wSSDC shares
 * - As SSDC rebases, wSSDC share price increases
 * - wSSDC balance stays constant, but represents more SSDC over time
 */
contract wSSDC is
    Initializable,
    ERC4626Upgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    // =========================================================================
    // Storage
    // =========================================================================

    /// @notice Maximum deposit cap (0 = unlimited)
    uint256 public depositCap;

    /// @notice Total deposited SSDC (for cap tracking)
    uint256 public totalDeposited;

    /// @notice Maximum batch size for operations
    uint256 public constant MAX_BATCH_SIZE = 100;

    /// @notice Daily wrap limit per account (0 = unlimited)
    uint256 public dailyWrapLimit;

    /// @notice Daily tracking for wrap limits
    mapping(address => uint256) public dailyWrapAmount;
    mapping(address => uint256) public lastWrapDay;

    /// @notice Rate limiting: minimum seconds between wraps for same account
    uint256 public wrapCooldown;
    mapping(address => uint256) public lastWrapTime;

    /// @notice Share price history for analytics
    struct SharePriceSnapshot {
        uint256 price;
        uint256 timestamp;
        uint256 totalAssets;
        uint256 totalSupply;
    }
    SharePriceSnapshot[] public sharePriceHistory;
    uint256 public snapshotInterval; // Minimum seconds between snapshots

    // =========================================================================
    // Errors
    // =========================================================================

    error InvalidAddress();
    error DepositCapExceeded();
    error InvalidDepositCap();
    error ArrayLengthMismatch();
    error BatchTooLarge();
    error EmptyArray();
    error DailyLimitExceeded();
    error RateLimitExceeded();
    error CooldownActive();

    // =========================================================================
    // Events
    // =========================================================================

    event Wrapped(address indexed account, uint256 SSDCAmount, uint256 wSSDCAmount);
    event Unwrapped(address indexed account, uint256 wSSDCAmount, uint256 SSDCAmount);
    event DepositCapUpdated(uint256 oldCap, uint256 newCap);
    event DailyWrapLimitUpdated(uint256 oldLimit, uint256 newLimit);
    event WrapCooldownUpdated(uint256 oldCooldown, uint256 newCooldown);
    event SnapshotIntervalUpdated(uint256 oldInterval, uint256 newInterval);
    event SharePriceSnapshotRecorded(uint256 price, uint256 totalAssets, uint256 totalSupply);
    event BatchWrapped(address indexed caller, uint256 totalSSDC, uint256 totalWSSDC, uint256 count);
    event BatchUnwrapped(address indexed caller, uint256 totalWSSDC, uint256 totalSSDC, uint256 count);
    // =========================================================================
    // Initialization
    // =========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize wSSDC
     * @param owner_ Owner address
     * @param SSDC_ SSDC token address
     */
    function initialize(
        address owner_,
        address SSDC_
    ) public initializer {
        if (owner_ == address(0)) revert InvalidAddress();
        if (SSDC_ == address(0)) revert InvalidAddress();

        __ERC4626_init(IERC20(SSDC_));
        __ERC20_init("Wrapped StateSet Dollar Coin", "wSSDC");
        __Ownable_init(owner_);
        __Pausable_init();
        __UUPSUpgradeable_init();
    }

    // =========================================================================
    // ERC4626 Overrides
    // =========================================================================

    /**
     * @notice Decimals (same as SSDC)
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    // =========================================================================
    // Convenience Functions
    // =========================================================================

    /**
     * @notice Wrap SSDC into wSSDC
     * @param SSDCAmount Amount of SSDC to wrap
     * @return wSSDCAmount Amount of wSSDC received
     */
    function wrap(uint256 SSDCAmount) external whenNotPaused returns (uint256 wSSDCAmount) {
        _checkWrapLimits(msg.sender, SSDCAmount);

        // Check deposit cap
        if (depositCap > 0 && totalDeposited + SSDCAmount > depositCap) {
            revert DepositCapExceeded();
        }

        // Update rate limiting
        _updateWrapTracking(msg.sender, SSDCAmount);

        wSSDCAmount = deposit(SSDCAmount, msg.sender);
        totalDeposited += SSDCAmount;

        // Record snapshot if interval passed
        _maybeRecordSnapshot();

        emit Wrapped(msg.sender, SSDCAmount, wSSDCAmount);
        return wSSDCAmount;
    }

    /**
     * @dev Check rate limits for wrapping
     */
    function _checkWrapLimits(address account, uint256 amount) internal view {
        // Check cooldown
        if (wrapCooldown > 0 && lastWrapTime[account] + wrapCooldown > block.timestamp) {
            revert CooldownActive();
        }

        // Check daily limit
        if (dailyWrapLimit > 0) {
            uint256 currentDay = block.timestamp / 1 days;
            uint256 usedToday = lastWrapDay[account] == currentDay ? dailyWrapAmount[account] : 0;
            if (usedToday + amount > dailyWrapLimit) {
                revert DailyLimitExceeded();
            }
        }
    }

    /**
     * @dev Update tracking after wrap
     */
    function _updateWrapTracking(address account, uint256 amount) internal {
        lastWrapTime[account] = block.timestamp;

        uint256 currentDay = block.timestamp / 1 days;
        if (lastWrapDay[account] != currentDay) {
            lastWrapDay[account] = currentDay;
            dailyWrapAmount[account] = amount;
        } else {
            dailyWrapAmount[account] += amount;
        }
    }

    /**
     * @dev Record share price snapshot if interval passed
     */
    function _maybeRecordSnapshot() internal {
        if (snapshotInterval == 0) return;

        uint256 len = sharePriceHistory.length;
        if (len > 0 && block.timestamp < sharePriceHistory[len - 1].timestamp + snapshotInterval) {
            return;
        }

        uint256 _totalAssets = totalAssets();
        uint256 _totalSupply = totalSupply();
        uint256 price = _totalSupply == 0 ? 1e18 : (_totalAssets * 1e18) / _totalSupply;

        sharePriceHistory.push(SharePriceSnapshot({
            price: price,
            timestamp: block.timestamp,
            totalAssets: _totalAssets,
            totalSupply: _totalSupply
        }));

        emit SharePriceSnapshotRecorded(price, _totalAssets, _totalSupply);
    }

    /**
     * @notice Unwrap wSSDC into SSDC
     * @param wSSDCAmount Amount of wSSDC to unwrap
     * @return SSDCAmount Amount of SSDC received
     */
    function unwrap(uint256 wSSDCAmount) external whenNotPaused returns (uint256 SSDCAmount) {
        SSDCAmount = redeem(wSSDCAmount, msg.sender, msg.sender);

        // Update deposit tracking
        if (totalDeposited >= SSDCAmount) {
            totalDeposited -= SSDCAmount;
        } else {
            totalDeposited = 0;
        }

        emit Unwrapped(msg.sender, wSSDCAmount, SSDCAmount);
        return SSDCAmount;
    }

    /**
     * @notice Get current share price (SSDC per wSSDC)
     * @return price Share price (1e18 = 1:1)
     * @dev Initially 1:1, increases as SSDC yield accrues
     */
    function getSharePrice() external view returns (uint256 price) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return 1e18; // 1:1 initially
        }
        return (totalAssets() * 1e18) / supply;
    }

    /**
     * @notice Get SSDC value of wSSDC holdings
     * @param account Account to query
     * @return value SSDC value
     */
    function getSSDCValue(address account) external view returns (uint256 value) {
        return convertToAssets(balanceOf(account));
    }

    /**
     * @notice Get wSSDC amount for given SSDC value
     * @param SSDCAmount SSDC amount
     * @return wSSDCAmount Equivalent wSSDC
     */
    function getWSSDCBySSDC(uint256 SSDCAmount) external view returns (uint256 wSSDCAmount) {
        return convertToShares(SSDCAmount);
    }

    /**
     * @notice Get SSDC amount for given wSSDC
     * @param wSSDCAmount wSSDC amount
     * @return SSDCAmount Equivalent SSDC
     */
    function getSSDCByWSSDC(uint256 wSSDCAmount) external view returns (uint256 SSDCAmount) {
        return convertToAssets(wSSDCAmount);
    }

    // =========================================================================
    // Batch Operations
    // =========================================================================

    /**
     * @notice Batch wrap SSDC for multiple recipients
     * @param recipients Array of recipients
     * @param amounts Array of SSDC amounts to wrap for each recipient
     * @return totalSSDC Total SSDC wrapped
     * @return totalWSSDC Total wSSDC minted
     */
    function batchWrap(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external whenNotPaused returns (uint256 totalSSDC, uint256 totalWSSDC) {
        if (recipients.length == 0) revert EmptyArray();
        if (recipients.length != amounts.length) revert ArrayLengthMismatch();
        if (recipients.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == address(0)) revert InvalidAddress();
            if (amounts[i] == 0) continue;

            // Check deposit cap
            if (depositCap > 0 && totalDeposited + amounts[i] > depositCap) {
                revert DepositCapExceeded();
            }

            uint256 shares = deposit(amounts[i], recipients[i]);
            totalDeposited += amounts[i];
            totalSSDC += amounts[i];
            totalWSSDC += shares;

            emit Wrapped(recipients[i], amounts[i], shares);
        }

        _maybeRecordSnapshot();
        emit BatchWrapped(msg.sender, totalSSDC, totalWSSDC, recipients.length);
        return (totalSSDC, totalWSSDC);
    }

    /**
     * @notice Batch unwrap wSSDC for caller
     * @param amounts Array of wSSDC amounts to unwrap
     * @return totalWSSDC Total wSSDC unwrapped
     * @return totalSSDC Total SSDC received
     */
    function batchUnwrap(
        uint256[] calldata amounts
    ) external whenNotPaused returns (uint256 totalWSSDC, uint256 totalSSDC) {
        if (amounts.length == 0) revert EmptyArray();
        if (amounts.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        for (uint256 i = 0; i < amounts.length; i++) {
            if (amounts[i] == 0) continue;

            uint256 assets = redeem(amounts[i], msg.sender, msg.sender);

            // Update deposit tracking
            if (totalDeposited >= assets) {
                totalDeposited -= assets;
            } else {
                totalDeposited = 0;
            }

            totalWSSDC += amounts[i];
            totalSSDC += assets;

            emit Unwrapped(msg.sender, amounts[i], assets);
        }

        emit BatchUnwrapped(msg.sender, totalWSSDC, totalSSDC, amounts.length);
        return (totalWSSDC, totalSSDC);
    }

    /**
     * @notice Batch query SSDC values for multiple accounts
     * @param accounts Accounts to query
     * @return values SSDC values for each account
     */
    function batchGetSSDCValues(
        address[] calldata accounts
    ) external view returns (uint256[] memory values) {
        values = new uint256[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            values[i] = convertToAssets(balanceOf(accounts[i]));
        }
        return values;
    }

    /**
     * @notice Batch query wSSDC balances for multiple accounts
     * @param accounts Accounts to query
     * @return balances wSSDC balances for each account
     */
    function batchBalanceOf(
        address[] calldata accounts
    ) external view returns (uint256[] memory balances) {
        balances = new uint256[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            balances[i] = balanceOf(accounts[i]);
        }
        return balances;
    }

    /**
     * @notice Preview batch wrap amounts
     * @param amounts SSDC amounts to wrap
     * @return shares wSSDC shares for each amount
     */
    function previewBatchWrap(
        uint256[] calldata amounts
    ) external view returns (uint256[] memory shares) {
        shares = new uint256[](amounts.length);
        for (uint256 i = 0; i < amounts.length; i++) {
            shares[i] = convertToShares(amounts[i]);
        }
        return shares;
    }

    /**
     * @notice Preview batch unwrap amounts
     * @param shareAmounts wSSDC amounts to unwrap
     * @return assets SSDC assets for each amount
     */
    function previewBatchUnwrap(
        uint256[] calldata shareAmounts
    ) external view returns (uint256[] memory assets) {
        assets = new uint256[](shareAmounts.length);
        for (uint256 i = 0; i < shareAmounts.length; i++) {
            assets[i] = convertToAssets(shareAmounts[i]);
        }
        return assets;
    }

    // =========================================================================
    // Admin Functions
    // =========================================================================

    /**
     * @notice Set deposit cap
     * @param newCap New deposit cap (0 = unlimited)
     */
    function setDepositCap(uint256 newCap) external onlyOwner {
        uint256 oldCap = depositCap;
        depositCap = newCap;
        emit DepositCapUpdated(oldCap, newCap);
    }

    /**
     * @notice Pause all wrap/unwrap operations
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause wrap/unwrap operations
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Set daily wrap limit per account
     * @param newLimit New daily limit (0 = unlimited)
     */
    function setDailyWrapLimit(uint256 newLimit) external onlyOwner {
        uint256 oldLimit = dailyWrapLimit;
        dailyWrapLimit = newLimit;
        emit DailyWrapLimitUpdated(oldLimit, newLimit);
    }

    /**
     * @notice Set wrap cooldown period
     * @param newCooldown New cooldown in seconds (0 = disabled)
     */
    function setWrapCooldown(uint256 newCooldown) external onlyOwner {
        uint256 oldCooldown = wrapCooldown;
        wrapCooldown = newCooldown;
        emit WrapCooldownUpdated(oldCooldown, newCooldown);
    }

    /**
     * @notice Set snapshot interval
     * @param newInterval New interval in seconds (0 = disabled)
     */
    function setSnapshotInterval(uint256 newInterval) external onlyOwner {
        uint256 oldInterval = snapshotInterval;
        snapshotInterval = newInterval;
        emit SnapshotIntervalUpdated(oldInterval, newInterval);
    }

    /**
     * @notice Manually trigger a share price snapshot
     */
    function triggerSnapshot() external onlyOwner {
        uint256 _totalAssets = totalAssets();
        uint256 _totalSupply = totalSupply();
        uint256 price = _totalSupply == 0 ? 1e18 : (_totalAssets * 1e18) / _totalSupply;

        sharePriceHistory.push(SharePriceSnapshot({
            price: price,
            timestamp: block.timestamp,
            totalAssets: _totalAssets,
            totalSupply: _totalSupply
        }));

        emit SharePriceSnapshotRecorded(price, _totalAssets, _totalSupply);
    }

    // =========================================================================
    // Monitoring Functions
    // =========================================================================

    /**
     * @notice Get vault status
     * @return assets Total SSDC assets in vault
     * @return supply Total wSSDC supply
     * @return sharePrice Current share price
     * @return cap Current deposit cap (0 = unlimited)
     * @return deposited Total deposited SSDC
     * @return remainingCap Remaining capacity for deposits
     * @return isPaused Whether vault is paused
     */
    function getVaultStatus() external view returns (
        uint256 assets,
        uint256 supply,
        uint256 sharePrice,
        uint256 cap,
        uint256 deposited,
        uint256 remainingCap,
        bool isPaused
    ) {
        uint256 _totalAssets = totalAssets();
        uint256 _totalSupply = totalSupply();
        uint256 _sharePrice = _totalSupply == 0 ? 1e18 : (_totalAssets * 1e18) / _totalSupply;
        uint256 _remainingCap = 0;
        if (depositCap > 0 && depositCap > totalDeposited) {
            _remainingCap = depositCap - totalDeposited;
        } else if (depositCap == 0) {
            _remainingCap = type(uint256).max; // Unlimited
        }

        return (
            _totalAssets,
            _totalSupply,
            _sharePrice,
            depositCap,
            totalDeposited,
            _remainingCap,
            paused()
        );
    }

    /**
     * @notice Get account details
     * @param account Account to query
     * @return wSSDCBalance wSSDC balance
     * @return SSDCValue Equivalent SSDC value
     * @return percentOfVault Percentage of vault owned (in basis points)
     */
    function getAccountDetails(address account) external view returns (
        uint256 wSSDCBalance,
        uint256 SSDCValue,
        uint256 percentOfVault
    ) {
        uint256 balance = balanceOf(account);
        uint256 value = convertToAssets(balance);
        uint256 supply = totalSupply();
        uint256 percent = supply > 0 ? (balance * 10000) / supply : 0;

        return (balance, value, percent);
    }

    /**
     * @notice Calculate yield accrued since initial 1:1 ratio
     * @return yieldBps Yield in basis points (100 = 1%)
     */
    function getAccruedYield() external view returns (uint256 yieldBps) {
        uint256 supply = totalSupply();
        if (supply == 0) return 0;

        uint256 sharePrice = (totalAssets() * 1e18) / supply;
        if (sharePrice <= 1e18) return 0;

        return ((sharePrice - 1e18) * 10000) / 1e18;
    }

    /**
     * @notice Maximum deposit considering cap
     * @param receiver Address receiving shares
     * @return maxAssets Maximum depositable assets
     */
    function maxDeposit(address receiver) public view override returns (uint256 maxAssets) {
        if (paused()) return 0;
        if (depositCap == 0) return type(uint256).max;
        if (totalDeposited >= depositCap) return 0;
        return depositCap - totalDeposited;
    }

    /**
     * @notice Maximum mint considering cap
     * @param receiver Address receiving shares
     * @return maxShares Maximum mintable shares
     */
    function maxMint(address receiver) public view override returns (uint256 maxShares) {
        if (paused()) return 0;
        uint256 maxAssets = maxDeposit(receiver);
        if (maxAssets == type(uint256).max) return type(uint256).max;
        return convertToShares(maxAssets);
    }

    /**
     * @notice Maximum withdraw when paused returns 0
     * @param owner Address to withdraw from
     * @return maxAssets Maximum withdrawable assets
     */
    function maxWithdraw(address owner) public view override returns (uint256 maxAssets) {
        if (paused()) return 0;
        return convertToAssets(balanceOf(owner));
    }

    /**
     * @notice Maximum redeem when paused returns 0
     * @param owner Address to redeem from
     * @return maxShares Maximum redeemable shares
     */
    function maxRedeem(address owner) public view override returns (uint256 maxShares) {
        if (paused()) return 0;
        return balanceOf(owner);
    }

    // =========================================================================
    // Analytics Functions
    // =========================================================================

    /**
     * @notice Get rate limiting status for an account
     * @param account Account to check
     * @return remainingDaily Remaining daily wrap capacity
     * @return cooldownRemaining Seconds until cooldown expires (0 = ready)
     * @return canWrap Whether account can wrap right now
     */
    function getRateLimitStatus(address account) external view returns (
        uint256 remainingDaily,
        uint256 cooldownRemaining,
        bool canWrap
    ) {
        // Calculate remaining daily
        if (dailyWrapLimit == 0) {
            remainingDaily = type(uint256).max;
        } else {
            uint256 currentDay = block.timestamp / 1 days;
            uint256 usedToday = lastWrapDay[account] == currentDay ? dailyWrapAmount[account] : 0;
            remainingDaily = dailyWrapLimit > usedToday ? dailyWrapLimit - usedToday : 0;
        }

        // Calculate cooldown
        if (wrapCooldown == 0) {
            cooldownRemaining = 0;
        } else {
            uint256 cooldownEnd = lastWrapTime[account] + wrapCooldown;
            cooldownRemaining = cooldownEnd > block.timestamp ? cooldownEnd - block.timestamp : 0;
        }

        canWrap = !paused() && remainingDaily > 0 && cooldownRemaining == 0;
        return (remainingDaily, cooldownRemaining, canWrap);
    }

    /**
     * @notice Get share price history length
     * @return count Number of snapshots
     */
    function getSnapshotCount() external view returns (uint256 count) {
        return sharePriceHistory.length;
    }

    /**
     * @notice Get share price history in range
     * @param startIndex Starting index
     * @param count Number of snapshots to return
     * @return prices Price array
     * @return timestamps Timestamp array
     */
    function getSharePriceHistoryRange(
        uint256 startIndex,
        uint256 count
    ) external view returns (
        uint256[] memory prices,
        uint256[] memory timestamps
    ) {
        uint256 len = sharePriceHistory.length;
        if (startIndex >= len) {
            return (new uint256[](0), new uint256[](0));
        }

        uint256 endIndex = startIndex + count;
        if (endIndex > len) endIndex = len;
        uint256 resultCount = endIndex - startIndex;

        prices = new uint256[](resultCount);
        timestamps = new uint256[](resultCount);

        for (uint256 i = 0; i < resultCount; i++) {
            SharePriceSnapshot storage snap = sharePriceHistory[startIndex + i];
            prices[i] = snap.price;
            timestamps[i] = snap.timestamp;
        }

        return (prices, timestamps);
    }

    /**
     * @notice Get latest share price snapshots
     * @param count Number of latest snapshots to return
     * @return prices Price array (newest first)
     * @return timestamps Timestamp array (newest first)
     */
    function getLatestSnapshots(uint256 count) external view returns (
        uint256[] memory prices,
        uint256[] memory timestamps
    ) {
        uint256 len = sharePriceHistory.length;
        if (len == 0 || count == 0) {
            return (new uint256[](0), new uint256[](0));
        }

        uint256 resultCount = count > len ? len : count;
        prices = new uint256[](resultCount);
        timestamps = new uint256[](resultCount);

        for (uint256 i = 0; i < resultCount; i++) {
            SharePriceSnapshot storage snap = sharePriceHistory[len - 1 - i];
            prices[i] = snap.price;
            timestamps[i] = snap.timestamp;
        }

        return (prices, timestamps);
    }

    /**
     * @notice Calculate yield over period using snapshots
     * @param periodSeconds Period in seconds to calculate yield over
     * @return yieldBps Yield in basis points over the period
     * @return annualizedBps Annualized yield in basis points
     */
    function getYieldOverPeriod(uint256 periodSeconds) external view returns (
        uint256 yieldBps,
        uint256 annualizedBps
    ) {
        uint256 len = sharePriceHistory.length;
        if (len < 2) return (0, 0);

        uint256 currentPrice = sharePriceHistory[len - 1].price;
        uint256 targetTime = block.timestamp - periodSeconds;

        // Find snapshot closest to target time
        uint256 startPrice = currentPrice;
        uint256 actualPeriod = 0;

        for (uint256 i = len - 1; i > 0; i--) {
            if (sharePriceHistory[i - 1].timestamp <= targetTime) {
                startPrice = sharePriceHistory[i - 1].price;
                actualPeriod = sharePriceHistory[len - 1].timestamp - sharePriceHistory[i - 1].timestamp;
                break;
            }
        }

        if (actualPeriod == 0 || startPrice == 0) return (0, 0);

        // Calculate yield
        if (currentPrice <= startPrice) return (0, 0);
        yieldBps = ((currentPrice - startPrice) * 10000) / startPrice;

        // Annualize
        uint256 secondsPerYear = 365 days;
        annualizedBps = (yieldBps * secondsPerYear) / actualPeriod;

        return (yieldBps, annualizedBps);
    }

    /**
     * @notice Get comprehensive vault statistics
     * @return assets Total SSDC assets
     * @return supply Total wSSDC supply
     * @return sharePrice Current share price
     * @return yieldBps Total yield in basis points
     * @return snapshotCount Number of price snapshots
     * @return dailyLimit Current daily wrap limit
     * @return cooldown Current cooldown period
     */
    function getVaultStatistics() external view returns (
        uint256 assets,
        uint256 supply,
        uint256 sharePrice,
        uint256 yieldBps,
        uint256 snapshotCount,
        uint256 dailyLimit,
        uint256 cooldown
    ) {
        uint256 _totalAssets = totalAssets();
        uint256 _totalSupply = totalSupply();
        uint256 _sharePrice = _totalSupply == 0 ? 1e18 : (_totalAssets * 1e18) / _totalSupply;

        uint256 _yieldBps = 0;
        if (_sharePrice > 1e18) {
            _yieldBps = ((_sharePrice - 1e18) * 10000) / 1e18;
        }

        return (
            _totalAssets,
            _totalSupply,
            _sharePrice,
            _yieldBps,
            sharePriceHistory.length,
            dailyWrapLimit,
            wrapCooldown
        );
    }

    /**
     * @notice Check if account can wrap specified amount
     * @param account Account to check
     * @param amount Amount to wrap
     * @return canWrap Whether wrap would succeed
     * @return reason Failure reason code (0=ok, 1=paused, 2=cap, 3=daily, 4=cooldown)
     */
    function canAccountWrap(
        address account,
        uint256 amount
    ) external view returns (bool canWrap, uint8 reason) {
        if (paused()) return (false, 1);

        // Check cap
        if (depositCap > 0 && totalDeposited + amount > depositCap) {
            return (false, 2);
        }

        // Check daily limit
        if (dailyWrapLimit > 0) {
            uint256 currentDay = block.timestamp / 1 days;
            uint256 usedToday = lastWrapDay[account] == currentDay ? dailyWrapAmount[account] : 0;
            if (usedToday + amount > dailyWrapLimit) {
                return (false, 3);
            }
        }

        // Check cooldown
        if (wrapCooldown > 0 && lastWrapTime[account] + wrapCooldown > block.timestamp) {
            return (false, 4);
        }

        return (true, 0);
    }

    // =========================================================================
    // Upgrade
    // =========================================================================

    /**
     * @dev Authorize upgrade (owner only)
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}