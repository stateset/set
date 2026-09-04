// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { SSDCV2TestBase } from "./SSDCV2TestBase.sol";
import { ProofOfReservesV2, IVaultReservesV2 } from "../../../stablecoin/v2/ProofOfReservesV2.sol";

contract ProofOfReservesV2Test is SSDCV2TestBase {
    ProofOfReservesV2 internal por;

    address internal attestor = address(0xA77E5);
    address internal reserveManager = address(0xBEEF);

    uint40 internal constant MAX_STALENESS = 24 hours;
    uint16 internal constant MIN_COVERAGE_BPS = 10_000; // require full backing
    uint16 internal constant MAX_DEVIATION_BPS = 2000; // 20% max move per attestation

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
        // Separation of duties: attestor is distinct from the NAV oracle.
        por.grantRole(por.ATTESTOR_ROLE(), attestor);

        // Allow the vault to deploy assets off-chain so we can exercise reserve coverage.
        vault.setReserveConfig(reserveManager, 0, 10_000);
        vm.stopPrank();
    }

    function _attest(
        uint256 reserveValue,
        uint64 epoch
    ) internal {
        vm.prank(attestor);
        por.submitAttestation(reserveValue, keccak256(abi.encode("portfolio", epoch)), epoch);
    }

    // --- Initial state ------------------------------------------------------

    function test_NoAttestation_IsStaleAndInsolvent() public view {
        assertFalse(por.hasAttestation());
        assertTrue(por.isStale());
        assertFalse(por.isSolvent());
        assertEq(por.attestationAge(), type(uint256).max);
    }

    function test_Constructor_RejectsBadConfig() public {
        vm.expectRevert(ProofOfReservesV2.ZERO_ADDRESS.selector);
        new ProofOfReservesV2(
            address(0),
            IVaultReservesV2(address(vault)),
            MAX_STALENESS,
            MIN_COVERAGE_BPS,
            MAX_DEVIATION_BPS
        );

        vm.expectRevert(ProofOfReservesV2.INVALID_CONFIG.selector);
        new ProofOfReservesV2(
            admin, IVaultReservesV2(address(vault)), 0, MIN_COVERAGE_BPS, MAX_DEVIATION_BPS
        );

        vm.expectRevert(ProofOfReservesV2.INVALID_CONFIG.selector);
        new ProofOfReservesV2(
            admin, IVaultReservesV2(address(vault)), MAX_STALENESS, MIN_COVERAGE_BPS, 10_001
        );

        vm.expectRevert(ProofOfReservesV2.INVALID_CONFIG.selector);
        new ProofOfReservesV2(
            admin,
            IVaultReservesV2(address(vault)),
            uint256(type(uint40).max) + 1,
            MIN_COVERAGE_BPS,
            MAX_DEVIATION_BPS
        );

        vm.expectRevert(ProofOfReservesV2.INVALID_CONFIG.selector);
        new ProofOfReservesV2(
            admin,
            IVaultReservesV2(address(vault)),
            MAX_STALENESS,
            uint256(type(uint16).max) + 1,
            MAX_DEVIATION_BPS
        );
    }

    function test_SetConfigRejectsNarrowingOverflow() public {
        vm.startPrank(admin);

        vm.expectRevert(ProofOfReservesV2.INVALID_CONFIG.selector);
        por.setConfig(uint256(type(uint40).max) + 1, MIN_COVERAGE_BPS, MAX_DEVIATION_BPS);

        vm.expectRevert(ProofOfReservesV2.INVALID_CONFIG.selector);
        por.setConfig(MAX_STALENESS, uint256(type(uint16).max) + 1, MAX_DEVIATION_BPS);
        vm.stopPrank();

        assertEq(por.maxStaleness(), MAX_STALENESS);
        assertEq(por.minCoverageBps(), MIN_COVERAGE_BPS);
    }

    // --- Coverage with fully on-chain backing -------------------------------

    function test_FullyOnchain_Solvent() public {
        _mintAndDeposit(user1, 1000e6);
        // Nothing deployed off-chain; vault holds all assets on-chain.
        _attest(0, 1);

        assertEq(por.liabilities(), 1000e6);
        assertEq(por.onchainLiquidValue(), 1000e6);
        assertEq(por.totalBackingValue(), 1000e6);
        assertEq(por.coverageRatioBps(), 10_000);
        assertTrue(por.isSolvent());
    }

    // --- Coverage with off-chain reserves -----------------------------------

    function test_DeployedReserves_AttestationCarriesCoverage() public {
        _mintAndDeposit(user1, 1000e6);

        vm.prank(admin);
        vault.deployReserve(600e6); // move 600 off-chain
        assertEq(por.onchainLiquidValue(), 400e6);
        assertEq(vault.deployedReserveAssets(), 600e6);

        // Attest the off-chain portfolio at full book value -> fully covered.
        _attest(600e6, 1);
        assertEq(por.totalBackingValue(), 1000e6);
        assertEq(por.coverageRatioBps(), 10_000);
        assertEq(por.reserveMarkBps(), 10_000);
        assertTrue(por.isSolvent());
    }

    function test_OffchainLoss_DetectedAsInsolvent() public {
        _mintAndDeposit(user1, 1000e6);
        vm.prank(admin);
        vault.deployReserve(600e6);
        _attest(600e6, 1);
        assertTrue(por.isSolvent());

        // Off-chain reserves lose 10% of value. Book value (deployedReserveAssets) still says 600e6,
        // but the attestation reveals the real mark — coverage and reserveMark both drop.
        _attest(540e6, 2);
        assertEq(por.totalBackingValue(), 940e6);
        assertEq(por.coverageRatioBps(), 9400);
        assertEq(por.reserveMarkBps(), 9000); // 540 / 600
        assertFalse(por.isSolvent());
    }

    // --- Epoch monotonicity -------------------------------------------------

    function test_EpochMustIncrease() public {
        _attest(100e6, 5);
        vm.prank(attestor);
        vm.expectRevert(ProofOfReservesV2.EPOCH.selector);
        por.submitAttestation(100e6, bytes32(0), 5);

        vm.prank(attestor);
        vm.expectRevert(ProofOfReservesV2.EPOCH.selector);
        por.submitAttestation(100e6, bytes32(0), 4);
    }

    // --- Deviation guard ----------------------------------------------------

    function test_DeviationGuard_BlocksLargeSwing() public {
        _attest(600e6, 1);

        // 30% drop exceeds the 20% deviation guard.
        vm.prank(attestor);
        vm.expectRevert(ProofOfReservesV2.DEVIATION.selector);
        por.submitAttestation(420e6, bytes32(0), 2);

        // A 20% move is exactly at the bound and allowed.
        _attest(480e6, 2);
        assertEq(por.attestedReserveValue(), 480e6);
    }

    function test_ForceAttestation_BypassesGuardAndPause() public {
        _attest(600e6, 1);

        vm.prank(admin);
        por.setPaused(true);

        // Normal path blocked by pause...
        vm.prank(attestor);
        vm.expectRevert(ProofOfReservesV2.PAUSED.selector);
        por.submitAttestation(420e6, bytes32(0), 2);

        // ...governance force path records a legitimate large discontinuity anyway.
        vm.prank(admin);
        por.forceAttestation(420e6, keccak256("restatement"), 2);
        assertEq(por.attestedReserveValue(), 420e6);
        (,, uint64 ep,,) = por.latest();
        assertEq(ep, 2); // epoch recorded
    }

    // --- Staleness ----------------------------------------------------------

    function test_Staleness_FlipsInsolvent() public {
        _mintAndDeposit(user1, 1000e6);
        _attest(0, 1);
        assertTrue(por.isSolvent());

        vm.warp(block.timestamp + MAX_STALENESS);
        assertTrue(por.isStale());
        assertFalse(por.isSolvent());
    }

    // --- Role separation ----------------------------------------------------

    function test_OnlyAttestorCanSubmit() public {
        vm.prank(user1);
        vm.expectRevert();
        por.submitAttestation(100e6, bytes32(0), 1);

        // The NAV oracle has no power here — duties are separated.
        vm.prank(oracle);
        vm.expectRevert();
        por.submitAttestation(100e6, bytes32(0), 1);
    }

    function test_OnlyAdminCanForceOrConfigure() public {
        vm.prank(attestor);
        vm.expectRevert();
        por.forceAttestation(100e6, bytes32(0), 1);

        vm.prank(attestor);
        vm.expectRevert();
        por.setConfig(MAX_STALENESS, MIN_COVERAGE_BPS, MAX_DEVIATION_BPS);
    }

    // --- Pause --------------------------------------------------------------

    function test_Pause_BlocksSubmit() public {
        vm.prank(admin);
        por.setPaused(true);

        vm.prank(attestor);
        vm.expectRevert(ProofOfReservesV2.PAUSED.selector);
        por.submitAttestation(100e6, bytes32(0), 1);
    }
}
