// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2TestBase, MockAsset} from "./SSDCV2TestBase.sol";
import {SSDCClaimQueueV2} from "../../../stablecoin/v2/SSDCClaimQueueV2.sol";
import {wSSDCVaultV2} from "../../../stablecoin/v2/wSSDCVaultV2.sol";

contract SSDCClaimQueueV2Test is SSDCV2TestBase {
    SSDCClaimQueueV2 internal queue;

    function setUp() public override {
        super.setUp();

        vm.prank(admin);
        queue = new SSDCClaimQueueV2(vault, asset, admin);

        bytes32 queueRole = vault.QUEUE_ROLE();
        vm.prank(admin);
        vault.grantRole(queueRole, address(queue));
    }

    function test_QueueSolvencyTracksClaimableAssets() public {
        _mintAndDeposit(user1, 100 ether);

        vm.startPrank(user1);
        vault.approve(address(queue), type(uint256).max);
        uint256 id1 = queue.requestRedeem(40 ether, user1);
        uint256 id2 = queue.requestRedeem(30 ether, user1);
        vm.stopPrank();

        asset.mint(admin, 100 ether);
        vm.startPrank(admin);
        asset.approve(address(queue), type(uint256).max);
        queue.refill(70 ether);
        queue.processQueue(10);
        vm.stopPrank();

        uint256 owedSum;
        for (uint256 i = 1; i <= 2; i++) {
            (, , uint256 assetsOwed, , SSDCClaimQueueV2.Status status) = queue.claims(i);
            if (status == SSDCClaimQueueV2.Status.CLAIMABLE) {
                owedSum += assetsOwed;
            }
        }

        assertEq(queue.reservedAssets(), owedSum);

        vm.prank(user1);
        queue.claim(id1);

        (, , uint256 id2Owed, , SSDCClaimQueueV2.Status id2Status) = queue.claims(id2);
        uint256 expectedReserved = id2Status == SSDCClaimQueueV2.Status.CLAIMABLE ? id2Owed : 0;
        assertEq(queue.reservedAssets(), expectedReserved);
    }

    function test_HeadLivenessSkipsCancelledAndClaimed() public {
        _mintAndDeposit(user1, 300 ether);

        vm.startPrank(user1);
        vault.approve(address(queue), type(uint256).max);
        uint256 id1 = queue.requestRedeem(50 ether, user1);
        uint256 id2 = queue.requestRedeem(50 ether, user1);
        uint256 id3 = queue.requestRedeem(50 ether, user1);
        vm.stopPrank();

        vm.prank(user1);
        queue.cancel(id1, user1);

        asset.mint(admin, 50 ether);
        vm.startPrank(admin);
        asset.approve(address(queue), type(uint256).max);
        queue.refill(50 ether);

        uint256 beforeHead = queue.head();
        queue.processQueue(5);
        uint256 afterHead = queue.head();
        vm.stopPrank();

        assertGe(afterHead, beforeHead);
        assertEq(afterHead, id3);

        vm.prank(user1);
        queue.claim(id2);

        asset.mint(admin, 50 ether);
        vm.startPrank(admin);
        asset.approve(address(queue), type(uint256).max);
        queue.refill(50 ether);

        uint256 headBeforeSecond = queue.head();
        queue.processQueue(5);
        uint256 headAfterSecond = queue.head();
        vm.stopPrank();

        assertGe(headAfterSecond, headBeforeSecond);
        assertEq(headAfterSecond, id3 + 1);
    }

    function test_ProcessQueueCanSkipOversizedHeadClaim() public {
        _mintAndDeposit(user1, 120 ether);

        vm.startPrank(user1);
        vault.approve(address(queue), type(uint256).max);
        uint256 id1 = queue.requestRedeem(90 ether, user1);
        uint256 id2 = queue.requestRedeem(10 ether, user1);
        uint256 id3 = queue.requestRedeem(10 ether, user1);
        vm.stopPrank();

        asset.mint(admin, 20 ether);
        vm.startPrank(admin);
        asset.approve(address(queue), type(uint256).max);
        queue.refill(20 ether);
        queue.processQueue(10);
        vm.stopPrank();

        (, , uint256 owed1, , SSDCClaimQueueV2.Status status1) = queue.claims(id1);
        (, , uint256 owed2, , SSDCClaimQueueV2.Status status2) = queue.claims(id2);
        (, , uint256 owed3, , SSDCClaimQueueV2.Status status3) = queue.claims(id3);

        assertEq(uint256(status1), uint256(SSDCClaimQueueV2.Status.PENDING));
        assertEq(owed1, 0);
        assertEq(queue.head(), id1);

        assertEq(uint256(status2), uint256(SSDCClaimQueueV2.Status.CLAIMABLE));
        assertEq(uint256(status3), uint256(SSDCClaimQueueV2.Status.CLAIMABLE));
        assertEq(owed2 + owed3, 20 ether);
        assertEq(queue.reservedAssets(), 20 ether);
    }

    function testFuzz_HeadMonotonic(uint8 claimCount, uint8 processA, uint8 processB) public {
        claimCount = uint8(bound(claimCount, 3, 12));
        processA = uint8(bound(processA, 1, claimCount));
        processB = uint8(bound(processB, 1, claimCount));

        uint256 total = uint256(claimCount) * 10 ether;
        _mintAndDeposit(user1, total);

        vm.startPrank(user1);
        vault.approve(address(queue), type(uint256).max);

        for (uint256 i = 0; i < claimCount; i++) {
            queue.requestRedeem(10 ether, user1);
        }

        queue.cancel(1, user1);
        vm.stopPrank();

        asset.mint(admin, total);
        vm.startPrank(admin);
        asset.approve(address(queue), type(uint256).max);
        queue.refill(total);

        uint256 h0 = queue.head();
        queue.processQueue(processA);
        uint256 h1 = queue.head();
        queue.processQueue(processB);
        uint256 h2 = queue.head();
        vm.stopPrank();

        assertGe(h1, h0);
        assertGe(h2, h1);
    }
}
