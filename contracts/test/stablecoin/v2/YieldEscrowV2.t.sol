// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2TestBase} from "./SSDCV2TestBase.sol";
import {YieldEscrowV2} from "../../../stablecoin/v2/YieldEscrowV2.sol";

contract YieldEscrowV2Test is SSDCV2TestBase {
    YieldEscrowV2 internal escrow;

    function setUp() public override {
        super.setUp();
        vm.prank(admin);
        escrow = new YieldEscrowV2(vault, nav, admin, user3);
    }

    function testFuzz_EscrowDustConservation(
        uint256 assetsDue,
        uint16 protocolFeeBps,
        uint16 buyerBps,
        uint256 navBps
    ) public {
        assetsDue = bound(assetsDue, 1e12, 1_000_000 ether);
        protocolFeeBps = uint16(bound(protocolFeeBps, 0, 10_000));
        buyerBps = uint16(bound(buyerBps, 0, 10_000));
        navBps = bound(navBps, 9_000, 12_000);

        _mintAndDeposit(user1, assetsDue * 2);

        vm.prank(admin);
        escrow.setProtocolFee(protocolFeeBps, user3);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: assetsDue,
            expiry: uint40(block.timestamp + 1 days),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, buyerBps);
        vm.stopPrank();

        (, , uint256 totalShares, , , ) = escrow.escrows(escrowId);

        uint256 navRay = (RAY * navBps) / 10_000;
        uint64 nextEpoch = nav.navEpoch() + 1;
        vm.prank(admin);
        nav.relayNAV(navRay, uint40(block.timestamp), 0, nextEpoch);

        uint256 buyerBefore = vault.balanceOf(user1);
        uint256 merchantBefore = vault.balanceOf(user2);
        uint256 feeBefore = vault.balanceOf(user3);

        escrow.release(escrowId);

        uint256 buyerDelta = vault.balanceOf(user1) - buyerBefore;
        uint256 merchantDelta = vault.balanceOf(user2) - merchantBefore;
        uint256 feeDelta = vault.balanceOf(user3) - feeBefore;

        assertEq(merchantDelta + buyerDelta + feeDelta, totalShares);
    }

    function test_FundEscrowRevertsOnShareSlippage() public {
        _mintAndDeposit(user1, 100 ether);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 100 ether,
            expiry: uint40(block.timestamp + 1 days),
            maxNavAge: uint40(48 hours),
            maxSharesIn: 50 ether
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        vm.expectRevert(YieldEscrowV2.SHARES_SLIPPAGE.selector);
        escrow.fundEscrow(user2, terms, 0);
        vm.stopPrank();
    }
}
