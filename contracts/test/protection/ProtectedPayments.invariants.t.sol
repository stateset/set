// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ProtectionTestBase.sol";

contract ProtectedPaymentsHandler is Test {
    ProtectedPayments public pp;
    MockSsUSD public token;
    uint256 public merchantKey;
    address public merchant;
    address public buyer;
    address public arbiter;
    address public fallbackArbiter;

    uint256[] public ids;
    uint256 nonce;
    mapping(bytes32 => uint256) public hits;

    constructor(
        ProtectedPayments pp_,
        MockSsUSD token_,
        uint256 merchantKey_,
        address buyer_,
        address arbiter_,
        address fallbackArbiter_
    ) {
        pp = pp_;
        token = token_;
        merchantKey = merchantKey_;
        merchant = vm.addr(merchantKey_);
        buyer = buyer_;
        arbiter = arbiter_;
        fallbackArbiter = fallbackArbiter_;
    }

    function idsLength() external view returns (uint256) {
        return ids.length;
    }

    function _pick(uint256 seed) internal view returns (uint256) {
        return ids[seed % ids.length];
    }

    function pay(uint128 amount) external {
        amount = uint128(bound(amount, 1, 5_000e6));
        ProtectedPayments.PaymentTerms memory t = ProtectedPayments.PaymentTerms({
            buyer: buyer,
            merchant: merchant,
            token: address(token),
            amount: amount,
            arbiter: arbiter,
            fulfillBy: uint64(block.timestamp + 7 days),
            protectionWindow: 30 days,
            orderRef: keccak256(abi.encode(++nonce)),
            deadline: uint64(block.timestamp + 1 hours)
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(merchantKey, pp.hashTerms(t));
        vm.prank(buyer);
        ids.push(pp.pay(t, abi.encodePacked(r, s, v)));
    }

    function warp(uint256 secs) external {
        vm.warp(block.timestamp + bound(secs, 1 hours, 20 days));
    }

    function fulfill(uint256 seed) external {
        if (ids.length == 0) return;
        vm.prank(merchant);
        pp.markFulfilled(_pick(seed), keccak256("f")); hits[keccak256("markFulfilled")]++;
    }

    function finalize(uint256 seed) external {
        if (ids.length == 0) return;
        pp.finalize(_pick(seed)); hits[keccak256("finalize")]++;
    }

    function confirm(uint256 seed) external {
        if (ids.length == 0) return;
        vm.prank(buyer);
        pp.confirm(_pick(seed)); hits[keccak256("confirm")]++;
    }

    function cancel(uint256 seed) external {
        if (ids.length == 0) return;
        vm.prank(buyer);
        pp.cancelUnfulfilled(_pick(seed)); hits[keccak256("cancelUnfulfilled")]++;
    }

    function merchantRefund(uint256 seed, uint128 amount) external {
        if (ids.length == 0) return;
        vm.prank(merchant);
        pp.merchantRefund(_pick(seed), uint128(bound(amount, 1, 5_000e6))); hits[keccak256("merchantRefund")]++;
    }

    function dispute(uint256 seed, uint128 requested) external {
        if (ids.length == 0) return;
        vm.prank(buyer);
        pp.openDispute(
            _pick(seed), ProtectedPayments.DisputeReason.NOT_RECEIVED, uint128(bound(requested, 1, 5_000e6)), keccak256("d")
        ); hits[keccak256("openDispute")]++;
    }

    function accept(uint256 seed) external {
        if (ids.length == 0) return;
        vm.prank(merchant);
        pp.acceptDispute(_pick(seed)); hits[keccak256("acceptDispute")]++;
    }

    function contest(uint256 seed) external {
        if (ids.length == 0) return;
        vm.prank(merchant);
        pp.contest(_pick(seed), keccak256("c")); hits[keccak256("contest")]++;
    }

    function executeDefault(uint256 seed) external {
        if (ids.length == 0) return;
        pp.executeDefault(_pick(seed)); hits[keccak256("executeDefault")]++;
    }

    function resolve(uint256 seed, uint128 award) external {
        if (ids.length == 0) return;
        uint256 id = _pick(seed);
        ProtectedPayments.Dispute memory d = pp.getDispute(id);
        vm.prank(d.arbiter);
        pp.resolve(id, uint128(bound(award, 0, d.requested)), keccak256("r")); hits[keccak256("resolve")]++;
    }

    function settle(uint256 seed, uint128 amount) external {
        if (ids.length == 0) return;
        uint256 id = _pick(seed);
        amount = uint128(bound(amount, 0, 5_000e6));
        vm.prank(buyer);
        try pp.proposeSettlement(id, amount) {} catch {}
        vm.prank(merchant);
        pp.proposeSettlement(id, amount); hits[keccak256("proposeSettlement")]++;
    }

    function timeout(uint256 seed) external {
        if (ids.length == 0) return;
        pp.arbiterTimeout(_pick(seed)); hits[keccak256("arbiterTimeout")]++;
    }

    function depositReserve(uint128 amount) external {
        vm.prank(merchant);
        pp.depositReserve(address(token), uint128(bound(amount, 1, 2_000e6))); hits[keccak256("depositReserve")]++;
    }

    function withdrawReserve(uint128 amount) external {
        vm.prank(merchant);
        pp.withdrawReserve(address(token), uint128(bound(amount, 1, 2_000e6))); hits[keccak256("withdrawReserve")]++;
    }

    function claimPending(uint256 seed) external {
        if (ids.length == 0) return;
        pp.claimPending(_pick(seed)); hits[keccak256("claimPending")]++;
    }

    function withdrawCredits(uint256 who) external {
        address[4] memory accounts = [buyer, merchant, arbiter, fallbackArbiter];
        vm.prank(accounts[who % 4]);
        pp.withdraw(address(token)); hits[keccak256("withdraw")]++;
    }
}

contract ProtectedPaymentsInvariantTest is ProtectionTestBase {
    ProtectedPaymentsHandler handler;

    function setUp() public override {
        super.setUp();
        _enableInstant(2500, 3_000e6);
        token.mint(buyer, 10_000_000e6);
        token.mint(merchant, 10_000_000e6);
        handler = new ProtectedPaymentsHandler(pp, token, merchantKey, buyer, arbiter, fallbackArbiter);
        // Keep arbiters bonded so contested cases can proceed through reassignment.
        _bondArbiter(arbiter, 10 * MIN_BOND);
        _bondArbiter(fallbackArbiter, 10 * MIN_BOND);
        targetContract(address(handler));
    }

    /// @dev Guards against a handler whose calls silently all fail.
    function test_handler_reaches_dispute_states() public {
        handler.pay(1_000e6);
        handler.pay(2_000e6);
        handler.fulfill(0);
        handler.dispute(0, 500e6);
        handler.contest(0);
        handler.resolve(0, 100e6);
        handler.dispute(1, 1_000e6);
        handler.warp(3 days);
        handler.executeDefault(1);
        handler.withdrawCredits(0);
        assertEq(handler.hits(keccak256("markFulfilled")), 1);
        assertEq(handler.hits(keccak256("openDispute")), 2);
        assertEq(handler.hits(keccak256("contest")), 1);
        assertEq(handler.hits(keccak256("resolve")), 1);
        assertEq(handler.hits(keccak256("executeDefault")), 1);
        assertEq(handler.hits(keccak256("withdraw")), 1);
        invariant_balance_matches_liabilities();
    }

    /// @dev Every token the contract holds is attributable to exactly one liability.
    function invariant_balance_matches_liabilities() public view {
        uint256 liabilities = pp.poolBalance(address(token)) + pp.protocolFeesAccrued(address(token))
            + pp.credits(address(token), buyer) + pp.credits(address(token), merchant)
            + pp.credits(address(token), arbiter) + pp.credits(address(token), fallbackArbiter);
        (uint128 free, uint128 locked,) = pp.reserves(merchant, address(token));
        liabilities += uint256(free) + locked;

        uint256 n = handler.idsLength();
        for (uint256 i = 0; i < n; i++) {
            uint256 id = handler.ids(i);
            ProtectedPayments.Payment memory p = pp.getPayment(id);
            liabilities += p.held;
            ProtectedPayments.Dispute memory d = pp.getDispute(id);
            liabilities += uint256(d.buyerBond) + d.merchantFee;
        }
        assertEq(token.balanceOf(address(pp)), liabilities);
    }

    /// @dev Aggregate locked reserve equals the sum of per-payment locks.
    function invariant_reserve_locks_consistent() public view {
        (, uint128 locked,) = pp.reserves(merchant, address(token));
        uint256 sum;
        uint256 n = handler.idsLength();
        for (uint256 i = 0; i < n; i++) {
            sum += pp.getPayment(handler.ids(i)).reserveLocked;
        }
        assertEq(uint256(locked), sum);
    }

    /// @dev Settled payments hold nothing and never refund more than was paid.
    function invariant_settled_payments_are_empty() public view {
        uint256 n = handler.idsLength();
        for (uint256 i = 0; i < n; i++) {
            ProtectedPayments.Payment memory p = pp.getPayment(handler.ids(i));
            assertLe(p.refunded, p.amount);
            if (p.status == ProtectedPayments.Status.COMPLETED || p.status == ProtectedPayments.Status.REFUNDED) {
                assertEq(p.held, 0);
                assertEq(p.reserveLocked, 0);
            }
            if (p.status == ProtectedPayments.Status.REFUNDED) assertEq(p.refunded, p.amount);
        }
    }
}
