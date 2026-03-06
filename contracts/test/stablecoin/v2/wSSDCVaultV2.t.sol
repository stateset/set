// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2TestBase} from "./SSDCV2TestBase.sol";
import {NAVControllerV2} from "../../../stablecoin/v2/NAVControllerV2.sol";
import {wSSDCVaultV2} from "../../../stablecoin/v2/wSSDCVaultV2.sol";

contract wSSDCVaultV2Test is SSDCV2TestBase {
    function test_MintRedeemPauseMatrix() public {
        _mintAndDeposit(user1, 100 ether);

        vm.prank(admin);
        vault.setMintRedeemPaused(true);

        vm.prank(user1);
        vault.transfer(user2, 10 ether);
        assertEq(vault.balanceOf(user2), 10 ether);

        asset.mint(user1, 10 ether);
        vm.startPrank(user1);
        asset.approve(address(vault), type(uint256).max);

        vm.expectRevert(wSSDCVaultV2.MINT_REDEEM_PAUSED.selector);
        vault.deposit(1 ether, user1);

        vm.expectRevert(wSSDCVaultV2.MINT_REDEEM_PAUSED.selector);
        vault.redeem(1 ether, user1, user1);
        vm.stopPrank();
    }

    function test_NAVStaleFailClosedButTransfersAllowed() public {
        _mintAndDeposit(user1, 100 ether);

        vm.warp(block.timestamp + nav.maxStaleness() + 1);

        vm.prank(user1);
        vault.transfer(user2, 10 ether);
        assertEq(vault.balanceOf(user2), 10 ether);

        asset.mint(user1, 5 ether);
        vm.startPrank(user1);
        asset.approve(address(vault), type(uint256).max);

        vm.expectRevert(NAVControllerV2.NAV_STALE.selector);
        vault.deposit(1 ether, user1);

        vm.expectRevert(NAVControllerV2.NAV_STALE.selector);
        vault.withdraw(1 ether, user1, user1);
        vm.stopPrank();
    }

    function test_RoundingHelpersMatchPolicy() public {
        uint64 nextEpoch = nav.navEpoch() + 1;
        vm.prank(admin);
        nav.relayNAV(11e26, uint40(block.timestamp), 0, nextEpoch);

        uint256 shares = 3;
        uint256 assetsFloor = vault.convertToAssets(shares);
        assertEq(assetsFloor, (shares * 11e26) / RAY);

        uint256 assets = 1e18 + 1;
        uint256 sharesDeposit = vault.convertToShares(assets);
        uint256 sharesWithdraw = vault.previewWithdraw(assets);

        assertLe(sharesDeposit, sharesWithdraw);
    }
}
