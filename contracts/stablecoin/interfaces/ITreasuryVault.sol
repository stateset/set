// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ITreasuryVault
 * @notice Interface for ssUSD treasury and collateral management
 */
interface ITreasuryVault {
    // =========================================================================
    // Types
    // =========================================================================

    enum RedemptionStatus {
        PENDING,
        PROCESSING,
        COMPLETED,
        CANCELLED
    }

    struct RedemptionRequest {
        uint256 id;
        address requester;
        uint256 ssUSDAmount;
        address collateralToken;
        uint256 requestedAt;
        uint256 processedAt;
        RedemptionStatus status;
    }

    // =========================================================================
    // Events
    // =========================================================================

    event Deposited(
        address indexed depositor,
        address indexed collateralToken,
        uint256 collateralAmount,
        uint256 ssUSDMinted,
        address indexed recipient
    );

    event RedemptionRequested(
        uint256 indexed requestId,
        address indexed requester,
        uint256 ssUSDAmount,
        address collateralToken
    );

    event RedemptionProcessed(
        uint256 indexed requestId,
        address indexed requester,
        uint256 collateralAmount
    );

    event RedemptionCancelled(uint256 indexed requestId, address indexed requester);

    event FeesUpdated(uint256 mintFee, uint256 redeemFee);

    event DepositsPaused(bool paused);

    event RedemptionsPaused(bool paused);

    event EmergencyWithdrawal(address indexed token, uint256 amount, address indexed recipient);

    event OperatorUpdated(address indexed operator, bool authorized);

    // =========================================================================
    // User Functions
    // =========================================================================

    /**
     * @notice Deposit collateral and mint ssUSD
     * @param collateralToken Token to deposit (USDC, USDT)
     * @param amount Amount of collateral
     * @param recipient Recipient of ssUSD
     * @return ssUSDMinted Amount of ssUSD minted
     */
    function deposit(
        address collateralToken,
        uint256 amount,
        address recipient
    ) external returns (uint256 ssUSDMinted);

    /**
     * @notice Request redemption of ssUSD for collateral
     * @param ssUSDAmount Amount of ssUSD to redeem
     * @param preferredCollateral Preferred collateral token
     * @return requestId Redemption request ID
     */
    function requestRedemption(
        uint256 ssUSDAmount,
        address preferredCollateral
    ) external returns (uint256 requestId);

    /**
     * @notice Cancel a pending redemption
     * @param requestId Redemption request ID
     */
    function cancelRedemption(uint256 requestId) external;

    // =========================================================================
    // Processing Functions
    // =========================================================================

    /**
     * @notice Process a redemption request
     * @param requestId Request ID to process
     */
    function processRedemption(uint256 requestId) external;

    /**
     * @notice Process multiple redemptions
     * @param requestIds Request IDs to process
     */
    function processBatchRedemptions(uint256[] calldata requestIds) external;

    // =========================================================================
    // View Functions
    // =========================================================================

    function getCollateralBalance(address token) external view returns (uint256);

    function getTotalCollateralValue() external view returns (uint256);

    function getCollateralRatio() external view returns (uint256);

    function getRedemptionRequest(uint256 requestId) external view returns (RedemptionRequest memory);

    function getPendingRedemptionCount() external view returns (uint256);

    function mintFee() external view returns (uint256);

    function redeemFee() external view returns (uint256);

    function redemptionDelay() external view returns (uint256);

    function depositsPaused() external view returns (bool);

    function redemptionsPaused() external view returns (bool);

    // =========================================================================
    // Admin Functions
    // =========================================================================

    function setFees(uint256 mintFee_, uint256 redeemFee_) external;

    function setRedemptionDelay(uint256 delay_) external;

    function pauseDeposits(bool paused) external;

    function pauseRedemptions(bool paused) external;

    function setOperator(address operator, bool authorized) external;

    function emergencyWithdraw(
        address token,
        uint256 amount,
        address recipient
    ) external;
}
