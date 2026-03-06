// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IETHUSDOracleV2 {
    /// @notice Returns ETH price in USD with 1e18 precision and updated timestamp.
    function latestPrice() external view returns (uint256 priceE18, uint256 updatedAt);
}
