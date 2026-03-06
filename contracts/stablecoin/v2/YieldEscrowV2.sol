// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {NAVControllerV2} from "./NAVControllerV2.sol";
import {RayMath} from "./RayMath.sol";
import {wSSDCVaultV2} from "./wSSDCVaultV2.sol";

contract YieldEscrowV2 is AccessControl, ReentrancyGuard {
    struct InvoiceTerms {
        uint256 assetsDue;
        uint40 expiry;
        uint40 maxNavAge;
        uint256 maxSharesIn;
    }

    struct Escrow {
        address buyer;
        address merchant;
        uint256 sharesHeld;
        uint256 principalAssetsSnapshot;
        uint16 buyerBps;
        bool released;
    }

    wSSDCVaultV2 public immutable vault;
    NAVControllerV2 public immutable navController;

    uint16 public protocolFeeBps;
    address public feeRecipient;

    uint256 public nextEscrowId;
    mapping(uint256 => Escrow) public escrows;

    error INVOICE_EXPIRED();
    error NAV_TOO_STALE();
    error SHARES_SLIPPAGE();
    error INVALID_BPS();
    error ESCROW_COMPLETE();
    error ESCROW_EMPTY();

    event EscrowFunded(
        uint256 indexed escrowId,
        address indexed buyer,
        address indexed merchant,
        uint256 sharesIn,
        uint256 principalAssetsSnapshot
    );

    event EscrowReleased(
        uint256 indexed escrowId,
        uint256 totalShares,
        uint256 principalShares,
        uint256 buyerYieldShares,
        uint256 merchantYieldShares,
        uint256 feeShares
    );

    event ProtocolFeeUpdated(uint16 protocolFeeBps, address feeRecipient);

    constructor(wSSDCVaultV2 vault_, NAVControllerV2 navController_, address admin, address feeRecipient_) {
        require(admin != address(0), "admin=0");
        require(feeRecipient_ != address(0), "fee=0");

        vault = vault_;
        navController = navController_;
        feeRecipient = feeRecipient_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

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

    function fundEscrow(address merchant, InvoiceTerms calldata terms, uint16 buyerBps) external returns (uint256 escrowId) {
        if (block.timestamp > terms.expiry) {
            revert INVOICE_EXPIRED();
        }
        if (buyerBps > 10_000) {
            revert INVALID_BPS();
        }

        uint256 navAge = block.timestamp - uint256(navController.t0());
        if (navAge > terms.maxNavAge) {
            revert NAV_TOO_STALE();
        }

        uint256 sharesIn = vault.convertToSharesInvoiceOrWithdraw(terms.assetsDue);
        if (sharesIn > terms.maxSharesIn) {
            revert SHARES_SLIPPAGE();
        }

        vault.transferFrom(msg.sender, address(this), sharesIn);

        uint256 principalAssetsSnapshot = vault.convertToAssets(sharesIn);

        escrowId = nextEscrowId;
        unchecked {
            nextEscrowId = escrowId + 1;
        }

        escrows[escrowId] = Escrow({
            buyer: msg.sender,
            merchant: merchant,
            sharesHeld: sharesIn,
            principalAssetsSnapshot: principalAssetsSnapshot,
            buyerBps: buyerBps,
            released: false
        });

        emit EscrowFunded(escrowId, msg.sender, merchant, sharesIn, principalAssetsSnapshot);
    }

    function release(uint256 escrowId) external nonReentrant {
        Escrow storage escrow = escrows[escrowId];
        if (escrow.released) {
            revert ESCROW_COMPLETE();
        }
        if (escrow.sharesHeld == 0) {
            revert ESCROW_EMPTY();
        }

        uint256 nav = navController.currentNAVRay();

        uint256 S = escrow.sharesHeld;
        uint256 A_principal = escrow.principalAssetsSnapshot;

        uint256 S_principal = RayMath.convertToSharesUp(A_principal, nav);
        if (S_principal > S) {
            S_principal = S;
        }

        uint256 S_yield = S - S_principal;
        uint256 S_fee = (S_yield * protocolFeeBps) / 10_000;
        uint256 S_yieldNet = S_yield - S_fee;
        uint256 S_buyerYield = (S_yieldNet * escrow.buyerBps) / 10_000;
        uint256 S_merchantYield = S_yieldNet - S_buyerYield;

        uint256 merchantShares = S_principal + S_merchantYield;

        if (merchantShares > 0) {
            vault.transfer(escrow.merchant, merchantShares);
        }
        if (S_buyerYield > 0) {
            vault.transfer(escrow.buyer, S_buyerYield);
        }
        if (S_fee > 0) {
            vault.transfer(feeRecipient, S_fee);
        }

        escrow.sharesHeld = 0;
        escrow.released = true;

        assert(merchantShares + S_buyerYield + S_fee == S);

        emit EscrowReleased(escrowId, S, S_principal, S_buyerYield, S_merchantYield, S_fee);
    }
}
