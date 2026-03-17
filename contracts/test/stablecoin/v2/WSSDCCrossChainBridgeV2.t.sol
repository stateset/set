// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2TestBase} from "./SSDCV2TestBase.sol";
import {WSSDCCrossChainBridgeV2} from "../../../stablecoin/v2/WSSDCCrossChainBridgeV2.sol";
import {NAVControllerV2} from "../../../stablecoin/v2/NAVControllerV2.sol";
import {wSSDCVaultV2} from "../../../stablecoin/v2/wSSDCVaultV2.sol";

contract WSSDCCrossChainBridgeV2Test is SSDCV2TestBase {
    WSSDCCrossChainBridgeV2 internal bridge;

    uint32 internal constant SRC_CHAIN = 101;
    uint32 internal constant ALT_CHAIN = 202;
    bytes32 internal constant SRC_PEER = bytes32(uint256(0xBEEF));
    bytes32 internal constant ALT_PEER = bytes32(uint256(0xCAFE));

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        bridge = new WSSDCCrossChainBridgeV2(vault, nav, admin);

        vault.grantRole(vault.BRIDGE_ROLE(), address(bridge));
        nav.grantRole(nav.BRIDGE_ROLE(), address(bridge));

        bridge.setTrustedPeer(SRC_CHAIN, SRC_PEER);
        bridge.setTrustedPeer(ALT_CHAIN, ALT_PEER);
        vm.stopPrank();
    }

    function test_ConstructorRejectsZeroDependencies() public {
        vm.expectRevert(WSSDCCrossChainBridgeV2.ZeroAddress.selector);
        new WSSDCCrossChainBridgeV2(wSSDCVaultV2(address(0)), nav, admin);

        vm.expectRevert(WSSDCCrossChainBridgeV2.ZeroAddress.selector);
        new WSSDCCrossChainBridgeV2(vault, NAVControllerV2(address(0)), admin);
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
        assertEq(vault.bridgedSharesBalance(user2), 40 ether);
        assertEq(vault.bridgedSharesSupply(), 40 ether);
        assertEq(bridge.outstandingShares(), 40 ether);
    }

    function test_BridgeOutIdsAreUniqueWithinBlock() public {
        _mintAndDeposit(user1, 100 ether);

        vm.startPrank(user1);
        bytes32 msgId1 = bridge.bridgeOut(SRC_CHAIN, bytes32(uint256(uint160(user2))), 10 ether);
        bytes32 msgId2 = bridge.bridgeOut(SRC_CHAIN, bytes32(uint256(uint160(user2))), 10 ether);
        vm.stopPrank();

        assertTrue(msgId1 != msgId2);
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

    function test_SameMsgIdDoesNotConflictAcrossPacketKinds() public {
        bytes32 sharedMsgId = keccak256("shared-msg-id");

        uint64 nextEpoch = nav.navEpoch() + 1;
        vm.prank(admin);
        bridge.relayNAV(SRC_CHAIN, SRC_PEER, sharedMsgId, RAY, uint40(block.timestamp), 0, nextEpoch);

        vm.prank(admin);
        bridge.receiveBridgeMint(SRC_CHAIN, SRC_PEER, sharedMsgId, user2, 5 ether);

        assertEq(vault.balanceOf(user2), 5 ether);
        assertTrue(bridge.processed(bridge.processedMessageKey(1, SRC_CHAIN, SRC_PEER, sharedMsgId)));
        assertTrue(bridge.processed(bridge.processedMessageKey(2, SRC_CHAIN, SRC_PEER, sharedMsgId)));
    }

    function test_SameMsgIdDoesNotConflictAcrossTrustedChains() public {
        bytes32 sharedMsgId = keccak256("shared-cross-chain-msg-id");

        vm.startPrank(admin);
        bridge.receiveBridgeMint(SRC_CHAIN, SRC_PEER, sharedMsgId, user1, 3 ether);
        bridge.receiveBridgeMint(ALT_CHAIN, ALT_PEER, sharedMsgId, user2, 4 ether);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), 3 ether);
        assertEq(vault.balanceOf(user2), 4 ether);
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
        bridge.setMintLimit(10 ether);

        vm.prank(admin);
        bridge.receiveBridgeMint(SRC_CHAIN, SRC_PEER, keccak256("ok"), user2, 10 ether);

        vm.prank(admin);
        vm.expectRevert(WSSDCCrossChainBridgeV2.MINT_LIMIT.selector);
        bridge.receiveBridgeMint(SRC_CHAIN, SRC_PEER, keccak256("over"), user2, 1);
    }

    function test_BridgeOutReopensOutstandingMintCapacity() public {
        vm.prank(admin);
        bridge.setMintLimit(10 ether);

        vm.prank(admin);
        bridge.receiveBridgeMint(SRC_CHAIN, SRC_PEER, keccak256("m1"), user1, 10 ether);
        assertEq(bridge.outstandingShares(), 10 ether);

        vm.prank(user1);
        bridge.bridgeOut(SRC_CHAIN, bytes32(uint256(uint160(user2))), 6 ether);
        assertEq(bridge.outstandingShares(), 4 ether);

        vm.prank(admin);
        bridge.receiveBridgeMint(SRC_CHAIN, SRC_PEER, keccak256("m2"), user2, 6 ether);
        assertEq(bridge.outstandingShares(), 10 ether);
    }

    function test_NativeBridgeOutDoesNotReopenOutstandingMintCapacity() public {
        _mintAndDeposit(user1, 20 ether);

        vm.prank(admin);
        bridge.setMintLimit(10 ether);

        vm.prank(admin);
        bridge.receiveBridgeMint(SRC_CHAIN, SRC_PEER, keccak256("native-bypass-seed"), user2, 10 ether);
        assertEq(bridge.outstandingShares(), 10 ether);

        vm.prank(user1);
        bridge.bridgeOut(SRC_CHAIN, bytes32(uint256(uint160(user3))), 5 ether);

        assertEq(vault.bridgedSharesBalance(user1), 0);
        assertEq(bridge.outstandingShares(), 10 ether);

        vm.prank(admin);
        vm.expectRevert(WSSDCCrossChainBridgeV2.MINT_LIMIT.selector);
        bridge.receiveBridgeMint(SRC_CHAIN, SRC_PEER, keccak256("native-bypass-over"), user3, 1 ether);
    }

    function test_TransferredBridgedSharesKeepProvenanceOnBridgeOut() public {
        vm.prank(admin);
        bridge.receiveBridgeMint(SRC_CHAIN, SRC_PEER, keccak256("transfer-seed"), user1, 10 ether);

        vm.prank(user1);
        vault.transfer(user2, 4 ether);

        assertEq(vault.bridgedSharesBalance(user1), 6 ether);
        assertEq(vault.bridgedSharesBalance(user2), 4 ether);
        assertEq(vault.bridgedSharesSupply(), 10 ether);

        vm.prank(user2);
        bridge.bridgeOut(SRC_CHAIN, bytes32(uint256(uint160(user3))), 4 ether);

        assertEq(vault.bridgedSharesBalance(user2), 0);
        assertEq(vault.bridgedSharesSupply(), 6 ether);
        assertEq(bridge.outstandingShares(), 6 ether);
    }

    function test_BridgeOutNeverMakesOutstandingNegative() public {
        _mintAndDeposit(user1, 20 ether);

        vm.prank(user1);
        bridge.bridgeOut(SRC_CHAIN, bytes32(uint256(uint160(user2))), 5 ether);

        assertEq(bridge.outstandingShares(), 0);
    }

    function test_ReceiveBridgeMintRejectsCoverageBreach() public {
        _mintAndDeposit(user1, 100 ether);

        uint64 nextEpoch = nav.navEpoch() + 1;
        vm.startPrank(admin);
        nav.relayNAV(12e26, uint40(block.timestamp), 0, nextEpoch);
        vault.setMinBridgeLiquidityCoverageBps(9_000);
        vm.stopPrank();

        vm.prank(admin);
        vm.expectRevert(wSSDCVaultV2.LIQUIDITY_COVERAGE.selector);
        bridge.receiveBridgeMint(SRC_CHAIN, SRC_PEER, keccak256("coverage"), user2, 1 ether);
    }
}
