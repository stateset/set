// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title IwssUSD
 * @notice Interface for Wrapped Set Stablecoin USD (non-rebasing ERC4626 vault)
 */
interface IwssUSD is IERC4626 {
    // =========================================================================
    // Events
    // =========================================================================

    event Wrapped(address indexed account, uint256 ssUSDAmount, uint256 wssUSDAmount);

    event Unwrapped(address indexed account, uint256 wssUSDAmount, uint256 ssUSDAmount);

    // =========================================================================
    // Convenience Functions
    // =========================================================================

    /**
     * @notice Wrap ssUSD into wssUSD
     * @param ssUSDAmount Amount of ssUSD to wrap
     * @return wssUSDAmount Amount of wssUSD received
     */
    function wrap(uint256 ssUSDAmount) external returns (uint256 wssUSDAmount);

    /**
     * @notice Unwrap wssUSD into ssUSD
     * @param wssUSDAmount Amount of wssUSD to unwrap
     * @return ssUSDAmount Amount of ssUSD received
     */
    function unwrap(uint256 wssUSDAmount) external returns (uint256 ssUSDAmount);

    /**
     * @notice Get current share price (ssUSD per wssUSD)
     * @return price Current share price (1e18 = 1:1)
     */
    function getSharePrice() external view returns (uint256 price);

    /**
     * @notice Get ssUSD value of wssUSD balance
     * @param account Account to query
     * @return value ssUSD value of wssUSD holdings
     */
    function getssUSDValue(address account) external view returns (uint256 value);
}
