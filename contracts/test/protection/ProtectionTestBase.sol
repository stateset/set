// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../commerce/protection/ProtectedPayments.sol";
import "../../commerce/protection/ArbiterRegistry.sol";
import "../MockSsUSD.sol";

contract MockInclusionVerifier is IVesInclusionVerifier {
    mapping(bytes32 => bool) public valid;

    function setValid(bytes32 leaf, bool ok) external {
        valid[leaf] = ok;
    }

    function verifyInclusion(bytes32, bytes32 leaf, bytes32[] calldata, uint256) external view returns (bool) {
        return valid[leaf];
    }
}

abstract contract ProtectionTestBase is Test {
    ProtectedPayments pp;
    ArbiterRegistry registry;
    MockSsUSD token;

    address admin = address(0xAD);
    address feeRecipient = address(0xFEE);
    address slashSink = address(0x5145);
    address buyer = address(0xB0B);
    address stranger = address(0x5757);
    address arbiter = address(0xA1);
    address fallbackArbiter = address(0xA2);

    uint256 merchantKey = 0xC0FFEE;
    address merchant;

    uint128 constant AMOUNT = 1_000e6;
    uint128 constant BOND = 25e6;
    uint128 constant ARB_FEE = 20e6;
    uint128 constant MIN_BOND = 500e6;
    uint128 constant SLASH = 100e6;
    uint16 constant PROTOCOL_BPS = 100; // 1%
    uint16 constant PROTECTION_BPS = 50; // 0.5%
    uint32 constant WINDOW = 30 days;

    uint256 orderNonce;

    function setUp() public virtual {
        merchant = vm.addr(merchantKey);
        token = new MockSsUSD();
        registry = new ArbiterRegistry(IERC20(address(token)), admin, MIN_BOND, SLASH, 14 days, slashSink);
        pp = new ProtectedPayments(
            registry,
            admin,
            feeRecipient,
            ProtectedPayments.Params({
                minProtectionWindow: 1 days,
                maxProtectionWindow: 120 days,
                merchantResponseWindow: 3 days,
                arbitrationWindow: 7 days,
                maxDisputeRatioBps: 0,
                minPaymentsForRatio: 0
            })
        );

        vm.startPrank(admin);
        registry.grantRole(registry.COURT_ROLE(), address(pp));
        pp.setTokenConfig(
            address(token),
            ProtectedPayments.TokenConfig({
                enabled: true,
                protocolFeeBps: PROTOCOL_BPS,
                protectionFeeBps: PROTECTION_BPS,
                buyerDisputeBond: BOND,
                arbitrationFee: ARB_FEE
            })
        );
        pp.setDefaultArbiter(fallbackArbiter);
        registry.setApproved(arbiter, true);
        registry.setApproved(fallbackArbiter, true);
        vm.stopPrank();

        _bondArbiter(arbiter, MIN_BOND);
        _bondArbiter(fallbackArbiter, MIN_BOND);

        token.mint(buyer, 100_000e6);
        token.mint(merchant, 100_000e6);
        vm.prank(buyer);
        token.approve(address(pp), type(uint256).max);
        vm.prank(merchant);
        token.approve(address(pp), type(uint256).max);
    }

    function _bondArbiter(address a, uint128 amount) internal {
        token.mint(a, amount);
        vm.startPrank(a);
        token.approve(address(registry), amount);
        registry.depositBond(amount);
        vm.stopPrank();
    }

    function _terms(uint128 amount) internal returns (ProtectedPayments.PaymentTerms memory t) {
        t = ProtectedPayments.PaymentTerms({
            buyer: buyer,
            merchant: merchant,
            token: address(token),
            amount: amount,
            arbiter: arbiter,
            fulfillBy: uint64(block.timestamp + 7 days),
            protectionWindow: WINDOW,
            orderRef: keccak256(abi.encode("order", ++orderNonce)),
            deadline: uint64(block.timestamp + 1 hours)
        });
    }

    function _sign(ProtectedPayments.PaymentTerms memory t, uint256 key) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, pp.hashTerms(t));
        return abi.encodePacked(r, s, v);
    }

    function _pay(ProtectedPayments.PaymentTerms memory t) internal returns (uint256 id) {
        bytes memory sig = _sign(t, merchantKey);
        vm.prank(t.buyer == address(0) ? buyer : t.buyer);
        id = pp.pay(t, sig);
    }

    function _payDefault() internal returns (uint256) {
        return _pay(_terms(AMOUNT));
    }

    function _fulfill(uint256 id) internal {
        vm.prank(merchant);
        pp.markFulfilled(id, keccak256("tracking"));
    }

    function _dispute(uint256 id, uint128 requested) internal {
        vm.prank(buyer);
        pp.openDispute(id, ProtectedPayments.DisputeReason.NOT_AS_DESCRIBED, requested, keccak256("photos"));
    }

    function _contest(uint256 id) internal {
        vm.prank(merchant);
        pp.contest(id, keccak256("rebuttal"));
    }

    function _enableInstant(uint16 ratioBps, uint128 reserve) internal {
        vm.prank(admin);
        pp.setMerchantRisk(merchant, true, ratioBps);
        if (reserve > 0) {
            vm.prank(merchant);
            pp.depositReserve(address(token), reserve);
        }
    }

    function _net(uint256 amount) internal pure returns (uint256) {
        return amount - (amount * PROTOCOL_BPS) / 10_000 - (amount * PROTECTION_BPS) / 10_000;
    }

    function _status(uint256 id) internal view returns (ProtectedPayments.Status) {
        return pp.getPayment(id).status;
    }
}
