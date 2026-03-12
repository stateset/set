// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SSDCV2TestBase} from "./SSDCV2TestBase.sol";
import {wSSDCVaultV2} from "../../../stablecoin/v2/wSSDCVaultV2.sol";

contract MockBadDecimalsAsset is ERC20 {
    constructor() ERC20("Bad Settlement", "bUSD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract wSSDCVaultV2Test is SSDCV2TestBase {
    function test_ConstructorRejectsNonSixDecimalSettlementAsset() public {
        MockBadDecimalsAsset badAsset = new MockBadDecimalsAsset();

        vm.expectRevert(wSSDCVaultV2.INVALID_SETTLEMENT_ASSET_DECIMALS.selector);
        new wSSDCVaultV2(badAsset, nav, admin);
    }

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

        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, user1, 1 ether, 0)
        );
        vault.deposit(1 ether, user1);

        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxWithdraw.selector, user1, 1 ether, 0)
        );
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

    function test_MaxWithdrawAndRedeemCapToSettlementLiquidity() public {
        _mintAndDeposit(user1, 100 ether);

        uint64 nextEpoch = nav.navEpoch() + 1;
        vm.prank(admin);
        nav.relayNAV(12e26, uint40(block.timestamp), 0, nextEpoch);

        assertEq(vault.availableSettlementAssets(), 100 ether);
        assertEq(vault.maxWithdraw(user1), 100 ether);
        assertEq(vault.maxRedeem(user1), vault.convertToShares(100 ether));
        assertLt(vault.maxRedeem(user1), vault.balanceOf(user1));
    }

    function test_WithdrawAndRedeemFailClosedOnLiquidityCap() public {
        _mintAndDeposit(user1, 100 ether);

        uint64 nextEpoch = nav.navEpoch() + 1;
        vm.prank(admin);
        nav.relayNAV(12e26, uint40(block.timestamp), 0, nextEpoch);

        vm.startPrank(user1);

        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxWithdraw.selector, user1, 101 ether, 100 ether)
        );
        vault.withdraw(101 ether, user1, user1);

        uint256 maxRedeemShares = vault.maxRedeem(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626.ERC4626ExceededMaxRedeem.selector,
                user1,
                maxRedeemShares + 1,
                maxRedeemShares
            )
        );
        vault.redeem(maxRedeemShares + 1, user1, user1);

        vm.stopPrank();
    }

    function test_TotalAssetsTracksNavLiabilities() public {
        _mintAndDeposit(user1, 100 ether);

        uint64 nextEpoch = nav.navEpoch() + 1;
        vm.prank(admin);
        nav.relayNAV(12e26, uint40(block.timestamp), 0, nextEpoch);

        assertEq(vault.availableSettlementAssets(), 100 ether);
        assertEq(vault.totalAssets(), 120 ether);
        assertEq(vault.totalLiabilityAssets(), 120 ether);
        assertEq(vault.liquidityCoverageBps(), 8_333);
    }

    function test_BridgeMintCoverageGuardBlocksUnderbackedMint() public {
        _mintAndDeposit(user1, 100 ether);

        uint64 nextEpoch = nav.navEpoch() + 1;
        vm.prank(admin);
        nav.relayNAV(12e26, uint40(block.timestamp), 0, nextEpoch);

        vm.prank(admin);
        vault.setMinBridgeLiquidityCoverageBps(9_000);

        assertEq(vault.previewLiquidityCoverageBpsAfterMint(1 ether), 8_250);

        vm.prank(admin);
        vm.expectRevert(wSSDCVaultV2.LIQUIDITY_COVERAGE.selector);
        vault.mintBridgeShares(user2, 1 ether);
    }

    function test_BridgedShareProvenanceMovesWithTransfersAndBurns() public {
        _mintAndDeposit(user1, 10 ether);

        vm.prank(admin);
        vault.mintBridgeShares(user1, 10 ether);

        assertEq(vault.bridgedSharesBalance(user1), 10 ether);
        assertEq(vault.bridgedSharesSupply(), 10 ether);

        vm.prank(user1);
        vault.transfer(user2, 12 ether);

        assertEq(vault.bridgedSharesBalance(user1), 4 ether);
        assertEq(vault.bridgedSharesBalance(user2), 6 ether);
        assertEq(vault.bridgedSharesSupply(), 10 ether);

        vm.prank(admin);
        uint256 bridgedBurned = vault.burnBridgeShares(user2, 4 ether);

        assertEq(bridgedBurned, 4 ether);
        assertEq(vault.bridgedSharesBalance(user2), 2 ether);
        assertEq(vault.bridgedSharesSupply(), 6 ether);
    }

    function test_DecimalsMirrorSixDecimalSettlementAsset() public view {
        assertEq(asset.decimals(), 6);
        assertEq(vault.decimals(), 6);
    }

    function test_ReserveDeployAndRecallTrackConfiguredState() public {
        address reserveManager = address(0x515E);
        _mintAndDeposit(user1, 100 ether);

        vm.prank(admin);
        vault.setReserveConfig(reserveManager, 25 ether, 2_000);

        vm.prank(admin);
        vault.deployReserve(20 ether);

        assertEq(vault.availableSettlementAssets(), 80 ether);
        assertEq(vault.deployedReserveAssets(), 20 ether);
        assertEq(asset.balanceOf(reserveManager), 20 ether);

        vm.startPrank(reserveManager);
        asset.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.prank(admin);
        vault.recallReserve(5 ether);

        assertEq(vault.availableSettlementAssets(), 85 ether);
        assertEq(vault.deployedReserveAssets(), 15 ether);
        assertEq(asset.balanceOf(reserveManager), 15 ether);
    }

    function test_ReserveDeployLimitAppliesPerCallNotCumulatively() public {
        address reserveManager = address(0x515E);
        _mintAndDeposit(user1, 100 ether);

        vm.prank(admin);
        vault.setReserveConfig(reserveManager, 0, 2_000);

        vm.startPrank(admin);
        vault.deployReserve(20 ether);
        vault.deployReserve(20 ether);
        vm.stopPrank();

        assertEq(vault.availableSettlementAssets(), 60 ether);
        assertEq(vault.deployedReserveAssets(), 40 ether);
        assertEq(asset.balanceOf(reserveManager), 40 ether);
    }

    function test_ReserveDeployBlockedWhenMintRedeemPaused() public {
        _mintAndDeposit(user1, 100 ether);

        vm.startPrank(admin);
        vault.setReserveConfig(address(0x515E), 10 ether, 2_000);
        vault.setMintRedeemPaused(true);
        vm.expectRevert(wSSDCVaultV2.MINT_REDEEM_PAUSED.selector);
        vault.deployReserve(10 ether);
        vm.stopPrank();
    }
}
