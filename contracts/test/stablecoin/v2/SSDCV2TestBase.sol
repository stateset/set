// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {NAVControllerV2} from "../../../stablecoin/v2/NAVControllerV2.sol";
import {wSSDCVaultV2} from "../../../stablecoin/v2/wSSDCVaultV2.sol";

contract MockAsset is ERC20 {
    constructor() ERC20("Mock Settlement", "mUSD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockETHUSDOracle {
    uint256 public priceE18;
    uint256 public updatedAt;

    function setPrice(uint256 newPriceE18) external {
        priceE18 = newPriceE18;
        updatedAt = block.timestamp;
    }

    function setStalePrice(uint256 newPriceE18, uint256 staleUpdatedAt) external {
        priceE18 = newPriceE18;
        updatedAt = staleUpdatedAt;
    }

    function latestPrice() external view returns (uint256, uint256) {
        return (priceE18, updatedAt);
    }
}

contract SSDCV2TestBase is Test {
    uint256 internal constant RAY = 1e27;

    address internal admin = address(0xA11CE);
    address internal oracle = address(0x0A11);
    address internal user1 = address(0x1001);
    address internal user2 = address(0x1002);
    address internal user3 = address(0x1003);

    MockAsset internal asset;
    NAVControllerV2 internal nav;
    wSSDCVaultV2 internal vault;

    function setUp() public virtual {
        vm.startPrank(admin);

        asset = new MockAsset();
        nav = new NAVControllerV2(
            admin,
            RAY,
            9e26,
            1e23,
            48 hours,
            2_000,
            3 // staleRecoveryJumpMultiplier
        );
        vault = new wSSDCVaultV2(asset, nav, admin);

        nav.grantRole(nav.ORACLE_ROLE(), oracle);
        vm.stopPrank();
    }

    function _mintAndDeposit(address user, uint256 assetsAmount) internal returns (uint256 shares) {
        asset.mint(user, assetsAmount);
        vm.startPrank(user);
        asset.approve(address(vault), assetsAmount);
        shares = vault.deposit(assetsAmount, user);
        vm.stopPrank();
    }

    function _updateNav(uint256 attestedNavRay, uint64 epoch) internal {
        vm.prank(oracle);
        nav.updateNAV(attestedNavRay, int256(0), epoch);
    }
}
