// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {MockAsset} from "./SSDCV2TestBase.sol";
import {NAVControllerV2} from "../../../stablecoin/v2/NAVControllerV2.sol";
import {WSSDCCrossChainBridgeV2} from "../../../stablecoin/v2/WSSDCCrossChainBridgeV2.sol";
import {wSSDCVaultV2} from "../../../stablecoin/v2/wSSDCVaultV2.sol";

contract BridgeHandlerV2 {
    uint256 internal constant RAY = 1e27;

    WSSDCCrossChainBridgeV2 public immutable bridge;
    NAVControllerV2 public immutable nav;
    wSSDCVaultV2 public immutable vault;

    uint32 public canonicalChain;
    bytes32 public canonicalPeer;
    uint64 public lastEpochObserved;
    uint256 public successfulMintedShares;
    uint256 public successfulBridgedOutShares;

    constructor(
        WSSDCCrossChainBridgeV2 bridge_,
        NAVControllerV2 nav_,
        wSSDCVaultV2 vault_,
        uint32 chain_,
        bytes32 peer_
    ) {
        bridge = bridge_;
        nav = nav_;
        vault = vault_;

        canonicalChain = chain_;
        canonicalPeer = peer_;
        lastEpochObserved = nav.navEpoch();
    }

    function opSetTrustedPeer(uint32 chainIdRaw, uint256 peerSalt) external {
        uint32 chainId = uint32((uint256(chainIdRaw) % 4) + 1);
        bytes32 peer = bytes32(peerSalt);
        if (peer == bytes32(0)) {
            peer = bytes32(uint256(1));
        }

        try bridge.setTrustedPeer(chainId, peer) {
            if (chainId == canonicalChain) {
                canonicalPeer = peer;
            }
        } catch {}

        _trackEpoch();
    }

    function opSetMintLimit(uint256 limitRaw) external {
        uint256 currentMinted = bridge.minted(address(this));
        uint256 limit = currentMinted + (limitRaw % 1_000_000 ether) + 1;

        try bridge.setMintLimit(address(this), limit) {} catch {}
        _trackEpoch();
    }

    function opReceiveBridgeMint(uint256 msgSalt, uint256 sharesRaw, bool useCanonicalPeer) external {
        uint256 shares = (sharesRaw % 10_000 ether) + 1;
        bytes32 msgId = keccak256(abi.encodePacked("mint", msgSalt));
        bytes32 peer = useCanonicalPeer ? canonicalPeer : bytes32(uint256(msgSalt));
        if (peer == bytes32(0)) {
            peer = bytes32(uint256(99));
        }

        uint256 balanceBefore = vault.balanceOf(address(this));
        try bridge.receiveBridgeMint(canonicalChain, peer, msgId, address(this), shares) {
            uint256 balanceAfter = vault.balanceOf(address(this));
            successfulMintedShares += balanceAfter - balanceBefore;
        } catch {}
        _trackEpoch();
    }

    function opRelayNAV(
        uint256 msgSalt,
        uint256 navBpsRaw,
        int256 rateRaw,
        uint8 epochMode,
        bool useCanonicalPeer
    ) external {
        bytes32 msgId = keccak256(abi.encodePacked("nav", msgSalt));

        uint256 navBps = (navBpsRaw % 4_001) + 8_000; // [8000,12000]
        uint256 nav0Ray = (RAY * navBps) / 10_000;

        int256 maxAbs = nav.maxRateAbsRay();
        int256 absRate = int256(uint256(rateRaw < 0 ? -rateRaw : rateRaw) % uint256(maxAbs + 1));
        int256 rate = rateRaw < 0 ? -absRate : absRate;

        uint64 currentEpoch = nav.navEpoch();
        uint64 newEpoch;
        if (epochMode == 0) {
            newEpoch = currentEpoch;
        } else {
            newEpoch = currentEpoch + uint64((epochMode % 3) + 1);
        }

        bytes32 peer = useCanonicalPeer ? canonicalPeer : bytes32(uint256(msgSalt));
        if (peer == bytes32(0)) {
            peer = bytes32(uint256(88));
        }

        try bridge.relayNAV(canonicalChain, peer, msgId, nav0Ray, uint40(block.timestamp), rate, newEpoch) {} catch {}
        _trackEpoch();
    }

    function opBridgeOut(uint256 sharesRaw, uint32 dstRaw) external {
        uint256 bal = vault.balanceOf(address(this));
        if (bal == 0) {
            _trackEpoch();
            return;
        }

        uint256 shares = (sharesRaw % bal) + 1;
        uint32 dst = uint32((uint256(dstRaw) % 4) + 1);

        uint256 balanceBefore = bal;
        try bridge.bridgeOut(dst, bytes32(uint256(uint160(address(this)))), shares) {
            uint256 balanceAfter = vault.balanceOf(address(this));
            successfulBridgedOutShares += balanceBefore - balanceAfter;
        } catch {}
        _trackEpoch();
    }

    function _trackEpoch() internal {
        uint64 current = nav.navEpoch();
        require(current >= lastEpochObserved, "EPOCH_REGRESSED");
        lastEpochObserved = current;
    }
}

contract WSSDCCrossChainBridgeV2InvariantTest is StdInvariant, Test {
    uint256 internal constant RAY = 1e27;

    address internal admin = address(0xA11CE);
    MockAsset internal asset;
    NAVControllerV2 internal nav;
    wSSDCVaultV2 internal vault;
    WSSDCCrossChainBridgeV2 internal bridge;
    BridgeHandlerV2 internal handler;

    uint32 internal constant CHAIN = 101;
    bytes32 internal constant PEER = bytes32(uint256(0xBEEF));

    function setUp() public {
        vm.startPrank(admin);

        asset = new MockAsset();
        nav = new NAVControllerV2(admin, RAY, 9e26, 1e23, 48 hours, 24 hours, 2_000);
        vault = new wSSDCVaultV2(asset, nav, admin);
        bridge = new WSSDCCrossChainBridgeV2(vault, nav, admin);

        vault.grantRole(vault.BRIDGE_ROLE(), address(bridge));
        nav.grantRole(nav.BRIDGE_ROLE(), address(bridge));

        bridge.setTrustedPeer(CHAIN, PEER);
        bridge.setMintLimit(admin, 1_000_000 ether);
        vm.stopPrank();

        handler = new BridgeHandlerV2(bridge, nav, vault, CHAIN, PEER);

        vm.startPrank(admin);
        bridge.grantRole(bridge.BRIDGE_ROLE(), address(handler));
        bridge.setMintLimit(address(handler), 1_000_000 ether);
        vm.stopPrank();

        targetContract(address(handler));
    }

    function invariant_navEpochMonotonic() public view {
        assertGe(nav.navEpoch(), handler.lastEpochObserved());
    }

    function invariant_handlerMintNeverExceedsLimit() public view {
        uint256 limit = bridge.mintLimit(address(handler));
        uint256 minted = bridge.minted(address(handler));
        if (limit > 0) {
            assertLe(minted, limit);
        }
    }

    function invariant_handlerOutstandingBalanceTracksNetBridgeFlow() public view {
        uint256 mintedShares = handler.successfulMintedShares();
        uint256 bridgedOutShares = handler.successfulBridgedOutShares();

        assertGe(mintedShares, bridgedOutShares);
        assertEq(vault.balanceOf(address(handler)), mintedShares - bridgedOutShares);
    }

    function invariant_handlerMintCounterTracksSuccessfulMints() public view {
        assertEq(bridge.minted(address(handler)), handler.successfulMintedShares());
    }
}
