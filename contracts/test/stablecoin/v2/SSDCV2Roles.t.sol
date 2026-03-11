// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2TestBase, MockETHUSDOracle} from "./SSDCV2TestBase.sol";
import {GroundingRegistryV2} from "../../../stablecoin/v2/GroundingRegistryV2.sol";
import {SSDCClaimQueueV2} from "../../../stablecoin/v2/SSDCClaimQueueV2.sol";
import {SSDCPolicyModuleV2} from "../../../stablecoin/v2/SSDCPolicyModuleV2.sol";
import {WSSDCCrossChainBridgeV2} from "../../../stablecoin/v2/WSSDCCrossChainBridgeV2.sol";
import {YieldPaymasterV2} from "../../../stablecoin/v2/YieldPaymasterV2.sol";
import {IETHUSDOracleV2} from "../../../stablecoin/v2/interfaces/IETHUSDOracleV2.sol";

contract SSDCV2RolesTest is SSDCV2TestBase {
    SSDCClaimQueueV2 internal queue;
    SSDCPolicyModuleV2 internal policy;
    GroundingRegistryV2 internal grounding;
    MockETHUSDOracle internal priceOracle;
    YieldPaymasterV2 internal paymaster;
    WSSDCCrossChainBridgeV2 internal bridge;

    address internal attacker = address(0xBAD);
    address internal oracleOperator = address(0x0B11);
    address internal bufferOperator = address(0xB00F);
    address internal bridgeOperator = address(0xB1D6E);
    address internal pauser = address(0xA115E);
    address internal entryPoint = address(0x4337);

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        queue = new SSDCClaimQueueV2(vault, asset, admin);
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
            admin
        );

        bridge = new WSSDCCrossChainBridgeV2(vault, nav, admin);

        nav.grantRole(nav.ORACLE_ROLE(), oracleOperator);
        nav.grantRole(nav.PAUSER_ROLE(), pauser);
        nav.grantRole(nav.BRIDGE_ROLE(), address(bridge));

        vault.grantRole(vault.PAUSER_ROLE(), pauser);
        vault.grantRole(vault.BRIDGE_ROLE(), address(bridge));
        vault.grantRole(vault.GATEWAY_ROLE(), address(queue));
        vault.grantRole(vault.QUEUE_ROLE(), address(queue));

        queue.grantRole(queue.BUFFER_ROLE(), bufferOperator);
        queue.grantRole(queue.QUEUE_ROLE(), bufferOperator);
        queue.grantRole(queue.PAUSER_ROLE(), pauser);

        bridge.grantRole(bridge.BRIDGE_ROLE(), bridgeOperator);
        bridge.grantRole(bridge.PAUSER_ROLE(), pauser);

        policy.grantRole(policy.POLICY_CONSUMER_ROLE(), address(paymaster));
        grounding.setCollateralProvider(address(paymaster), true);

        vm.stopPrank();
    }

    function test_UnauthorizedCallsRevert() public {
        uint64 unauthorizedEpoch = nav.navEpoch() + 1;

        vm.prank(attacker);
        vm.expectRevert();
        nav.updateNAV(101e25, int256(0), unauthorizedEpoch);

        vm.prank(attacker);
        vm.expectRevert();
        vault.setMintRedeemPaused(true);

        vm.prank(attacker);
        vm.expectRevert();
        queue.refill(1 ether);

        vm.prank(attacker);
        vm.expectRevert();
        bridge.setTrustedPeer(101, bytes32(uint256(0xBEEF)));

        vm.prank(attacker);
        vm.expectRevert();
        queue.setSkipBlockedClaims(true);

        vm.prank(bridgeOperator);
        vm.expectRevert();
        bridge.setMintLimit(1 ether);

        vm.prank(attacker);
        vm.expectRevert();
        paymaster.setEntryPoint(address(0x1234));

        vm.prank(attacker);
        vm.expectRevert();
        policy.setPolicy(user1, 1, 1, 1, uint40(block.timestamp + 1 days), false);
    }

    function test_RoleHoldersCanOperate() public {
        uint64 nextEpoch = nav.navEpoch() + 1;
        vm.prank(oracleOperator);
        nav.updateNAV(101e25, int256(0), nextEpoch);

        asset.mint(bufferOperator, 10 ether);
        vm.startPrank(bufferOperator);
        asset.approve(address(queue), type(uint256).max);
        queue.refill(5 ether);
        vm.stopPrank();
        assertEq(queue.availableAssets(), 5 ether);

        vm.prank(admin);
        bridge.setTrustedPeer(101, bytes32(uint256(0xBEEF)));

        vm.prank(bridgeOperator);
        bridge.receiveBridgeMint(101, bytes32(uint256(0xBEEF)), keccak256("roles-mint"), user1, 1 ether);
        assertEq(vault.balanceOf(user1), 1 ether);

        vm.prank(pauser);
        vault.setMintRedeemPaused(true);
        assertTrue(vault.mintRedeemPaused());

        vm.prank(pauser);
        bridge.setBridgePaused(true);
        assertTrue(bridge.bridgePaused());

        vm.prank(pauser);
        queue.setQueueOpsPaused(true);
        assertTrue(queue.queueOpsPaused());

        vm.prank(admin);
        queue.setSkipBlockedClaims(true);
        assertTrue(queue.skipBlockedClaims());
    }
}
