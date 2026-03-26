// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {wSSDCVaultV2} from "./wSSDCVaultV2.sol";

contract SSDCClaimQueueV2 is ERC721, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant BUFFER_ROLE = keccak256("BUFFER_ROLE");
    bytes32 public constant QUEUE_ROLE = keccak256("QUEUE_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    enum Status {
        PENDING,
        CLAIMABLE,
        CLAIMED,
        CANCELLED
    }

    /// @dev Packed from 4 slots to 2:
    ///   Slot 1: sharesLocked(16) + assetsSnapshot(16) = 32
    ///   Slot 2: assetsOwed(16) + requestedAt(5) + status(1) = 22
    struct Claim {
        uint128 sharesLocked;
        uint128 assetsSnapshot;
        uint128 assetsOwed;
        uint40 requestedAt;
        Status status;
    }

    wSSDCVaultV2 public immutable vault;
    IERC20 public immutable settlementAsset;

    mapping(uint256 => Claim) public claims;
    uint256 public head;
    uint256 public nextClaimId;

    uint256 public availableAssets;
    uint256 public reservedAssets;

    uint256 public minClaimShares;

    bool public processQueuePermissionless;
    bool public skipBlockedClaims;
    bool public queueOpsPaused;

    error ZeroAddress();
    error MINT_REDEEM_PAUSED();
    error QUEUE_OPS_PAUSED();
    error NOT_PENDING();
    error NOT_CLAIMABLE();
    error NOT_OWNER();
    error INSUFFICIENT_AVAILABLE();
    error INSUFFICIENT_RESERVED();
    error BELOW_MIN_CLAIM();

    event RedeemRequested(
        uint256 indexed claimId,
        address indexed receiver,
        uint256 shares,
        uint256 assetsSnapshot
    );
    event RedeemCancelled(uint256 indexed claimId, address indexed receiver, uint256 sharesReturned);
    event RedeemClaimable(uint256 indexed claimId, uint256 assetsOwed);
    event RedeemClaimed(uint256 indexed claimId, address indexed caller, uint256 assetsPaid);

    event ClaimSkipped(uint256 indexed claimId, uint256 assetsNeeded, uint256 availableBuffer);
    event BufferRefilled(address indexed from, uint256 amount);
    event QueuePermissionlessSet(bool permissionless);
    event QueueSkipBlockedClaimsSet(bool enabled);
    event QueueOpsPausedSet(bool paused);
    event MinClaimSharesUpdated(uint256 minShares);

    constructor(wSSDCVaultV2 vault_, IERC20 settlementAsset_, address admin) ERC721("SSDC Claim", "SSDC_Claim") {
        if (address(vault_) == address(0)) revert ZeroAddress();
        if (address(settlementAsset_) == address(0)) revert ZeroAddress();
        if (admin == address(0)) revert ZeroAddress();

        vault = vault_;
        settlementAsset = settlementAsset_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(BUFFER_ROLE, admin);
        _grantRole(QUEUE_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        head = 1;
        nextClaimId = 1;
        processQueuePermissionless = true;
        skipBlockedClaims = false;
    }

    function requestRedeem(uint256 shares, address receiver) external nonReentrant returns (uint256 claimId) {
        _requireQueueOpsActive();
        _requireMintRedeemActive();
        if (shares < minClaimShares && minClaimShares > 0) {
            revert BELOW_MIN_CLAIM();
        }

        vault.currentNAVRay();
        vault.transferFrom(msg.sender, address(this), shares);

        uint256 assetsSnapshot = vault.convertToAssets(shares);

        claimId = nextClaimId;
        unchecked {
            nextClaimId = claimId + 1;
        }

        claims[claimId] = Claim({
            sharesLocked: uint128(shares),
            assetsSnapshot: uint128(assetsSnapshot),
            assetsOwed: 0,
            requestedAt: uint40(block.timestamp),
            status: Status.PENDING
        });

        _mint(receiver, claimId);

        emit RedeemRequested(claimId, receiver, shares, assetsSnapshot);
    }

    function cancel(uint256 claimId, address receiver) external nonReentrant {
        _requireQueueOpsActive();
        if (ownerOf(claimId) != msg.sender) {
            revert NOT_OWNER();
        }

        Claim storage claimRef = claims[claimId];
        if (claimRef.status != Status.PENDING) {
            revert NOT_PENDING();
        }

        uint256 sharesReturned = claimRef.sharesLocked;

        _burn(claimId);
        vault.transfer(receiver, sharesReturned);

        claimRef.status = Status.CANCELLED;
        claimRef.sharesLocked = 0;

        emit RedeemCancelled(claimId, receiver, sharesReturned);
    }

    function processQueue(uint256 maxClaims) external nonReentrant returns (uint256 processed) {
        _requireQueueOpsActive();
        _requireMintRedeemActive();

        if (!processQueuePermissionless) {
            _checkRole(QUEUE_ROLE, msg.sender);
        }

        _syncHead();

        uint256 cursor = head;
        uint256 maxId = nextClaimId;
        uint256 scansRemaining = _scanBudget(maxClaims);
        bool canSkipBlockedClaims = skipBlockedClaims;

        while (cursor < maxId && processed < maxClaims && scansRemaining > 0) {
            if (claims[cursor].status != Status.PENDING) {
                unchecked {
                    ++cursor;
                    --scansRemaining;
                }
                continue;
            }

            if (_tryProcessClaim(cursor)) {
                unchecked {
                    ++processed;
                }
            } else if (canSkipBlockedClaims) {
                Claim storage skipped = claims[cursor];
                uint256 assetsNeeded = vault.convertToAssets(skipped.sharesLocked);
                emit ClaimSkipped(cursor, assetsNeeded, availableAssets);
            } else {
                break;
            }

            unchecked {
                ++cursor;
                --scansRemaining;
            }
        }

        _syncHead();
    }

    function claim(uint256 claimId) external nonReentrant {
        _requireQueueOpsActive();
        if (ownerOf(claimId) != msg.sender) {
            revert NOT_OWNER();
        }

        Claim storage claimRef = claims[claimId];
        if (claimRef.status != Status.CLAIMABLE) {
            revert NOT_CLAIMABLE();
        }

        uint256 assetsPaid = claimRef.assetsOwed;

        _burn(claimId);

        claimRef.status = Status.CLAIMED;
        claimRef.assetsOwed = 0;

        _disburseReserved(msg.sender, assetsPaid);

        emit RedeemClaimed(claimId, msg.sender, assetsPaid);
    }

    function refill(uint256 amount) external onlyRole(BUFFER_ROLE) nonReentrant {
        settlementAsset.safeTransferFrom(msg.sender, address(this), amount);
        availableAssets += amount;
        emit BufferRefilled(msg.sender, amount);
    }

    function setProcessQueuePermissionless(bool permissionless) external onlyRole(DEFAULT_ADMIN_ROLE) {
        processQueuePermissionless = permissionless;
        emit QueuePermissionlessSet(permissionless);
    }

    function setSkipBlockedClaims(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        skipBlockedClaims = enabled;
        emit QueueSkipBlockedClaimsSet(enabled);
    }

    function setQueueOpsPaused(bool paused) external onlyRole(PAUSER_ROLE) {
        queueOpsPaused = paused;
        emit QueueOpsPausedSet(paused);
    }

    function setMinClaimShares(uint256 minShares) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minClaimShares = minShares;
        emit MinClaimSharesUpdated(minShares);
    }

    function pendingClaimCount() external view returns (uint256 count) {
        uint256 maxId = nextClaimId;
        for (uint256 i = head; i < maxId; ) {
            if (claims[i].status == Status.PENDING) {
                unchecked { ++count; }
            }
            unchecked { ++i; }
        }
    }

    function queueDepth() external view returns (uint256) {
        return nextClaimId - head;
    }

    function reserve(uint256 amount) external onlyRole(BUFFER_ROLE) {
        _reserve(amount);
    }

    function disburseReserved(address to, uint256 amount) external onlyRole(BUFFER_ROLE) {
        _disburseReserved(to, amount);
    }

    function _reserve(uint256 amount) internal {
        if (availableAssets < amount) {
            revert INSUFFICIENT_AVAILABLE();
        }

        unchecked {
            availableAssets -= amount;
            reservedAssets += amount;
        }
    }

    function _disburseReserved(address to, uint256 amount) internal {
        if (reservedAssets < amount) {
            revert INSUFFICIENT_RESERVED();
        }

        unchecked {
            reservedAssets -= amount;
        }

        settlementAsset.safeTransfer(to, amount);
    }

    function _requireMintRedeemActive() internal view {
        if (vault.mintRedeemPaused()) {
            revert MINT_REDEEM_PAUSED();
        }
    }

    function _requireQueueOpsActive() internal view {
        if (queueOpsPaused) {
            revert QUEUE_OPS_PAUSED();
        }
    }

    function _tryProcessClaim(uint256 claimId) internal returns (bool processedClaim) {
        Claim storage claimRef = claims[claimId];
        if (claimRef.status != Status.PENDING) {
            return false;
        }

        uint256 assetsNow = vault.convertToAssets(claimRef.sharesLocked);
        uint256 vaultAssets = settlementAsset.balanceOf(address(vault));
        uint256 assetsFromVault = assetsNow;
        if (assetsFromVault > vaultAssets) {
            assetsFromVault = vaultAssets;
        }

        uint256 neededFromBuffer = assetsNow - assetsFromVault;
        if (availableAssets < neededFromBuffer) {
            return false;
        }

        // Pull real settlement assets from the vault before falling back to the external queue buffer.
        if (assetsFromVault > 0) {
            uint256 sharesBurnedByWithdraw = vault.withdraw(assetsFromVault, address(this), address(this));
            availableAssets += assetsFromVault;

            if (sharesBurnedByWithdraw < claimRef.sharesLocked) {
                vault.burnQueuedShares(claimRef.sharesLocked - sharesBurnedByWithdraw);
            }
        } else {
            vault.burnQueuedShares(claimRef.sharesLocked);
        }

        _reserve(assetsNow);

        claimRef.assetsOwed = uint128(assetsNow);
        claimRef.sharesLocked = 0;
        claimRef.status = Status.CLAIMABLE;

        emit RedeemClaimable(claimId, assetsNow);
        return true;
    }

    function _syncHead() internal {
        uint256 cursor = head;
        uint256 maxId = nextClaimId;

        while (cursor < maxId && claims[cursor].status != Status.PENDING) {
            unchecked {
                ++cursor;
            }
        }

        head = cursor;
    }

    function _scanBudget(uint256 maxClaims) internal pure returns (uint256 scans) {
        if (maxClaims > type(uint256).max / 8) {
            return type(uint256).max;
        }
        return maxClaims * 8;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
