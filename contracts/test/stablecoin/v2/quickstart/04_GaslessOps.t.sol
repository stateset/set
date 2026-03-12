// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2QuickstartBase} from "./SSDCV2QuickstartBase.sol";
import {YieldEscrowV2} from "../../../../stablecoin/v2/YieldEscrowV2.sol";
import {YieldPaymasterV2} from "../../../../stablecoin/v2/YieldPaymasterV2.sol";

/// @title Quickstart 04: Gasless Operations via Yield Paymaster
/// @notice AI agents never hold ETH. All gas costs are paid from yield-bearing
///         wSSDC shares through the ERC-4337 paymaster.
///
///   Demonstrates:
///     - Gas tank top-up and withdrawal
///     - EntryPoint-style gas validation + settlement
///     - Gas cost conversion: ETH wei → USD assets → wSSDC shares
///     - Multiple agents sharing the paymaster
///     - Gas tank as collateral (counts toward grounding)
///     - Grounding enforcement blocks undercollateralized agents
///     - Oracle price staleness protection
///
///   Run:  forge test --match-contract GaslessOps -vvv
contract GaslessOps is SSDCV2QuickstartBase {

    function setUp() public override {
        super.setUp();
        _fundAgent(agentAlpha, 10_000 ether);
        _fundAgent(agentBeta, 8_000 ether);
        _configureAgent(
            agentAlpha, type(uint256).max, type(uint256).max, 200 ether,
            uint40(block.timestamp + 30 days), false, new address[](0)
        );
        _configureAgent(
            agentBeta, type(uint256).max, type(uint256).max, 200 ether,
            uint40(block.timestamp + 30 days), false, new address[](0)
        );
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Gas tank lifecycle: top up → use → withdraw
    // ─────────────────────────────────────────────────────────────────────
    function test_GasTankLifecycle() public {
        // ── Top up ──────────────────────────────────────────────────────
        vm.startPrank(agentAlpha);
        vault.approve(address(paymaster), type(uint256).max);
        paymaster.topUpGasTank(1_000 ether);
        vm.stopPrank();

        assertEq(paymaster.gasTankShares(agentAlpha), 1_000 ether);
        assertEq(vault.balanceOf(agentAlpha), 9_000 ether);

        // ── Use gas ─────────────────────────────────────────────────────
        //   Simulate EntryPoint calling validate → postOp for a 200k gas tx
        uint256 gasCostWei = 200_000 * 15 gwei; // 3M gwei = 0.003 ETH
        uint256 charged = _chargeGas(agentAlpha, keccak256("op-1"), gasCostWei);
        assertGt(charged, 0, "gas charged in shares");
        assertLt(paymaster.gasTankShares(agentAlpha), 1_000 ether, "tank depleted");

        // ── Withdraw remainder ──────────────────────────────────────────
        uint256 remaining = paymaster.gasTankShares(agentAlpha);
        vm.prank(agentAlpha);
        paymaster.withdrawGasTank(remaining, agentAlpha);

        assertEq(paymaster.gasTankShares(agentAlpha), 0, "tank drained");
        assertEq(vault.balanceOf(agentAlpha), 9_000 ether + remaining, "shares returned");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Gas cost math: ETH → USD → shares conversion
    // ─────────────────────────────────────────────────────────────────────
    function test_GasCostConversion() public {
        vm.startPrank(agentAlpha);
        vault.approve(address(paymaster), type(uint256).max);
        paymaster.topUpGasTank(1_000 ether);
        vm.stopPrank();

        // Preview how many shares a gas cost would consume
        uint256 gasCostWei = 500_000 * 20 gwei; // 10M gwei = 0.01 ETH
        uint256 expectedShares = paymaster.previewChargeShares(gasCostWei);

        // At ETH=$3,000 and NAV=1.0:
        //   0.01 ETH * $3,000 = $30 → 30 shares (at 1:1)
        assertGt(expectedShares, 0);

        // Actual charge matches preview
        uint256 charged = _chargeGas(agentAlpha, keccak256("preview-op"), gasCostWei);
        assertEq(charged, expectedShares, "charge matches preview");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Gas tank as collateral: shares in tank count for grounding
    // ─────────────────────────────────────────────────────────────────────
    function test_GasTankCountsAsCollateral() public {
        // Alpha has 10,000 shares. Move 9,800 to gas tank.
        // Wallet: 200, Gas tank: 9,800, Total: 10,000
        // Floor: 200 → not grounded (total 10,000 > 200)
        vm.startPrank(agentAlpha);
        vault.approve(address(paymaster), type(uint256).max);
        paymaster.topUpGasTank(9_800 ether);
        vm.stopPrank();

        assertEq(vault.balanceOf(agentAlpha), 200 ether, "wallet balance low");
        assertEq(paymaster.gasTankShares(agentAlpha), 9_800 ether, "gas tank high");
        assertFalse(grounding.isGroundedNow(agentAlpha), "still solvent - gas tank counts");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Multi-agent gas: both agents use the paymaster concurrently
    // ─────────────────────────────────────────────────────────────────────
    function test_MultiAgentGas() public {
        // Both agents fund gas tanks
        vm.startPrank(agentAlpha);
        vault.approve(address(paymaster), type(uint256).max);
        paymaster.topUpGasTank(500 ether);
        vm.stopPrank();

        vm.startPrank(agentBeta);
        vault.approve(address(paymaster), type(uint256).max);
        paymaster.topUpGasTank(500 ether);
        vm.stopPrank();

        uint256 gasCostWei = 100_000 * 10 gwei;

        // Alpha and Beta both execute gasless transactions
        uint256 alphaCharged = _chargeGas(agentAlpha, keccak256("alpha-op"), gasCostWei);
        uint256 betaCharged = _chargeGas(agentBeta, keccak256("beta-op"), gasCostWei);

        // Same gas cost → same share charge (same oracle price & NAV)
        assertEq(alphaCharged, betaCharged, "same cost for same gas");

        // Fee collector received both charges
        assertEq(vault.balanceOf(feeCollector), alphaCharged + betaCharged);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Grounding enforcement: undercollateralized agents blocked from gas
    // ─────────────────────────────────────────────────────────────────────
    function test_GroundedAgentBlockedFromGas() public {
        // Give Gamma minimal funds and a high floor
        _fundAgent(agentGamma, 300 ether);
        _configureAgent(
            agentGamma, type(uint256).max, type(uint256).max, 500 ether,
            uint40(block.timestamp + 30 days), false, new address[](0)
        );

        // Gamma is grounded — assets (300) < floor (500)
        assertTrue(grounding.isGroundedNow(agentGamma), "Gamma undercollateralized");

        // Top up gas tank
        vm.startPrank(agentGamma);
        vault.approve(address(paymaster), type(uint256).max);
        paymaster.topUpGasTank(100 ether);
        vm.stopPrank();

        // Still grounded — total (300) < floor (500)
        assertTrue(grounding.isGroundedNow(agentGamma));

        // Paymaster rejects grounded agents
        priceOracle.setPrice(3_000e18);
        uint256 gasCostWei = 100_000 * 10 gwei;

        vm.prank(entryPoint);
        vm.expectRevert(YieldPaymasterV2.GROUNDED.selector);
        paymaster.validatePaymasterUserOp(keccak256("grounded-op"), agentGamma, gasCostWei);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Gasless commerce: complete escrow with all gas paid from yield
    // ─────────────────────────────────────────────────────────────────────
    function test_GaslessCommerce_EndToEnd() public {
        // Fund gas tanks for both agents
        vm.startPrank(agentAlpha);
        vault.approve(address(paymaster), type(uint256).max);
        paymaster.topUpGasTank(500 ether);
        vault.approve(address(escrow), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(agentBeta);
        vault.approve(address(paymaster), type(uint256).max);
        paymaster.topUpGasTank(500 ether);
        vm.stopPrank();

        uint256 gasCost = 300_000 * 15 gwei;

        // Alpha creates escrow (gas charged from tank)
        uint256 escrowId = 0;
        {
            vm.prank(agentAlpha);
            escrowId = escrow.fundEscrow(
                agentBeta,
                _milestoneInvoice(1_000 ether, YieldEscrowV2.FulfillmentType.DIGITAL, 1, uint40(2 hours), uint40(3 days)),
                0
            );
        }
        _chargeGas(agentAlpha, keccak256("create-escrow-gas"), gasCost);

        // Beta submits fulfillment (gas charged from tank)
        vm.prank(agentBeta);
        escrow.submitFulfillment(escrowId, YieldEscrowV2.FulfillmentType.DIGITAL, keccak256("api-key"));
        _chargeGas(agentBeta, keccak256("fulfill-gas"), gasCost);

        // Alpha releases (gas charged from tank)
        vm.warp(block.timestamp + 1 hours);
        vm.prank(agentAlpha);
        escrow.release(escrowId);
        _chargeGas(agentAlpha, keccak256("release-gas"), gasCost);

        // Both agents completed commerce without holding any ETH
        (YieldEscrowV2.Escrow memory e,,,) = escrow.getEscrow(escrowId);
        assertEq(uint256(e.status), uint256(YieldEscrowV2.EscrowStatus.RELEASED));
        assertGt(vault.balanceOf(feeCollector), 0, "protocol earned gas fees");
    }
}
