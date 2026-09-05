// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {wSSDCVaultV2} from "./wSSDCVaultV2.sol";
import {SSDCPolicyModuleV2} from "./SSDCPolicyModuleV2.sol";

/// @notice Opt-in custody boundary for direct wSSDC merchant payments.
/// @dev The owner is trusted; session keys have no generic execute/approve path.
///      Configure policy for THIS account and grant it POLICY_CONSUMER_ROLE.
///      This is not an ERC-4337 account or an escrow/bridge/gas integration.
contract AgentPaymentAccountV2 is Ownable2Step, ReentrancyGuard, EIP712 {
    using SafeERC20 for IERC20;

    bytes32 public constant INVOICE_TYPEHASH = keccak256(
        "Invoice(bytes32 orderId,address merchant,address vault,uint256 assets,uint40 deadline)"
    );

    struct Session {
        address merchant;
        uint40 expiresAt;
        uint256 remainingAssets;
        uint256 epoch;
    }

    wSSDCVaultV2 public immutable vault;
    SSDCPolicyModuleV2 public immutable policy;
    mapping(address => Session) public sessions;
    mapping(bytes32 => bool) public paidOrders;
    uint256 public nextNonce;

    error InvalidConfiguration();
    error InvalidSession();
    error InvalidPayment();
    error AlreadyPaid();
    error BudgetExceeded();
    error CollateralFloor();
    error InvalidInvoiceSignature();

    event SessionUpdated(address indexed key, address indexed merchant, uint256 epoch, uint40 expiresAt, uint256 budgetAssets);
    event PaymentExecuted(bytes32 indexed orderId, address indexed key, address indexed merchant, uint256 nonce, uint256 assetsCharged, uint256 shares);
    event OwnerWithdrawal(address indexed recipient, uint256 shares);

    constructor(wSSDCVaultV2 vault_, SSDCPolicyModuleV2 policy_, address owner_)
        Ownable(owner_) EIP712("AgentPaymentAccountV2", "1")
    {
        if (address(vault_).code.length == 0 || address(policy_).code.length == 0) revert InvalidConfiguration();
        vault = vault_;
        policy = policy_;
    }

    /// @notice Replacing a session invalidates all transactions bearing its old epoch.
    function setSession(address key, address merchant, uint40 expiresAt, uint256 budgetAssets) external onlyOwner {
        if (key == address(0) || merchant == address(0) || merchant == address(this) ||
            expiresAt <= block.timestamp || budgetAssets == 0) revert InvalidConfiguration();
        uint256 epoch = sessions[key].epoch + 1;
        sessions[key] = Session(merchant, expiresAt, budgetAssets, epoch);
        emit SessionUpdated(key, merchant, epoch, expiresAt, budgetAssets);
    }

    function revokeSession(address key) external onlyOwner {
        uint256 epoch = sessions[key].epoch + 1;
        sessions[key] = Session(address(0), 0, 0, epoch);
        emit SessionUpdated(key, address(0), epoch, 0, 0);
    }

    /// @notice Merchant-signed invoice bound to this account, chain and vault.
    /// @dev Session authorization is separate; this is not a user-signed purchase mandate.
    function invoiceDigest(bytes32 orderId, address merchant, uint256 assets, uint40 deadline)
        public view returns (bytes32)
    {
        return _hashTypedDataV4(keccak256(abi.encode(INVOICE_TYPEHASH, orderId, merchant, address(vault), assets, deadline)));
    }

    /// @notice Merchant authenticates order/amount/deadline. The session transaction
    ///         additionally binds epoch, nonce and share slippage. No unsigned fallback.
    function pay(bytes32 orderId, uint256 epoch, uint256 nonce, uint256 assets, uint256 maxShares, uint40 deadline, bytes calldata merchantSignature)
        external nonReentrant returns (uint256 shares)
    {
        Session storage session = sessions[msg.sender];
        if (session.merchant == address(0) || epoch != session.epoch || block.timestamp >= session.expiresAt)
            revert InvalidSession();
        if (orderId == bytes32(0) || assets == 0 || nonce != nextNonce || block.timestamp >= deadline)
            revert InvalidPayment();
        if (paidOrders[orderId]) revert AlreadyPaid();
        if (!SignatureChecker.isValidSignatureNow(
            session.merchant, invoiceDigest(orderId, session.merchant, assets, deadline), merchantSignature
        )) revert InvalidInvoiceSignature();

        // Fresh NAV is mandatory. Charge rounded-up share value, not merely the
        // requested amount, so repeated tiny transfers cannot evade asset budgets.
        uint256 navRay = vault.currentNAVRay();
        shares = Math.mulDiv(assets, 1e27, navRay, Math.Rounding.Ceil);
        if (shares > maxShares) revert InvalidPayment();
        uint256 charged = Math.mulDiv(shares, navRay, 1e27, Math.Rounding.Ceil);
        if (charged > session.remainingAssets) revert BudgetExceeded();
        _requireFloorAfter(shares, navRay);

        session.remainingAssets -= charged;
        paidOrders[orderId] = true;
        nextNonce = nonce + 1;
        policy.consumeSpend(address(this), session.merchant, charged);
        IERC20(address(vault)).safeTransfer(session.merchant, shares);
        emit PaymentExecuted(orderId, msg.sender, session.merchant, nonce, charged, shares);
    }

    /// @notice Trusted-owner recovery, never callable by a session key. It does
    ///         not consume purchase budget, but preserves outstanding collateral.
    function withdrawShares(address recipient, uint256 shares) external onlyOwner nonReentrant {
        if (recipient == address(0) || recipient == address(this) || shares == 0) revert InvalidPayment();
        _requireFloorAfter(shares, vault.currentNAVRay());
        IERC20(address(vault)).safeTransfer(recipient, shares);
        emit OwnerWithdrawal(recipient, shares);
    }

    function _requireFloorAfter(uint256 shares, uint256 navRay) internal view {
        uint256 balance = vault.balanceOf(address(this));
        if (shares > balance || Math.mulDiv(balance - shares, navRay, 1e27) < policy.getMinAssetsFloor(address(this)))
            revert CollateralFloor();
    }
}
