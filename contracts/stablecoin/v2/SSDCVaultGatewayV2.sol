// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {YieldEscrowV2} from "./YieldEscrowV2.sol";
import {YieldPaymasterV2} from "./YieldPaymasterV2.sol";
import {wSSDCVaultV2} from "./wSSDCVaultV2.sol";

contract SSDCVaultGatewayV2 is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    wSSDCVaultV2 public immutable vault;
    IERC20 public immutable settlementAsset;

    error MIN_SHARES_OUT();
    error MAX_ASSETS_IN();
    error MAX_SHARES_BURNED();
    error MIN_ASSETS_OUT();

    event GatewayDeposit(address indexed caller, address indexed receiver, uint256 assetsIn, uint256 sharesOut);
    event GatewayMint(address indexed caller, address indexed receiver, uint256 assetsIn, uint256 sharesOut);
    event GatewayWithdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assetsOut,
        uint256 sharesBurned
    );
    event GatewayRedeem(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assetsOut,
        uint256 sharesBurned
    );
    event GatewayGasTankTopUp(
        address indexed caller,
        address indexed paymaster,
        address indexed agent,
        uint256 assetsIn,
        uint256 sharesOut
    );
    event GatewayEscrowFunded(
        address indexed caller,
        address indexed escrow,
        uint256 indexed escrowId,
        address merchant,
        uint256 assetsIn,
        uint256 sharesOut
    );
    event Swept(address indexed token, address indexed to, uint256 amount);

    constructor(wSSDCVaultV2 vault_, address admin) {
        require(address(vault_) != address(0), "vault=0");
        require(admin != address(0), "admin=0");

        vault = vault_;
        settlementAsset = IERC20(vault_.asset());

        settlementAsset.forceApprove(address(vault_), type(uint256).max);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function deposit(uint256 assets, address receiver, uint256 minSharesOut)
        external
        nonReentrant
        returns (uint256 sharesOut)
    {
        sharesOut = vault.previewDeposit(assets);
        if (sharesOut < minSharesOut) {
            revert MIN_SHARES_OUT();
        }

        settlementAsset.safeTransferFrom(msg.sender, address(this), assets);
        sharesOut = vault.deposit(assets, receiver);

        emit GatewayDeposit(msg.sender, receiver, assets, sharesOut);
    }

    function mint(uint256 shares, address receiver, uint256 maxAssetsIn)
        external
        nonReentrant
        returns (uint256 assetsIn)
    {
        assetsIn = vault.previewMint(shares);
        if (assetsIn > maxAssetsIn) {
            revert MAX_ASSETS_IN();
        }

        settlementAsset.safeTransferFrom(msg.sender, address(this), assetsIn);
        assetsIn = vault.mint(shares, receiver);

        emit GatewayMint(msg.sender, receiver, assetsIn, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner, uint256 maxSharesBurned)
        external
        nonReentrant
        returns (uint256 sharesBurned)
    {
        sharesBurned = vault.previewWithdraw(assets);
        if (sharesBurned > maxSharesBurned) {
            revert MAX_SHARES_BURNED();
        }

        sharesBurned = vault.withdraw(assets, receiver, owner);

        emit GatewayWithdraw(msg.sender, receiver, owner, assets, sharesBurned);
    }

    function depositToGasTank(YieldPaymasterV2 paymaster, uint256 assets, address agent, uint256 minSharesOut)
        external
        nonReentrant
        returns (uint256 sharesOut)
    {
        sharesOut = vault.previewDeposit(assets);
        if (sharesOut < minSharesOut) {
            revert MIN_SHARES_OUT();
        }

        settlementAsset.safeTransferFrom(msg.sender, address(this), assets);
        sharesOut = vault.deposit(assets, address(this));

        IERC20(address(vault)).forceApprove(address(paymaster), sharesOut);
        paymaster.topUpGasTankFor(agent, sharesOut);

        emit GatewayGasTankTopUp(msg.sender, address(paymaster), agent, assets, sharesOut);
    }

    function depositToEscrow(
        YieldEscrowV2 escrow,
        address merchant,
        YieldEscrowV2.InvoiceTerms calldata terms,
        uint16 buyerBps,
        uint256 maxAssetsIn
    ) external nonReentrant returns (uint256 escrowId, uint256 assetsIn, uint256 sharesOut) {
        sharesOut = vault.convertToSharesInvoiceOrWithdraw(terms.assetsDue);
        assetsIn = vault.previewMint(sharesOut);
        if (assetsIn > maxAssetsIn) {
            revert MAX_ASSETS_IN();
        }

        settlementAsset.safeTransferFrom(msg.sender, address(this), assetsIn);
        assetsIn = vault.mint(sharesOut, address(this));

        IERC20(address(vault)).forceApprove(address(escrow), sharesOut);
        escrowId = escrow.fundEscrowFor(msg.sender, msg.sender, merchant, terms, buyerBps);

        emit GatewayEscrowFunded(msg.sender, address(escrow), escrowId, merchant, assetsIn, sharesOut);
    }

    function redeem(uint256 shares, address receiver, address owner, uint256 minAssetsOut)
        external
        nonReentrant
        returns (uint256 assetsOut)
    {
        assetsOut = vault.previewRedeem(shares);
        if (assetsOut < minAssetsOut) {
            revert MIN_ASSETS_OUT();
        }

        assetsOut = vault.redeem(shares, receiver, owner);

        emit GatewayRedeem(msg.sender, receiver, owner, assetsOut, shares);
    }

    function sweep(IERC20 token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "to=0");
        token.safeTransfer(to, amount);
        emit Swept(address(token), to, amount);
    }
}
