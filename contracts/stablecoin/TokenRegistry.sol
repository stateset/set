// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/ITokenRegistry.sol";

/**
 * @title TokenRegistry
 * @notice Manages verified tokens on Set Chain
 * @dev Provides a curated token list with collateral whitelist for ssUSD
 */
contract TokenRegistry is
    ITokenRegistry,
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // =========================================================================
    // Storage
    // =========================================================================

    /// @notice Token info by address
    mapping(address => TokenInfo) private _tokens;

    /// @notice Whether token is registered
    mapping(address => bool) private _isRegistered;

    /// @notice List of all registered tokens
    address[] private _tokenList;

    /// @notice Approved collateral tokens
    mapping(address => bool) private _approvedCollateral;

    /// @notice Token index in list (for removal)
    mapping(address => uint256) private _tokenIndex;

    // =========================================================================
    // Errors
    // =========================================================================

    error TokenAlreadyRegistered();
    error TokenNotRegistered();
    error InvalidTokenAddress();
    error InvalidDecimals();

    // =========================================================================
    // Initialization
    // =========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the registry
     * @param owner_ Owner address
     */
    function initialize(address owner_) public initializer {
        __Ownable_init(owner_);
        __UUPSUpgradeable_init();
    }

    // =========================================================================
    // Registration
    // =========================================================================

    /**
     * @notice Register a new token
     */
    function registerToken(
        address token,
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        TokenCategory category,
        TrustLevel trustLevel,
        bool isCollateral_,
        string calldata logoURI
    ) external onlyOwner {
        if (token == address(0)) revert InvalidTokenAddress();
        if (_isRegistered[token]) revert TokenAlreadyRegistered();
        if (decimals > 18) revert InvalidDecimals();

        _tokens[token] = TokenInfo({
            tokenAddress: token,
            name: name,
            symbol: symbol,
            decimals: decimals,
            logoURI: logoURI,
            category: category,
            trustLevel: trustLevel,
            isCollateral: isCollateral_,
            addedAt: block.timestamp,
            updatedAt: block.timestamp
        });

        _isRegistered[token] = true;
        _tokenIndex[token] = _tokenList.length;
        _tokenList.push(token);

        if (isCollateral_) {
            _approvedCollateral[token] = true;
        }

        emit TokenRegistered(token, name, symbol, category, trustLevel);
    }

    /**
     * @notice Update token metadata
     */
    function updateTokenMetadata(
        address token,
        string calldata name,
        string calldata symbol,
        string calldata logoURI
    ) external onlyOwner {
        if (!_isRegistered[token]) revert TokenNotRegistered();

        TokenInfo storage info = _tokens[token];
        info.name = name;
        info.symbol = symbol;
        info.logoURI = logoURI;
        info.updatedAt = block.timestamp;

        emit TokenUpdated(token, "metadata");
    }

    /**
     * @notice Set collateral status
     */
    function setCollateralStatus(address token, bool status) external onlyOwner {
        if (!_isRegistered[token]) revert TokenNotRegistered();

        _tokens[token].isCollateral = status;
        _tokens[token].updatedAt = block.timestamp;
        _approvedCollateral[token] = status;

        emit CollateralStatusChanged(token, status);
    }

    /**
     * @notice Set token category
     */
    function setTokenCategory(address token, TokenCategory category) external onlyOwner {
        if (!_isRegistered[token]) revert TokenNotRegistered();

        _tokens[token].category = category;
        _tokens[token].updatedAt = block.timestamp;

        emit TokenUpdated(token, "category");
    }

    /**
     * @notice Set trust level
     */
    function setTrustLevel(address token, TrustLevel level) external onlyOwner {
        if (!_isRegistered[token]) revert TokenNotRegistered();

        _tokens[token].trustLevel = level;
        _tokens[token].updatedAt = block.timestamp;

        emit TokenUpdated(token, "trustLevel");
    }

    /**
     * @notice Remove token from registry
     */
    function removeToken(address token) external onlyOwner {
        if (!_isRegistered[token]) revert TokenNotRegistered();

        // Remove from list (swap with last)
        uint256 index = _tokenIndex[token];
        uint256 lastIndex = _tokenList.length - 1;

        if (index != lastIndex) {
            address lastToken = _tokenList[lastIndex];
            _tokenList[index] = lastToken;
            _tokenIndex[lastToken] = index;
        }

        _tokenList.pop();
        delete _tokenIndex[token];
        delete _tokens[token];
        delete _isRegistered[token];
        delete _approvedCollateral[token];

        emit TokenRemoved(token);
    }

    // =========================================================================
    // View Functions
    // =========================================================================

    /**
     * @notice Get token info
     */
    function getTokenInfo(address token) external view returns (TokenInfo memory) {
        if (!_isRegistered[token]) revert TokenNotRegistered();
        return _tokens[token];
    }

    /**
     * @notice Get all registered tokens
     */
    function getAllTokens() external view returns (address[] memory) {
        return _tokenList;
    }

    /**
     * @notice Get tokens by category
     */
    function getTokensByCategory(
        TokenCategory category
    ) external view returns (address[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < _tokenList.length; i++) {
            if (_tokens[_tokenList[i]].category == category) {
                count++;
            }
        }

        address[] memory result = new address[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < _tokenList.length; i++) {
            if (_tokens[_tokenList[i]].category == category) {
                result[index] = _tokenList[i];
                index++;
            }
        }

        return result;
    }

    /**
     * @notice Get approved collateral tokens
     */
    function getCollateralTokens() external view returns (address[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < _tokenList.length; i++) {
            if (_approvedCollateral[_tokenList[i]]) {
                count++;
            }
        }

        address[] memory result = new address[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < _tokenList.length; i++) {
            if (_approvedCollateral[_tokenList[i]]) {
                result[index] = _tokenList[i];
                index++;
            }
        }

        return result;
    }

    /**
     * @notice Check if token is registered
     */
    function isRegistered(address token) external view returns (bool) {
        return _isRegistered[token];
    }

    /**
     * @notice Check if token is approved collateral
     */
    function isApprovedCollateral(address token) external view returns (bool) {
        return _approvedCollateral[token];
    }

    /**
     * @notice Get token count
     */
    function tokenCount() external view returns (uint256) {
        return _tokenList.length;
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
