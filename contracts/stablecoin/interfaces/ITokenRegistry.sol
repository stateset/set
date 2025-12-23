// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ITokenRegistry
 * @notice Interface for Set Chain's verified token registry
 */
interface ITokenRegistry {
    // =========================================================================
    // Types
    // =========================================================================

    enum TokenCategory {
        NATIVE,      // Native chain tokens (ETH, ssUSD)
        BRIDGED,     // Bridged from L1 (USDC, USDT)
        STABLECOIN,  // Stablecoins
        VERIFIED,    // Verified project tokens
        UNKNOWN      // Unverified tokens
    }

    enum TrustLevel {
        TRUSTED,     // Core protocol tokens
        VERIFIED,    // Audited third-party tokens
        UNVERIFIED   // Community-added tokens
    }

    struct TokenInfo {
        address tokenAddress;
        string name;
        string symbol;
        uint8 decimals;
        string logoURI;
        TokenCategory category;
        TrustLevel trustLevel;
        bool isCollateral;
        uint256 addedAt;
        uint256 updatedAt;
    }

    // =========================================================================
    // Events
    // =========================================================================

    event TokenRegistered(
        address indexed token,
        string name,
        string symbol,
        TokenCategory category,
        TrustLevel trustLevel
    );

    event TokenUpdated(address indexed token, string field);

    event TokenRemoved(address indexed token);

    event CollateralStatusChanged(address indexed token, bool isCollateral);

    // =========================================================================
    // Functions
    // =========================================================================

    function registerToken(
        address token,
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        TokenCategory category,
        TrustLevel trustLevel,
        bool isCollateral,
        string calldata logoURI
    ) external;

    function updateTokenMetadata(
        address token,
        string calldata name,
        string calldata symbol,
        string calldata logoURI
    ) external;

    function setCollateralStatus(address token, bool status) external;

    function setTokenCategory(address token, TokenCategory category) external;

    function setTrustLevel(address token, TrustLevel level) external;

    function removeToken(address token) external;

    function getTokenInfo(address token) external view returns (TokenInfo memory);

    function getAllTokens() external view returns (address[] memory);

    function getTokensByCategory(TokenCategory category) external view returns (address[] memory);

    function getCollateralTokens() external view returns (address[] memory);

    function isRegistered(address token) external view returns (bool);

    function isApprovedCollateral(address token) external view returns (bool);

    function tokenCount() external view returns (uint256);
}
