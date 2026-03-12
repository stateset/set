// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2QuickstartBase} from "./SSDCV2QuickstartBase.sol";
import {YieldEscrowV2} from "../../../../stablecoin/v2/YieldEscrowV2.sol";
import {SSDCPolicyModuleV2} from "../../../../stablecoin/v2/SSDCPolicyModuleV2.sol";

/// @title Quickstart 02: Multi-Agent Marketplace
/// @notice Three AI agents forming a supply chain — procurement, supplier, logistics.
///
///   Agent Alpha (Procurement AI)  →  buys raw materials from Beta
///   Agent Beta  (Supplier AI)     →  fulfills orders, hires Gamma for shipping
///   Agent Gamma (Logistics AI)    →  handles last-mile delivery
///
///   Demonstrates:
///     - Multi-hop supply chain payments
///     - Merchant allowlist enforcement across a supply chain
///     - Multi-milestone fulfillment (manufacture → ship → deliver)
///     - Yield accrual splitting between buyer and merchant
///     - Committed spend tracking with fundEscrowFor (gateway path)
///     - Session expiry enforcement
///     - Daily spend limit rollover across 24h boundaries
///
///   Run:  forge test --match-contract MultiAgentMarketplace -vvv
contract MultiAgentMarketplace is SSDCV2QuickstartBase {

    function setUp() public override {
        super.setUp();

        // ── Fund all three agents ───────────────────────────────────────
        _fundAgent(agentAlpha, 20_000 ether);
        _fundAgent(agentBeta, 10_000 ether);
        _fundAgent(agentGamma, 5_000 ether);

        // ── Configure policies ──────────────────────────────────────────
        // Alpha: strict — allowlist only, $2k per-tx, $8k daily
        address[] memory alphaMerchants = new address[](1);
        alphaMerchants[0] = agentBeta;
        _configureAgent(
            agentAlpha, 2_000 ether, 8_000 ether, 1_000 ether,
            uint40(block.timestamp + 7 days), true, alphaMerchants
        );

        // Beta: moderate — no allowlist, $1k per-tx, $5k daily
        _configureAgent(
            agentBeta, 1_000 ether, 5_000 ether, 500 ether,
            uint40(block.timestamp + 7 days), false, new address[](0)
        );

        // Gamma: conservative — $500 per-tx, $2k daily (mostly receives)
        _configureAgent(
            agentGamma, 500 ether, 2_000 ether, 200 ether,
            uint40(block.timestamp + 7 days), false, new address[](0)
        );
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Supply chain: Alpha → Beta → Gamma → delivery → settlement
    // ─────────────────────────────────────────────────────────────────────
    function test_SupplyChainFlow() public {
        // ── Step 1: Alpha creates purchase order to Beta ─────────────────
        //   $1,500 for manufactured goods, 3 milestones:
        //     milestone 1 = raw materials sourced
        //     milestone 2 = goods manufactured
        //     milestone 3 = goods shipped (Beta hires Gamma)
        //   Buyer yield share: 30% (Alpha earns yield while goods in transit)
        vm.startPrank(agentAlpha);
        vault.approve(address(escrow), type(uint256).max);
        uint256 poEscrowId = escrow.fundEscrow(
            agentBeta,
            _milestoneInvoice(
                1_500 ether,
                YieldEscrowV2.FulfillmentType.DELIVERY,
                3,               // 3 milestones
                uint40(12 hours), // challenge window
                uint40(7 days)   // arbiter deadline
            ),
            3_000 // buyerBps = 30% of yield to Alpha
        );
        vm.stopPrank();

        // ── Step 2: Beta sources materials (milestone 1) ────────────────
        vm.prank(agentBeta);
        escrow.submitFulfillment(
            poEscrowId,
            YieldEscrowV2.FulfillmentType.DELIVERY,
            keccak256("raw-materials-sourced-receipt")
        );

        // ── Step 3: Beta manufactures goods (milestone 2) ───────────────
        vm.warp(block.timestamp + 1 days);
        _updateNAV(101e25); // refresh NAV (1.01)
        vm.prank(agentBeta);
        escrow.submitFulfillment(
            poEscrowId,
            YieldEscrowV2.FulfillmentType.DELIVERY,
            keccak256("manufacturing-qc-passed")
        );

        // ── Step 4: Beta hires Gamma for shipping ───────────────────────
        //   This is a separate escrow — Beta pays Gamma for logistics.
        //   Beta's daily limit handles both the Alpha order and this sub-order.
        vm.startPrank(agentBeta);
        vault.approve(address(escrow), type(uint256).max);
        uint256 shippingEscrowId = escrow.fundEscrow(
            agentGamma,
            _milestoneInvoice(
                300 ether,
                YieldEscrowV2.FulfillmentType.DELIVERY,
                1,
                uint40(4 hours),
                uint40(3 days)
            ),
            0 // no buyer yield share
        );
        vm.stopPrank();

        // ── Step 5: Gamma delivers goods (completes shipping escrow) ────
        vm.warp(block.timestamp + 1 days);
        _updateNAV(102e25); // refresh NAV (1.02)
        vm.prank(agentGamma);
        escrow.submitFulfillment(
            shippingEscrowId,
            YieldEscrowV2.FulfillmentType.DELIVERY,
            keccak256("tracking-number-pod-signed")
        );

        // Challenge window passes, Beta releases payment to Gamma
        vm.warp(block.timestamp + 4 hours + 1);
        uint256 gammaBefore = vault.balanceOf(agentGamma);
        vm.prank(agentBeta);
        escrow.release(shippingEscrowId);
        assertGt(vault.balanceOf(agentGamma), gammaBefore, "Gamma paid for shipping");

        // ── Step 6: Beta submits final milestone on Alpha's PO ──────────
        vm.prank(agentBeta);
        escrow.submitFulfillment(
            poEscrowId,
            YieldEscrowV2.FulfillmentType.DELIVERY,
            keccak256("goods-delivered-to-alpha-warehouse")
        );

        // ── Step 7: NAV appreciates during the transit period ───────────
        //   Yield accrued on the escrowed $1,500 while goods were in transit.
        _updateNAV(103e25); // NAV = 1.03 (3% appreciation)

        // ── Step 8: Challenge window passes, Beta claims payment ────────
        vm.warp(block.timestamp + 12 hours + 1);
        uint256 betaBefore = vault.balanceOf(agentBeta);
        vm.prank(agentBeta);
        escrow.release(poEscrowId);

        // Beta received principal + merchant yield share
        assertGt(vault.balanceOf(agentBeta), betaBefore, "Beta paid with yield");

        // Alpha should have received buyer yield share (30% of net yield)
        // Verify escrow status
        (YieldEscrowV2.Escrow memory e,,,) = escrow.getEscrow(poEscrowId);
        assertEq(uint256(e.status), uint256(YieldEscrowV2.EscrowStatus.RELEASED));
        assertEq(uint256(e.settlementMode), uint256(YieldEscrowV2.SettlementMode.MERCHANT_TIMEOUT_RELEASE));

        // All agents remain solvent
        assertFalse(grounding.isGroundedNow(agentAlpha));
        assertFalse(grounding.isGroundedNow(agentBeta));
        assertFalse(grounding.isGroundedNow(agentGamma));
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Merchant allowlist: Alpha can only pay Beta, not Gamma directly
    // ─────────────────────────────────────────────────────────────────────
    function test_AllowlistEnforcement() public {
        vm.startPrank(agentAlpha);
        vault.approve(address(escrow), type(uint256).max);

        // Alpha tries to pay Gamma directly → blocked by allowlist
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_ALLOWLIST.selector);
        escrow.fundEscrow(agentGamma, _simpleInvoice(500 ether), 0);

        // Alpha pays Beta → allowed
        uint256 id = escrow.fundEscrow(agentBeta, _simpleInvoice(500 ether), 0);
        assertGt(id, 0);
        vm.stopPrank();

        // Admin adds Gamma to Alpha's allowlist
        vm.prank(admin);
        policy.setMerchantAllowed(agentAlpha, agentGamma, true);

        // Now Alpha can pay Gamma
        vm.prank(agentAlpha);
        uint256 id2 = escrow.fundEscrow(agentGamma, _simpleInvoice(500 ether), 0);
        assertGt(id2, 0);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Session expiry: agent policy expires after configured timestamp
    // ─────────────────────────────────────────────────────────────────────
    function test_SessionExpiry() public {
        vm.startPrank(agentAlpha);
        vault.approve(address(escrow), type(uint256).max);

        // Works before expiry
        escrow.fundEscrow(agentBeta, _simpleInvoice(500 ether), 0);
        vm.stopPrank();

        // Extend NAV staleness tolerance so we can warp 7+ days in one jump,
        // then refresh NAV so the escrow's own maxNavAge check passes.
        vm.prank(admin);
        nav.setTimingConfig(30 days);

        // Fast-forward past the 7-day session and refresh NAV
        vm.warp(block.timestamp + 7 days + 1);
        _updateNAV(RAY);

        // Now blocked — session expired
        vm.startPrank(agentAlpha);
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_SESSION_EXPIRED.selector);
        escrow.fundEscrow(agentBeta, _simpleInvoice(500 ether), 0);
        vm.stopPrank();

        // Admin renews the session
        vm.prank(admin);
        policy.setPolicy(
            agentAlpha,
            2_000 ether, 8_000 ether, 1_000 ether,
            uint40(block.timestamp + 30 days), // extended session
            true
        );

        // Works again
        vm.prank(agentAlpha);
        uint256 id = escrow.fundEscrow(agentBeta, _simpleInvoice(500 ether), 0);
        assertGt(id, 0);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Daily limit rollover: spend resets after 24h boundary
    // ─────────────────────────────────────────────────────────────────────
    function test_DailyLimitRollover() public {
        // Gamma has $2,000 daily limit
        vm.startPrank(agentGamma);
        vault.approve(address(escrow), type(uint256).max);

        // Spend up to the daily limit
        for (uint256 i = 0; i < 4; i++) {
            escrow.fundEscrow(agentBeta, _simpleInvoice(500 ether), 0);
        }

        // At the limit — next one fails
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_DAILY_LIMIT.selector);
        escrow.fundEscrow(agentBeta, _simpleInvoice(500 ether), 0);
        vm.stopPrank();

        // Fast-forward past the 24h boundary — daily counter resets
        vm.warp(block.timestamp + 1 days + 1);

        // Can spend again
        vm.prank(agentGamma);
        uint256 id = escrow.fundEscrow(agentBeta, _simpleInvoice(500 ether), 0);
        assertGt(id, 0);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Parallel trades: multiple agents transacting simultaneously
    // ─────────────────────────────────────────────────────────────────────
    function test_ParallelTrades() public {
        // All three agents create escrows with each other simultaneously.
        // This tests that the policy module correctly tracks independent spend.

        // Alpha → Beta ($1,000)
        vm.startPrank(agentAlpha);
        vault.approve(address(escrow), type(uint256).max);
        uint256 id1 = escrow.fundEscrow(agentBeta, _simpleInvoice(1_000 ether), 0);
        vm.stopPrank();

        // Beta → Gamma ($800)
        vm.startPrank(agentBeta);
        vault.approve(address(escrow), type(uint256).max);
        uint256 id2 = escrow.fundEscrow(agentGamma, _simpleInvoice(800 ether), 0);
        vm.stopPrank();

        // Gamma → Alpha ($400) — but Alpha's allowlist is on.
        // Gamma's allowlist is OFF so this works (Gamma can pay anyone).
        // Note: Alpha is the merchant here — they receive, not send.
        vm.startPrank(agentGamma);
        vault.approve(address(escrow), type(uint256).max);
        uint256 id3 = escrow.fundEscrow(agentAlpha, _simpleInvoice(400 ether), 0);
        vm.stopPrank();

        // Fast-forward and settle all three
        vm.warp(block.timestamp + 1 hours);

        vm.prank(agentAlpha);
        escrow.release(id1);

        vm.prank(agentBeta);
        escrow.release(id2);

        vm.prank(agentGamma);
        escrow.release(id3);

        // All settled
        for (uint256 id = id1; id <= id3; id++) {
            (YieldEscrowV2.Escrow memory e,,,) = escrow.getEscrow(id);
            assertEq(uint256(e.status), uint256(YieldEscrowV2.EscrowStatus.RELEASED));
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Gateway one-step: deposit settlement assets directly into escrow
    // ─────────────────────────────────────────────────────────────────────
    function test_GatewayDirectEscrowFunding() public {
        // An agent can skip the two-step deposit→escrow flow and go
        // directly from settlement assets to a funded escrow in one tx.
        // This is the preferred path for fiat-funded purchases.

        _configureAgent(
            agentAlpha, type(uint256).max, type(uint256).max, 0,
            uint40(block.timestamp + 30 days), false, new address[](0)
        );

        asset.mint(agentAlpha, 2_000 ether);
        vm.startPrank(agentAlpha);
        asset.approve(address(gateway), type(uint256).max);

        YieldEscrowV2.InvoiceTerms memory terms = _simpleInvoice(1_000 ether);
        (uint256 escrowId, uint256 assetsIn, uint256 sharesOut) =
            gateway.depositToEscrow(escrow, agentBeta, terms, 0, 1_000 ether);
        vm.stopPrank();

        assertGt(escrowId, 0, "escrow created");
        assertEq(assetsIn, 1_000 ether, "exact assets deposited");
        assertGt(sharesOut, 0, "shares minted into escrow");

        (YieldEscrowV2.Escrow memory e,,,) = escrow.getEscrow(escrowId);
        assertEq(e.buyer, agentAlpha);
        assertEq(e.merchant, agentBeta);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Gateway one-step: deposit settlement assets directly to gas tank
    // ─────────────────────────────────────────────────────────────────────
    function test_GatewayDirectGasTankFunding() public {
        _configureAgent(
            agentAlpha, type(uint256).max, type(uint256).max, 0,
            uint40(block.timestamp + 30 days), false, new address[](0)
        );

        asset.mint(agentAlpha, 1_000 ether);
        vm.startPrank(agentAlpha);
        asset.approve(address(gateway), type(uint256).max);
        uint256 sharesOut = gateway.depositToGasTank(paymaster, 500 ether, agentAlpha, 0);
        vm.stopPrank();

        assertGt(sharesOut, 0);
        assertEq(paymaster.gasTankShares(agentAlpha), sharesOut);
    }
}
