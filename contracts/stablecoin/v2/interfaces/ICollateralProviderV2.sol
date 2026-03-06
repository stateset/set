// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ICollateralProviderV2 {
    function collateralSharesOf(address agent) external view returns (uint256 shares);
}
