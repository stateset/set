// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2QuickstartBase} from "./quickstart/SSDCV2QuickstartBase.sol";
import {SSDCV2CircuitBreaker} from "../../../stablecoin/v2/SSDCV2CircuitBreaker.sol";
import {ProofOfReservesV2, IVaultReservesV2} from "../../../stablecoin/v2/ProofOfReservesV2.sol";
import {SSDCStatusLensV2} from "../../../stablecoin/v2/SSDCStatusLensV2.sol";

/// @notice Exercises the permissionless insolvency trip: the circuit breaker consuming the
///         Proof-of-Reserves solvency signal on a fully-wired SSDC V2 deployment.
contract ProofOfReservesBreakerV2Test is SSDCV2QuickstartBase {
    ProofOfReservesV2 internal por;

    address internal attestor = address(0xA77E5);
    address internal reserveManager = address(0xBEEF);
    address internal anyone = address(0x12345);

    uint40 internal constant MAX_STALENESS = 24 hours;
    uint16 internal constant MIN_COVERAGE_BPS = 10_000;
    uint16 internal constant MAX_DEVIATION_BPS = 2_000;

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        por = new ProofOfReservesV2(
            admin,
            IVaultReservesV2(address(vault)),
            MAX_STALENESS,
            MIN_COVERAGE_BPS,
            MAX_DEVIATION_BPS
        );
        por.grantRole(por.ATTESTOR_ROLE(), attestor);
        breaker.setProofOfReserves(por);

        // Simplify deposits and enable off-chain reserve deployment for these tests.
        vault.setGatewayRequired(false);
        vault.setReserveConfig(reserveManager, 0, 10_000);
        vm.stopPrank();
    }

    function _deposit(address user, uint256 amount) internal {
        asset.mint(user, amount);
        vm.startPrank(user);
        asset.approve(address(vault), amount);
        vault.deposit(amount, user);
        vm.stopPrank();
    }

    function _attest(uint256 reserveValue, uint64 epoch) internal {
        vm.prank(attestor);
        por.submitAttestation(reserveValue, keccak256(abi.encode(epoch)), epoch);
    }

    /// Undercollateralize: deposit, push assets off-chain, then attest them below book value.
    function _makeInsolvent() internal {
        _deposit(anyone, 1_000e6);
        vm.prank(admin);
        vault.deployReserve(600e6); // on-chain liquid now 400e6
        _attest(300e6, 1); // backing = 700e6 vs 1_000e6 liabilities -> 7000 bps < floor
    }

    function test_TripsWhenFreshAndUndercollateralized() public {
        _makeInsolvent();
        assertFalse(por.isSolvent());
        assertEq(por.coverageRatioBps(), 7_000);

        // Anyone — no role — can trip once insolvency is provable on-chain.
        vm.prank(anyone);
        breaker.tripIfInsolvent();

        assertTrue(breaker.breakerTripped());
        assertTrue(vault.mintRedeemPaused());
        assertTrue(nav.navUpdatesPaused());
    }

    function test_RevertsWhenSolvent() public {
        _deposit(anyone, 1_000e6); // nothing deployed -> fully backed on-chain
        _attest(0, 1);
        assertTrue(por.isSolvent());

        vm.prank(anyone);
        vm.expectRevert(SSDCV2CircuitBreaker.RESERVES_SOLVENT.selector);
        breaker.tripIfInsolvent();
        assertFalse(breaker.breakerTripped());
    }

    function test_RevertsWhenStale_NoGriefing() public {
        _makeInsolvent();
        // Even though coverage is below floor, a STALE attestation must not allow a trip —
        // staleness happens routinely and would otherwise be a griefing vector.
        vm.warp(block.timestamp + MAX_STALENESS);
        assertTrue(por.isStale());

        vm.prank(anyone);
        vm.expectRevert(SSDCV2CircuitBreaker.RESERVES_SOLVENT.selector);
        breaker.tripIfInsolvent();
        assertFalse(breaker.breakerTripped());
    }

    function test_RevertsWhenProofNotSet() public {
        // A breaker with no PoR wired cannot be tripped this way.
        SSDCV2CircuitBreaker bare = new SSDCV2CircuitBreaker(nav, vault, queue, bridge, escrow, paymaster, admin);
        vm.prank(anyone);
        vm.expectRevert(SSDCV2CircuitBreaker.PROOF_NOT_SET.selector);
        bare.tripIfInsolvent();
    }

    function test_OnlyAdminSetsProofOfReserves() public {
        vm.prank(attestor);
        vm.expectRevert();
        breaker.setProofOfReserves(por);
    }

    function test_LensSurfacesReserveStatus() public {
        _makeInsolvent(); // deposit 1000e6, deploy 600e6 off-chain, attest 300e6
        SSDCStatusLensV2.ReserveStatus memory rs = lens.getReserveStatus(por);

        assertTrue(rs.attested);
        assertFalse(rs.solvent);
        assertFalse(rs.stale);
        assertEq(rs.coverageRatioBps, 7_000); // (400 + 300) / 1000
        assertEq(rs.reserveMarkBps, 5_000); // attested 300 / book-value deployed 600
        assertEq(rs.attestedReserveValue, 300e6);
        assertEq(rs.totalBackingValue, 700e6);
        assertEq(rs.liabilityAssets, 1_000e6);
    }

    function test_LensRejectsZeroProofOfReserves() public {
        vm.expectRevert(SSDCStatusLensV2.ZeroAddress.selector);
        lens.getReserveStatus(ProofOfReservesV2(address(0)));
    }
}
