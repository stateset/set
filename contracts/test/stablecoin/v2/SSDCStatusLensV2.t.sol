// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2TestBase} from "./SSDCV2TestBase.sol";
import {SSDCClaimQueueV2} from "../../../stablecoin/v2/SSDCClaimQueueV2.sol";
import {SSDCStatusLensV2} from "../../../stablecoin/v2/SSDCStatusLensV2.sol";
import {WSSDCCrossChainBridgeV2} from "../../../stablecoin/v2/WSSDCCrossChainBridgeV2.sol";

contract SSDCStatusLensV2Test is SSDCV2TestBase {
    SSDCClaimQueueV2 internal queue;
    WSSDCCrossChainBridgeV2 internal bridge;
    SSDCStatusLensV2 internal lens;

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        queue = new SSDCClaimQueueV2(vault, asset, admin);
        bridge = new WSSDCCrossChainBridgeV2(vault, nav, admin);
        lens = new SSDCStatusLensV2(nav, vault, queue, bridge);
        vm.stopPrank();
    }

    function test_StatusHappyPath() public view {
        SSDCStatusLensV2.Status memory status = lens.getStatus();

        assertTrue(status.transfersAllowed);
        assertTrue(status.navFresh);
        assertTrue(status.navConversionsAllowed);
        assertTrue(status.mintDepositAllowed);
        assertTrue(status.redeemWithdrawAllowed);
        assertTrue(status.requestRedeemAllowed);
        assertTrue(status.processQueueAllowed);
        assertTrue(status.bridgingAllowed);
        assertEq(status.navRay, RAY);
    }

    function test_StatusWhenMintRedeemPaused() public {
        vm.prank(admin);
        vault.setMintRedeemPaused(true);

        SSDCStatusLensV2.Status memory status = lens.getStatus();

        assertTrue(status.transfersAllowed);
        assertTrue(status.navFresh);
        assertFalse(status.mintDepositAllowed);
        assertFalse(status.redeemWithdrawAllowed);
        assertFalse(status.requestRedeemAllowed);
        assertFalse(status.processQueueAllowed);
        assertTrue(status.bridgingAllowed);
    }

    function test_StatusWhenNAVStale() public {
        vm.warp(block.timestamp + nav.maxStaleness() + 1);

        SSDCStatusLensV2.Status memory status = lens.getStatus();

        assertTrue(status.transfersAllowed);
        assertFalse(status.navFresh);
        assertFalse(status.navConversionsAllowed);
        assertFalse(status.mintDepositAllowed);
        assertFalse(status.redeemWithdrawAllowed);
        assertFalse(status.requestRedeemAllowed);
        assertFalse(status.processQueueAllowed);
        assertTrue(status.bridgingAllowed);
        assertEq(status.navRay, 0);
    }

    function test_StatusWhenNAVBelowFloor() public {
        uint64 nextEpoch = nav.navEpoch() + 1;
        uint256 minNavRay = nav.minNavRay();
        int256 maxNegativeRate = -nav.maxRateAbsRay();
        vm.prank(admin);
        nav.relayNAV(minNavRay, uint40(block.timestamp), maxNegativeRate, nextEpoch);

        vm.warp(block.timestamp + 1);

        SSDCStatusLensV2.Status memory status = lens.getStatus();

        assertTrue(status.navFresh);
        assertFalse(status.navConversionsAllowed);
        assertFalse(status.mintDepositAllowed);
        assertFalse(status.redeemWithdrawAllowed);
        assertFalse(status.requestRedeemAllowed);
        assertFalse(status.processQueueAllowed);
        assertEq(status.navRay, 0);
    }

    function test_StatusWhenBridgePaused() public {
        vm.prank(admin);
        bridge.setBridgePaused(true);

        SSDCStatusLensV2.Status memory status = lens.getStatus();
        assertFalse(status.bridgingAllowed);
        assertTrue(status.navFresh);
        assertTrue(status.requestRedeemAllowed);
    }

    function test_StatusWhenQueuePaused() public {
        vm.prank(admin);
        queue.setQueueOpsPaused(true);

        SSDCStatusLensV2.Status memory status = lens.getStatus();

        assertTrue(status.navFresh);
        assertTrue(status.mintDepositAllowed);
        assertTrue(status.redeemWithdrawAllowed);
        assertFalse(status.requestRedeemAllowed);
        assertFalse(status.processQueueAllowed);
        assertTrue(status.bridgingAllowed);
    }
}
