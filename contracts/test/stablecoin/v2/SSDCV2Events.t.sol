// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2TestBase, MockETHUSDOracle} from "./SSDCV2TestBase.sol";
import {GroundingRegistryV2} from "../../../stablecoin/v2/GroundingRegistryV2.sol";
import {NAVControllerV2} from "../../../stablecoin/v2/NAVControllerV2.sol";
import {SSDCClaimQueueV2} from "../../../stablecoin/v2/SSDCClaimQueueV2.sol";
import {SSDCPolicyModuleV2} from "../../../stablecoin/v2/SSDCPolicyModuleV2.sol";
import {WSSDCCrossChainBridgeV2} from "../../../stablecoin/v2/WSSDCCrossChainBridgeV2.sol";
import {YieldEscrowV2} from "../../../stablecoin/v2/YieldEscrowV2.sol";
import {YieldPaymasterV2} from "../../../stablecoin/v2/YieldPaymasterV2.sol";
import {IETHUSDOracleV2} from "../../../stablecoin/v2/interfaces/IETHUSDOracleV2.sol";

contract SSDCV2EventsTest is SSDCV2TestBase {
    SSDCClaimQueueV2 internal queue;
    YieldEscrowV2 internal escrow;
    SSDCPolicyModuleV2 internal policy;
    GroundingRegistryV2 internal grounding;
    MockETHUSDOracle internal priceOracle;
    YieldPaymasterV2 internal paymaster;
    WSSDCCrossChainBridgeV2 internal bridge;

    address internal entryPoint = address(0x4337);
    bytes32 internal peer101 = bytes32(uint256(0xBEEF));

    event NAVUpdated(
        uint64 indexed navEpoch,
        uint256 nav0Ray,
        uint40 t0,
        int256 ratePerSecondRay,
        uint256 attestedNAVRay
    );

    event RedeemRequested(
        uint256 indexed claimId,
        address indexed receiver,
        uint256 shares,
        uint256 assetsSnapshot
    );
    event RedeemCancelled(uint256 indexed claimId, address indexed receiver, uint256 sharesReturned);
    event RedeemClaimable(uint256 indexed claimId, uint256 assetsOwed);
    event RedeemClaimed(uint256 indexed claimId, address indexed caller, uint256 assetsPaid);

    event EscrowReleased(
        uint256 indexed escrowId,
        uint256 totalShares,
        uint256 principalShares,
        uint256 buyerYieldShares,
        uint256 merchantYieldShares,
        uint256 feeShares
    );

    event AgentGrounded(
        address indexed agent,
        uint256 assetsNow,
        uint256 minAssetsFloor,
        uint256 currentNAVRay
    );
    event AgentUngrounded(
        address indexed agent,
        uint256 assetsNow,
        uint256 minAssetsFloor,
        uint256 currentNAVRay
    );

    event GasCharged(
        address indexed agent,
        uint256 sharesCharged,
        uint256 gasUsed,
        uint256 effectiveGasPrice
    );

    event NAVRelayed(uint64 indexed navEpoch, uint256 nav0Ray, uint40 t0, int256 ratePerSecondRay);

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        queue = new SSDCClaimQueueV2(vault, asset, admin);
        escrow = new YieldEscrowV2(vault, nav, admin, user3);
        policy = new SSDCPolicyModuleV2(admin);
        grounding = new GroundingRegistryV2(policy, nav, vault, admin);
        priceOracle = new MockETHUSDOracle();
        priceOracle.setPrice(3_000e18);

        paymaster = new YieldPaymasterV2(
            vault,
            nav,
            policy,
            grounding,
            IETHUSDOracleV2(address(priceOracle)),
            entryPoint,
            admin,
            user3
        );

        bridge = new WSSDCCrossChainBridgeV2(vault, nav, admin);
        bridge.setTrustedPeer(101, peer101);

        nav.grantRole(nav.BRIDGE_ROLE(), address(bridge));
        vault.grantRole(vault.QUEUE_ROLE(), address(queue));
        vault.grantRole(vault.BRIDGE_ROLE(), address(bridge));
        policy.grantRole(policy.POLICY_CONSUMER_ROLE(), address(paymaster));
        grounding.setCollateralProvider(address(paymaster), true);

        vm.stopPrank();
    }

    function test_Event_NAVUpdated() public {
        uint256 navCurrent = nav.currentNAVRay();
        uint64 nextEpoch = nav.navEpoch() + 1;
        uint256 attested = navCurrent + 12_345_678_900_000_000_000_000;

        int256 expectedRate = (int256(attested) - int256(navCurrent)) / int256(nav.targetSmoothingWindow());
        int256 maxRate = nav.maxRateAbsRay();
        if (expectedRate > maxRate) {
            expectedRate = maxRate;
        } else if (expectedRate < -maxRate) {
            expectedRate = -maxRate;
        }

        vm.expectEmit(true, false, false, true, address(nav));
        emit NAVUpdated(nextEpoch, navCurrent, uint40(block.timestamp), expectedRate, attested);

        vm.prank(oracle);
        nav.updateNAV(attested, nextEpoch);
    }

    function test_Event_QueueLifecycle() public {
        _mintAndDeposit(user1, 1_000 ether);
        vm.prank(user1);
        vault.approve(address(queue), type(uint256).max);

        uint256 shares = 200 ether;
        uint256 claimId = queue.nextClaimId();
        uint256 snapshot = vault.convertToAssets(shares);

        vm.expectEmit(true, true, false, true, address(queue));
        emit RedeemRequested(claimId, user1, shares, snapshot);

        vm.prank(user1);
        queue.requestRedeem(shares, user1);

        vm.expectEmit(true, true, false, true, address(queue));
        emit RedeemCancelled(claimId, user1, shares);

        vm.prank(user1);
        queue.cancel(claimId, user1);

        uint256 claimId2 = queue.nextClaimId();
        uint256 shares2 = 150 ether;
        uint256 owed = vault.convertToAssets(shares2);

        vm.prank(user1);
        queue.requestRedeem(shares2, user1);

        asset.mint(admin, owed);
        vm.startPrank(admin);
        asset.approve(address(queue), owed);
        queue.refill(owed);

        vm.expectEmit(true, false, false, true, address(queue));
        emit RedeemClaimable(claimId2, owed);
        queue.processQueue(10);
        vm.stopPrank();

        vm.expectEmit(true, true, false, true, address(queue));
        emit RedeemClaimed(claimId2, user1, owed);

        vm.prank(user1);
        queue.claim(claimId2);
    }

    function test_Event_EscrowReleased() public {
        _mintAndDeposit(user1, 1_000 ether);

        vm.prank(admin);
        escrow.setProtocolFee(1_000, user3);

        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 500 ether,
            expiry: uint40(block.timestamp + 1 days),
            maxNavAge: 1 days,
            maxSharesIn: 510 ether
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(user2, terms, 2_500);
        vm.stopPrank();

        uint64 relayEpoch = nav.navEpoch() + 1;
        vm.prank(admin);
        nav.relayNAV(12e26, uint40(block.timestamp), 0, relayEpoch);

        (, , uint256 S, uint256 A_principal, uint16 buyerBps, ) = escrow.escrows(escrowId);
        uint256 navRay = nav.currentNAVRay();

        uint256 S_principal = vault.convertToSharesInvoiceOrWithdraw(A_principal);
        if (S_principal > S) {
            S_principal = S;
        }
        uint256 S_yield = S - S_principal;
        uint256 S_fee = (S_yield * escrow.protocolFeeBps()) / 10_000;
        uint256 S_yieldNet = S_yield - S_fee;
        uint256 S_buyerYield = (S_yieldNet * buyerBps) / 10_000;
        uint256 S_merchantYield = S_yieldNet - S_buyerYield;

        vm.expectEmit(true, false, false, true, address(escrow));
        emit EscrowReleased(escrowId, S, S_principal, S_buyerYield, S_merchantYield, S_fee);

        vm.assertGt(navRay, 0);
        escrow.release(escrowId);
    }

    function test_Event_GroundingTransitions() public {
        _mintAndDeposit(user1, 100 ether);

        uint256 navRay = nav.currentNAVRay();
        uint256 assetsNow = vault.convertToAssets(vault.balanceOf(user1));
        uint256 floor = assetsNow + 1;

        vm.prank(admin);
        policy.setPolicy(user1, 0, 0, floor, 0, false);

        vm.expectEmit(true, false, false, true, address(grounding));
        emit AgentGrounded(user1, assetsNow, floor, navRay);
        grounding.poke(user1);

        vm.prank(admin);
        policy.setPolicy(user1, 0, 0, assetsNow, 0, false);

        vm.expectEmit(true, false, false, true, address(grounding));
        emit AgentUngrounded(user1, assetsNow, assetsNow, navRay);
        grounding.poke(user1);
    }

    function test_Event_GasCharged() public {
        _mintAndDeposit(user1, 1_000 ether);

        vm.prank(admin);
        policy.setPolicy(user1, type(uint256).max, type(uint256).max, 0, 0, false);

        vm.startPrank(user1);
        vault.approve(address(paymaster), type(uint256).max);
        paymaster.topUpGasTank(300 ether);
        vm.stopPrank();

        uint256 gasUsed = 200_000;
        uint256 gasPrice = 1 gwei;
        uint256 sharesCharged = paymaster.previewChargeShares(gasUsed * gasPrice);

        vm.expectEmit(true, false, false, true, address(paymaster));
        emit GasCharged(user1, sharesCharged, gasUsed, gasPrice);

        vm.prank(entryPoint);
        paymaster.postOp(user1, gasUsed, gasPrice, user2);
    }

    function test_Event_BridgeNavRelayed() public {
        uint64 nextEpoch = nav.navEpoch() + 1;
        bytes32 msgId = keccak256("nav-relay-msg-1");
        uint256 nav0Ray = 11e26;
        uint40 relayT0 = uint40(block.timestamp);
        int256 rate = int256(1e20);

        vm.expectEmit(true, false, false, true, address(bridge));
        emit NAVRelayed(nextEpoch, nav0Ray, relayT0, rate);

        vm.prank(admin);
        bridge.relayNAV(101, peer101, msgId, nav0Ray, relayT0, rate, nextEpoch);
    }
}
