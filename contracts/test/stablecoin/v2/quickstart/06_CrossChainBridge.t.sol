// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2QuickstartBase} from "./SSDCV2QuickstartBase.sol";
import {WSSDCCrossChainBridgeV2} from "../../../../stablecoin/v2/WSSDCCrossChainBridgeV2.sol";
import {SSDCStatusLensV2} from "../../../../stablecoin/v2/SSDCStatusLensV2.sol";

/// @title Quickstart 06: Cross-Chain Bridge Operations
/// @notice Demonstrates how AI agents move wSSDC shares between chains,
///         how NAV is synchronized cross-chain, and capacity management.
///
///   On Set Chain, the WSSDCCrossChainBridgeV2 manages:
///     - Bridge-out: burn shares locally, mint on destination
///     - Bridge-in:  receive minted shares from a source chain
///     - NAV relay:  synchronize NAV across chains
///     - Capacity:   limit outstanding bridged shares
///     - Replay protection: each message processed exactly once
///
///   Note: In production, bridge messages are relayed by off-chain attestors.
///         Here we simulate both sides on a single chain for clarity.
///
///   Run:  forge test --match-contract CrossChainBridge -vvv
contract CrossChainBridge is SSDCV2QuickstartBase {
    uint32 constant CHAIN_ARBITRUM = 42161;
    uint32 constant CHAIN_BASE    = 8453;
    bytes32 constant ARBITRUM_PEER = bytes32(uint256(uint160(0xA4B17E1)));
    bytes32 constant BASE_PEER     = bytes32(uint256(uint160(0xBA5E001)));

    function setUp() public override {
        super.setUp();

        // Configure trusted peers and mint limit
        vm.startPrank(admin);
        bridge.setTrustedPeer(CHAIN_ARBITRUM, ARBITRUM_PEER);
        bridge.setTrustedPeer(CHAIN_BASE, BASE_PEER);
        bridge.setMintLimit(50_000 ether); // max 50k bridged shares outstanding
        vm.stopPrank();

        // Fund agents
        _fundAgent(agentAlpha, 20_000 ether);
        _fundAgent(agentBeta, 15_000 ether);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Bridge out: agent burns shares to move them to another chain
    // ─────────────────────────────────────────────────────────────────────
    function test_BridgeOut() public {
        uint256 sharesBefore = vault.balanceOf(agentAlpha);

        // Preflight check
        assertTrue(bridge.canBridge(CHAIN_ARBITRUM, 5_000 ether));

        // Alpha bridges 5,000 shares to Arbitrum
        vm.prank(agentAlpha);
        bytes32 msgId = bridge.bridgeOut(
            CHAIN_ARBITRUM,
            bytes32(uint256(uint160(agentAlpha))), // recipient on Arbitrum
            5_000 ether
        );

        assertGt(uint256(msgId), 0, "message ID generated");
        assertEq(vault.balanceOf(agentAlpha), sharesBefore - 5_000 ether, "shares burned");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Bridge in: receive minted shares from another chain
    // ─────────────────────────────────────────────────────────────────────
    function test_BridgeIn() public {
        uint256 betaBefore = vault.balanceOf(agentBeta);

        // Simulate receiving a bridge message from Arbitrum
        bytes32 msgId = keccak256("bridge-msg-from-arbitrum-001");
        vm.prank(admin); // admin has BRIDGE_ROLE
        bridge.receiveBridgeMint(
            CHAIN_ARBITRUM,
            ARBITRUM_PEER,
            msgId,
            agentBeta,
            3_000 ether
        );

        assertEq(vault.balanceOf(agentBeta), betaBefore + 3_000 ether, "shares minted");
        assertEq(vault.bridgedSharesBalance(agentBeta), 3_000 ether, "tracked as bridged");
        assertEq(bridge.outstandingShares(), 3_000 ether, "outstanding updated");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Bridge round-trip: out from Alpha → in to Beta → trade → out
    // ─────────────────────────────────────────────────────────────────────
    function test_BridgeRoundTrip() public {
        // ── Step 1: Alpha bridges out 8,000 shares to Arbitrum ──────────
        vm.prank(agentAlpha);
        bytes32 outMsgId = bridge.bridgeOut(
            CHAIN_ARBITRUM,
            bytes32(uint256(uint160(agentBeta))),
            8_000 ether
        );

        assertEq(vault.balanceOf(agentAlpha), 12_000 ether); // 20k - 8k

        // ── Step 2: Beta receives 8,000 bridged shares ──────────────────
        vm.prank(admin);
        bridge.receiveBridgeMint(
            CHAIN_ARBITRUM, ARBITRUM_PEER,
            keccak256("relay-of-outMsg"),
            agentBeta,
            8_000 ether
        );

        assertEq(vault.balanceOf(agentBeta), 23_000 ether); // 15k + 8k
        assertEq(vault.bridgedSharesBalance(agentBeta), 8_000 ether);
        assertEq(bridge.outstandingShares(), 8_000 ether);

        // ── Step 3: Beta bridges some shares back to Base ───────────────
        vm.prank(agentBeta);
        bridge.bridgeOut(
            CHAIN_BASE,
            bytes32(uint256(uint160(agentAlpha))),
            3_000 ether
        );

        // Outstanding should track correctly — bridged provenance follows transfers
        assertEq(vault.balanceOf(agentBeta), 20_000 ether); // 23k - 3k
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Mint limit enforcement: capacity cannot be exceeded
    // ─────────────────────────────────────────────────────────────────────
    function test_MintLimit() public {
        // Mint limit is 50,000 shares
        assertEq(bridge.remainingMintCapacityShares(), 50_000 ether);

        // Bridge in 40,000 shares
        vm.prank(admin);
        bridge.receiveBridgeMint(
            CHAIN_ARBITRUM, ARBITRUM_PEER,
            keccak256("big-mint-1"),
            agentAlpha,
            40_000 ether
        );

        assertEq(bridge.remainingMintCapacityShares(), 10_000 ether);

        // Try to bridge in 15,000 more → exceeds limit
        vm.prank(admin);
        vm.expectRevert(WSSDCCrossChainBridgeV2.MINT_LIMIT.selector);
        bridge.receiveBridgeMint(
            CHAIN_ARBITRUM, ARBITRUM_PEER,
            keccak256("big-mint-2"),
            agentBeta,
            15_000 ether
        );

        // Bridge in exactly 10,000 → fits remaining capacity
        vm.prank(admin);
        bridge.receiveBridgeMint(
            CHAIN_ARBITRUM, ARBITRUM_PEER,
            keccak256("exact-fit"),
            agentBeta,
            10_000 ether
        );

        assertEq(bridge.remainingMintCapacityShares(), 0, "capacity exhausted");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Replay protection: same message cannot be processed twice
    // ─────────────────────────────────────────────────────────────────────
    function test_ReplayProtection() public {
        bytes32 msgId = keccak256("unique-bridge-msg");

        vm.prank(admin);
        bridge.receiveBridgeMint(CHAIN_ARBITRUM, ARBITRUM_PEER, msgId, agentAlpha, 1_000 ether);

        // Attempt replay
        vm.prank(admin);
        vm.expectRevert(WSSDCCrossChainBridgeV2.REPLAY.selector);
        bridge.receiveBridgeMint(CHAIN_ARBITRUM, ARBITRUM_PEER, msgId, agentAlpha, 1_000 ether);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Untrusted peer rejection
    // ─────────────────────────────────────────────────────────────────────
    function test_UntrustedPeerRejected() public {
        uint32 unknownChain = 999;
        bytes32 fakePeer = bytes32(uint256(0xBAD));

        // Bridge out to untrusted chain
        vm.prank(agentAlpha);
        vm.expectRevert(WSSDCCrossChainBridgeV2.UNTRUSTED_PEER.selector);
        bridge.bridgeOut(unknownChain, bytes32(uint256(uint160(agentBeta))), 100 ether);

        // Bridge in from wrong peer
        vm.prank(admin);
        vm.expectRevert(WSSDCCrossChainBridgeV2.UNTRUSTED_PEER.selector);
        bridge.receiveBridgeMint(
            CHAIN_ARBITRUM, fakePeer,
            keccak256("untrusted"),
            agentAlpha, 100 ether
        );
    }

    // ─────────────────────────────────────────────────────────────────────
    //  NAV relay: synchronize NAV across chains via bridge
    // ─────────────────────────────────────────────────────────────────────
    function test_NAVRelay() public {
        uint64 currentEpoch = nav.navEpoch();
        uint256 newNavRay = 102e25; // 1.02

        // Relay NAV from Arbitrum peer
        bytes32 msgId = keccak256("nav-relay-msg");
        vm.prank(admin);
        bridge.relayNAV(
            CHAIN_ARBITRUM,
            ARBITRUM_PEER,
            msgId,
            newNavRay,
            uint40(block.timestamp), // t0 = now
            int256(0),               // zero forward rate
            currentEpoch + 1
        );

        assertEq(nav.currentNAVRay(), newNavRay, "NAV synchronized via relay");
        assertEq(nav.navEpoch(), currentEpoch + 1, "epoch advanced");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Bridge status via StatusLens
    // ─────────────────────────────────────────────────────────────────────
    function test_BridgeStatusLens() public {
        // Bridge in some shares
        vm.prank(admin);
        bridge.receiveBridgeMint(
            CHAIN_ARBITRUM, ARBITRUM_PEER,
            keccak256("status-test"),
            agentAlpha, 10_000 ether
        );

        SSDCStatusLensV2.Status memory s = lens.getStatus();
        assertEq(s.bridgeOutstandingShares, 10_000 ether);
        assertEq(s.bridgeOutstandingLimitShares, 50_000 ether);
        assertEq(s.bridgeRemainingCapacityShares, 40_000 ether);
        assertTrue(s.bridgingAllowed);
        assertTrue(s.bridgeMintAllowed);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Bridge pause: isolated from other subsystems
    // ─────────────────────────────────────────────────────────────────────
    function test_BridgePause_Isolated() public {
        // Pause only the bridge
        vm.prank(admin);
        bridge.setBridgePaused(true);

        // Bridge operations fail
        vm.prank(agentAlpha);
        vm.expectRevert(WSSDCCrossChainBridgeV2.BRIDGE_PAUSED.selector);
        bridge.bridgeOut(CHAIN_ARBITRUM, bytes32(uint256(uint160(agentBeta))), 100 ether);

        // But everything else works
        SSDCStatusLensV2.Status memory s = lens.getStatus();
        assertTrue(s.mintDepositAllowed, "vault still operational");
        assertFalse(s.escrowOpsPaused, "escrow still operational");
        assertFalse(s.bridgingAllowed, "bridge paused");
    }
}
