// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library RayMath {
    uint256 internal constant RAY = 1e27;

    function mulDivDown(uint256 a, uint256 b, uint256 den) internal pure returns (uint256) {
        return Math.mulDiv(a, b, den, Math.Rounding.Floor);
    }

    function mulDivUp(uint256 a, uint256 b, uint256 den) internal pure returns (uint256) {
        return Math.mulDiv(a, b, den, Math.Rounding.Ceil);
    }

    function convertToAssetsDown(uint256 shares, uint256 navRay) internal pure returns (uint256) {
        return mulDivDown(shares, navRay, RAY);
    }

    function convertToSharesDown(uint256 assets, uint256 navRay) internal pure returns (uint256) {
        return mulDivDown(assets, RAY, navRay);
    }

    function convertToSharesUp(uint256 assets, uint256 navRay) internal pure returns (uint256) {
        return mulDivUp(assets, RAY, navRay);
    }
}
