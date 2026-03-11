// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2TestBase, MockETHUSDOracle} from "./SSDCV2TestBase.sol";
import {GroundingRegistryV2} from "../../../stablecoin/v2/GroundingRegistryV2.sol";
import {SSDCClaimQueueV2} from "../../../stablecoin/v2/SSDCClaimQueueV2.sol";
import {SSDCPolicyModuleV2} from "../../../stablecoin/v2/SSDCPolicyModuleV2.sol";
import {SSDCStatusLensV2} from "../../../stablecoin/v2/SSDCStatusLensV2.sol";
import {WSSDCCrossChainBridgeV2} from "../../../stablecoin/v2/WSSDCCrossChainBridgeV2.sol";
import {YieldEscrowV2} from "../../../stablecoin/v2/YieldEscrowV2.sol";
import {YieldPaymasterV2} from "../../../stablecoin/v2/YieldPaymasterV2.sol";
import {IETHUSDOracleV2} from "../../../stablecoin/v2/interfaces/IETHUSDOracleV2.sol";

contract SSDCStatusLensV2Test is SSDCV2TestBase {
    SSDCClaimQueueV2 internal queue;
    WSSDCCrossChainBridgeV2 internal bridge;
    YieldEscrowV2 internal escrow;
    YieldPaymasterV2 internal paymaster;
    SSDCStatusLensV2 internal lens;

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        queue = new SSDCClaimQueueV2(vault, asset, admin);
        bridge = new WSSDCCrossChainBridgeV2(vault, nav, admin);
        vault.grantRole(vault.BRIDGE_ROLE(), address(bridge));

        SSDCPolicyModuleV2 policy = new SSDCPolicyModuleV2(admin);
        GroundingRegistryV2 grounding = new GroundingRegistryV2(policy, nav, vault, admin);
        escrow = new YieldEscrowV2(vault, nav, policy, grounding, admin, admin);

        MockETHUSDOracle priceOracle = new MockETHUSDOracle();
        priceOracle.setPrice(3_000e18);
        paymaster = new YieldPaymasterV2(
            vault, nav, policy, grounding,
            IETHUSDOracleV2(address(priceOracle)),
            address(0x4337), admin, admin
        );

        lens = new SSDCStatusLensV2(nav, vault, queue, bridge, escrow, paymaster);
        vm.stopPrank();
    }

    function test_StatusHappyPath() public view {
        SSDCStatusLensV2.Status memory status = lens.getStatus();

        assertTrue(status.transfersAllowed);
        assertTrue(status.navFresh);
        assertTrue(status.navConversionsAllowed);
        assertTrue(status.mintDepositAllowed);
        assertTrue(status.redeemWithdrawAllowed);
        assertTrue(status.requestRedeemAllowed);
        assertTrue(status.processQueueAllowed);
        assertFalse(status.queueSkipsBlockedClaims);
        assertTrue(status.bridgingAllowed);
        assertTrue(status.bridgeMintAllowed);
        assertEq(status.bridgeOutstandingShares, 0);
        assertEq(status.bridgeOutstandingLimitShares, 0);
        assertEq(status.bridgeRemainingCapacityShares, type(uint256).max);
        assertEq(status.minBridgeLiquidityCoverageBps, 0);
        assertFalse(status.gatewayRequired);
        assertFalse(status.escrowOpsPaused);
        assertFalse(status.paymasterPaused);
        assertEq(status.liabilityAssets, 0);
        assertEq(status.settlementAssetsAvailable, 0);
        assertEq(status.queueBufferAvailable, 0);
        assertEq(status.queueReservedAssets, 0);
        assertEq(status.liquidityCoverageBps, 10_000);
        assertEq(status.navRay, RAY);
    }

    function test_StatusWhenMintRedeemPaused() public {
        vm.prank(admin);
        vault.setMintRedeemPaused(true);

        SSDCStatusLensV2.Status memory status = lens.getStatus();

        assertTrue(status.transfersAllowed);
        assertTrue(status.navFresh);
        assertFalse(status.mintDepositAllowed);
        assertFalse(status.redeemWithdrawAllowed);
        assertFalse(status.requestRedeemAllowed);
        assertFalse(status.processQueueAllowed);
        assertTrue(status.bridgingAllowed);
    }

    function test_StatusWhenNAVStale() public {
        vm.warp(block.timestamp + nav.maxStaleness() + 1);

        SSDCStatusLensV2.Status memory status = lens.getStatus();

        assertTrue(status.transfersAllowed);
        assertFalse(status.navFresh);
        assertFalse(status.navConversionsAllowed);
        assertFalse(status.mintDepositAllowed);
        assertFalse(status.redeemWithdrawAllowed);
        assertFalse(status.requestRedeemAllowed);
        assertFalse(status.processQueueAllowed);
        assertTrue(status.bridgingAllowed);
        assertEq(status.navRay, 0);
    }

    function test_StatusWhenNAVBelowFloor() public {
        uint64 nextEpoch = nav.navEpoch() + 1;
        uint256 minNavRay = nav.minNavRay();
        int256 maxNegativeRate = -nav.maxRateAbsRay();
        vm.prank(admin);
        nav.relayNAV(minNavRay, uint40(block.timestamp), maxNegativeRate, nextEpoch);

        vm.warp(block.timestamp + 1);

        SSDCStatusLensV2.Status memory status = lens.getStatus();

        assertTrue(status.navFresh);
        assertFalse(status.navConversionsAllowed);
        assertFalse(status.mintDepositAllowed);
        assertFalse(status.redeemWithdrawAllowed);
        assertFalse(status.requestRedeemAllowed);
        assertFalse(status.processQueueAllowed);
        assertEq(status.navRay, 0);
    }

    function test_StatusWhenBridgePaused() public {
        vm.prank(admin);
        bridge.setBridgePaused(true);

        SSDCStatusLensV2.Status memory status = lens.getStatus();
        assertFalse(status.bridgingAllowed);
        assertTrue(status.navFresh);
        assertTrue(status.requestRedeemAllowed);
    }

    function test_StatusWhenQueuePaused() public {
        vm.prank(admin);
        queue.setQueueOpsPaused(true);

        SSDCStatusLensV2.Status memory status = lens.getStatus();

        assertTrue(status.navFresh);
        assertTrue(status.mintDepositAllowed);
        assertTrue(status.redeemWithdrawAllowed);
        assertFalse(status.requestRedeemAllowed);
        assertFalse(status.processQueueAllowed);
        assertTrue(status.bridgingAllowed);
    }

    function test_StatusReportsQueueSkipPolicy() public {
        vm.prank(admin);
        queue.setSkipBlockedClaims(true);

        SSDCStatusLensV2.Status memory status = lens.getStatus();

        assertTrue(status.queueSkipsBlockedClaims);
        assertTrue(status.processQueueAllowed);
    }

    function test_StatusReportsGatewayRequirementAndVaultLiquidity() public {
        _mintAndDeposit(user1, 25 ether);

        vm.prank(admin);
        vault.setGatewayRequired(true);

        SSDCStatusLensV2.Status memory status = lens.getStatus();

        assertTrue(status.gatewayRequired);
        assertEq(status.liabilityAssets, 25 ether);
        assertEq(status.settlementAssetsAvailable, 25 ether);
        assertEq(status.liquidityCoverageBps, 10_000);
    }

    function test_StatusReportsLiabilityCoverageGap() public {
        _mintAndDeposit(user1, 100 ether);

        uint64 nextEpoch = nav.navEpoch() + 1;
        vm.prank(admin);
        nav.relayNAV(12e26, uint40(block.timestamp), 0, nextEpoch);

        SSDCStatusLensV2.Status memory status = lens.getStatus();

        assertEq(status.liabilityAssets, 120 ether);
        assertEq(status.settlementAssetsAvailable, 100 ether);
        assertEq(status.liquidityCoverageBps, 8_333);
        assertTrue(status.bridgeMintAllowed);
    }

    function test_StatusReportsBridgeMintCoverageGuard() public {
        _mintAndDeposit(user1, 100 ether);

        uint64 nextEpoch = nav.navEpoch() + 1;
        vm.startPrank(admin);
        nav.relayNAV(12e26, uint40(block.timestamp), 0, nextEpoch);
        vault.setMinBridgeLiquidityCoverageBps(9_000);
        vm.stopPrank();

        SSDCStatusLensV2.Status memory status = lens.getStatus();

        assertEq(status.minBridgeLiquidityCoverageBps, 9_000);
        assertEq(status.liquidityCoverageBps, 8_333);
        assertFalse(status.bridgeMintAllowed);
    }

    function test_StatusReportsOutstandingBridgeCapacity() public {
        vm.startPrank(admin);
        bridge.setTrustedPeer(101, bytes32(uint256(0xBEEF)));
        bridge.setMintLimit(10 ether);
        bridge.receiveBridgeMint(101, bytes32(uint256(0xBEEF)), keccak256("m1"), user1, 4 ether);
        vm.stopPrank();

        SSDCStatusLensV2.Status memory status = lens.getStatus();

        assertEq(status.bridgeOutstandingShares, 4 ether);
        assertEq(status.bridgeOutstandingLimitShares, 10 ether);
        assertEq(status.bridgeRemainingCapacityShares, 6 ether);
        assertTrue(status.bridgeMintAllowed);
    }

    function test_StatusBlocksBridgeMintWhenOutstandingLimitExhausted() public {
        vm.startPrank(admin);
        bridge.setTrustedPeer(101, bytes32(uint256(0xBEEF)));
        bridge.setMintLimit(4 ether);
        bridge.receiveBridgeMint(101, bytes32(uint256(0xBEEF)), keccak256("m2"), user1, 4 ether);
        vm.stopPrank();

        SSDCStatusLensV2.Status memory status = lens.getStatus();

        assertEq(status.bridgeOutstandingShares, 4 ether);
        assertEq(status.bridgeRemainingCapacityShares, 0);
        assertFalse(status.bridgeMintAllowed);
    }
}
