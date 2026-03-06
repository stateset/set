// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2TestBase} from "./SSDCV2TestBase.sol";
import {NAVControllerV2} from "../../../stablecoin/v2/NAVControllerV2.sol";

contract NAVControllerV2Test is SSDCV2TestBase {
    function testFuzz_CurrentNavIntegrityWithinBounds(
        int256 rawRate,
        uint40 rawDt,
        uint256 rawBaseNav
    ) public {
        vm.assume(rawRate != type(int256).min);

        int256 maxRate = nav.maxRateAbsRay();
        int256 rate = int256(bound(uint256(rawRate < 0 ? -rawRate : rawRate), 0, uint256(uint256(maxRate)))) ;
        if (rawRate < 0) {
            rate = -rate;
        }

        uint256 maxStaleness = nav.maxStaleness();
        uint256 dt = bound(uint256(rawDt), 0, maxStaleness);

        uint256 minNav = nav.minNavRay();
        uint256 nav0 = bound(rawBaseNav, minNav, 3 * RAY);

        if (rate < 0) {
            uint256 drop = uint256(-rate) * maxStaleness;
            if (nav0 <= minNav + drop) {
                nav0 = minNav + drop + 1;
            }
        }

        vm.prank(admin);
        nav.setNavBounds(minNav, maxRate, 0);

        uint64 nextEpoch = nav.navEpoch() + 1;
        vm.prank(admin);
        nav.relayNAV(nav0, uint40(block.timestamp), rate, nextEpoch);

        vm.warp(block.timestamp + dt);

        uint256 current = nav.currentNAVRay();
        int256 expected = int256(nav0) + (rate * int256(dt));

        assertEq(current, uint256(expected));
    }

    function test_CurrentNAVRevertsWhenStale() public {
        vm.warp(block.timestamp + nav.maxStaleness() + 1);
        vm.expectRevert(NAVControllerV2.NAV_STALE.selector);
        nav.currentNAVRay();
    }

    function test_UpdateNAVRecoversFromStaleController() public {
        vm.warp(block.timestamp + nav.maxStaleness() + 1);

        uint256 attestedNavRay = 105e25;
        uint64 nextEpoch = nav.navEpoch() + 1;
        vm.prank(oracle);
        nav.updateNAV(attestedNavRay, nextEpoch);

        assertEq(nav.currentNAVRay(), attestedNavRay);
        assertEq(nav.ratePerSecondRay(), 0);
    }

    function test_NAVContinuityAtUpdate() public {
        _updateNav(11e26, nav.navEpoch() + 1);

        vm.warp(block.timestamp + 2 hours);
        uint256 beforeNav = nav.currentNAVRay();

        _updateNav(105e25, nav.navEpoch() + 1);
        uint256 afterNav = nav.currentNAVRay();

        assertEq(beforeNav, afterNav);
    }

    function test_SignedDeltaHandlesNegativeYield() public {
        _updateNav(95e25, nav.navEpoch() + 1);
        assertLt(nav.ratePerSecondRay(), 0);
    }

    function test_UpdateNAVRevertsOnOutOfOrderEpoch() public {
        uint64 currentEpoch = nav.navEpoch();
        vm.prank(oracle);
        vm.expectRevert(NAVControllerV2.EPOCH.selector);
        nav.updateNAV(RAY, currentEpoch);
    }

    function test_RelayNAVRejectsFutureTimestamp() public {
        uint64 nextEpoch = nav.navEpoch() + 1;
        vm.prank(admin);
        vm.expectRevert(NAVControllerV2.NAV_T0_IN_FUTURE.selector);
        nav.relayNAV(RAY, uint40(block.timestamp + 1), 0, nextEpoch);
    }

    function test_RelayNAVRejectsOutOfBoundsRate() public {
        uint64 nextEpoch = nav.navEpoch() + 1;
        int256 outOfBoundsRate = nav.maxRateAbsRay() + 1;
        vm.prank(admin);
        vm.expectRevert(NAVControllerV2.RATE_OUT_OF_BOUNDS.selector);
        nav.relayNAV(RAY, uint40(block.timestamp), outOfBoundsRate, nextEpoch);
    }
}
