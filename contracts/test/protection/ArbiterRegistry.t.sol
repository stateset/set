// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ProtectionTestBase.sol";

contract ArbiterRegistryTest is ProtectionTestBase {
    address court = address(0xC0C0);
    address newArbiter = address(0xA3);

    function setUp() public override {
        super.setUp();
        vm.startPrank(admin);
        registry.grantRole(registry.COURT_ROLE(), court);
        registry.setApproved(newArbiter, true);
        vm.stopPrank();
    }

    function test_eligibility_requires_approval_and_min_bond() public {
        assertFalse(registry.isEligible(newArbiter));
        _bondArbiter(newArbiter, MIN_BOND - 1);
        assertFalse(registry.isEligible(newArbiter));
        _bondArbiter(newArbiter, 1);
        assertTrue(registry.isEligible(newArbiter));
        vm.prank(admin);
        registry.setApproved(newArbiter, false);
        assertFalse(registry.isEligible(newArbiter));
    }

    function test_only_court_opens_and_closes_cases() public {
        vm.prank(stranger);
        vm.expectRevert();
        registry.openCase(arbiter);
        vm.prank(stranger);
        vm.expectRevert();
        registry.closeCase(arbiter, ArbiterRegistry.CaseOutcome.MISSED);
    }

    function test_open_case_requires_eligible_arbiter() public {
        vm.prank(court);
        vm.expectRevert(ArbiterRegistry.NotApproved.selector);
        registry.openCase(newArbiter);
    }

    function test_withdraw_excess_bond_needs_no_open_cases_and_keeps_minimum() public {
        _bondArbiter(arbiter, 100e6);
        vm.prank(court);
        registry.openCase(arbiter);

        vm.prank(arbiter);
        vm.expectRevert(ArbiterRegistry.OpenCases.selector);
        registry.withdrawExcessBond(100e6);

        vm.prank(court);
        registry.closeCase(arbiter, ArbiterRegistry.CaseOutcome.RESOLVED);

        vm.startPrank(arbiter);
        vm.expectRevert(ArbiterRegistry.InsufficientBond.selector);
        registry.withdrawExcessBond(100e6 + 1);
        registry.withdrawExcessBond(100e6);
        vm.stopPrank();
        assertEq(token.balanceOf(arbiter), 100e6);
    }

    function test_exit_waits_for_cases_and_unbonding() public {
        vm.prank(court);
        registry.openCase(arbiter);

        vm.prank(arbiter);
        registry.requestExit();
        assertFalse(registry.isEligible(arbiter));

        vm.startPrank(arbiter);
        vm.expectRevert(ArbiterRegistry.ExitPending.selector);
        registry.depositBond(1);
        vm.expectRevert(ArbiterRegistry.OpenCases.selector);
        registry.completeExit();
        vm.stopPrank();

        vm.prank(court);
        registry.closeCase(arbiter, ArbiterRegistry.CaseOutcome.RESOLVED);

        vm.prank(arbiter);
        vm.expectRevert(ArbiterRegistry.UnbondingActive.selector);
        registry.completeExit();

        vm.warp(block.timestamp + 14 days);
        vm.prank(arbiter);
        registry.completeExit();
        assertEq(token.balanceOf(arbiter), MIN_BOND);
        (bool approved, uint128 bond,,,,,) = registry.arbiters(arbiter);
        assertFalse(approved);
        assertEq(bond, 0);
    }

    function test_slash_is_capped_at_remaining_bond() public {
        vm.prank(admin);
        registry.setParams(MIN_BOND, MIN_BOND * 2, 14 days, slashSink);
        vm.startPrank(court);
        registry.openCase(arbiter);
        registry.closeCase(arbiter, ArbiterRegistry.CaseOutcome.MISSED);
        vm.stopPrank();
        (, uint128 bond,,, uint32 missed,,) = registry.arbiters(arbiter);
        assertEq(bond, 0);
        assertEq(missed, 1);
        assertEq(token.balanceOf(slashSink), MIN_BOND);
    }

    function test_withdrawn_case_is_neutral() public {
        vm.startPrank(court);
        registry.openCase(arbiter);
        registry.closeCase(arbiter, ArbiterRegistry.CaseOutcome.WITHDRAWN);
        vm.stopPrank();
        (, uint128 bond, uint32 open, uint32 resolved, uint32 missed,,) = registry.arbiters(arbiter);
        assertEq(bond, MIN_BOND);
        assertEq(open + resolved + missed, 0);
    }

    function test_params_require_slash_recipient() public {
        vm.prank(admin);
        vm.expectRevert(ArbiterRegistry.ZeroAddress.selector);
        registry.setParams(1, 1, 1, address(0));
    }
}
