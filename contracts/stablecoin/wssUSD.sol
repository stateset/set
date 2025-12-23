// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IssUSD.sol";

/**
 * @title wssUSD (Wrapped Set Stablecoin USD)
 * @notice Non-rebasing wrapper for ssUSD using ERC4626 vault standard
 * @dev
 * - ssUSD rebases (balance changes with yield)
 * - wssUSD does NOT rebase (balance stable, value accrues)
 *
 * This makes wssUSD compatible with DeFi protocols that don't handle rebasing tokens:
 * - AMMs (Uniswap, etc.)
 * - Lending protocols (Aave, Compound)
 * - Yield aggregators
 *
 * Mechanics:
 * - Deposit ssUSD → Receive wssUSD shares
 * - As ssUSD rebases, wssUSD share price increases
 * - wssUSD balance stays constant, but represents more ssUSD over time
 */
contract wssUSD is
    Initializable,
    ERC4626Upgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // =========================================================================
    // Events
    // =========================================================================

    event Wrapped(address indexed account, uint256 ssUSDAmount, uint256 wssUSDAmount);
    event Unwrapped(address indexed account, uint256 wssUSDAmount, uint256 ssUSDAmount);
    // =========================================================================
    // Initialization
    // =========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize wssUSD
     * @param owner_ Owner address
     * @param ssUSD_ ssUSD token address
     */
    function initialize(
        address owner_,
        address ssUSD_
    ) public initializer {
        __ERC4626_init(IERC20(ssUSD_));
        __ERC20_init("Wrapped Set Stablecoin USD", "wssUSD");
        __Ownable_init(owner_);
        __UUPSUpgradeable_init();
    }

    // =========================================================================
    // ERC4626 Overrides
    // =========================================================================

    /**
     * @notice Decimals (same as ssUSD)
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    // =========================================================================
    // Convenience Functions
    // =========================================================================

    /**
     * @notice Wrap ssUSD into wssUSD
     * @param ssUSDAmount Amount of ssUSD to wrap
     * @return wssUSDAmount Amount of wssUSD received
     */
    function wrap(uint256 ssUSDAmount) external returns (uint256 wssUSDAmount) {
        wssUSDAmount = deposit(ssUSDAmount, msg.sender);
        emit Wrapped(msg.sender, ssUSDAmount, wssUSDAmount);
        return wssUSDAmount;
    }

    /**
     * @notice Unwrap wssUSD into ssUSD
     * @param wssUSDAmount Amount of wssUSD to unwrap
     * @return ssUSDAmount Amount of ssUSD received
     */
    function unwrap(uint256 wssUSDAmount) external returns (uint256 ssUSDAmount) {
        ssUSDAmount = redeem(wssUSDAmount, msg.sender, msg.sender);
        emit Unwrapped(msg.sender, wssUSDAmount, ssUSDAmount);
        return ssUSDAmount;
    }

    /**
     * @notice Get current share price (ssUSD per wssUSD)
     * @return price Share price (1e18 = 1:1)
     * @dev Initially 1:1, increases as ssUSD yield accrues
     */
    function getSharePrice() external view returns (uint256 price) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return 1e18; // 1:1 initially
        }
        return (totalAssets() * 1e18) / supply;
    }

    /**
     * @notice Get ssUSD value of wssUSD holdings
     * @param account Account to query
     * @return value ssUSD value
     */
    function getssUSDValue(address account) external view returns (uint256 value) {
        return convertToAssets(balanceOf(account));
    }

    /**
     * @notice Get wssUSD amount for given ssUSD value
     * @param ssUSDAmount ssUSD amount
     * @return wssUSDAmount Equivalent wssUSD
     */
    function getWssUSDBySSUSD(uint256 ssUSDAmount) external view returns (uint256 wssUSDAmount) {
        return convertToShares(ssUSDAmount);
    }

    /**
     * @notice Get ssUSD amount for given wssUSD
     * @param wssUSDAmount wssUSD amount
     * @return ssUSDAmount Equivalent ssUSD
     */
    function getSSUSDByWssUSD(uint256 wssUSDAmount) external view returns (uint256 ssUSDAmount) {
        return convertToAssets(wssUSDAmount);
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
