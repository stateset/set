// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ProtectionTestBase.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract FeeOnTransferSsUSD is MockSsUSD {
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            uint256 fee = value / 100;
            super._update(from, address(0), fee);
            super._update(from, to, value - fee);
            return;
        }
        super._update(from, to, value);
    }
}

contract MerchantWallet is IERC1271 {
    address public immutable owner;

    constructor(address owner_) {
        owner = owner_;
    }

    function isValidSignature(bytes32 hash, bytes calldata sig) external view returns (bytes4) {
        return ECDSA.recover(hash, sig) == owner ? IERC1271.isValidSignature.selector : bytes4(0xffffffff);
    }
}

contract ProtectedPaymentsTest is ProtectionTestBase {
    event VerifiedEvidenceAttached(uint256 indexed paymentId, address indexed by, bytes32 indexed batchId, bytes32 leaf);

    // ═══ held-mode lifecycle ════════════════════════════════════════════════

    function test_held_payment_completes_after_protection_window() public {
        uint256 id = _payDefault();
        ProtectedPayments.Payment memory p = pp.getPayment(id);
        assertEq(p.held, AMOUNT);
        assertFalse(p.instant);
        assertEq(token.balanceOf(address(pp)), AMOUNT);

        _fulfill(id);
        vm.warp(block.timestamp + WINDOW - 1);
        vm.expectRevert(ProtectedPayments.WindowOpen.selector);
        pp.finalize(id);

        vm.warp(block.timestamp + 1);
        vm.prank(stranger);
        pp.finalize(id);

        assertEq(uint256(_status(id)), uint256(ProtectedPayments.Status.COMPLETED));
        assertEq(pp.credits(address(token), merchant), _net(AMOUNT));
        assertEq(pp.protocolFeesAccrued(address(token)), (AMOUNT * PROTOCOL_BPS) / 10_000);
        assertEq(pp.poolBalance(address(token)), (AMOUNT * PROTECTION_BPS) / 10_000);

        uint256 before = token.balanceOf(merchant);
        vm.prank(merchant);
        pp.withdraw(address(token));
        assertEq(token.balanceOf(merchant) - before, _net(AMOUNT));

        pp.sweepProtocolFees(address(token));
        assertEq(token.balanceOf(feeRecipient), (AMOUNT * PROTOCOL_BPS) / 10_000);
    }

    function test_finalize_requires_fulfillment() public {
        uint256 id = _payDefault();
        vm.warp(block.timestamp + 365 days);
        vm.expectRevert(ProtectedPayments.InvalidStatus.selector);
        pp.finalize(id);
    }

    function test_buyer_confirm_waives_protection() public {
        uint256 id = _payDefault();
        vm.prank(stranger);
        vm.expectRevert(ProtectedPayments.NotAuthorized.selector);
        pp.confirm(id);

        vm.prank(buyer);
        pp.confirm(id);
        assertEq(pp.credits(address(token), merchant), _net(AMOUNT));
    }

    function test_cancel_unfulfilled_refunds_buyer() public {
        uint256 id = _payDefault();
        ProtectedPayments.Payment memory p = pp.getPayment(id);

        vm.prank(buyer);
        vm.expectRevert(ProtectedPayments.DeadlineNotReached.selector);
        pp.cancelUnfulfilled(id);

        vm.warp(p.fulfillBy + 1);
        vm.prank(merchant);
        vm.expectRevert(ProtectedPayments.DeadlinePassed.selector);
        pp.markFulfilled(id, keccak256("late"));

        vm.prank(stranger);
        vm.expectRevert(ProtectedPayments.NotAuthorized.selector);
        pp.cancelUnfulfilled(id);

        vm.prank(buyer);
        pp.cancelUnfulfilled(id);
        assertEq(uint256(_status(id)), uint256(ProtectedPayments.Status.REFUNDED));
        assertEq(pp.credits(address(token), buyer), AMOUNT);
    }

    function test_anyone_cancels_abandoned_unfulfilled_order() public {
        uint256 id = _payDefault();
        ProtectedPayments.Payment memory p = pp.getPayment(id);
        vm.warp(uint256(p.fulfillBy) + WINDOW);
        vm.prank(stranger);
        pp.cancelUnfulfilled(id);
        assertEq(pp.credits(address(token), buyer), AMOUNT);
    }

    function test_merchant_partial_then_full_refund_held() public {
        uint256 id = _payDefault();
        vm.prank(merchant);
        pp.merchantRefund(id, 300e6);
        assertEq(pp.getPayment(id).held, AMOUNT - 300e6);
        assertEq(uint256(_status(id)), uint256(ProtectedPayments.Status.OPEN));

        vm.prank(merchant);
        vm.expectRevert(ProtectedPayments.InvalidAmount.selector);
        pp.merchantRefund(id, 701e6);

        vm.prank(merchant);
        pp.merchantRefund(id, 700e6);
        assertEq(uint256(_status(id)), uint256(ProtectedPayments.Status.REFUNDED));
        assertEq(pp.credits(address(token), buyer), AMOUNT);
    }

    function test_partial_refund_then_completion_charges_fees_on_kept_amount() public {
        uint256 id = _payDefault();
        vm.prank(merchant);
        pp.merchantRefund(id, 400e6);
        vm.prank(buyer);
        pp.confirm(id);
        assertEq(pp.credits(address(token), merchant), _net(600e6));
        assertEq(pp.credits(address(token), buyer), 400e6);
    }

    // ═══ terms & signatures ═════════════════════════════════════════════════

    function test_rejects_signature_from_wrong_key() public {
        ProtectedPayments.PaymentTerms memory t = _terms(AMOUNT);
        bytes memory sig = _sign(t, 0xBAD);
        vm.prank(buyer);
        vm.expectRevert(ProtectedPayments.BadSignature.selector);
        pp.pay(t, sig);
    }

    function test_rejects_tampered_terms() public {
        ProtectedPayments.PaymentTerms memory t = _terms(AMOUNT);
        bytes memory sig = _sign(t, merchantKey);
        t.amount = 1e6;
        vm.prank(buyer);
        vm.expectRevert(ProtectedPayments.BadSignature.selector);
        pp.pay(t, sig);
    }

    function test_rejects_order_replay() public {
        ProtectedPayments.PaymentTerms memory t = _terms(AMOUNT);
        bytes memory sig = _sign(t, merchantKey);
        vm.prank(buyer);
        pp.pay(t, sig);
        vm.prank(buyer);
        vm.expectRevert(ProtectedPayments.OrderRefUsed.selector);
        pp.pay(t, sig);
    }

    function test_rejects_expired_terms_and_other_payer() public {
        ProtectedPayments.PaymentTerms memory t = _terms(AMOUNT);
        bytes memory sig = _sign(t, merchantKey);

        vm.prank(stranger);
        vm.expectRevert(ProtectedPayments.InvalidTerms.selector);
        pp.pay(t, sig);

        vm.warp(t.deadline + 1);
        vm.prank(buyer);
        vm.expectRevert(ProtectedPayments.TermsExpired.selector);
        pp.pay(t, sig);
    }

    function test_open_terms_can_be_paid_by_anyone() public {
        ProtectedPayments.PaymentTerms memory t = _terms(AMOUNT);
        t.buyer = address(0);
        token.mint(stranger, AMOUNT);
        vm.prank(stranger);
        token.approve(address(pp), AMOUNT);
        bytes memory sig = _sign(t, merchantKey);
        vm.prank(stranger);
        uint256 id = pp.pay(t, sig);
        assertEq(pp.getPayment(id).buyer, stranger);
    }

    function test_rejects_bad_windows_arbiter_and_token() public {
        ProtectedPayments.PaymentTerms memory t = _terms(AMOUNT);
        t.protectionWindow = 121 days;
        bytes memory sig = _sign(t, merchantKey);
        vm.prank(buyer);
        vm.expectRevert(ProtectedPayments.InvalidTerms.selector);
        pp.pay(t, sig);

        t = _terms(AMOUNT);
        t.arbiter = address(0xDEAD);
        sig = _sign(t, merchantKey);
        vm.prank(buyer);
        vm.expectRevert(ProtectedPayments.ArbiterNotEligible.selector);
        pp.pay(t, sig);

        t = _terms(AMOUNT);
        t.arbiter = merchant;
        sig = _sign(t, merchantKey);
        vm.prank(buyer);
        vm.expectRevert(ProtectedPayments.ArbiterNotEligible.selector);
        pp.pay(t, sig);

        t = _terms(AMOUNT);
        t.token = address(new MockSsUSD());
        sig = _sign(t, merchantKey);
        vm.prank(buyer);
        vm.expectRevert(ProtectedPayments.TokenNotEnabled.selector);
        pp.pay(t, sig);
    }

    function test_pause_blocks_payments_but_not_settlement() public {
        uint256 id = _payDefault();
        vm.prank(admin);
        pp.setPaymentsPaused(true);

        ProtectedPayments.PaymentTerms memory t = _terms(AMOUNT);
        bytes memory sig = _sign(t, merchantKey);
        vm.prank(buyer);
        vm.expectRevert(ProtectedPayments.Paused.selector);
        pp.pay(t, sig);

        _dispute(id, AMOUNT);
        vm.prank(merchant);
        pp.acceptDispute(id);
        vm.prank(buyer);
        pp.withdraw(address(token));
    }

    function test_erc1271_merchant_wallet() public {
        MerchantWallet wallet = new MerchantWallet(vm.addr(merchantKey));
        ProtectedPayments.PaymentTerms memory t = _terms(AMOUNT);
        t.merchant = address(wallet);
        bytes memory sig = _sign(t, merchantKey);
        vm.prank(buyer);
        uint256 id = pp.pay(t, sig);
        assertEq(pp.getPayment(id).merchant, address(wallet));
    }

    function test_rejects_fee_on_transfer_token() public {
        FeeOnTransferSsUSD fot = new FeeOnTransferSsUSD();
        vm.prank(admin);
        pp.setTokenConfig(
            address(fot),
            ProtectedPayments.TokenConfig({
                enabled: true, protocolFeeBps: 0, protectionFeeBps: 0, buyerDisputeBond: 0, arbitrationFee: 0
            })
        );
        fot.mint(buyer, AMOUNT);
        vm.prank(buyer);
        fot.approve(address(pp), AMOUNT);
        ProtectedPayments.PaymentTerms memory t = _terms(AMOUNT);
        t.token = address(fot);
        bytes memory sig = _sign(t, merchantKey);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(ProtectedPayments.UnsupportedTokenTransfer.selector, AMOUNT, AMOUNT - AMOUNT / 100));
        pp.pay(t, sig);
    }

    function test_governance_config_bounds() public {
        vm.startPrank(admin);
        vm.expectRevert(ProtectedPayments.InvalidConfig.selector);
        pp.setTokenConfig(
            address(token),
            ProtectedPayments.TokenConfig({
                enabled: true, protocolFeeBps: 900, protectionFeeBps: 101, buyerDisputeBond: 0, arbitrationFee: 0
            })
        );
        vm.expectRevert(ProtectedPayments.InvalidConfig.selector);
        pp.setParams(
            ProtectedPayments.Params({
                minProtectionWindow: 10 days,
                maxProtectionWindow: 1 days,
                merchantResponseWindow: 1,
                arbitrationWindow: 1
            })
        );
        vm.expectRevert(ProtectedPayments.InvalidConfig.selector);
        pp.setMerchantRisk(merchant, true, 10_001);
        vm.stopPrank();

        vm.prank(stranger);
        vm.expectRevert();
        pp.setMerchantRisk(merchant, true, 5000);
    }

    function test_fee_snapshot_protects_merchant_from_later_fee_change() public {
        uint256 id = _payDefault();
        vm.prank(admin);
        pp.setTokenConfig(
            address(token),
            ProtectedPayments.TokenConfig({
                enabled: true, protocolFeeBps: 900, protectionFeeBps: 100, buyerDisputeBond: BOND, arbitrationFee: ARB_FEE
            })
        );
        vm.prank(buyer);
        pp.confirm(id);
        assertEq(pp.credits(address(token), merchant), _net(AMOUNT));
    }

    // ═══ disputes: merchant stage ═══════════════════════════════════════════

    function test_merchant_accepts_partial_claim() public {
        uint256 id = _payDefault();
        _fulfill(id);
        _dispute(id, 250e6);
        assertEq(uint256(_status(id)), uint256(ProtectedPayments.Status.DISPUTED));

        vm.prank(stranger);
        vm.expectRevert(ProtectedPayments.NotAuthorized.selector);
        pp.acceptDispute(id);

        vm.prank(merchant);
        pp.acceptDispute(id);

        assertEq(uint256(_status(id)), uint256(ProtectedPayments.Status.COMPLETED));
        assertEq(pp.credits(address(token), buyer), 250e6 + BOND);
        assertEq(pp.credits(address(token), merchant), _net(750e6));
        assertEq(uint256(pp.getDispute(id).outcome), uint256(ProtectedPayments.Outcome.MERCHANT_ACCEPTED));
    }

    function test_merchant_silence_defaults_to_buyer() public {
        uint256 id = _payDefault();
        _fulfill(id);
        _dispute(id, AMOUNT);

        vm.expectRevert(ProtectedPayments.DeadlineNotReached.selector);
        pp.executeDefault(id);

        vm.warp(block.timestamp + 3 days);
        vm.prank(merchant);
        vm.expectRevert(ProtectedPayments.DeadlinePassed.selector);
        pp.contest(id, keccak256("late"));

        vm.prank(stranger);
        pp.executeDefault(id);
        assertEq(uint256(_status(id)), uint256(ProtectedPayments.Status.REFUNDED));
        assertEq(pp.credits(address(token), buyer), AMOUNT + BOND);
        assertEq(pp.credits(address(token), merchant), 0);
    }

    function test_dispute_window_and_single_dispute() public {
        uint256 id = _payDefault();
        _dispute(id, 1e6); // disputable before fulfillment
        vm.prank(buyer);
        vm.expectRevert(ProtectedPayments.InvalidStatus.selector);
        pp.openDispute(id, ProtectedPayments.DisputeReason.OTHER, 1e6, keccak256("again"));

        uint256 id2 = _payDefault();
        _fulfill(id2);
        vm.warp(block.timestamp + WINDOW);
        vm.prank(buyer);
        vm.expectRevert(ProtectedPayments.WindowClosed.selector);
        pp.openDispute(id2, ProtectedPayments.DisputeReason.DEFECTIVE, 1e6, keccak256("late"));
    }

    function test_dispute_input_validation() public {
        uint256 id = _payDefault();
        vm.startPrank(buyer);
        vm.expectRevert(ProtectedPayments.InvalidAmount.selector);
        pp.openDispute(id, ProtectedPayments.DisputeReason.OTHER, AMOUNT + 1, keccak256("x"));
        vm.expectRevert(ProtectedPayments.InvalidConfig.selector);
        pp.openDispute(id, ProtectedPayments.DisputeReason.NONE, 1, keccak256("x"));
        vm.expectRevert(ProtectedPayments.InvalidEvidence.selector);
        pp.openDispute(id, ProtectedPayments.DisputeReason.OTHER, 1, bytes32(0));
        vm.stopPrank();

        vm.prank(merchant);
        vm.expectRevert(ProtectedPayments.NotAuthorized.selector);
        pp.openDispute(id, ProtectedPayments.DisputeReason.OTHER, 1, keccak256("x"));
    }

    // ═══ disputes: negotiated settlement ════════════════════════════════════

    function test_matching_proposals_settle_before_arbitration() public {
        uint256 id = _payDefault();
        _fulfill(id);
        _dispute(id, AMOUNT);

        vm.prank(merchant);
        pp.proposeSettlement(id, 300e6);
        vm.prank(buyer);
        pp.proposeSettlement(id, 400e6); // counter-offer, no settlement
        assertEq(uint256(_status(id)), uint256(ProtectedPayments.Status.DISPUTED));

        vm.prank(merchant);
        pp.proposeSettlement(id, 400e6);
        assertEq(uint256(pp.getDispute(id).outcome), uint256(ProtectedPayments.Outcome.SETTLED));
        assertEq(pp.credits(address(token), buyer), 400e6 + BOND);
        assertEq(pp.credits(address(token), merchant), _net(600e6));
    }

    function test_settlement_during_arbitration_returns_fee_and_withdraws_case() public {
        uint256 id = _payDefault();
        _fulfill(id);
        _dispute(id, AMOUNT);
        _contest(id);
        (,, uint32 openBefore,,,,) = registry.arbiters(arbiter);
        assertEq(openBefore, 1);

        vm.prank(buyer);
        pp.proposeSettlement(id, 500e6);
        vm.prank(merchant);
        pp.proposeSettlement(id, 500e6);

        (,, uint32 openCases, uint32 resolved, uint32 missed,,) = registry.arbiters(arbiter);
        assertEq(openCases, 0);
        assertEq(resolved, 0);
        assertEq(missed, 0);
        assertEq(pp.credits(address(token), arbiter), 0);
        assertEq(pp.credits(address(token), merchant), _net(500e6) + ARB_FEE);
        assertEq(pp.credits(address(token), buyer), 500e6 + BOND);
    }

    function test_third_party_cannot_propose() public {
        uint256 id = _payDefault();
        _dispute(id, AMOUNT);
        vm.prank(stranger);
        vm.expectRevert(ProtectedPayments.NotAuthorized.selector);
        pp.proposeSettlement(id, 1);
    }

    // ═══ disputes: arbitration ══════════════════════════════════════════════

    function test_arbiter_partial_ruling() public {
        uint256 id = _payDefault();
        _fulfill(id);
        _dispute(id, 800e6);
        _contest(id);
        assertEq(pp.getDispute(id).arbiter, arbiter);

        vm.prank(arbiter);
        pp.resolve(id, 300e6, keccak256("ruling"));

        assertEq(pp.credits(address(token), buyer), 300e6 + BOND);
        assertEq(pp.credits(address(token), merchant), _net(700e6));
        assertEq(pp.credits(address(token), arbiter), ARB_FEE);
        (,,, uint32 resolved,,,) = registry.arbiters(arbiter);
        assertEq(resolved, 1);
    }

    function test_merchant_wins_outright_takes_bond() public {
        uint256 id = _payDefault();
        _fulfill(id);
        _dispute(id, AMOUNT);
        _contest(id);
        vm.prank(arbiter);
        pp.resolve(id, 0, keccak256("ruling"));
        assertEq(pp.credits(address(token), buyer), 0);
        assertEq(pp.credits(address(token), merchant), _net(AMOUNT) + BOND);
        assertEq(uint256(_status(id)), uint256(ProtectedPayments.Status.COMPLETED));
    }

    function test_resolve_guards() public {
        uint256 id = _payDefault();
        _fulfill(id);
        _dispute(id, 500e6);

        vm.prank(arbiter);
        vm.expectRevert(ProtectedPayments.InvalidStage.selector);
        pp.resolve(id, 1, keccak256("r"));

        _contest(id);
        vm.prank(stranger);
        vm.expectRevert(ProtectedPayments.NotAuthorized.selector);
        pp.resolve(id, 1, keccak256("r"));

        vm.startPrank(arbiter);
        vm.expectRevert(ProtectedPayments.InvalidAmount.selector);
        pp.resolve(id, 501e6, keccak256("r"));
        vm.expectRevert(ProtectedPayments.InvalidEvidence.selector);
        pp.resolve(id, 1, bytes32(0));
        vm.warp(block.timestamp + 7 days);
        vm.expectRevert(ProtectedPayments.DeadlinePassed.selector);
        pp.resolve(id, 1, keccak256("r"));
        vm.stopPrank();
    }

    function test_arbiter_timeout_slashes_and_reassigns_then_refunds() public {
        uint256 id = _payDefault();
        _fulfill(id);
        _dispute(id, AMOUNT);
        _contest(id);

        vm.expectRevert(ProtectedPayments.DeadlineNotReached.selector);
        pp.arbiterTimeout(id);

        vm.warp(block.timestamp + 7 days);
        pp.arbiterTimeout(id);
        assertEq(pp.getDispute(id).arbiter, fallbackArbiter);
        assertTrue(pp.getDispute(id).reassigned);
        assertEq(token.balanceOf(slashSink), SLASH);
        (, uint128 bond,,, uint32 missed,,) = registry.arbiters(arbiter);
        assertEq(bond, MIN_BOND - SLASH);
        assertEq(missed, 1);
        assertFalse(registry.isEligible(arbiter));

        vm.warp(block.timestamp + 7 days);
        pp.arbiterTimeout(id);
        assertEq(uint256(pp.getDispute(id).outcome), uint256(ProtectedPayments.Outcome.ARBITER_TIMEOUT));
        assertEq(pp.credits(address(token), buyer), AMOUNT + BOND);
        assertEq(pp.credits(address(token), merchant), ARB_FEE);
        assertEq(token.balanceOf(slashSink), 2 * SLASH);
    }

    function test_fallback_arbiter_can_rule_after_reassignment() public {
        uint256 id = _payDefault();
        _fulfill(id);
        _dispute(id, AMOUNT);
        _contest(id);
        vm.warp(block.timestamp + 7 days);
        pp.arbiterTimeout(id);

        vm.prank(arbiter);
        vm.expectRevert(ProtectedPayments.NotAuthorized.selector);
        pp.resolve(id, 0, keccak256("stale"));

        vm.prank(fallbackArbiter);
        pp.resolve(id, 100e6, keccak256("ruling"));
        assertEq(pp.credits(address(token), fallbackArbiter), ARB_FEE);
    }

    function test_contest_falls_back_when_named_arbiter_ineligible() public {
        uint256 id = _payDefault();
        vm.prank(admin);
        registry.setApproved(arbiter, false);
        _dispute(id, AMOUNT);
        _contest(id);
        assertEq(pp.getDispute(id).arbiter, fallbackArbiter);
    }

    function test_contest_without_any_arbiter_reverts_and_merchant_defaults() public {
        uint256 id = _payDefault();
        vm.startPrank(admin);
        registry.setApproved(arbiter, false);
        registry.setApproved(fallbackArbiter, false);
        vm.stopPrank();
        _dispute(id, AMOUNT);
        vm.prank(merchant);
        vm.expectRevert(ProtectedPayments.NoArbiter.selector);
        pp.contest(id, keccak256("rebuttal"));

        vm.warp(block.timestamp + 3 days);
        pp.executeDefault(id);
        assertEq(pp.credits(address(token), buyer), AMOUNT + BOND);
    }

    // ═══ instant settlement & chargebacks ═══════════════════════════════════

    function test_instant_settlement_pays_merchant_immediately() public {
        _enableInstant(2000, 1_000e6); // 20% reserve ratio
        assertEq(pp.instantCapacity(merchant, address(token)), 5_000e6);

        uint256 before = token.balanceOf(merchant);
        uint256 id = _payDefault();
        ProtectedPayments.Payment memory p = pp.getPayment(id);
        assertTrue(p.instant);
        assertEq(p.held, 0);
        assertEq(p.reserveLocked, 200e6);
        assertEq(token.balanceOf(merchant) - before, _net(AMOUNT));

        (uint128 free, uint128 locked,) = pp.reserves(merchant, address(token));
        assertEq(free, 800e6);
        assertEq(locked, 200e6);

        _fulfill(id);
        vm.warp(block.timestamp + WINDOW);
        pp.finalize(id);
        (free, locked,) = pp.reserves(merchant, address(token));
        assertEq(free, 1_000e6);
        assertEq(locked, 0);
        assertEq(pp.credits(address(token), merchant), 0); // already paid at purchase
    }

    function test_chargeback_after_instant_settlement_from_locked_reserve() public {
        _enableInstant(2000, 1_000e6);
        uint256 id = _payDefault();
        _fulfill(id);
        vm.warp(block.timestamp + 20 days); // merchant was paid 20 days ago
        _dispute(id, 150e6);
        vm.prank(merchant);
        pp.acceptDispute(id);

        assertEq(pp.credits(address(token), buyer), 150e6 + BOND);
        (uint128 free, uint128 locked, uint128 debt) = pp.reserves(merchant, address(token));
        assertEq(free, 850e6);
        assertEq(locked, 0);
        assertEq(debt, 0);
    }

    function test_chargeback_waterfall_reserve_pool_debt_pending() public {
        _enableInstant(1000, 200e6); // 10% ratio → lock 100 of 200
        uint256 id = _payDefault();
        _fulfill(id);

        // Pool holds this payment's protection fee (5) plus a 45 top-up.
        vm.prank(stranger);
        vm.expectRevert(); // no balance/allowance
        pp.fundPool(address(token), 45e6);
        token.mint(address(this), 45e6);
        token.approve(address(pp), 45e6);
        pp.fundPool(address(token), 45e6);
        assertEq(pp.poolBalance(address(token)), 50e6);

        _dispute(id, AMOUNT);
        vm.warp(block.timestamp + 3 days);
        pp.executeDefault(id); // merchant silent; buyer owed 1,000

        // 100 locked + 100 free + 50 pool = 250 paid; 750 pending.
        assertEq(pp.credits(address(token), buyer), 250e6 + BOND);
        assertEq(pp.pendingClaims(id), 750e6);
        assertEq(pp.poolBalance(address(token)), 0);
        (uint128 free, uint128 locked, uint128 debt) = pp.reserves(merchant, address(token));
        assertEq(free, 0);
        assertEq(locked, 0);
        assertEq(debt, 800e6);
        assertEq(uint256(_status(id)), uint256(ProtectedPayments.Status.REFUNDED));

        // Debt blocks withdrawals and instant settlement.
        vm.prank(merchant);
        vm.expectRevert(ProtectedPayments.DebtOutstanding.selector);
        pp.withdrawReserve(address(token), 1);
        assertEq(pp.instantCapacity(merchant, address(token)), 0);

        vm.expectRevert(ProtectedPayments.NothingToClaim.selector);
        pp.claimPending(id);

        // Merchant deposits: debt repaid into pool, buyer claims from pool.
        vm.prank(merchant);
        pp.depositReserve(address(token), 900e6);
        (free,, debt) = pp.reserves(merchant, address(token));
        assertEq(debt, 0);
        assertEq(free, 100e6);
        assertEq(pp.poolBalance(address(token)), 800e6);

        pp.claimPending(id);
        assertEq(pp.pendingClaims(id), 0);
        assertEq(pp.credits(address(token), buyer), AMOUNT + BOND);
        assertEq(pp.poolBalance(address(token)), 50e6);
    }

    function test_insufficient_reserve_falls_back_to_held() public {
        _enableInstant(5000, 100e6);
        uint256 id = _payDefault();
        ProtectedPayments.Payment memory p = pp.getPayment(id);
        assertFalse(p.instant);
        assertEq(p.held, AMOUNT);
    }

    function test_instant_merchant_refund_funded_from_wallet() public {
        _enableInstant(2000, 1_000e6);
        uint256 id = _payDefault();
        uint256 before = token.balanceOf(merchant);
        vm.prank(merchant);
        pp.merchantRefund(id, AMOUNT);
        assertEq(before - token.balanceOf(merchant), AMOUNT);
        assertEq(pp.credits(address(token), buyer), AMOUNT);
        (uint128 free, uint128 locked,) = pp.reserves(merchant, address(token));
        assertEq(free, 1_000e6);
        assertEq(locked, 0);
    }

    function test_reserve_withdraw_limited_to_free() public {
        _enableInstant(2000, 1_000e6);
        _payDefault();
        vm.startPrank(merchant);
        vm.expectRevert(ProtectedPayments.InsufficientReserve.selector);
        pp.withdrawReserve(address(token), 801e6);
        pp.withdrawReserve(address(token), 800e6);
        vm.stopPrank();
    }

    // ═══ verified evidence ══════════════════════════════════════════════════

    function test_attach_verified_evidence() public {
        MockInclusionVerifier verifier = new MockInclusionVerifier();
        uint256 id = _payDefault();
        bytes32[] memory proof = new bytes32[](0);
        bytes32 leaf = keccak256("ves:order.delivered");

        vm.prank(buyer);
        vm.expectRevert(ProtectedPayments.InvalidEvidence.selector);
        pp.attachVerifiedEvidence(id, bytes32("batch"), leaf, proof, 0);

        vm.prank(admin);
        pp.setEvidenceVerifier(verifier);

        vm.prank(merchant);
        vm.expectRevert(ProtectedPayments.InvalidEvidence.selector);
        pp.attachVerifiedEvidence(id, bytes32("batch"), leaf, proof, 0);

        verifier.setValid(leaf, true);
        vm.prank(stranger);
        vm.expectRevert(ProtectedPayments.NotAuthorized.selector);
        pp.attachVerifiedEvidence(id, bytes32("batch"), leaf, proof, 0);

        vm.expectEmit(true, true, true, true, address(pp));
        emit VerifiedEvidenceAttached(id, merchant, bytes32("batch"), leaf);
        vm.prank(merchant);
        pp.attachVerifiedEvidence(id, bytes32("batch"), leaf, proof, 0);

        _dispute(id, AMOUNT);
        _contest(id);
        vm.prank(arbiter);
        pp.attachVerifiedEvidence(id, bytes32("batch"), leaf, proof, 0);
    }

    // ═══ fuzz ═══════════════════════════════════════════════════════════════

    function testFuzz_arbitrated_split_conserves_value(uint128 amount, uint128 requested, uint128 award) public {
        amount = uint128(bound(amount, 1, 50_000e6));
        requested = uint128(bound(requested, 1, amount));
        award = uint128(bound(award, 0, requested));

        uint256 id = _pay(_terms(amount));
        _fulfill(id);
        _dispute(id, requested);
        _contest(id);
        vm.prank(arbiter);
        pp.resolve(id, award, keccak256("ruling"));

        uint256 kept = amount - award;
        uint256 fees = (kept * PROTOCOL_BPS) / 10_000 + (kept * PROTECTION_BPS) / 10_000;
        uint256 total = pp.credits(address(token), buyer) + pp.credits(address(token), merchant)
            + pp.credits(address(token), arbiter) + pp.protocolFeesAccrued(address(token))
            + pp.poolBalance(address(token));
        assertEq(total, uint256(amount) + BOND + ARB_FEE);
        assertEq(pp.protocolFeesAccrued(address(token)) + pp.poolBalance(address(token)), fees);
        assertEq(token.balanceOf(address(pp)), total);
    }
}
