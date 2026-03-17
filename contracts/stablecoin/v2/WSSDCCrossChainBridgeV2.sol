// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {NAVControllerV2} from "./NAVControllerV2.sol";
import {wSSDCVaultV2} from "./wSSDCVaultV2.sol";

contract WSSDCCrossChainBridgeV2 is AccessControl, ReentrancyGuard {
    uint8 internal constant MESSAGE_KIND_BRIDGE_MINT = 1;
    uint8 internal constant MESSAGE_KIND_NAV_RELAY = 2;

    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    wSSDCVaultV2 public immutable vault;
    NAVControllerV2 public immutable navController;

    bool public bridgePaused;

    mapping(uint32 => bytes32) public trustedPeer;
    mapping(bytes32 => bool) public processed;

    mapping(address => uint256) public bridgeOutNonce;

    uint256 public maxOutstandingShares;

    error ZeroAddress();
    error BRIDGE_PAUSED();
    error UNTRUSTED_PEER();
    error REPLAY();
    error MINT_LIMIT();
    error INVALID_RECIPIENT();
    error INVALID_SHARES();

    event TrustedPeerSet(uint32 indexed chainId, bytes32 indexed peer);
    event BridgePausedSet(bool paused);
    event MintLimitSet(uint256 limit);

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
        if (address(vault_) == address(0)) revert ZeroAddress();
        if (address(navController_) == address(0)) revert ZeroAddress();
        if (admin == address(0)) revert ZeroAddress();

        vault = vault_;
        navController = navController_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(BRIDGE_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    function setTrustedPeer(uint32 chainId, bytes32 peer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        trustedPeer[chainId] = peer;
        emit TrustedPeerSet(chainId, peer);
    }

    function setBridgePaused(bool paused) external onlyRole(PAUSER_ROLE) {
        bridgePaused = paused;
        emit BridgePausedSet(paused);
    }

    function setMintLimit(uint256 limit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxOutstandingShares = limit;
        emit MintLimitSet(limit);
    }

    function remainingMintCapacityShares() external view returns (uint256) {
        uint256 limit = maxOutstandingShares;
        uint256 currentOutstanding = outstandingShares();
        if (limit == 0 || currentOutstanding >= limit) {
            return limit == 0 ? type(uint256).max : 0;
        }
        return limit - currentOutstanding;
    }

    function outstandingShares() public view returns (uint256) {
        return vault.bridgedSharesSupply();
    }

    /// @notice Preflight check: can a bridge-out of `shares` to `dstChain` proceed?
    ///         Returns false if bridge is paused, peer is untrusted, or shares are zero.
    function canBridge(uint32 dstChain, uint256 shares) external view returns (bool) {
        if (bridgePaused) return false;
        if (shares == 0) return false;
        if (trustedPeer[dstChain] == bytes32(0)) return false;
        return true;
    }

    function bridgeOut(uint32 dstChain, bytes32 recipient, uint256 shares) external nonReentrant returns (bytes32 msgId) {
        if (bridgePaused) {
            revert BRIDGE_PAUSED();
        }
        if (shares == 0) {
            revert INVALID_SHARES();
        }
        if (recipient == bytes32(0)) {
            revert INVALID_RECIPIENT();
        }
        if (trustedPeer[dstChain] == bytes32(0)) {
            revert UNTRUSTED_PEER();
        }

        vault.burnBridgeShares(msg.sender, shares);
        uint256 nonce = bridgeOutNonce[msg.sender];
        unchecked {
            bridgeOutNonce[msg.sender] = nonce + 1;
        }

        msgId = keccak256(
            abi.encode(address(this), block.chainid, dstChain, msg.sender, recipient, shares, nonce)
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
        bytes32 processedKey = _processedKey(MESSAGE_KIND_BRIDGE_MINT, srcChain, srcPeer, msgId);
        if (processed[processedKey]) {
            revert REPLAY();
        }

        if (to == address(0)) {
            revert INVALID_RECIPIENT();
        }
        if (shares == 0) {
            revert INVALID_SHARES();
        }

        processed[processedKey] = true;

        uint256 limit = maxOutstandingShares;
        uint256 currentOutstanding = outstandingShares();
        if (limit > 0) {
            uint256 nextOutstanding = currentOutstanding + shares;
            if (nextOutstanding > limit) {
                revert MINT_LIMIT();
            }
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
        bytes32 processedKey = _processedKey(MESSAGE_KIND_NAV_RELAY, srcChain, srcPeer, msgId);
        if (processed[processedKey]) {
            revert REPLAY();
        }

        processed[processedKey] = true;

        navController.relayNAV(nav0Ray, t0, ratePerSecondRay, newEpoch);
        emit NAVRelayed(newEpoch, nav0Ray, t0, ratePerSecondRay);
    }

    function processedMessageKey(uint8 messageKind, uint32 srcChain, bytes32 srcPeer, bytes32 msgId)
        external
        view
        returns (bytes32)
    {
        return _processedKey(messageKind, srcChain, srcPeer, msgId);
    }

    function _processedKey(uint8 messageKind, uint32 srcChain, bytes32 srcPeer, bytes32 msgId)
        internal
        view
        returns (bytes32)
    {
        return keccak256(abi.encode(address(this), block.chainid, messageKind, srcChain, srcPeer, msgId));
    }
}
