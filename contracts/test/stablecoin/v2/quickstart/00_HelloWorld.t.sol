// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2QuickstartBase} from "./SSDCV2QuickstartBase.sol";
import {YieldEscrowV2} from "../../../../stablecoin/v2/YieldEscrowV2.sol";

/// @title Quickstart 00: Hello World
/// @notice The absolute simplest path to agentic commerce in ~30 lines.
///         One agent deposits, pays another, and the recipient cashes out.
///         Start here. Read the other files when you want to go deeper.
///
///   Run:  forge test --match-contract HelloWorld -vvv
contract HelloWorld is SSDCV2QuickstartBase {

    function test_HelloAgenticCommerce() public {
        // ── 1. Deposit: Alpha gets $5,000 in yield-bearing wSSDC shares ───
        uint256 shares = _fundAgent(agentAlpha, 5_000 ether);
        assertEq(shares, 5_000 ether, "1:1 at par NAV");

        // ── 2. Policy: admin sets spend limits for Alpha ──────────────────
        _configureAgent(
            agentAlpha, 2_000 ether, 10_000 ether, 100 ether,
            uint40(block.timestamp + 7 days), false, new address[](0)
        );

        // ── 3. Escrow: Alpha pays Beta $1,000 ────────────────────────────
        vm.startPrank(agentAlpha);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(
            agentBeta,
            _simpleInvoice(1_000 ether),
            0 // no buyer yield share
        );
        vm.stopPrank();

        // ── 4. Release: after the time lock, Alpha confirms payment ──────
        vm.warp(block.timestamp + 1 hours);
        vm.prank(agentAlpha);
        escrow.release(escrowId);

        // ── 5. Verify: Beta received payment, escrow is settled ──────────
        assertEq(vault.balanceOf(agentBeta), 1_000 ether, "Beta got paid");
        assertEq(vault.balanceOf(agentAlpha), 4_000 ether, "Alpha spent $1k");

        (YieldEscrowV2.Escrow memory e,,,) = escrow.getEscrow(escrowId);
        assertEq(uint256(e.status), uint256(YieldEscrowV2.EscrowStatus.RELEASED));

        // ── 6. Redeem: Beta cashes out to settlement assets ──────────────
        vm.startPrank(agentBeta);
        vault.approve(address(queue), type(uint256).max);
        uint256 claimId = queue.requestRedeem(1_000 ether, agentBeta);
        vm.stopPrank();

        // Admin processes the queue (in production this is automated)
        asset.mint(admin, 2_000 ether);
        vm.startPrank(admin);
        asset.approve(address(queue), type(uint256).max);
        queue.refill(2_000 ether);
        queue.processQueue(10);
        vm.stopPrank();

        vm.prank(agentBeta);
        queue.claim(claimId);
        assertEq(asset.balanceOf(agentBeta), 1_000 ether, "Beta cashed out to USD");
    }
}
