// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./interfaces/ITreasuryVault.sol";
import "./interfaces/ITokenRegistry.sol";
import "./interfaces/INAVOracle.sol";
import "./interfaces/IssUSD.sol";

/**
 * @title TreasuryVault
 * @notice Manages collateral deposits and ssUSD minting/redemption
 * @dev
 * Flow:
 * 1. User deposits USDC/USDT
 * 2. Vault mints ssUSD shares (1:1 for stables)
 * 3. User requests redemption
 * 4. After delay, redemption is processed
 * 5. User receives collateral back
 */
contract TreasuryVault is
    ITreasuryVault,
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    // =========================================================================
    // Constants
    // =========================================================================

    /// @notice Basis points denominator
    uint256 public constant BPS_DENOMINATOR = 10000;

    /// @notice Maximum fee (1%)
    uint256 public constant MAX_FEE_BPS = 100;

    /// @notice Precision for calculations
    uint256 public constant PRECISION = 1e18;

    /// @notice Minimum deposit amount ($1)
    uint256 public constant MIN_DEPOSIT = 1e18;

    // =========================================================================
    // Storage
    // =========================================================================

    /// @notice Token registry
    ITokenRegistry public tokenRegistry;

    /// @notice NAV oracle
    INAVOracle public navOracle;

    /// @notice ssUSD token
    IssUSD public ssUSD;

    /// @notice Collateral balances per token
    mapping(address => uint256) public collateralBalances;

    /// @notice Total collateral value in USD (18 decimals)
    uint256 public totalCollateralValue;

    /// @notice Redemption requests
    RedemptionRequest[] private _redemptionRequests;

    /// @notice User redemption request IDs
    mapping(address => uint256[]) private _userRedemptions;

    /// @notice Pending redemption count
    uint256 public pendingRedemptionCount;

    /// @notice Shares locked for pending redemptions (burned at request time for accurate accounting)
    /// Maps requestId => shares that were burned
    mapping(uint256 => uint256) public redemptionShares;

    /// @notice Total shares pending redemption (for NAV calculations)
    uint256 public totalPendingRedemptionShares;

    /// @notice Mint fee in basis points
    uint256 public mintFee;

    /// @notice Redeem fee in basis points
    uint256 public redeemFee;

    /// @notice Redemption delay in seconds
    uint256 public redemptionDelay;

    /// @notice Deposits paused
    bool public depositsPaused;

    /// @notice Redemptions paused
    bool public redemptionsPaused;

    /// @notice Authorized operators
    mapping(address => bool) public operators;

    // =========================================================================
    // Errors
    // =========================================================================

    error NotApprovedCollateral();
    error InsufficientDeposit();
    error DepositsArePaused();
    error RedemptionsArePaused();
    error RedemptionNotFound();
    error RedemptionNotReady();
    error RedemptionAlreadyProcessed();
    error NotRequestOwner();
    error FeeTooHigh();
    error InsufficientCollateral();
    error NotOperator();
    error InvalidAmount();

    // =========================================================================
    // Modifiers
    // =========================================================================

    modifier onlyOperator() {
        if (!operators[msg.sender] && msg.sender != owner()) {
            revert NotOperator();
        }
        _;
    }

    modifier whenDepositsNotPaused() {
        if (depositsPaused) revert DepositsArePaused();
        _;
    }

    modifier whenRedemptionsNotPaused() {
        if (redemptionsPaused) revert RedemptionsArePaused();
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
     * @notice Initialize the treasury vault
     * @param owner_ Owner address
     * @param tokenRegistry_ Token registry address
     * @param navOracle_ NAV oracle address
     * @param ssUSD_ ssUSD token address
     */
    function initialize(
        address owner_,
        address tokenRegistry_,
        address navOracle_,
        address ssUSD_
    ) public initializer {
        __Ownable_init(owner_);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        tokenRegistry = ITokenRegistry(tokenRegistry_);
        navOracle = INAVOracle(navOracle_);
        ssUSD = IssUSD(ssUSD_);

        // Default settings
        mintFee = 0; // 0%
        redeemFee = 10; // 0.1%
        redemptionDelay = 1 hours;
    }

    // =========================================================================
    // Deposit
    // =========================================================================

    /**
     * @notice Deposit collateral and mint ssUSD
     * @param collateralToken Token to deposit (USDC, USDT)
     * @param amount Amount of collateral (in token decimals)
     * @param recipient Recipient of ssUSD
     * @return ssUSDMinted Amount of ssUSD minted
     */
    function deposit(
        address collateralToken,
        uint256 amount,
        address recipient
    ) external nonReentrant whenDepositsNotPaused returns (uint256 ssUSDMinted) {
        // Validate collateral
        if (!tokenRegistry.isApprovedCollateral(collateralToken)) {
            revert NotApprovedCollateral();
        }

        // Normalize to 18 decimals
        uint8 tokenDecimals = IERC20Metadata(collateralToken).decimals();
        uint256 normalizedAmount = _normalize(amount, tokenDecimals);

        if (normalizedAmount < MIN_DEPOSIT) {
            revert InsufficientDeposit();
        }

        // Transfer collateral
        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), amount);

        // Update collateral tracking
        collateralBalances[collateralToken] += amount;
        totalCollateralValue += normalizedAmount;

        // Calculate ssUSD to mint (1:1 for stables, minus fee)
        uint256 feeAmount = (normalizedAmount * mintFee) / BPS_DENOMINATOR;
        ssUSDMinted = normalizedAmount - feeAmount;

        // Convert to shares at current NAV
        uint256 sharesToMint = ssUSD.getSharesByAmount(ssUSDMinted);

        // Mint ssUSD shares
        ssUSD.mintShares(recipient, sharesToMint);

        emit Deposited(msg.sender, collateralToken, amount, ssUSDMinted, recipient);

        return ssUSDMinted;
    }

    // =========================================================================
    // Redemption
    // =========================================================================

    /**
     * @notice Request redemption of ssUSD for collateral
     * @param ssUSDAmount Amount of ssUSD to redeem
     * @param preferredCollateral Preferred collateral token
     * @return requestId Redemption request ID
     *
     * SECURITY FIX: Shares are now burned at request time to prevent
     * manipulation via NAV changes between request and processing.
     * The ssUSD amount stored in the request is the value at request time,
     * and the shares burned are tracked separately for accurate accounting.
     */
    function requestRedemption(
        uint256 ssUSDAmount,
        address preferredCollateral
    ) external nonReentrant whenRedemptionsNotPaused returns (uint256 requestId) {
        if (ssUSDAmount == 0) revert InvalidAmount();

        // Check user has sufficient balance
        uint256 userBalance = IERC20(address(ssUSD)).balanceOf(msg.sender);
        if (userBalance < ssUSDAmount) revert InvalidAmount();

        // Calculate shares to burn at current NAV
        // CRITICAL: Lock in the share count now to prevent NAV manipulation attacks
        uint256 sharesToBurn = ssUSD.getSharesByAmount(ssUSDAmount);

        // Create redemption request BEFORE burning to get the ID
        requestId = _redemptionRequests.length;

        // SECURITY FIX: Burn shares immediately at request time
        // This locks in the redemption value and prevents:
        // 1. Users redeeming more than their share if NAV increases
        // 2. Protocol losing funds if NAV decreases before processing
        // 3. Front-running attacks on NAV oracle updates
        IERC20(address(ssUSD)).safeTransferFrom(msg.sender, address(this), ssUSDAmount);
        ssUSD.burnShares(address(this), sharesToBurn);

        // Track the shares burned for this redemption
        redemptionShares[requestId] = sharesToBurn;
        totalPendingRedemptionShares += sharesToBurn;

        _redemptionRequests.push(RedemptionRequest({
            id: requestId,
            requester: msg.sender,
            ssUSDAmount: ssUSDAmount,  // Store original amount for reference/events
            collateralToken: preferredCollateral,
            requestedAt: block.timestamp,
            processedAt: 0,
            status: RedemptionStatus.PENDING
        }));

        _userRedemptions[msg.sender].push(requestId);
        pendingRedemptionCount++;

        emit RedemptionRequested(requestId, msg.sender, ssUSDAmount, preferredCollateral);

        return requestId;
    }

    /**
     * @notice Cancel a pending redemption
     * @param requestId Redemption request ID
     *
     * SECURITY FIX: Since shares are now burned at request time,
     * cancellation must re-mint shares back to the user.
     */
    function cancelRedemption(uint256 requestId) external nonReentrant {
        RedemptionRequest storage request = _redemptionRequests[requestId];

        if (request.requester != msg.sender) revert NotRequestOwner();
        if (request.status != RedemptionStatus.PENDING) revert RedemptionAlreadyProcessed();

        request.status = RedemptionStatus.CANCELLED;
        pendingRedemptionCount--;

        // Get the shares that were burned at request time
        uint256 sharesToRestore = redemptionShares[requestId];

        // Clear the tracked shares
        delete redemptionShares[requestId];
        totalPendingRedemptionShares -= sharesToRestore;

        // Re-mint shares back to user (shares were burned at request time)
        // This restores the user's position at the current NAV
        ssUSD.mintShares(msg.sender, sharesToRestore);

        emit RedemptionCancelled(requestId, msg.sender);
    }

    /**
     * @notice Process a redemption request
     * @param requestId Request ID to process
     */
    function processRedemption(uint256 requestId) external nonReentrant {
        RedemptionRequest storage request = _redemptionRequests[requestId];

        if (request.status != RedemptionStatus.PENDING) revert RedemptionAlreadyProcessed();
        if (block.timestamp < request.requestedAt + redemptionDelay) revert RedemptionNotReady();

        _processRedemption(request);
    }

    /**
     * @notice Process multiple redemptions
     * @param requestIds Request IDs to process
     */
    function processBatchRedemptions(
        uint256[] calldata requestIds
    ) external onlyOperator nonReentrant {
        for (uint256 i = 0; i < requestIds.length; i++) {
            RedemptionRequest storage request = _redemptionRequests[requestIds[i]];

            if (request.status == RedemptionStatus.PENDING &&
                block.timestamp >= request.requestedAt + redemptionDelay) {
                _processRedemption(request);
            }
        }
    }

    /**
     * @dev Internal redemption processing
     *
     * SECURITY FIX: Shares were already burned at request time.
     * This function only handles collateral transfer and state cleanup.
     * The collateral value is based on the ssUSD amount at request time,
     * ensuring consistent accounting regardless of NAV changes.
     */
    function _processRedemption(RedemptionRequest storage request) internal {
        request.status = RedemptionStatus.PROCESSING;

        // Calculate collateral to return (minus fee)
        // Uses the ssUSD amount that was locked at request time
        uint256 feeAmount = (request.ssUSDAmount * redeemFee) / BPS_DENOMINATOR;
        uint256 collateralValue = request.ssUSDAmount - feeAmount;

        // Get preferred collateral or use any available
        address collateralToken = request.collateralToken;
        if (collateralToken == address(0) || collateralBalances[collateralToken] == 0) {
            // Find any available collateral
            address[] memory collaterals = tokenRegistry.getCollateralTokens();
            for (uint256 i = 0; i < collaterals.length; i++) {
                if (collateralBalances[collaterals[i]] > 0) {
                    collateralToken = collaterals[i];
                    break;
                }
            }
        }

        // Denormalize to token decimals
        uint8 tokenDecimals = IERC20Metadata(collateralToken).decimals();
        uint256 collateralAmount = _denormalize(collateralValue, tokenDecimals);

        if (collateralBalances[collateralToken] < collateralAmount) {
            revert InsufficientCollateral();
        }

        // Update state
        collateralBalances[collateralToken] -= collateralAmount;
        totalCollateralValue -= collateralValue;
        request.processedAt = block.timestamp;
        request.status = RedemptionStatus.COMPLETED;
        pendingRedemptionCount--;

        // SECURITY FIX: Shares were already burned at request time
        // Just clean up the tracking - do NOT burn again
        uint256 burnedShares = redemptionShares[request.id];
        delete redemptionShares[request.id];
        totalPendingRedemptionShares -= burnedShares;

        // Transfer collateral to user
        IERC20(collateralToken).safeTransfer(request.requester, collateralAmount);

        emit RedemptionProcessed(request.id, request.requester, collateralAmount);
    }

    // =========================================================================
    // View Functions
    // =========================================================================

    /**
     * @notice Get collateral balance for a token
     */
    function getCollateralBalance(address token) external view returns (uint256) {
        return collateralBalances[token];
    }

    /**
     * @notice Get total collateral value
     */
    function getTotalCollateralValue() external view returns (uint256) {
        return totalCollateralValue;
    }

    /**
     * @notice Get collateral ratio
     * @return ratio Collateral ratio (1e18 = 100%)
     */
    function getCollateralRatio() external view returns (uint256 ratio) {
        uint256 totalSupply = IERC20(address(ssUSD)).totalSupply();
        if (totalSupply == 0) {
            return type(uint256).max;
        }
        return (totalCollateralValue * PRECISION) / totalSupply;
    }

    /**
     * @notice Get redemption request
     */
    function getRedemptionRequest(
        uint256 requestId
    ) external view returns (RedemptionRequest memory) {
        return _redemptionRequests[requestId];
    }

    /**
     * @notice Get pending redemption count
     */
    function getPendingRedemptionCount() external view returns (uint256) {
        return pendingRedemptionCount;
    }

    /**
     * @notice Get user's redemption requests
     */
    function getUserRedemptions(
        address user
    ) external view returns (uint256[] memory) {
        return _userRedemptions[user];
    }

    // =========================================================================
    // Admin Functions
    // =========================================================================

    /**
     * @notice Set fees
     */
    function setFees(uint256 mintFee_, uint256 redeemFee_) external onlyOwner {
        if (mintFee_ > MAX_FEE_BPS || redeemFee_ > MAX_FEE_BPS) {
            revert FeeTooHigh();
        }
        mintFee = mintFee_;
        redeemFee = redeemFee_;
        emit FeesUpdated(mintFee_, redeemFee_);
    }

    /**
     * @notice Set redemption delay
     */
    function setRedemptionDelay(uint256 delay_) external onlyOwner {
        redemptionDelay = delay_;
    }

    /**
     * @notice Pause deposits
     */
    function pauseDeposits(bool paused) external onlyOwner {
        depositsPaused = paused;
        emit DepositsPaused(paused);
    }

    /**
     * @notice Pause redemptions
     */
    function pauseRedemptions(bool paused) external onlyOwner {
        redemptionsPaused = paused;
        emit RedemptionsPaused(paused);
    }

    /**
     * @notice Set operator
     */
    function setOperator(address operator, bool authorized) external onlyOwner {
        operators[operator] = authorized;
        emit OperatorUpdated(operator, authorized);
    }

    /**
     * @notice Emergency withdraw (timelock enforced via owner)
     */
    function emergencyWithdraw(
        address token,
        uint256 amount,
        address recipient
    ) external onlyOwner {
        IERC20(token).safeTransfer(recipient, amount);

        // Update tracking if it's collateral
        if (collateralBalances[token] >= amount) {
            uint8 decimals = IERC20Metadata(token).decimals();
            uint256 normalizedAmount = _normalize(amount, decimals);
            collateralBalances[token] -= amount;
            totalCollateralValue -= normalizedAmount;
        }

        emit EmergencyWithdrawal(token, amount, recipient);
    }

    // =========================================================================
    // Internal Functions
    // =========================================================================

    /**
     * @dev Normalize amount to 18 decimals
     */
    function _normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        if (decimals < 18) {
            return amount * 10 ** (18 - decimals);
        }
        return amount / 10 ** (decimals - 18);
    }

    /**
     * @dev Denormalize from 18 decimals to token decimals
     */
    function _denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        if (decimals < 18) {
            return amount / 10 ** (18 - decimals);
        }
        return amount * 10 ** (decimals - 18);
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
