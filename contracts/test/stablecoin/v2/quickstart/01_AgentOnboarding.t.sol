// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2QuickstartBase} from "./SSDCV2QuickstartBase.sol";
import {YieldEscrowV2} from "../../../../stablecoin/v2/YieldEscrowV2.sol";
import {SSDCStatusLensV2} from "../../../../stablecoin/v2/SSDCStatusLensV2.sol";
import {SSDCPolicyModuleV2} from "../../../../stablecoin/v2/SSDCPolicyModuleV2.sol";

/// @title Quickstart 01: Agent Onboarding & First Transaction
/// @notice The minimal path from zero to a completed agent-to-agent payment.
///
///   This example walks through:
///     1. System health check via StatusLens
///     2. Depositing settlement assets into the wSSDC vault
///     3. Configuring agent spend policies
///     4. Funding a gas tank for gasless operations
///     5. Creating and settling a simple escrow payment
///     6. Redeeming profits back to settlement assets
///
///   Run:  forge test --match-contract AgentOnboardingQuickstart -vvv
contract AgentOnboardingQuickstart is SSDCV2QuickstartBase {

    function test_01_CheckSystemHealth() public view {
        // Before doing anything, query the StatusLens to verify the system
        // is operational. This is the first thing an agent SDK should call.
        SSDCStatusLensV2.Status memory s = lens.getStatus();

        assertTrue(s.mintDepositAllowed,       "deposits should be open");
        assertTrue(s.redeemWithdrawAllowed,     "redemptions should be open");
        assertTrue(s.navFresh,                  "NAV should be fresh");
        assertTrue(s.navConversionsAllowed,     "share conversions should work");
        assertFalse(s.escrowOpsPaused,          "escrow should be active");
        assertFalse(s.paymasterPaused,          "paymaster should be active");
        assertEq(s.navRay, RAY,                 "NAV should be 1.0");
        assertEq(s.liquidityCoverageBps, 10_000, "100% coverage when empty");
    }

    function test_02_DepositAndCheckBalance() public {
        // Agent Alpha receives 10,000 mUSD off-chain (fiat on-ramp, bridge, etc.)
        // and deposits into the wSSDC vault to get yield-bearing shares.
        uint256 depositAmount = 10_000 ether;
        uint256 shares = _fundAgent(agentAlpha, depositAmount);

        // At NAV = 1.0, shares == assets
        assertEq(shares, depositAmount,       "1:1 at par NAV");
        assertEq(vault.balanceOf(agentAlpha), depositAmount);

        // The vault now holds settlement assets backing the shares
        SSDCStatusLensV2.Status memory s = lens.getStatus();
        assertEq(s.settlementAssetsAvailable, depositAmount);
        assertEq(s.totalShareSupply, depositAmount);
    }

    function test_03_ConfigureSpendPolicy() public {
        _fundAgent(agentAlpha, 10_000 ether);

        // The agent's owner (admin/multisig) sets spend guardrails:
        //   - Max $1,000 per transaction
        //   - Max $5,000 per day
        //   - Must maintain $500 minimum balance (collateral floor)
        //   - Session expires in 30 days
        //   - Only pay approved merchants
        address[] memory allowedMerchants = new address[](1);
        allowedMerchants[0] = agentBeta;

        _configureAgent(
            agentAlpha,
            1_000 ether,    // perTxLimit
            5_000 ether,    // dailyLimit
            500 ether,      // minAssetsFloor
            uint40(block.timestamp + 30 days),
            true,           // enforceMerchantAllowlist
            allowedMerchants
        );

        // Verify policy is active
        assertTrue(policy.canSpend(agentAlpha, agentBeta, 999 ether));
        assertFalse(policy.canSpend(agentAlpha, agentBeta, 1_001 ether)); // over per-tx
        assertFalse(policy.canSpend(agentAlpha, address(0xDEAD), 100 ether)); // not on allowlist
    }

    function test_04_FundGasTankForGaslessOps() public {
        _fundAgent(agentAlpha, 5_000 ether);
        _configureAgent(
            agentAlpha, type(uint256).max, type(uint256).max, 100 ether,
            uint40(block.timestamp + 30 days), false, new address[](0)
        );

        // Agent deposits wSSDC shares into the paymaster gas tank.
        // Gas costs are paid from yield — the agent never needs ETH.
        vm.startPrank(agentAlpha);
        vault.approve(address(paymaster), type(uint256).max);
        paymaster.topUpGasTank(500 ether);
        vm.stopPrank();

        assertEq(paymaster.gasTankShares(agentAlpha), 500 ether);

        // Gas tank shares count as collateral for grounding checks.
        // Total collateral = wallet (4,500) + gas tank (500) = 5,000
        assertFalse(grounding.isGroundedNow(agentAlpha));
    }

    function test_05_FirstPayment_SimpleEscrow() public {
        // Fund both agents
        _fundAgent(agentAlpha, 5_000 ether);
        _fundAgent(agentBeta, 1_000 ether);

        // Configure Alpha with generous limits
        _configureAgent(
            agentAlpha, 2_000 ether, 10_000 ether, 100 ether,
            uint40(block.timestamp + 7 days), false, new address[](0)
        );

        // Alpha pays Beta $800 for a batch of components — no fulfillment
        // required (simple payment, not a purchase order).
        vm.startPrank(agentAlpha);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(
            agentBeta,
            _simpleInvoice(800 ether),
            0 // no buyer yield share
        );
        vm.stopPrank();

        // Fast-forward past the release lock
        vm.warp(block.timestamp + 1 hours);

        // Alpha confirms receipt — buyer-initiated release
        uint256 betaBefore = vault.balanceOf(agentBeta);
        vm.prank(agentAlpha);
        escrow.release(escrowId);

        assertGt(vault.balanceOf(agentBeta), betaBefore, "Beta received payment");

        (YieldEscrowV2.Escrow memory e,,,) = escrow.getEscrow(escrowId);
        assertEq(uint256(e.status), uint256(YieldEscrowV2.EscrowStatus.RELEASED));
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Error paths: what happens when guardrails kick in
    // ─────────────────────────────────────────────────────────────────────
    function test_06_WhatHappensWhenYouExceedYourLimit() public {
        _fundAgent(agentAlpha, 5_000 ether);
        _fundAgent(agentBeta, 1_000 ether);

        // Alpha: $1,000 per-tx limit, $3,000 daily limit, $500 floor
        _configureAgent(
            agentAlpha, 1_000 ether, 3_000 ether, 500 ether,
            uint40(block.timestamp + 7 days), false, new address[](0)
        );

        vm.startPrank(agentAlpha);
        vault.approve(address(escrow), type(uint256).max);

        // Over per-tx limit ($1,200 > $1,000)
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_LIMIT.selector);
        escrow.fundEscrow(agentBeta, _simpleInvoice(1_200 ether), 0);

        // Within per-tx, succeeds 3x ($3,000 total = daily limit)
        escrow.fundEscrow(agentBeta, _simpleInvoice(1_000 ether), 0);
        escrow.fundEscrow(agentBeta, _simpleInvoice(1_000 ether), 0);
        escrow.fundEscrow(agentBeta, _simpleInvoice(1_000 ether), 0);

        // Daily limit hit ($3,000 spent)
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_DAILY_LIMIT.selector);
        escrow.fundEscrow(agentBeta, _simpleInvoice(500 ether), 0);

        vm.stopPrank();
    }

    function test_07_RedeemProfits() public {
        // Beta has shares and wants to cash out to settlement assets
        _fundAgent(agentBeta, 2_000 ether);

        vm.startPrank(agentBeta);
        vault.approve(address(queue), type(uint256).max);
        uint256 claimId = queue.requestRedeem(1_000 ether, agentBeta);
        vm.stopPrank();

        // Process the queue (admin refills buffer)
        asset.mint(admin, 5_000 ether);
        vm.startPrank(admin);
        asset.approve(address(queue), type(uint256).max);
        queue.refill(5_000 ether);
        queue.processQueue(10);
        vm.stopPrank();

        // Beta claims the settlement assets
        uint256 betaAssetsBefore = asset.balanceOf(agentBeta);
        vm.prank(agentBeta);
        queue.claim(claimId);

        assertGt(asset.balanceOf(agentBeta), betaAssetsBefore, "Beta cashed out");
    }
}
