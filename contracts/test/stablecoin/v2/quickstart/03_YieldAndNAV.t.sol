// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2QuickstartBase} from "./SSDCV2QuickstartBase.sol";
import {YieldEscrowV2} from "../../../../stablecoin/v2/YieldEscrowV2.sol";
import {SSDCStatusLensV2} from "../../../../stablecoin/v2/SSDCStatusLensV2.sol";
import {RayMath} from "../../../../stablecoin/v2/RayMath.sol";
import {wSSDCVaultV2} from "../../../../stablecoin/v2/wSSDCVaultV2.sol";

/// @title Quickstart 03: Yield Accrual, NAV Dynamics & Reserve Management
/// @notice How agents earn yield on idle balances, how yield splits work in
///         escrow, and how the treasury deploys reserves for off-chain yield.
///
///   Demonstrates:
///     - NAV appreciation over time (shares grow in value)
///     - Forward rate projection (continuous yield between oracle updates)
///     - Yield splitting in escrow (buyer vs merchant vs protocol vs reserve)
///     - Reserve deployment & recall (treasury management)
///     - Liquidity coverage monitoring
///     - NAV jump protection
///
///   Run:  forge test --match-contract YieldAndNAV -vvv
contract YieldAndNAV is SSDCV2QuickstartBase {

    function setUp() public override {
        super.setUp();
        // Fund agents with generous limits
        _fundAgent(agentAlpha, 50_000 ether);
        _fundAgent(agentBeta, 30_000 ether);
        _configureAgent(
            agentAlpha, type(uint256).max, type(uint256).max, 100 ether,
            uint40(block.timestamp + 30 days), false, new address[](0)
        );
        _configureAgent(
            agentBeta, type(uint256).max, type(uint256).max, 100 ether,
            uint40(block.timestamp + 30 days), false, new address[](0)
        );
    }

    // ─────────────────────────────────────────────────────────────────────
    //  NAV appreciation: shares appreciate as Treasury yields accrue
    // ─────────────────────────────────────────────────────────────────────
    function test_NAVAppreciation_SharesGrowInValue() public {
        // Alpha holds 50,000 shares at NAV = 1.0 → worth $50,000
        uint256 initialAssets = vault.convertToAssets(vault.balanceOf(agentAlpha));
        assertEq(initialAssets, 50_000 ether);

        // Oracle reports NAV = 1.05 (5% appreciation from Treasury yield)
        _updateNAV(105e25);

        // Same shares, now worth $52,500
        uint256 newAssets = vault.convertToAssets(vault.balanceOf(agentAlpha));
        assertEq(newAssets, 52_500 ether, "5% appreciation");

        // No action required by the agent — yield accrues passively
        assertEq(vault.balanceOf(agentAlpha), 50_000 ether, "share count unchanged");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Forward rate: continuous yield projection between oracle updates
    // ─────────────────────────────────────────────────────────────────────
    function test_ForwardRate_ContinuousYieldProjection() public {
        // Oracle sets NAV = 1.0 with a forward rate of +1e18 ray/second
        // This means NAV increases by 1e18 per second (~0.0000001% per second)
        // Over 1 day (86,400 seconds): +86,400e18 = +0.0000864 ray
        int256 ratePerSecond = 1e18; // tiny positive rate
        _updateNAVWithRate(RAY, ratePerSecond);

        uint256 navNow = nav.currentNAVRay();
        assertEq(navNow, RAY, "NAV at update time = 1.0");

        // Fast-forward 1 day
        vm.warp(block.timestamp + 1 days);

        uint256 navAfter1Day = nav.currentNAVRay();
        uint256 expectedNav = RAY + uint256(ratePerSecond) * 1 days;
        assertEq(navAfter1Day, expectedNav, "NAV projected via rate");
        assertGt(navAfter1Day, RAY, "NAV increased");

        // Agent's shares are now worth more
        uint256 alphaAssets = vault.convertToAssets(vault.balanceOf(agentAlpha));
        assertGt(alphaAssets, 50_000 ether, "idle balance earned yield via rate");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Yield splitting: how escrow yield is divided
    // ─────────────────────────────────────────────────────────────────────
    function test_YieldSplit_InEscrow() public {
        // Alpha escrows $10,000 to Beta with 40% buyer yield share.
        // Reserve = 2%, Protocol fee = 1% (set in base setUp)
        vm.startPrank(agentAlpha);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(
            agentBeta,
            _simpleInvoice(10_000 ether),
            4_000 // buyerBps = 40% of net yield to buyer
        );
        vm.stopPrank();

        // Yield accrues: NAV goes from 1.0 → 1.10 (10% yield)
        _updateNAV(110e25);

        // Preview the release split before settlement
        YieldEscrowV2.ReleaseSplit memory split = escrow.previewReleaseSplit(escrowId);

        // Expected math (10,000 shares deposited at NAV=1.0, NAV now 1.1):
        //   principalShares = 10,000 assets / 1.1 NAV ~= 9,090.9 shares
        //   grossYield = 10,000 - principalShares ~= 909.1 shares
        //   reserve (2% of gross) ~= 18.2 shares
        //   fee (1% of post-reserve) ~= 8.9 shares
        //   netYield = gross - reserve - fee ~= 881.9 shares
        //   buyerYield (40% of net) ~= 352.8 shares
        //   merchantYield (60% of net) ~= 529.2 shares
        //
        // We use 1% tolerance (0.01e18) because integer rounding in
        // share/asset conversions introduces small deviations.
        uint256 expectedPrincipal = vault.convertToShares(10_000 ether);
        uint256 expectedGross = 10_000 ether - expectedPrincipal;
        assertApproxEqRel(split.principalShares, expectedPrincipal, 0.01e18, "principal ~9,091 shares");
        assertApproxEqRel(split.grossYieldShares, expectedGross, 0.01e18, "gross yield ~909 shares");
        assertApproxEqRel(split.reserveShares, expectedGross * 200 / 10_000, 0.01e18, "reserve ~18 shares (2%)");
        assertGt(split.feeShares, 0, "protocol fee collected");
        assertGt(split.buyerYieldShares, 0, "buyer earned yield");
        assertGt(split.merchantYieldShares, 0, "merchant earned yield");
        assertGt(split.merchantYieldShares, split.buyerYieldShares, "merchant gets 60%");
        // Buyer gets 40% of net yield, merchant gets 60%
        assertApproxEqRel(
            split.buyerYieldShares * 10_000 / (split.buyerYieldShares + split.merchantYieldShares),
            4_000,
            0.01e18,
            "buyer/merchant ratio is 40/60"
        );
        assertEq(
            split.principalShares + split.merchantYieldShares +
            split.buyerYieldShares + split.reserveShares + split.feeShares,
            split.totalShares,
            "split sums to total"
        );

        // Release and verify actual transfers
        vm.warp(block.timestamp + 1 hours);
        uint256 betaBefore = vault.balanceOf(agentBeta);
        uint256 alphaBefore = vault.balanceOf(agentAlpha);
        uint256 feeBefore = vault.balanceOf(feeCollector);

        vm.prank(agentAlpha);
        escrow.release(escrowId);

        // Beta got principal + merchant yield
        assertGt(vault.balanceOf(agentBeta) - betaBefore, split.principalShares);
        // Alpha got buyer yield share
        assertEq(vault.balanceOf(agentAlpha) - alphaBefore, split.buyerYieldShares);
        // Fee collector got reserve + protocol fee
        assertEq(vault.balanceOf(feeCollector) - feeBefore, split.reserveShares + split.feeShares);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Reserve management: deploy vault assets for off-chain yield
    // ─────────────────────────────────────────────────────────────────────
    function test_ReserveDeployAndRecall() public {
        // The treasury manager can deploy idle settlement assets to yield
        // strategies (e.g., T-bills) while maintaining a minimum floor.
        address reserveManager = address(0x7E5);
        vm.startPrank(admin);
        vault.setReserveConfig(
            reserveManager,
            10_000 ether,   // reserveFloor: always keep $10k liquid
            2_000            // maxDeployBps: max 20% per deploy call
        );
        vm.stopPrank();

        uint256 totalAvailable = vault.availableSettlementAssets();
        assertEq(totalAvailable, 80_000 ether, "50k + 30k deposited");

        // Deploy $15,000 to reserve manager (within 20% of liabilities)
        vm.prank(admin);
        vault.deployReserve(15_000 ether);

        assertEq(vault.availableSettlementAssets(), 65_000 ether);
        assertEq(vault.deployedReserveAssets(), 15_000 ether);
        assertEq(asset.balanceOf(reserveManager), 15_000 ether);

        // Verify StatusLens reflects the deployment
        SSDCStatusLensV2.Status memory s = lens.getStatus();
        assertEq(s.reserveDeployedAssets, 15_000 ether);
        assertEq(s.reserveFloor, 10_000 ether);

        // Recall $10,000 from reserve manager
        vm.prank(reserveManager);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(admin);
        vault.recallReserve(10_000 ether);

        assertEq(vault.availableSettlementAssets(), 75_000 ether);
        assertEq(vault.deployedReserveAssets(), 5_000 ether);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Reserve floor: cannot deploy below the minimum liquidity floor
    // ─────────────────────────────────────────────────────────────────────
    function test_ReserveFloor_PreventsOverDeployment() public {
        address reserveManager = address(0x7E5);
        vm.startPrank(admin);
        vault.setReserveConfig(reserveManager, 75_000 ether, 10_000);
        vm.stopPrank();

        // Try to deploy $10,000 — would leave only $70,000 < $75,000 floor
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("RESERVE_FLOOR()"));
        vault.deployReserve(10_000 ether);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  NAV jump protection: oracle cannot report impossible NAV changes
    // ─────────────────────────────────────────────────────────────────────
    function test_NAVJumpProtection() public {
        // Max jump is 20% (2_000 bps configured in base setUp).
        // Current NAV = 1.0. Trying to jump to 1.25 (25%) should fail.
        uint64 nextEpoch = nav.navEpoch() + 1;
        vm.prank(oracleAddr);
        vm.expectRevert(abi.encodeWithSignature("NAV_JUMP()"));
        nav.updateNAV(125e25, int256(0), nextEpoch); // 25% jump → blocked

        // 15% jump is within bounds
        vm.prank(oracleAddr);
        nav.updateNAV(115e25, int256(0), nextEpoch); // 15% jump → OK
        assertEq(nav.currentNAVRay(), 115e25);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Liquidity coverage: monitor vault backing ratio
    // ─────────────────────────────────────────────────────────────────────
    function test_LiquidityCoverage_Monitoring() public {
        // Initially 100% covered — settlement assets = liabilities
        assertEq(vault.liquidityCoverageBps(), 10_000);

        // Deploy reserves — coverage drops proportionally
        address reserveManager = address(0x7E5);
        vm.startPrank(admin);
        vault.setReserveConfig(reserveManager, 0, 10_000);
        vault.deployReserve(40_000 ether); // deploy half
        vm.stopPrank();

        // Available = $40k, Liabilities = $80k → 50% coverage
        assertEq(vault.liquidityCoverageBps(), 5_000);

        SSDCStatusLensV2.Status memory s = lens.getStatus();
        assertEq(s.liquidityCoverageBps, 5_000);
        assertEq(s.settlementAssetsAvailable, 40_000 ether);
    }
}
