// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {NAVControllerV2} from "./NAVControllerV2.sol";
import {wSSDCVaultV2} from "./wSSDCVaultV2.sol";

contract WSSDCCrossChainBridgeV2 is AccessControl, ReentrancyGuard {
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    wSSDCVaultV2 public immutable vault;
    NAVControllerV2 public immutable navController;

    bool public bridgePaused;

    mapping(uint32 => bytes32) public trustedPeer;
    mapping(bytes32 => bool) public processed;

    mapping(address => uint256) public mintLimit;
    mapping(address => uint256) public minted;

    error BRIDGE_PAUSED();
    error UNTRUSTED_PEER();
    error REPLAY();
    error MINT_LIMIT();

    event TrustedPeerSet(uint32 indexed chainId, bytes32 indexed peer);
    event BridgePausedSet(bool paused);
    event MintLimitSet(address indexed bridge, uint256 limit);

    event BridgeOut(
        bytes32 indexed msgId,
        address indexed from,
        uint32 indexed dstChain,
        bytes32 recipient,
        uint256 shares
    );

    event BridgeIn(bytes32 indexed msgId, address indexed to, uint32 indexed srcChain, uint256 shares);
    event NAVRelayed(uint64 indexed navEpoch, uint256 nav0Ray, uint40 t0, int256 ratePerSecondRay);

    constructor(wSSDCVaultV2 vault_, NAVControllerV2 navController_, address admin) {
        require(admin != address(0), "admin=0");

        vault = vault_;
        navController = navController_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(BRIDGE_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    function setTrustedPeer(uint32 chainId, bytes32 peer) external onlyRole(BRIDGE_ROLE) {
        trustedPeer[chainId] = peer;
        emit TrustedPeerSet(chainId, peer);
    }

    function setBridgePaused(bool paused) external onlyRole(PAUSER_ROLE) {
        bridgePaused = paused;
        emit BridgePausedSet(paused);
    }

    function setMintLimit(address bridge, uint256 limit) external onlyRole(BRIDGE_ROLE) {
        mintLimit[bridge] = limit;
        emit MintLimitSet(bridge, limit);
    }

    function bridgeOut(uint32 dstChain, bytes32 recipient, uint256 shares) external nonReentrant returns (bytes32 msgId) {
        if (bridgePaused) {
            revert BRIDGE_PAUSED();
        }
        if (trustedPeer[dstChain] == bytes32(0)) {
            revert UNTRUSTED_PEER();
        }

        vault.burnBridgeShares(msg.sender, shares);

        msgId = keccak256(
            abi.encodePacked(block.chainid, dstChain, msg.sender, recipient, shares, block.number, block.timestamp)
        );

        emit BridgeOut(msgId, msg.sender, dstChain, recipient, shares);
    }

    function receiveBridgeMint(
        uint32 srcChain,
        bytes32 srcPeer,
        bytes32 msgId,
        address to,
        uint256 shares
    ) external onlyRole(BRIDGE_ROLE) nonReentrant {
        if (bridgePaused) {
            revert BRIDGE_PAUSED();
        }
        if (trustedPeer[srcChain] != srcPeer) {
            revert UNTRUSTED_PEER();
        }
        if (processed[msgId]) {
            revert REPLAY();
        }

        processed[msgId] = true;

        uint256 limit = mintLimit[msg.sender];
        if (limit > 0) {
            uint256 nextMinted = minted[msg.sender] + shares;
            if (nextMinted > limit) {
                revert MINT_LIMIT();
            }
            minted[msg.sender] = nextMinted;
        }

        vault.mintBridgeShares(to, shares);

        emit BridgeIn(msgId, to, srcChain, shares);
    }

    function relayNAV(
        uint32 srcChain,
        bytes32 srcPeer,
        bytes32 msgId,
        uint256 nav0Ray,
        uint40 t0,
        int256 ratePerSecondRay,
        uint64 newEpoch
    ) external onlyRole(BRIDGE_ROLE) {
        if (bridgePaused) {
            revert BRIDGE_PAUSED();
        }
        if (trustedPeer[srcChain] != srcPeer) {
            revert UNTRUSTED_PEER();
        }
        if (processed[msgId]) {
            revert REPLAY();
        }

        processed[msgId] = true;

        navController.relayNAV(nav0Ray, t0, ratePerSecondRay, newEpoch);
        emit NAVRelayed(newEpoch, nav0Ray, t0, ratePerSecondRay);
    }
}
