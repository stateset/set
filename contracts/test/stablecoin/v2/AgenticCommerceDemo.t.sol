// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2TestBase, MockETHUSDOracle} from "./SSDCV2TestBase.sol";
import {GroundingRegistryV2} from "../../../stablecoin/v2/GroundingRegistryV2.sol";
import {SSDCClaimQueueV2} from "../../../stablecoin/v2/SSDCClaimQueueV2.sol";
import {SSDCPolicyModuleV2} from "../../../stablecoin/v2/SSDCPolicyModuleV2.sol";
import {SSDCVaultGatewayV2} from "../../../stablecoin/v2/SSDCVaultGatewayV2.sol";
import {YieldEscrowV2} from "../../../stablecoin/v2/YieldEscrowV2.sol";
import {YieldPaymasterV2} from "../../../stablecoin/v2/YieldPaymasterV2.sol";
import {IETHUSDOracleV2} from "../../../stablecoin/v2/interfaces/IETHUSDOracleV2.sol";

/// @title Agentic Commerce Demo — Two AI Agents Transacting via SSDC V2
/// @notice Demonstrates autonomous AI agent commerce on Set Chain:
///   - Agent Alpha: procurement AI (buys inventory, manages supplier payments)
///   - Agent Beta:  supplier AI (fulfills orders, manages receivables)
///   Both agents operate under policy-bounded spend limits, earn yield on idle
///   balances via the wSSDC vault, and pay gas through the yield paymaster.
///   All settlement uses SSDC — the Treasury-backed stablecoin.
contract AgenticCommerceDemoTest is SSDCV2TestBase {
    // ── Infrastructure ──────────────────────────────────────────────────
    SSDCVaultGatewayV2 internal gateway;
    SSDCClaimQueueV2 internal queue;
    YieldEscrowV2 internal escrow;
    SSDCPolicyModuleV2 internal policy;
    GroundingRegistryV2 internal grounding;
    YieldPaymasterV2 internal paymaster;
    MockETHUSDOracle internal priceOracle;

    // ── Actors ──────────────────────────────────────────────────────────
    address internal agentAlpha = address(0xA1FA);   // procurement AI
    address internal agentBeta = address(0xBE7A);    // supplier AI
    address internal arbiter = address(0xA4B1);      // dispute resolver
    address internal protocolFeeCollector = address(0xFEE0);
    address internal entryPoint = address(0x4337);

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);

        // Deploy infrastructure
        gateway = new SSDCVaultGatewayV2(vault, admin);
        queue = new SSDCClaimQueueV2(vault, asset, admin);
        policy = new SSDCPolicyModuleV2(admin);
        grounding = new GroundingRegistryV2(policy, nav, vault, admin);
        escrow = new YieldEscrowV2(vault, nav, policy, grounding, admin, protocolFeeCollector);

        priceOracle = new MockETHUSDOracle();
        priceOracle.setPrice(3_000e18); // ETH = $3,000

        paymaster = new YieldPaymasterV2(
            vault, nav, policy, grounding,
            IETHUSDOracleV2(address(priceOracle)),
            entryPoint, admin, protocolFeeCollector
        );

        // Wire roles
        vault.grantRole(vault.GATEWAY_ROLE(), address(gateway));
        vault.grantRole(vault.GATEWAY_ROLE(), address(queue));
        vault.grantRole(vault.QUEUE_ROLE(), address(queue));
        escrow.grantRole(escrow.FUNDER_ROLE(), address(gateway));
        escrow.grantRole(escrow.ARBITER_ROLE(), arbiter);
        policy.grantRole(policy.POLICY_CONSUMER_ROLE(), address(escrow));
        policy.grantRole(policy.POLICY_CONSUMER_ROLE(), address(paymaster));
        grounding.setCollateralProvider(address(paymaster), true);
        vault.setGatewayRequired(true);

        // Configure Agent Alpha — procurement AI
        //   per-tx: 500 SSDC | daily: 2,000 SSDC | min floor: 100 SSDC
        //   merchant allowlist ON — can only pay approved suppliers
        //   session: 7 days
        policy.setPolicy(
            agentAlpha,
            500 ether,       // perTxLimitAssets
            2_000 ether,     // dailyLimitAssets
            100 ether,       // minAssetsFloor
            uint40(block.timestamp + 7 days),
            true             // enforceMerchantAllowlist
        );
        policy.setMerchantAllowed(agentAlpha, agentBeta, true);

        // Configure Agent Beta — supplier AI
        //   per-tx: 300 SSDC | daily: 1,000 SSDC | min floor: 50 SSDC
        //   merchant allowlist OFF — can pay anyone (e.g. logistics, sub-suppliers)
        //   session: 7 days
        policy.setPolicy(
            agentBeta,
            300 ether,
            1_000 ether,
            50 ether,
            uint40(block.timestamp + 7 days),
            false
        );

        // Set escrow yield split: 1% protocol fee, 2% reserve
        escrow.setProtocolFee(100, protocolFeeCollector); // 1%
        escrow.setReserveConfig(200, protocolFeeCollector); // 2%

        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────
    //  SCENARIO 1: Happy-path agent-to-agent purchase order
    //  Alpha buys $400 of raw materials from Beta. Beta fulfills in
    //  2 milestones (shipping + delivery). Yield accrues during escrow
    //  and is split between buyer and merchant.
    // ─────────────────────────────────────────────────────────────────────
    function test_Scenario1_AgentPurchaseOrder_HappyPath() public {
        // ── STEP 1: Both agents deposit funds into the vault ────────────
        //   Alpha deposits 1,000 SSDC, Beta deposits 500 SSDC.
        //   Funds earn yield via NAV accrual while sitting in wSSDC.
        asset.mint(agentAlpha, 1_000 ether);
        vm.startPrank(agentAlpha);
        asset.approve(address(gateway), type(uint256).max);
        gateway.deposit(1_000 ether, agentAlpha, 1_000 ether);
        vm.stopPrank();

        asset.mint(agentBeta, 500 ether);
        vm.startPrank(agentBeta);
        asset.approve(address(gateway), type(uint256).max);
        gateway.deposit(500 ether, agentBeta, 500 ether);
        vm.stopPrank();

        uint256 alphaSharesBefore = vault.balanceOf(agentAlpha);
        uint256 betaSharesBefore = vault.balanceOf(agentBeta);
        assertGt(alphaSharesBefore, 0, "Alpha should have shares");
        assertGt(betaSharesBefore, 0, "Beta should have shares");

        // ── STEP 2: Alpha creates a purchase order via yield escrow ─────
        //   Invoice: $400 for raw materials, 2 delivery milestones,
        //   6-hour buyer challenge window, 7-day arbiter deadline.
        //   Buyer yield share: 20% of net yield to Alpha, 80% to Beta.
        vm.startPrank(agentAlpha);
        vault.approve(address(escrow), type(uint256).max);
        YieldEscrowV2.InvoiceTerms memory purchaseOrder = YieldEscrowV2.InvoiceTerms({
            assetsDue: 400 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp + 12 hours),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 2,
            challengeWindow: uint40(6 hours),
            arbiterDeadline: uint40(7 days),
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.REFUND
        });
        uint256 escrowId = escrow.fundEscrow(agentBeta, purchaseOrder, 2_000);
        vm.stopPrank();

        // Verify policy tracked the spend
        assertEq(vault.balanceOf(agentAlpha), alphaSharesBefore - vault.convertToSharesInvoiceOrWithdraw(400 ether));

        // ── STEP 3: NAV appreciates — yield accrues on escrowed funds ───
        //   Oracle attests NAV = 1.05 (5% gain). Both agents' idle funds
        //   and the escrowed shares appreciate.
        uint64 epoch2 = nav.navEpoch() + 1;
        vm.prank(oracle);
        nav.updateNAV(105e25, int256(0), epoch2); // NAV = 1.05

        // Fast-forward past release lock
        vm.warp(block.timestamp + 12 hours);
        priceOracle.setPrice(3_000e18);

        // ── STEP 4: Beta fulfills the order in 2 milestones ─────────────
        //   Milestone 1: goods shipped (tracking proof)
        //   Milestone 2: goods delivered (delivery confirmation)
        vm.prank(agentBeta);
        escrow.submitFulfillment(
            escrowId,
            YieldEscrowV2.FulfillmentType.DELIVERY,
            keccak256("shipment-tracking-proof-hash")
        );

        vm.warp(block.timestamp + 2 hours);
        vm.prank(agentBeta);
        escrow.submitFulfillment(
            escrowId,
            YieldEscrowV2.FulfillmentType.DELIVERY,
            keccak256("delivery-confirmation-proof-hash")
        );

        // ── STEP 5: Challenge window passes, Beta claims payment ────────
        vm.warp(block.timestamp + 6 hours + 1);
        uint256 betaSharesBeforeRelease = vault.balanceOf(agentBeta);

        vm.prank(agentBeta);
        escrow.release(escrowId);

        uint256 betaSharesAfterRelease = vault.balanceOf(agentBeta);
        assertGt(betaSharesAfterRelease, betaSharesBeforeRelease, "Beta received payment shares");

        // Verify escrow is settled
        (YieldEscrowV2.Escrow memory e,,,) = escrow.getEscrow(escrowId);
        assertEq(uint256(e.status), uint256(YieldEscrowV2.EscrowStatus.RELEASED));
        assertEq(uint256(e.settlementMode), uint256(YieldEscrowV2.SettlementMode.MERCHANT_TIMEOUT_RELEASE));

        // Both agents remain above collateral floor
        assertFalse(grounding.isGroundedNow(agentAlpha), "Alpha above floor");
        assertFalse(grounding.isGroundedNow(agentBeta), "Beta above floor");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  SCENARIO 2: Bidirectional agent commerce + dispute resolution
    //  After scenario 1, Beta orders $200 of packaging services from
    //  Alpha. Alpha fails to deliver, Beta disputes, arbiter resolves
    //  with a refund. Then a second order succeeds.
    // ─────────────────────────────────────────────────────────────────────
    function test_Scenario2_BidirectionalCommerce_WithDispute() public {
        // ── Bootstrap: fund both agents ─────────────────────────────────
        asset.mint(agentAlpha, 1_000 ether);
        vm.startPrank(agentAlpha);
        asset.approve(address(gateway), type(uint256).max);
        gateway.deposit(1_000 ether, agentAlpha, 1_000 ether);
        vm.stopPrank();

        asset.mint(agentBeta, 800 ether);
        vm.startPrank(agentBeta);
        asset.approve(address(gateway), type(uint256).max);
        gateway.deposit(800 ether, agentBeta, 800 ether);
        vm.stopPrank();

        // ── TRADE 1: Beta buys packaging services from Alpha ────────────
        //   Beta is the buyer, Alpha is the merchant.
        //   Beta's policy doesn't enforce merchant allowlist, so any merchant works.
        vm.startPrank(agentBeta);
        vault.approve(address(escrow), type(uint256).max);
        YieldEscrowV2.InvoiceTerms memory serviceOrder = YieldEscrowV2.InvoiceTerms({
            assetsDue: 200 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp + 6 hours),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.SERVICE,
            requiredMilestones: 1,
            challengeWindow: uint40(4 hours),
            arbiterDeadline: uint40(3 days),
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.REFUND
        });
        uint256 escrowId1 = escrow.fundEscrow(agentAlpha, serviceOrder, 2_000);
        vm.stopPrank();

        // Alpha fails to deliver — Beta disputes
        vm.warp(block.timestamp + 6 hours);
        vm.prank(agentBeta);
        escrow.dispute(
            escrowId1,
            YieldEscrowV2.DisputeReason.NON_DELIVERY,
            keccak256("service-not-rendered-evidence")
        );

        // Arbiter reviews and resolves in favor of Beta (refund)
        vm.prank(arbiter);
        escrow.resolveDispute(
            escrowId1,
            YieldEscrowV2.DisputeResolution.REFUND,
            keccak256("arbiter-evidence-non-delivery-confirmed")
        );

        // Beta (buyer) reclaims funds
        uint256 betaSharesBeforeRefund = vault.balanceOf(agentBeta);
        vm.prank(agentBeta);
        escrow.refund(escrowId1);
        assertGt(vault.balanceOf(agentBeta), betaSharesBeforeRefund, "Beta refunded");

        (YieldEscrowV2.Escrow memory e1,,,) = escrow.getEscrow(escrowId1);
        assertEq(uint256(e1.status), uint256(YieldEscrowV2.EscrowStatus.REFUNDED));
        assertEq(uint256(e1.settlementMode), uint256(YieldEscrowV2.SettlementMode.ARBITER_REFUND));

        // ── TRADE 2: Alpha buys raw materials from Beta (success) ───────
        //   This time Alpha is the buyer again, Beta is the merchant.
        //   Simple 1-milestone delivery, buyer releases manually.
        vm.startPrank(agentAlpha);
        vault.approve(address(escrow), type(uint256).max);
        YieldEscrowV2.InvoiceTerms memory materialOrder = YieldEscrowV2.InvoiceTerms({
            assetsDue: 250 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp + 1 hours),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 1,
            challengeWindow: uint40(2 hours),
            arbiterDeadline: uint40(3 days),
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.REFUND
        });
        uint256 escrowId2 = escrow.fundEscrow(agentBeta, materialOrder, 2_000);
        vm.stopPrank();

        // Beta fulfills immediately
        vm.prank(agentBeta);
        escrow.submitFulfillment(
            escrowId2,
            YieldEscrowV2.FulfillmentType.DELIVERY,
            keccak256("materials-delivered-proof")
        );

        // Alpha confirms — buyer-initiated release
        vm.warp(block.timestamp + 1 hours);
        uint256 betaSharesBeforeTrade2 = vault.balanceOf(agentBeta);
        vm.prank(agentAlpha);
        escrow.release(escrowId2);

        (YieldEscrowV2.Escrow memory e2,,,) = escrow.getEscrow(escrowId2);
        assertEq(uint256(e2.status), uint256(YieldEscrowV2.EscrowStatus.RELEASED));
        assertEq(uint256(e2.settlementMode), uint256(YieldEscrowV2.SettlementMode.BUYER_RELEASE));
        assertGt(vault.balanceOf(agentBeta), betaSharesBeforeTrade2, "Beta received payment");

        // Both agents still solvent
        assertFalse(grounding.isGroundedNow(agentAlpha), "Alpha solvent");
        assertFalse(grounding.isGroundedNow(agentBeta), "Beta solvent");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  SCENARIO 3: Full lifecycle — deposit, trade, yield, gas, redeem
    //  Both agents go through a complete commerce cycle including gasless
    //  transaction execution via the yield paymaster and async redemption.
    // ─────────────────────────────────────────────────────────────────────
    function test_Scenario3_FullLifecycle_DepositTradeGasRedeem() public {
        // ── Phase 1: Onboard both agents ────────────────────────────────
        asset.mint(agentAlpha, 2_000 ether);
        vm.startPrank(agentAlpha);
        asset.approve(address(gateway), type(uint256).max);
        gateway.deposit(2_000 ether, agentAlpha, 2_000 ether);
        vm.stopPrank();

        asset.mint(agentBeta, 1_500 ether);
        vm.startPrank(agentBeta);
        asset.approve(address(gateway), type(uint256).max);
        gateway.deposit(1_500 ether, agentBeta, 1_500 ether);
        vm.stopPrank();

        // ── Phase 2: Agents fund gas tanks for gasless ops ──────────────
        vm.startPrank(agentAlpha);
        vault.approve(address(paymaster), type(uint256).max);
        paymaster.topUpGasTank(200 ether);
        vm.stopPrank();

        vm.startPrank(agentBeta);
        vault.approve(address(paymaster), type(uint256).max);
        paymaster.topUpGasTank(150 ether);
        vm.stopPrank();

        assertEq(paymaster.gasTankShares(agentAlpha), 200 ether, "Alpha gas tank funded");
        assertEq(paymaster.gasTankShares(agentBeta), 150 ether, "Beta gas tank funded");

        // Gas tanks count as collateral via GroundingRegistry
        assertFalse(grounding.isGroundedNow(agentAlpha));
        assertFalse(grounding.isGroundedNow(agentBeta));

        // ── Phase 3: Alpha purchases digital goods from Beta ────────────
        vm.startPrank(agentAlpha);
        vault.approve(address(escrow), type(uint256).max);
        YieldEscrowV2.InvoiceTerms memory digitalOrder = YieldEscrowV2.InvoiceTerms({
            assetsDue: 300 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp + 1 hours),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DIGITAL,
            requiredMilestones: 1,
            challengeWindow: uint40(1 hours),
            arbiterDeadline: uint40(3 days),
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.REFUND
        });
        uint256 escrowId = escrow.fundEscrow(agentBeta, digitalOrder, 2_000);
        vm.stopPrank();

        // ── Phase 4: Paymaster charges gas for Alpha's escrow creation ──
        //   In production, the EntryPoint calls validate+postOp atomically.
        //   Here we simulate the entry point charging Alpha for the gas cost
        //   of creating the escrow transaction.
        priceOracle.setPrice(3_000e18);
        uint256 gasUsed = 300_000;
        uint256 gasPrice = 15 gwei;
        uint256 gasCostWei = gasUsed * gasPrice;
        bytes32 opKey1 = keccak256("alpha-escrow-creation-op");

        vm.prank(entryPoint);
        paymaster.validatePaymasterUserOp(opKey1, agentAlpha, gasCostWei);
        vm.prank(entryPoint);
        uint256 alphaGasCharged = paymaster.postOp(opKey1, agentAlpha, gasCostWei);
        assertGt(alphaGasCharged, 0, "Gas charged to Alpha");

        // ── Phase 5: Beta fulfills and gets paid ────────────────────────
        vm.prank(agentBeta);
        escrow.submitFulfillment(
            escrowId,
            YieldEscrowV2.FulfillmentType.DIGITAL,
            keccak256("api-key-delivered-hash")
        );

        vm.warp(block.timestamp + 1 hours);

        // Paymaster charges gas for Beta's fulfillment submission
        bytes32 opKey2 = keccak256("beta-fulfillment-op");
        priceOracle.setPrice(3_000e18);
        vm.prank(entryPoint);
        paymaster.validatePaymasterUserOp(opKey2, agentBeta, gasCostWei);
        vm.prank(entryPoint);
        uint256 betaGasCharged = paymaster.postOp(opKey2, agentBeta, gasCostWei);
        assertGt(betaGasCharged, 0, "Gas charged to Beta");

        // Alpha confirms receipt — buyer release
        vm.prank(agentAlpha);
        escrow.release(escrowId);

        (YieldEscrowV2.Escrow memory e,,,) = escrow.getEscrow(escrowId);
        assertEq(uint256(e.status), uint256(YieldEscrowV2.EscrowStatus.RELEASED));

        // ── Phase 6: Beta redeems profits through async claim queue ─────
        uint256 betaShares = vault.balanceOf(agentBeta);
        uint256 redeemShares = betaShares / 4; // redeem 25% of holdings

        vm.startPrank(agentBeta);
        vault.approve(address(queue), type(uint256).max);
        uint256 claimId = queue.requestRedeem(redeemShares, agentBeta);
        vm.stopPrank();

        // Admin refills buffer & processes queue
        asset.mint(admin, 5_000 ether);
        vm.startPrank(admin);
        asset.approve(address(queue), type(uint256).max);
        queue.refill(5_000 ether);
        queue.processQueue(10);
        vm.stopPrank();

        (,, uint256 assetsOwed,, SSDCClaimQueueV2.Status status) = queue.claims(claimId);
        assertEq(uint256(status), uint256(SSDCClaimQueueV2.Status.CLAIMABLE));
        assertGt(assetsOwed, 0, "Beta has claimable assets");

        // Beta withdraws settlement assets
        uint256 betaAssetsBefore = asset.balanceOf(agentBeta);
        vm.prank(agentBeta);
        queue.claim(claimId);
        assertEq(asset.balanceOf(agentBeta), betaAssetsBefore + assetsOwed, "Beta redeemed");

        // ── Phase 7: Final solvency check — both agents above floor ─────
        assertFalse(grounding.isGroundedNow(agentAlpha), "Alpha remains solvent");
        assertFalse(grounding.isGroundedNow(agentBeta), "Beta remains solvent");

        // Protocol collected fees from gas + escrow yield
        assertGt(vault.balanceOf(protocolFeeCollector), 0, "Protocol earned fees");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  SCENARIO 4: Policy guardrails — agents cannot exceed spend limits
    //  Demonstrates that the policy module enforces per-tx and daily
    //  limits, merchant allowlists, and collateral floor requirements.
    // ─────────────────────────────────────────────────────────────────────
    function test_Scenario4_PolicyGuardrails() public {
        // Fund Alpha with 3,000 SSDC (enough that collateral floor
        // does not bind before the daily spend limit does)
        asset.mint(agentAlpha, 3_000 ether);
        vm.startPrank(agentAlpha);
        asset.approve(address(gateway), type(uint256).max);
        gateway.deposit(3_000 ether, agentAlpha, 3_000 ether);
        vault.approve(address(escrow), type(uint256).max);
        vm.stopPrank();

        // ── Test 1: Per-tx limit blocks oversized purchase ──────────────
        //   Alpha's per-tx limit is 500 SSDC. A 501 SSDC order should fail.
        vm.startPrank(agentAlpha);
        YieldEscrowV2.InvoiceTerms memory bigOrder = YieldEscrowV2.InvoiceTerms({
            assetsDue: 501 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp + 1 hours),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: 0,
            arbiterDeadline: 0,
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_LIMIT.selector);
        escrow.fundEscrow(agentBeta, bigOrder, 0);
        vm.stopPrank();

        // ── Test 2: Merchant allowlist blocks unapproved merchants ──────
        //   Alpha can only pay agentBeta. Paying an unknown address fails.
        address unknownMerchant = address(0xDEAD);
        vm.startPrank(agentAlpha);
        YieldEscrowV2.InvoiceTerms memory unknownOrder = YieldEscrowV2.InvoiceTerms({
            assetsDue: 100 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp + 1 hours),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: 0,
            arbiterDeadline: 0,
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_ALLOWLIST.selector);
        escrow.fundEscrow(unknownMerchant, unknownOrder, 0);
        vm.stopPrank();

        // ── Test 3: Valid purchase within policy succeeds ────────────────
        vm.startPrank(agentAlpha);
        YieldEscrowV2.InvoiceTerms memory validOrder = YieldEscrowV2.InvoiceTerms({
            assetsDue: 400 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp + 1 hours),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: 0,
            arbiterDeadline: 0,
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });
        uint256 validEscrowId = escrow.fundEscrow(agentBeta, validOrder, 0);
        vm.stopPrank();
        assertGt(validEscrowId, 0, "Valid order placed successfully");

        // ── Test 4: Daily limit blocks cumulative overspend ─────────────
        //   Alpha already spent 400. With daily limit 2,000, another 400 should work
        //   but not if it would push total above daily limit when repeated.
        vm.startPrank(agentAlpha);
        // Place three more 400 orders to approach daily limit (400 * 4 = 1600)
        for (uint256 i = 0; i < 3; i++) {
            escrow.fundEscrow(agentBeta, validOrder, 0);
        }

        // Next 400 would make total 2,000, exactly at the limit
        escrow.fundEscrow(agentBeta, validOrder, 0);

        // Now at 2,000 daily — the next 400 should exceed the daily limit
        vm.expectRevert(SSDCPolicyModuleV2.POLICY_DAILY_LIMIT.selector);
        escrow.fundEscrow(agentBeta, validOrder, 0);
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────
    //  SCENARIO 5: Dispute timeout auto-resolution
    //  Alpha buys from Beta, disputes, arbiter doesn't respond within
    //  the deadline. The pre-configured timeout resolution (REFUND) is
    //  automatically applied.
    // ─────────────────────────────────────────────────────────────────────
    function test_Scenario5_DisputeTimeoutAutoResolution() public {
        // Fund Alpha
        asset.mint(agentAlpha, 1_000 ether);
        vm.startPrank(agentAlpha);
        asset.approve(address(gateway), type(uint256).max);
        gateway.deposit(1_000 ether, agentAlpha, 1_000 ether);
        vm.stopPrank();

        // Alpha places order with 3-day arbiter deadline and REFUND timeout
        vm.startPrank(agentAlpha);
        vault.approve(address(escrow), type(uint256).max);
        YieldEscrowV2.InvoiceTerms memory order = YieldEscrowV2.InvoiceTerms({
            assetsDue: 300 ether,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp + 1 hours),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: YieldEscrowV2.FulfillmentType.DELIVERY,
            requiredMilestones: 1,
            challengeWindow: uint40(2 hours),
            arbiterDeadline: uint40(3 days),
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.REFUND
        });
        uint256 escrowId = escrow.fundEscrow(agentBeta, order, 2_000);
        vm.stopPrank();

        uint256 alphaSharesBeforeDispute = vault.balanceOf(agentAlpha);

        // Beta submits fulfillment (but Alpha claims it's wrong)
        vm.prank(agentBeta);
        escrow.submitFulfillment(
            escrowId,
            YieldEscrowV2.FulfillmentType.DELIVERY,
            keccak256("bad-fulfillment")
        );

        // Alpha disputes within challenge window
        vm.prank(agentAlpha);
        escrow.dispute(
            escrowId,
            YieldEscrowV2.DisputeReason.NOT_AS_DESCRIBED,
            keccak256("goods-defective-evidence")
        );

        // Arbiter does NOT respond — time passes beyond the 3-day deadline
        vm.warp(block.timestamp + 3 days + 1);

        // Anyone can execute the timeout — auto-refund to Alpha
        escrow.executeTimeout(escrowId);

        (YieldEscrowV2.Escrow memory e,,,) = escrow.getEscrow(escrowId);
        assertEq(uint256(e.status), uint256(YieldEscrowV2.EscrowStatus.REFUNDED));
        assertEq(uint256(e.settlementMode), uint256(YieldEscrowV2.SettlementMode.DISPUTE_TIMEOUT_REFUND));
        assertGt(vault.balanceOf(agentAlpha), alphaSharesBeforeDispute, "Alpha refunded via timeout");
    }
}
