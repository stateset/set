// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {NAVControllerV2} from "./NAVControllerV2.sol";
import {RayMath} from "./RayMath.sol";
import {GroundingRegistryV2} from "./GroundingRegistryV2.sol";
import {SSDCPolicyModuleV2} from "./SSDCPolicyModuleV2.sol";
import {wSSDCVaultV2} from "./wSSDCVaultV2.sol";

contract YieldEscrowV2 is AccessControl, ReentrancyGuard {
    bytes32 public constant FUNDER_ROLE = keccak256("FUNDER_ROLE");
    bytes32 public constant ARBITER_ROLE = keccak256("ARBITER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    enum EscrowStatus {
        NONE,
        FUNDED,
        RELEASED,
        REFUNDED
    }

    enum DisputeResolution {
        NONE,
        RELEASE,
        REFUND
    }

    enum FulfillmentType {
        NONE,
        DELIVERY,
        SERVICE,
        DIGITAL,
        OTHER
    }

    enum DisputeReason {
        NONE,
        NON_DELIVERY,
        QUALITY,
        NOT_AS_DESCRIBED,
        FRAUD_OR_CANCELLED,
        OTHER
    }

    enum SettlementMode {
        NONE,
        BUYER_RELEASE,
        MERCHANT_TIMEOUT_RELEASE,
        DISPUTE_TIMEOUT_RELEASE,
        ARBITER_RELEASE,
        BUYER_REFUND,
        DISPUTE_TIMEOUT_REFUND,
        ARBITER_REFUND
    }

    struct InvoiceTerms {
        uint256 assetsDue;
        uint40 expiry;
        uint40 releaseAfter;
        uint40 maxNavAge;
        uint256 maxSharesIn;
        bool requiresFulfillment;
        FulfillmentType fulfillmentType;
        uint8 requiredMilestones;
        uint40 challengeWindow;    // time after fulfillment for buyer to dispute
        uint40 arbiterDeadline;    // time after dispute for arbiter to resolve
        DisputeResolution disputeTimeoutResolution;
    }

    /// @dev sharesHeld/principalAssetsSnapshot/committedAssets use uint128
    ///      (max ~3.4e38 — sufficient for any practical share/asset amount)
    struct Escrow {
        address buyer;
        address merchant;
        address refundRecipient;
        uint128 sharesHeld;
        uint128 principalAssetsSnapshot;
        uint128 committedAssets;
        uint40 releaseAfter;
        uint16 buyerBps;
        EscrowStatus status;
        bool requiresFulfillment;
        FulfillmentType fulfillmentType;
        bool disputed;
        DisputeReason disputeReason;
        uint40 fulfilledAt;
        bytes32 fulfillmentEvidence;
        DisputeResolution resolution;
        uint40 resolvedAt;
        bytes32 resolutionEvidence;
        uint40 challengeWindow;
        uint40 arbiterDeadline;
        DisputeResolution timeoutResolution;
        uint40 disputedAt;
        SettlementMode settlementMode;
        uint40 settledAt;
    }

    struct ReleaseSplit {
        uint256 totalShares;
        uint256 principalShares;
        uint256 grossYieldShares;
        uint256 reserveShares;
        uint256 feeShares;
        uint256 buyerYieldShares;
        uint256 merchantYieldShares;
    }

    struct SettlementPreview {
        EscrowStatus status;
        bool releaseAfterPassed;
        bool fulfillmentSubmitted;
        bool fulfillmentComplete;
        bool disputeActive;
        bool disputeResolved;
        bool disputeTimedOut;
        bool requiresArbiterResolution;
        bool canBuyerRelease;
        bool canMerchantRelease;
        bool canArbiterRelease;
        bool canBuyerRefund;
        bool canArbiterRefund;
        bool canArbiterResolve;
        SettlementMode buyerReleaseMode;
        SettlementMode merchantReleaseMode;
        SettlementMode arbiterReleaseMode;
        SettlementMode buyerRefundMode;
        SettlementMode arbiterRefundMode;
        uint8 requiredMilestones;
        uint8 completedMilestones;
        uint8 nextMilestoneNumber;
        uint8 disputedMilestone;
        uint40 challengeWindowEndsAt;
        uint40 disputeWindowEndsAt;
    }

    wSSDCVaultV2 public immutable vault;
    NAVControllerV2 public immutable navController;
    SSDCPolicyModuleV2 public immutable policyModule;
    GroundingRegistryV2 public immutable groundingRegistry;

    uint16 public protocolFeeBps;
    address public feeRecipient;
    uint16 public reserveBps;
    address public reserveRecipient;

    bool public escrowOpsPaused;

    uint256 public nextEscrowId;
    mapping(uint256 => Escrow) public escrows;
    mapping(uint256 => uint8) public escrowRequiredMilestones;
    mapping(uint256 => uint8) public escrowCompletedMilestones;
    mapping(uint256 => uint8) public escrowDisputedMilestones;

    error ZeroAddress();
    error SPLIT_INVARIANT();
    error ESCROW_OPS_PAUSED();
    error INVOICE_EXPIRED();
    error NAV_TOO_STALE();
    error SHARES_SLIPPAGE();
    error INVALID_BPS();
    error INVALID_MERCHANT();
    error INVALID_REFUND_RECIPIENT();
    error INVALID_RELEASE_TIME();
    error INVALID_TIMEOUT_RESOLUTION();
    error INVALID_FULFILLMENT_TYPE();
    error INVALID_MILESTONE_COUNT();
    error INVALID_MILESTONE_TARGET();
    error INVALID_DISPUTE_REASON();
    error FLOOR();
    error RELEASE_LOCKED();
    error ESCROW_COMPLETE();
    error ESCROW_EMPTY();
    error SETTLEMENT_AUTH();
    error FULFILLMENT_AUTH();
    error DISPUTE_AUTH();
    error FULFILLMENT_NOT_REQUIRED();
    error FULFILLMENT_PENDING();
    error FULFILLMENT_ALREADY_SUBMITTED();
    error FULFILLMENT_SUBMITTED();
    error DISPUTED();
    error DISPUTE_REQUIRED();
    error DISPUTE_PENDING();
    error INVALID_RESOLUTION();
    error RESOLUTION_MISMATCH();
    error RESOLUTION_ALREADY_SET();
    error MERCHANT_RELEASE_LOCKED();
    error INVALID_EVIDENCE();
    error TIMEOUT_NOT_READY();
    error INVALID_WINDOW_CONFIG();
    error ARBITER_DEADLINE_EXPIRED();

    event EscrowFunded(
        uint256 indexed escrowId,
        address indexed buyer,
        address indexed merchant,
        address refundRecipient,
        uint256 sharesIn,
        uint256 principalAssetsSnapshot,
        uint256 committedAssets,
        uint40 releaseAfter
    );

    event EscrowReleased(
        uint256 indexed escrowId,
        address indexed actor,
        SettlementMode indexed settlementMode,
        uint256 totalShares,
        uint256 principalShares,
        uint256 buyerYieldShares,
        uint256 merchantYieldShares,
        uint256 reserveShares,
        uint256 feeShares
    );

    event EscrowRefunded(
        uint256 indexed escrowId,
        address indexed actor,
        address indexed recipient,
        SettlementMode settlementMode,
        uint256 sharesReturned
    );
    event EscrowFulfillmentSubmitted(
        uint256 indexed escrowId,
        address indexed actor,
        FulfillmentType indexed fulfillmentType,
        uint8 milestoneNumber,
        uint8 requiredMilestones,
        bytes32 evidenceHash,
        bool fulfillmentComplete,
        uint40 fulfilledAt
    );
    event EscrowDisputed(
        uint256 indexed escrowId,
        address indexed actor,
        DisputeReason indexed disputeReason,
        uint8 disputedMilestone,
        bytes32 reasonHash
    );
    event EscrowResolved(
        uint256 indexed escrowId,
        address indexed actor,
        bytes32 indexed evidenceHash,
        DisputeResolution resolution,
        uint40 resolvedAt
    );
    event EscrowTimeoutExecuted(
        uint256 indexed escrowId,
        address indexed executor,
        SettlementMode indexed settlementMode,
        DisputeResolution resolution
    );
    event EscrowOpsPausedSet(bool paused);
    event ProtocolFeeUpdated(uint16 protocolFeeBps, address feeRecipient);
    event ReserveConfigUpdated(uint16 reserveBps, address reserveRecipient);

    constructor(
        wSSDCVaultV2 vault_,
        NAVControllerV2 navController_,
        SSDCPolicyModuleV2 policyModule_,
        GroundingRegistryV2 groundingRegistry_,
        address admin,
        address feeRecipient_
    ) {
        if (address(vault_) == address(0)) revert ZeroAddress();
        if (address(navController_) == address(0)) revert ZeroAddress();
        if (admin == address(0)) revert ZeroAddress();
        if (feeRecipient_ == address(0)) revert ZeroAddress();
        if (address(policyModule_) == address(0)) revert ZeroAddress();
        if (address(groundingRegistry_) == address(0)) revert ZeroAddress();

        vault = vault_;
        navController = navController_;
        policyModule = policyModule_;
        groundingRegistry = groundingRegistry_;
        feeRecipient = feeRecipient_;
        reserveRecipient = feeRecipient_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FUNDER_ROLE, admin);
        _grantRole(ARBITER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        nextEscrowId = 1;
    }

    function setProtocolFee(uint16 protocolFeeBps_, address feeRecipient_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (protocolFeeBps_ > 10_000 || feeRecipient_ == address(0)) {
            revert INVALID_BPS();
        }

        protocolFeeBps = protocolFeeBps_;
        feeRecipient = feeRecipient_;

        emit ProtocolFeeUpdated(protocolFeeBps_, feeRecipient_);
    }

    function setEscrowOpsPaused(bool paused) external onlyRole(PAUSER_ROLE) {
        escrowOpsPaused = paused;
        emit EscrowOpsPausedSet(paused);
    }

    function setReserveConfig(uint16 reserveBps_, address reserveRecipient_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (reserveBps_ > 10_000 || reserveRecipient_ == address(0)) {
            revert INVALID_BPS();
        }

        reserveBps = reserveBps_;
        reserveRecipient = reserveRecipient_;

        emit ReserveConfigUpdated(reserveBps_, reserveRecipient_);
    }

    function getEscrow(uint256 escrowId)
        external
        view
        returns (
            Escrow memory escrowData,
            uint8 requiredMilestones,
            uint8 completedMilestones,
            uint8 disputedMilestone
        )
    {
        escrowData = escrows[escrowId];
        requiredMilestones = escrowRequiredMilestones[escrowId];
        completedMilestones = escrowCompletedMilestones[escrowId];
        disputedMilestone = escrowDisputedMilestones[escrowId];
    }

    function previewReleaseSplit(uint256 escrowId) external view returns (ReleaseSplit memory split) {
        Escrow storage escrow = escrows[escrowId];
        if (escrow.status == EscrowStatus.NONE || escrow.sharesHeld == 0) {
            revert ESCROW_EMPTY();
        }
        if (escrow.status != EscrowStatus.FUNDED) {
            revert ESCROW_COMPLETE();
        }

        return _previewReleaseSplit(escrow.sharesHeld, escrow.principalAssetsSnapshot, escrow.buyerBps, navController.currentNAVRay());
    }

    function previewSettlement(uint256 escrowId) external view returns (SettlementPreview memory preview) {
        Escrow storage escrow = escrows[escrowId];
        if (escrow.status == EscrowStatus.NONE) {
            revert ESCROW_EMPTY();
        }

        preview.status = escrow.status;
        preview.releaseAfterPassed = block.timestamp >= escrow.releaseAfter;
        preview.requiredMilestones = escrowRequiredMilestones[escrowId];
        preview.completedMilestones = escrowCompletedMilestones[escrowId];
        preview.fulfillmentSubmitted = preview.completedMilestones != 0;
        preview.fulfillmentComplete = escrow.fulfilledAt != 0;
        preview.disputeActive = escrow.disputed;
        preview.disputeResolved = escrow.resolution != DisputeResolution.NONE;
        preview.disputeTimedOut = escrow.disputed && _disputeWindowExpired(escrow);
        preview.requiresArbiterResolution = _requiresArbiterResolution(escrow);
        preview.canBuyerRelease = _canBuyerReleasePreview(escrow);
        preview.canMerchantRelease = _canMerchantReleasePreview(escrow);
        preview.canArbiterRelease = _canArbiterReleasePreview(escrow);
        preview.canBuyerRefund = _canBuyerRefundPreview(escrow);
        preview.canArbiterRefund = _canArbiterRefundPreview(escrow);
        preview.canArbiterResolve = _canArbiterResolvePreview(escrow);
        preview.buyerReleaseMode =
            preview.canBuyerRelease ? _releaseSettlementMode(escrow, false, false) : SettlementMode.NONE;
        preview.merchantReleaseMode =
            preview.canMerchantRelease ? _releaseSettlementMode(escrow, false, true) : SettlementMode.NONE;
        preview.arbiterReleaseMode =
            preview.canArbiterRelease ? _releaseSettlementMode(escrow, true, false) : SettlementMode.NONE;
        preview.buyerRefundMode = preview.canBuyerRefund ? _refundSettlementMode(escrow, false) : SettlementMode.NONE;
        preview.arbiterRefundMode =
            preview.canArbiterRefund ? _refundSettlementMode(escrow, true) : SettlementMode.NONE;
        preview.nextMilestoneNumber = _nextMilestoneNumber(preview.completedMilestones, preview.requiredMilestones);
        preview.disputedMilestone = escrowDisputedMilestones[escrowId];
        preview.challengeWindowEndsAt = _challengeWindowEndsAt(escrow);
        preview.disputeWindowEndsAt = _disputeWindowEndsAt(escrow);
    }

    function fundEscrow(address merchant, InvoiceTerms calldata terms, uint16 buyerBps) external nonReentrant returns (uint256 escrowId) {
        return _fundEscrow(msg.sender, msg.sender, msg.sender, merchant, terms, buyerBps);
    }

    function fundEscrowFor(
        address buyer,
        address refundRecipient,
        address merchant,
        InvoiceTerms calldata terms,
        uint16 buyerBps
    ) external onlyRole(FUNDER_ROLE) nonReentrant returns (uint256 escrowId) {
        return _fundEscrow(buyer, msg.sender, refundRecipient, merchant, terms, buyerBps);
    }

    function _fundEscrow(
        address buyer,
        address sharesSource,
        address refundRecipient,
        address merchant,
        InvoiceTerms calldata terms,
        uint16 buyerBps
    ) internal returns (uint256 escrowId) {
        if (escrowOpsPaused) {
            revert ESCROW_OPS_PAUSED();
        }
        if (buyer == address(0)) revert ZeroAddress();
        if (merchant == address(0)) {
            revert INVALID_MERCHANT();
        }
        if (refundRecipient == address(0)) {
            revert INVALID_REFUND_RECIPIENT();
        }
        if (block.timestamp > terms.expiry) {
            revert INVOICE_EXPIRED();
        }
        if (buyerBps > 10_000) {
            revert INVALID_BPS();
        }
        if (terms.releaseAfter < block.timestamp) {
            revert INVALID_RELEASE_TIME();
        }
        if (terms.requiresFulfillment) {
            if (terms.fulfillmentType == FulfillmentType.NONE) {
                revert INVALID_FULFILLMENT_TYPE();
            }
            if (terms.requiredMilestones == 0) {
                revert INVALID_MILESTONE_COUNT();
            }
        } else {
            if (terms.fulfillmentType != FulfillmentType.NONE) {
                revert INVALID_FULFILLMENT_TYPE();
            }
            if (terms.requiredMilestones != 0) {
                revert INVALID_MILESTONE_COUNT();
            }
        }
        // If both windows are 0, no timeout resolution allowed
        if (terms.challengeWindow == 0 && terms.arbiterDeadline == 0) {
            if (terms.disputeTimeoutResolution != DisputeResolution.NONE) {
                revert INVALID_TIMEOUT_RESOLUTION();
            }
        } else {
            // If arbiterDeadline is set, must have a timeout resolution
            if (terms.arbiterDeadline > 0 && terms.disputeTimeoutResolution == DisputeResolution.NONE) {
                revert INVALID_TIMEOUT_RESOLUTION();
            }
            // challengeWindow can be set independently (for merchant auto-release)
        }

        uint256 navAge = block.timestamp - uint256(navController.t0());
        if (navAge > terms.maxNavAge) {
            revert NAV_TOO_STALE();
        }

        uint256 sharesIn = vault.convertToSharesInvoiceOrWithdraw(terms.assetsDue);
        if (sharesIn > terms.maxSharesIn) {
            revert SHARES_SLIPPAGE();
        }
        if (sharesSource == buyer) {
            uint256 nav = navController.currentNAVRay();
            uint256 totalShares = groundingRegistry.totalShares(buyer);
            if (sharesIn > totalShares) {
                revert FLOOR();
            }
            uint256 minAssetsFloor = policyModule.getMinAssetsFloor(buyer);
            uint256 postAssets = RayMath.convertToAssetsDown(totalShares - sharesIn, nav);
            if (postAssets < minAssetsFloor) {
                revert FLOOR();
            }
        }

        // Enforce the same spend policy on invoice funding that is enforced on gas sponsorship.
        policyModule.consumeSpend(buyer, merchant, terms.assetsDue);

        vault.transferFrom(sharesSource, address(this), sharesIn);

        uint256 principalAssetsSnapshot = vault.convertToAssets(sharesIn);
        uint256 committedAssets;
        if (sharesSource != buyer) {
            (uint256 assetsNow, uint256 minAssetsFloor, ) = groundingRegistry.currentAssets(buyer);
            committedAssets = principalAssetsSnapshot;
            if (assetsNow < minAssetsFloor + committedAssets) {
                revert FLOOR();
            }
            policyModule.reserveCommittedSpend(buyer, committedAssets);
        }

        escrowId = nextEscrowId;
        unchecked {
            nextEscrowId = escrowId + 1;
        }
        escrowRequiredMilestones[escrowId] = terms.requiredMilestones;

        escrows[escrowId] = Escrow({
            buyer: buyer,
            merchant: merchant,
            refundRecipient: refundRecipient,
            sharesHeld: uint128(sharesIn),
            principalAssetsSnapshot: uint128(principalAssetsSnapshot),
            committedAssets: uint128(committedAssets),
            releaseAfter: terms.releaseAfter,
            buyerBps: buyerBps,
            status: EscrowStatus.FUNDED,
            requiresFulfillment: terms.requiresFulfillment,
            fulfillmentType: terms.fulfillmentType,
            disputed: false,
            disputeReason: DisputeReason.NONE,
            fulfilledAt: 0,
            fulfillmentEvidence: bytes32(0),
            resolution: DisputeResolution.NONE,
            resolvedAt: 0,
            resolutionEvidence: bytes32(0),
            challengeWindow: terms.challengeWindow,
            arbiterDeadline: terms.arbiterDeadline,
            timeoutResolution: terms.disputeTimeoutResolution,
            disputedAt: 0,
            settlementMode: SettlementMode.NONE,
            settledAt: 0
        });

        emit EscrowFunded(
            escrowId,
            buyer,
            merchant,
            refundRecipient,
            sharesIn,
            principalAssetsSnapshot,
            committedAssets,
            terms.releaseAfter
        );
    }

    function release(uint256 escrowId) external nonReentrant {
        if (escrowOpsPaused) {
            revert ESCROW_OPS_PAUSED();
        }
        Escrow storage escrow = escrows[escrowId];
        if (escrow.status == EscrowStatus.NONE || escrow.sharesHeld == 0) {
            revert ESCROW_EMPTY();
        }
        if (escrow.status != EscrowStatus.FUNDED) {
            revert ESCROW_COMPLETE();
        }
        bool isArbiter = hasRole(ARBITER_ROLE, msg.sender);
        bool isMerchant = msg.sender == escrow.merchant;
        if (msg.sender != escrow.buyer && !isArbiter) {
            if (!isMerchant) {
                revert SETTLEMENT_AUTH();
            }
            if (!escrow.disputed && !_merchantMayRelease(escrow)) {
                revert MERCHANT_RELEASE_LOCKED();
            }
        }
        if (block.timestamp < escrow.releaseAfter) {
            revert RELEASE_LOCKED();
        }
        bool releaseAuthorizedByResolution;
        if (escrow.disputed) {
            if (escrow.resolution == DisputeResolution.NONE) {
                if (!_disputeWindowExpired(escrow)) {
                    revert DISPUTE_PENDING();
                }
                if (escrow.timeoutResolution != DisputeResolution.RELEASE) {
                    revert RESOLUTION_MISMATCH();
                }
            } else if (escrow.resolution != DisputeResolution.RELEASE) {
                revert RESOLUTION_MISMATCH();
            } else {
                releaseAuthorizedByResolution = true;
            }
        }
        if (escrow.requiresFulfillment && escrow.fulfilledAt == 0 && !releaseAuthorizedByResolution && !isArbiter) {
            revert FULFILLMENT_PENDING();
        }

        SettlementMode settlementMode = _releaseSettlementMode(escrow, isArbiter, isMerchant);

        uint256 nav = navController.currentNAVRay();

        uint256 S = escrow.sharesHeld;
        uint256 committedAssets = escrow.committedAssets;
        ReleaseSplit memory split =
            _previewReleaseSplit(S, escrow.principalAssetsSnapshot, escrow.buyerBps, nav);
        uint256 merchantShares = split.principalShares + split.merchantYieldShares;

        if (committedAssets > 0) {
            policyModule.releaseCommittedSpend(escrow.buyer, committedAssets);
        }
        escrow.sharesHeld = 0;
        escrow.committedAssets = 0;
        escrow.status = EscrowStatus.RELEASED;
        escrow.settlementMode = settlementMode;
        escrow.settledAt = uint40(block.timestamp);

        if (merchantShares > 0) {
            vault.transfer(escrow.merchant, merchantShares);
        }
        if (split.buyerYieldShares > 0) {
            vault.transfer(escrow.buyer, split.buyerYieldShares);
        }
        if (split.reserveShares > 0) {
            vault.transfer(reserveRecipient, split.reserveShares);
        }
        if (split.feeShares > 0) {
            vault.transfer(feeRecipient, split.feeShares);
        }

        if (merchantShares + split.buyerYieldShares + split.reserveShares + split.feeShares != split.totalShares) {
            revert SPLIT_INVARIANT();
        }

        emit EscrowReleased(
            escrowId,
            msg.sender,
            settlementMode,
            split.totalShares,
            split.principalShares,
            split.buyerYieldShares,
            split.merchantYieldShares,
            split.reserveShares,
            split.feeShares
        );
    }

    function refund(uint256 escrowId) external nonReentrant {
        if (escrowOpsPaused) {
            revert ESCROW_OPS_PAUSED();
        }
        Escrow storage escrow = escrows[escrowId];
        if (escrow.status == EscrowStatus.NONE || escrow.sharesHeld == 0) {
            revert ESCROW_EMPTY();
        }
        if (escrow.status != EscrowStatus.FUNDED) {
            revert ESCROW_COMPLETE();
        }
        bool isArbiter = _requireSettlementAuthority(escrow);
        bool refundAuthorizedByResolution;
        if (escrow.disputed) {
            if (escrow.resolution == DisputeResolution.NONE) {
                if (!_disputeWindowExpired(escrow)) {
                    revert DISPUTE_PENDING();
                }
                if (escrow.timeoutResolution != DisputeResolution.REFUND) {
                    revert RESOLUTION_MISMATCH();
                }
            } else if (escrow.resolution != DisputeResolution.REFUND) {
                revert RESOLUTION_MISMATCH();
            }
            refundAuthorizedByResolution = true;
        }
        if (escrow.requiresFulfillment && escrow.fulfilledAt != 0 && !refundAuthorizedByResolution && !isArbiter) {
            revert FULFILLMENT_SUBMITTED();
        }

        SettlementMode settlementMode = _refundSettlementMode(escrow, isArbiter);

        uint256 sharesHeld = escrow.sharesHeld;
        uint256 committedAssets = escrow.committedAssets;
        address refundRecipient = escrow.refundRecipient;

        if (committedAssets > 0) {
            policyModule.releaseCommittedSpend(escrow.buyer, committedAssets);
        }
        escrow.sharesHeld = 0;
        escrow.committedAssets = 0;
        escrow.status = EscrowStatus.REFUNDED;
        escrow.settlementMode = settlementMode;
        escrow.settledAt = uint40(block.timestamp);

        vault.transfer(refundRecipient, sharesHeld);

        emit EscrowRefunded(escrowId, msg.sender, refundRecipient, settlementMode, sharesHeld);
    }

    function submitFulfillment(uint256 escrowId, FulfillmentType fulfillmentType, bytes32 evidenceHash) external {
        if (escrowOpsPaused) {
            revert ESCROW_OPS_PAUSED();
        }
        Escrow storage escrow = escrows[escrowId];
        uint8 requiredMilestones = escrowRequiredMilestones[escrowId];
        uint8 completedMilestones = escrowCompletedMilestones[escrowId];
        if (escrow.status == EscrowStatus.NONE || escrow.sharesHeld == 0) {
            revert ESCROW_EMPTY();
        }
        if (escrow.status != EscrowStatus.FUNDED) {
            revert ESCROW_COMPLETE();
        }
        if (!escrow.requiresFulfillment) {
            revert FULFILLMENT_NOT_REQUIRED();
        }
        if (msg.sender != escrow.merchant && !hasRole(ARBITER_ROLE, msg.sender)) {
            revert FULFILLMENT_AUTH();
        }
        if (fulfillmentType == FulfillmentType.NONE || fulfillmentType != escrow.fulfillmentType) {
            revert INVALID_FULFILLMENT_TYPE();
        }
        if (evidenceHash == bytes32(0)) {
            revert INVALID_EVIDENCE();
        }
        if (completedMilestones >= requiredMilestones) {
            revert FULFILLMENT_ALREADY_SUBMITTED();
        }

        completedMilestones += 1;
        escrowCompletedMilestones[escrowId] = completedMilestones;

        bool fulfillmentComplete = completedMilestones == requiredMilestones;
        uint40 fulfilledAt;
        if (fulfillmentComplete) {
            fulfilledAt = uint40(block.timestamp);
            escrow.fulfilledAt = fulfilledAt;
        }
        escrow.fulfillmentEvidence = evidenceHash;

        emit EscrowFulfillmentSubmitted(
            escrowId,
            msg.sender,
            fulfillmentType,
            completedMilestones,
            requiredMilestones,
            evidenceHash,
            fulfillmentComplete,
            fulfilledAt
        );
    }

    function dispute(uint256 escrowId, DisputeReason disputeReason, bytes32 reasonHash) external {
        _dispute(escrowId, disputeReason, _defaultDisputeMilestone(escrowId), reasonHash);
    }

    function disputeMilestone(uint256 escrowId, DisputeReason disputeReason, uint8 milestoneNumber, bytes32 reasonHash)
        external
    {
        _dispute(escrowId, disputeReason, milestoneNumber, reasonHash);
    }

    function _dispute(uint256 escrowId, DisputeReason disputeReason, uint8 milestoneNumber, bytes32 reasonHash)
        internal
    {
        if (escrowOpsPaused) {
            revert ESCROW_OPS_PAUSED();
        }
        Escrow storage escrow = escrows[escrowId];
        if (escrow.status == EscrowStatus.NONE || escrow.sharesHeld == 0) {
            revert ESCROW_EMPTY();
        }
        if (escrow.status != EscrowStatus.FUNDED) {
            revert ESCROW_COMPLETE();
        }
        if (msg.sender != escrow.buyer && msg.sender != escrow.merchant && !hasRole(ARBITER_ROLE, msg.sender)) {
            revert DISPUTE_AUTH();
        }
        if (disputeReason == DisputeReason.NONE) {
            revert INVALID_DISPUTE_REASON();
        }
        if (reasonHash == bytes32(0)) {
            revert INVALID_EVIDENCE();
        }
        if (escrow.disputed) {
            revert DISPUTED();
        }
        _validateDisputeMilestone(escrow, escrowId, milestoneNumber);

        escrow.disputed = true;
        escrow.disputeReason = disputeReason;
        escrow.disputedAt = uint40(block.timestamp);
        escrowDisputedMilestones[escrowId] = milestoneNumber;

        emit EscrowDisputed(escrowId, msg.sender, disputeReason, milestoneNumber, reasonHash);
    }

    function resolveDispute(uint256 escrowId, DisputeResolution resolution, bytes32 evidenceHash)
        external
        onlyRole(ARBITER_ROLE)
    {
        if (escrowOpsPaused) {
            revert ESCROW_OPS_PAUSED();
        }
        Escrow storage escrow = escrows[escrowId];
        if (escrow.status == EscrowStatus.NONE || escrow.sharesHeld == 0) {
            revert ESCROW_EMPTY();
        }
        if (escrow.status != EscrowStatus.FUNDED) {
            revert ESCROW_COMPLETE();
        }
        if (!escrow.disputed) {
            revert DISPUTE_REQUIRED();
        }
        if (resolution == DisputeResolution.NONE) {
            revert INVALID_RESOLUTION();
        }
        if (evidenceHash == bytes32(0)) {
            revert INVALID_EVIDENCE();
        }
        if (escrow.resolution != DisputeResolution.NONE) {
            revert RESOLUTION_ALREADY_SET();
        }
        if (_arbiterDeadlineExpired(escrow)) {
            revert ARBITER_DEADLINE_EXPIRED();
        }

        escrow.resolution = resolution;
        escrow.resolvedAt = uint40(block.timestamp);
        escrow.resolutionEvidence = evidenceHash;

        emit EscrowResolved(escrowId, msg.sender, evidenceHash, resolution, escrow.resolvedAt);
    }

    /// @notice Execute a timed-out dispute when the arbiter failed to act within the arbiterDeadline.
    ///         Applies the pre-configured disputeTimeoutResolution (RELEASE or REFUND).
    ///         Callable by anyone once the arbiter deadline has expired.
    function executeTimeout(uint256 escrowId) external nonReentrant {
        if (escrowOpsPaused) {
            revert ESCROW_OPS_PAUSED();
        }
        Escrow storage escrow = escrows[escrowId];
        if (escrow.status == EscrowStatus.NONE || escrow.sharesHeld == 0) {
            revert ESCROW_EMPTY();
        }
        if (escrow.status != EscrowStatus.FUNDED) {
            revert ESCROW_COMPLETE();
        }
        if (!escrow.disputed) {
            revert DISPUTE_REQUIRED();
        }
        if (escrow.resolution != DisputeResolution.NONE) {
            revert RESOLUTION_ALREADY_SET();
        }
        if (!_arbiterDeadlineExpired(escrow)) {
            revert TIMEOUT_NOT_READY();
        }

        DisputeResolution timeoutRes = escrow.timeoutResolution;
        if (timeoutRes == DisputeResolution.NONE) {
            revert INVALID_TIMEOUT_RESOLUTION();
        }

        if (timeoutRes == DisputeResolution.RELEASE) {
            // Execute as release
            if (block.timestamp < escrow.releaseAfter) {
                revert RELEASE_LOCKED();
            }

            SettlementMode settlementMode = SettlementMode.DISPUTE_TIMEOUT_RELEASE;
            uint256 nav = navController.currentNAVRay();
            uint256 S = escrow.sharesHeld;
            uint256 committedAssets = escrow.committedAssets;
            ReleaseSplit memory split =
                _previewReleaseSplit(S, escrow.principalAssetsSnapshot, escrow.buyerBps, nav);
            uint256 merchantShares = split.principalShares + split.merchantYieldShares;

            if (committedAssets > 0) {
                policyModule.releaseCommittedSpend(escrow.buyer, committedAssets);
            }
            escrow.sharesHeld = 0;
            escrow.committedAssets = 0;
            escrow.status = EscrowStatus.RELEASED;
            escrow.settlementMode = settlementMode;
            escrow.settledAt = uint40(block.timestamp);

            if (merchantShares > 0) vault.transfer(escrow.merchant, merchantShares);
            if (split.buyerYieldShares > 0) vault.transfer(escrow.buyer, split.buyerYieldShares);
            if (split.reserveShares > 0) vault.transfer(reserveRecipient, split.reserveShares);
            if (split.feeShares > 0) vault.transfer(feeRecipient, split.feeShares);

            emit EscrowTimeoutExecuted(escrowId, msg.sender, settlementMode, timeoutRes);
        } else {
            // Execute as refund
            SettlementMode settlementMode = SettlementMode.DISPUTE_TIMEOUT_REFUND;
            uint256 sharesHeld = escrow.sharesHeld;
            uint256 committedAssets = escrow.committedAssets;
            address refundRecipient = escrow.refundRecipient;

            if (committedAssets > 0) {
                policyModule.releaseCommittedSpend(escrow.buyer, committedAssets);
            }
            escrow.sharesHeld = 0;
            escrow.committedAssets = 0;
            escrow.status = EscrowStatus.REFUNDED;
            escrow.settlementMode = settlementMode;
            escrow.settledAt = uint40(block.timestamp);

            vault.transfer(refundRecipient, sharesHeld);

            emit EscrowTimeoutExecuted(escrowId, msg.sender, settlementMode, timeoutRes);
        }
    }

    function _requireSettlementAuthority(Escrow storage escrow) internal view returns (bool isArbiter) {
        isArbiter = hasRole(ARBITER_ROLE, msg.sender);
        if (msg.sender != escrow.buyer && !isArbiter) {
            revert SETTLEMENT_AUTH();
        }
    }

    function _merchantMayRelease(Escrow storage escrow) internal view returns (bool) {
        if (msg.sender != escrow.merchant) {
            return false;
        }
        if (escrow.disputed) {
            if (escrow.resolution == DisputeResolution.RELEASE) {
                return true;
            }
            if (escrow.resolution == DisputeResolution.NONE) {
                return escrow.timeoutResolution == DisputeResolution.RELEASE && _disputeWindowExpired(escrow);
            }

            return false;
        }
        if (!escrow.requiresFulfillment || escrow.fulfilledAt == 0) {
            return false;
        }

        return _challengeWindowExpired(escrow);
    }

    function _isFunded(Escrow storage escrow) internal view returns (bool) {
        return escrow.status == EscrowStatus.FUNDED && escrow.sharesHeld != 0;
    }

    function _defaultDisputeMilestone(uint256 escrowId) internal view returns (uint8) {
        return escrowCompletedMilestones[escrowId];
    }

    function _validateDisputeMilestone(Escrow storage escrow, uint256 escrowId, uint8 milestoneNumber) internal view {
        if (!escrow.requiresFulfillment) {
            if (milestoneNumber != 0) {
                revert INVALID_MILESTONE_TARGET();
            }
            return;
        }

        if (milestoneNumber > escrowCompletedMilestones[escrowId]) {
            revert INVALID_MILESTONE_TARGET();
        }
    }

    function _requiresArbiterResolution(Escrow storage escrow) internal view returns (bool) {
        if (!_isFunded(escrow) || !escrow.disputed || escrow.resolution != DisputeResolution.NONE) {
            return false;
        }
        if (escrow.arbiterDeadline == 0) {
            return true;
        }

        return !_arbiterDeadlineExpired(escrow);
    }

    function _canBuyerReleasePreview(Escrow storage escrow) internal view returns (bool) {
        if (!_isFunded(escrow) || block.timestamp < escrow.releaseAfter) {
            return false;
        }

        bool releaseAuthorizedByResolution;
        if (escrow.disputed) {
            if (escrow.resolution == DisputeResolution.NONE) {
                if (!_disputeWindowExpired(escrow) || escrow.timeoutResolution != DisputeResolution.RELEASE) {
                    return false;
                }
            } else if (escrow.resolution != DisputeResolution.RELEASE) {
                return false;
            } else {
                releaseAuthorizedByResolution = true;
            }
        }

        return !escrow.requiresFulfillment || escrow.fulfilledAt != 0 || releaseAuthorizedByResolution;
    }

    function _canMerchantReleasePreview(Escrow storage escrow) internal view returns (bool) {
        if (!_isFunded(escrow) || block.timestamp < escrow.releaseAfter) {
            return false;
        }
        if (escrow.disputed) {
            if (escrow.resolution == DisputeResolution.NONE) {
                if (!_disputeWindowExpired(escrow) || escrow.timeoutResolution != DisputeResolution.RELEASE) {
                    return false;
                }

                return !escrow.requiresFulfillment || escrow.fulfilledAt != 0;
            }

            return escrow.resolution == DisputeResolution.RELEASE;
        }
        if (!escrow.requiresFulfillment || escrow.fulfilledAt == 0) {
            return false;
        }

        return _challengeWindowExpired(escrow);
    }

    function _canArbiterReleasePreview(Escrow storage escrow) internal view returns (bool) {
        if (!_isFunded(escrow) || block.timestamp < escrow.releaseAfter) {
            return false;
        }
        if (!escrow.disputed) {
            return true;
        }
        if (escrow.resolution == DisputeResolution.NONE) {
            return _disputeWindowExpired(escrow) && escrow.timeoutResolution == DisputeResolution.RELEASE;
        }

        return escrow.resolution == DisputeResolution.RELEASE;
    }

    function _canBuyerRefundPreview(Escrow storage escrow) internal view returns (bool) {
        if (!_isFunded(escrow)) {
            return false;
        }

        bool refundAuthorizedByResolution;
        if (escrow.disputed) {
            if (escrow.resolution == DisputeResolution.NONE) {
                if (!_disputeWindowExpired(escrow) || escrow.timeoutResolution != DisputeResolution.REFUND) {
                    return false;
                }
            } else if (escrow.resolution != DisputeResolution.REFUND) {
                return false;
            }
            refundAuthorizedByResolution = true;
        }

        return !escrow.requiresFulfillment || escrow.fulfilledAt == 0 || refundAuthorizedByResolution;
    }

    function _canArbiterRefundPreview(Escrow storage escrow) internal view returns (bool) {
        if (!_isFunded(escrow)) {
            return false;
        }
        if (!escrow.disputed) {
            return true;
        }
        if (escrow.resolution == DisputeResolution.NONE) {
            return _disputeWindowExpired(escrow) && escrow.timeoutResolution == DisputeResolution.REFUND;
        }

        return escrow.resolution == DisputeResolution.REFUND;
    }

    function _canArbiterResolvePreview(Escrow storage escrow) internal view returns (bool) {
        return _isFunded(escrow) && escrow.disputed && escrow.resolution == DisputeResolution.NONE
            && !_arbiterDeadlineExpired(escrow);
    }

    function _challengeWindowExpired(Escrow storage escrow) internal view returns (bool) {
        if (!escrow.requiresFulfillment || escrow.fulfilledAt == 0) {
            return false;
        }
        if (escrow.challengeWindow == 0) {
            return true;
        }

        return block.timestamp >= uint256(escrow.fulfilledAt) + uint256(escrow.challengeWindow);
    }

    /// @dev Returns true when the arbiter's deadline to resolve a dispute has expired.
    function _arbiterDeadlineExpired(Escrow storage escrow) internal view returns (bool) {
        if (escrow.disputedAt == 0 || escrow.arbiterDeadline == 0) {
            return false;
        }

        return block.timestamp >= uint256(escrow.disputedAt) + uint256(escrow.arbiterDeadline);
    }

    /// @dev Kept for backwards compatibility in release/refund timeout paths.
    function _disputeWindowExpired(Escrow storage escrow) internal view returns (bool) {
        return _arbiterDeadlineExpired(escrow);
    }

    function _challengeWindowEndsAt(Escrow storage escrow) internal view returns (uint40) {
        if (!escrow.requiresFulfillment) {
            return 0;
        }

        return _windowEndsAt(escrow.fulfilledAt, escrow.challengeWindow);
    }

    function _disputeWindowEndsAt(Escrow storage escrow) internal view returns (uint40) {
        return _windowEndsAt(escrow.disputedAt, escrow.arbiterDeadline);
    }

    function _windowEndsAt(uint40 startedAt, uint40 window) internal pure returns (uint40) {
        if (startedAt == 0 || window == 0) {
            return 0;
        }

        uint256 endsAt = uint256(startedAt) + uint256(window);
        if (endsAt > type(uint40).max) {
            return type(uint40).max;
        }

        // forge-lint: disable-next-line(unsafe-typecast)
        return uint40(endsAt);
    }

    function _nextMilestoneNumber(uint8 completedMilestones, uint8 requiredMilestones) internal pure returns (uint8) {
        if (requiredMilestones == 0 || completedMilestones >= requiredMilestones) {
            return 0;
        }

        unchecked {
            return completedMilestones + 1;
        }
    }

    function _releaseSettlementMode(Escrow storage escrow, bool isArbiter, bool isMerchant)
        internal
        view
        returns (SettlementMode)
    {
        if (escrow.disputed) {
            if (escrow.resolution == DisputeResolution.NONE) {
                return SettlementMode.DISPUTE_TIMEOUT_RELEASE;
            }
            return SettlementMode.ARBITER_RELEASE;
        }
        if (isArbiter) {
            return SettlementMode.ARBITER_RELEASE;
        }
        if (isMerchant) {
            return SettlementMode.MERCHANT_TIMEOUT_RELEASE;
        }

        return SettlementMode.BUYER_RELEASE;
    }

    function _refundSettlementMode(Escrow storage escrow, bool isArbiter) internal view returns (SettlementMode) {
        if (escrow.disputed) {
            if (escrow.resolution == DisputeResolution.NONE) {
                return SettlementMode.DISPUTE_TIMEOUT_REFUND;
            }

            return SettlementMode.ARBITER_REFUND;
        }
        if (isArbiter) {
            return SettlementMode.ARBITER_REFUND;
        }

        return SettlementMode.BUYER_REFUND;
    }

    function _previewReleaseSplit(
        uint256 totalShares,
        uint256 principalAssetsSnapshot,
        uint16 buyerBps,
        uint256 nav
    ) internal view returns (ReleaseSplit memory split) {
        split.totalShares = totalShares;
        split.principalShares = RayMath.convertToSharesUp(principalAssetsSnapshot, nav);
        if (split.principalShares > totalShares) {
            split.principalShares = totalShares;
        }

        split.grossYieldShares = totalShares - split.principalShares;
        split.reserveShares = (split.grossYieldShares * reserveBps) / 10_000;

        uint256 yieldAfterReserve = split.grossYieldShares - split.reserveShares;
        split.feeShares = (yieldAfterReserve * protocolFeeBps) / 10_000;

        uint256 netYieldShares = yieldAfterReserve - split.feeShares;
        split.buyerYieldShares = (netYieldShares * buyerBps) / 10_000;
        split.merchantYieldShares = netYieldShares - split.buyerYieldShares;
    }
}
