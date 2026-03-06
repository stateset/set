// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2TestBase} from "./SSDCV2TestBase.sol";
import {WSSDCCrossChainBridgeV2} from "../../../stablecoin/v2/WSSDCCrossChainBridgeV2.sol";
import {NAVControllerV2} from "../../../stablecoin/v2/NAVControllerV2.sol";

contract WSSDCCrossChainBridgeV2Test is SSDCV2TestBase {
    WSSDCCrossChainBridgeV2 internal bridge;

    uint32 internal constant SRC_CHAIN = 101;
    bytes32 internal constant SRC_PEER = bytes32(uint256(0xBEEF));

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        bridge = new WSSDCCrossChainBridgeV2(vault, nav, admin);

        vault.grantRole(vault.BRIDGE_ROLE(), address(bridge));
        nav.grantRole(nav.BRIDGE_ROLE(), address(bridge));

        bridge.setTrustedPeer(SRC_CHAIN, SRC_PEER);
        vm.stopPrank();
    }

    function test_BridgeSharesOneToOne() public {
        _mintAndDeposit(user1, 100 ether);

        uint256 before = vault.balanceOf(user1);
        vm.prank(user1);
        bridge.bridgeOut(SRC_CHAIN, bytes32(uint256(uint160(user2))), 40 ether);

        assertEq(vault.balanceOf(user1), before - 40 ether);

        bytes32 msgId = keccak256("m1");
        vm.prank(admin);
        bridge.receiveBridgeMint(SRC_CHAIN, SRC_PEER, msgId, user2, 40 ether);

        assertEq(vault.balanceOf(user2), 40 ether);
    }

    function test_RelayNAVRejectsOutOfOrderEpoch() public {
        bytes32 msg1 = keccak256("nav-1");
        uint64 nextEpoch = nav.navEpoch() + 1;
        vm.prank(admin);
        bridge.relayNAV(SRC_CHAIN, SRC_PEER, msg1, RAY, uint40(block.timestamp), 0, nextEpoch);

        bytes32 msg2 = keccak256("nav-2");
        uint64 currentEpoch = nav.navEpoch();
        vm.prank(admin);
        vm.expectRevert(NAVControllerV2.EPOCH.selector);
        bridge.relayNAV(SRC_CHAIN, SRC_PEER, msg2, RAY, uint40(block.timestamp), 0, currentEpoch);
    }

    function test_ReplayProtectionOnRelay() public {
        bytes32 msgId = keccak256("replay-nav");

        uint64 firstEpoch = nav.navEpoch() + 1;
        vm.prank(admin);
        bridge.relayNAV(SRC_CHAIN, SRC_PEER, msgId, RAY, uint40(block.timestamp), 0, firstEpoch);

        uint64 secondEpoch = nav.navEpoch() + 1;
        vm.prank(admin);
        vm.expectRevert(WSSDCCrossChainBridgeV2.REPLAY.selector);
        bridge.relayNAV(SRC_CHAIN, SRC_PEER, msgId, RAY, uint40(block.timestamp), 0, secondEpoch);
    }

    function test_ReplayProtectionOnReceiveBridgeMint() public {
        bytes32 msgId = keccak256("replay-mint");

        vm.prank(admin);
        bridge.receiveBridgeMint(SRC_CHAIN, SRC_PEER, msgId, user2, 5 ether);

        vm.prank(admin);
        vm.expectRevert(WSSDCCrossChainBridgeV2.REPLAY.selector);
        bridge.receiveBridgeMint(SRC_CHAIN, SRC_PEER, msgId, user2, 5 ether);
    }

    function test_ReceiveBridgeMintRejectsUntrustedPeer() public {
        vm.prank(admin);
        vm.expectRevert(WSSDCCrossChainBridgeV2.UNTRUSTED_PEER.selector);
        bridge.receiveBridgeMint(SRC_CHAIN, bytes32(uint256(0xBAD)), keccak256("bad-peer"), user2, 1 ether);
    }

    function test_BridgePauseBlocksBridgeOutAndReceive() public {
        _mintAndDeposit(user1, 20 ether);

        vm.prank(admin);
        bridge.setBridgePaused(true);

        vm.prank(user1);
        vm.expectRevert(WSSDCCrossChainBridgeV2.BRIDGE_PAUSED.selector);
        bridge.bridgeOut(SRC_CHAIN, bytes32(uint256(uint160(user2))), 5 ether);

        vm.prank(admin);
        vm.expectRevert(WSSDCCrossChainBridgeV2.BRIDGE_PAUSED.selector);
        bridge.receiveBridgeMint(SRC_CHAIN, SRC_PEER, keccak256("paused"), user2, 5 ether);
    }

    function test_MintLimitCapsBlastRadius() public {
        vm.prank(admin);
        bridge.setMintLimit(admin, 10 ether);

        vm.prank(admin);
        bridge.receiveBridgeMint(SRC_CHAIN, SRC_PEER, keccak256("ok"), user2, 10 ether);

        vm.prank(admin);
        vm.expectRevert(WSSDCCrossChainBridgeV2.MINT_LIMIT.selector);
        bridge.receiveBridgeMint(SRC_CHAIN, SRC_PEER, keccak256("over"), user2, 1);
    }
}
