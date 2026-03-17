// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {NAVControllerV2} from "./NAVControllerV2.sol";
import {RayMath} from "./RayMath.sol";

contract wSSDCVaultV2 is ERC20, ERC4626, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant GATEWAY_ROLE = keccak256("GATEWAY_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");
    bytes32 public constant QUEUE_ROLE = keccak256("QUEUE_ROLE");
    bytes32 public constant RESERVE_ROLE = keccak256("RESERVE_ROLE");

    NAVControllerV2 public immutable navController;

    bool public mintRedeemPaused;
    bool public gatewayRequired;
    uint256 public minBridgeLiquidityCoverageBps;
    mapping(address => uint256) public bridgedSharesBalance;
    uint256 public bridgedSharesSupply;

    // Reserve management
    address public reserveManager; // address that receives deployed assets
    uint256 public reserveFloor; // minimum settlement assets that must remain in vault
    uint256 public maxDeployBps; // max percentage of total assets deployable per call (basis points)
    uint256 public deployedReserveAssets; // total assets currently deployed to reserve manager

    error ZeroAddress();
    error InvalidBps();
    error MINT_REDEEM_PAUSED();
    error GATEWAY_ONLY();
    error LIQUIDITY_COVERAGE();
    error RESERVE_FLOOR();
    error RESERVE_DEPLOY_LIMIT();
    error RESERVE_RECALL_EXCEEDS_DEPLOYED();
    error RESERVE_MANAGER_NOT_SET();
    error INVALID_SETTLEMENT_ASSET_DECIMALS();

    event MintRedeemPauseSet(bool paused);
    event GatewayRequirementSet(bool required);
    event MinBridgeLiquidityCoverageSet(uint256 minCoverageBps);
    event ReserveDeployed(address indexed manager, uint256 amount, uint256 totalDeployed);
    event ReserveRecalled(address indexed manager, uint256 amount, uint256 totalDeployed);
    event ReserveConfigUpdated(address reserveManager, uint256 reserveFloor, uint256 maxDeployBps);

    function availableSettlementAssets() public view returns (uint256) {
        return ERC20(asset()).balanceOf(address(this));
    }

    function totalLiabilityAssets() public view returns (uint256) {
        return RayMath.convertToAssetsDown(totalSupply(), _accountingNAVRay());
    }

    function totalAssets() public view override returns (uint256) {
        return totalLiabilityAssets();
    }

    function liquidityCoverageBps() public view returns (uint256) {
        uint256 liabilityAssets = totalLiabilityAssets();
        if (liabilityAssets == 0) {
            return 10_000;
        }

        uint256 liquidAssets = availableSettlementAssets();
        if (liquidAssets >= liabilityAssets) {
            return 10_000;
        }

        return (liquidAssets * 10_000) / liabilityAssets;
    }

    function previewLiquidityCoverageBpsAfterMint(uint256 additionalShares) public view returns (uint256) {
        uint256 navRay = _riskCheckNAVRay();
        uint256 postLiabilityAssets = RayMath.convertToAssetsDown(totalSupply() + additionalShares, navRay);
        if (postLiabilityAssets == 0) {
            return 10_000;
        }

        uint256 liquidAssets = availableSettlementAssets();
        if (liquidAssets >= postLiabilityAssets) {
            return 10_000;
        }

        return (liquidAssets * 10_000) / postLiabilityAssets;
    }

    constructor(
        ERC20 settlementAsset,
        NAVControllerV2 navController_,
        address admin
    ) ERC20("Wrapped SSDC", "wSSDC") ERC4626(settlementAsset) {
        if (admin == address(0)) revert ZeroAddress();
        if (address(navController_) == address(0)) revert ZeroAddress();
        if (settlementAsset.decimals() != 6) {
            revert INVALID_SETTLEMENT_ASSET_DECIMALS();
        }

        navController = navController_;
        gatewayRequired = false;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(BRIDGE_ROLE, admin);
        _grantRole(GATEWAY_ROLE, admin);
        _grantRole(QUEUE_ROLE, admin);
        _grantRole(RESERVE_ROLE, admin);
    }

    function currentNAVRay() external view returns (uint256) {
        return navController.currentNAVRay();
    }

    function tryCurrentNAVRay() external view returns (uint256 navRay, bool stale) {
        return navController.tryCurrentNAVRay();
    }

    function convertToSharesDeposit(uint256 assets) external view returns (uint256) {
        return RayMath.convertToSharesDown(assets, navController.currentNAVRay());
    }

    function convertToSharesInvoiceOrWithdraw(uint256 assets) external view returns (uint256) {
        return RayMath.convertToSharesUp(assets, navController.currentNAVRay());
    }

    function setMintRedeemPaused(bool paused) external onlyRole(PAUSER_ROLE) {
        mintRedeemPaused = paused;
        emit MintRedeemPauseSet(paused);
    }

    function setGatewayRequired(bool required_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        gatewayRequired = required_;
        emit GatewayRequirementSet(required_);
    }

    function setMinBridgeLiquidityCoverageBps(uint256 minCoverageBps_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (minCoverageBps_ > 10_000) revert InvalidBps();
        minBridgeLiquidityCoverageBps = minCoverageBps_;
        emit MinBridgeLiquidityCoverageSet(minCoverageBps_);
    }

    // -------------------------------------------------------------------------
    // Reserve Management
    // -------------------------------------------------------------------------

    function setReserveConfig(address reserveManager_, uint256 reserveFloor_, uint256 maxDeployBps_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (maxDeployBps_ > 10_000) revert InvalidBps();
        reserveManager = reserveManager_;
        reserveFloor = reserveFloor_;
        maxDeployBps = maxDeployBps_;
        emit ReserveConfigUpdated(reserveManager_, reserveFloor_, maxDeployBps_);
    }

    /// @notice Deploy settlement assets to the reserve manager for off-chain yield strategies.
    ///         Must respect reserveFloor and maxDeployBps constraints.
    function deployReserve(uint256 amount) external onlyRole(RESERVE_ROLE) {
        _requireMintRedeemActive();
        if (reserveManager == address(0)) {
            revert RESERVE_MANAGER_NOT_SET();
        }

        uint256 available = availableSettlementAssets();
        // After deployment, vault must retain at least reserveFloor
        if (amount > available || available - amount < reserveFloor) {
            revert RESERVE_FLOOR();
        }

        // A single deployment call cannot exceed maxDeployBps of total liability
        uint256 totalLiability = RayMath.convertToAssetsDown(totalSupply(), _riskCheckNAVRay());
        uint256 maxDeployable = (totalLiability * maxDeployBps) / 10_000;
        if (amount > maxDeployable) {
            revert RESERVE_DEPLOY_LIMIT();
        }

        deployedReserveAssets += amount;
        IERC20(asset()).safeTransfer(reserveManager, amount);

        emit ReserveDeployed(reserveManager, amount, deployedReserveAssets);
    }

    /// @notice Recall deployed assets from the reserve manager back into the vault.
    ///         The reserve manager must have approved the vault to transferFrom.
    function recallReserve(uint256 amount) external onlyRole(RESERVE_ROLE) {
        if (reserveManager == address(0)) {
            revert RESERVE_MANAGER_NOT_SET();
        }
        if (amount > deployedReserveAssets) {
            revert RESERVE_RECALL_EXCEEDS_DEPLOYED();
        }

        deployedReserveAssets -= amount;
        IERC20(asset()).safeTransferFrom(reserveManager, address(this), amount);

        emit ReserveRecalled(reserveManager, amount, deployedReserveAssets);
    }

    function mintBridgeShares(address to, uint256 shares) external onlyRole(BRIDGE_ROLE) {
        uint256 minCoverageBps = minBridgeLiquidityCoverageBps;
        if (minCoverageBps > 0 && previewLiquidityCoverageBpsAfterMint(shares) < minCoverageBps) {
            revert LIQUIDITY_COVERAGE();
        }
        _mint(to, shares);
        unchecked {
            bridgedSharesBalance[to] += shares;
            bridgedSharesSupply += shares;
        }
    }

    function burnBridgeShares(address from, uint256 shares) external onlyRole(BRIDGE_ROLE) returns (uint256 bridgedSharesBurned) {
        bridgedSharesBurned = _bridgedSharesPortion(from, shares);
        _burn(from, shares);
    }

    function burnQueuedShares(uint256 shares) external onlyRole(QUEUE_ROLE) {
        _burn(msg.sender, shares);
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        _requireMintRedeemActive();
        _requireGatewayIfEnabled();
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override returns (uint256) {
        _requireMintRedeemActive();
        _requireGatewayIfEnabled();
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        _requireMintRedeemActive();
        _requireGatewayIfEnabled();
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        _requireMintRedeemActive();
        _requireGatewayIfEnabled();
        return super.redeem(shares, receiver, owner);
    }

    function maxDeposit(address receiver) public view override returns (uint256) {
        (, bool navUsable) = _usableNAV();
        if (mintRedeemPaused || !navUsable) {
            return 0;
        }
        return super.maxDeposit(receiver);
    }

    function maxMint(address receiver) public view override returns (uint256) {
        (, bool navUsable) = _usableNAV();
        if (mintRedeemPaused || !navUsable) {
            return 0;
        }
        return super.maxMint(receiver);
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        (uint256 navRay, bool navUsable) = _usableNAV();
        if (mintRedeemPaused || !navUsable) {
            return 0;
        }

        uint256 ownerAssets = RayMath.convertToAssetsDown(balanceOf(owner), navRay);
        uint256 liquidAssets = availableSettlementAssets();
        return ownerAssets < liquidAssets ? ownerAssets : liquidAssets;
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        (uint256 navRay, bool navUsable) = _usableNAV();
        if (mintRedeemPaused || !navUsable) {
            return 0;
        }

        uint256 ownerShares = balanceOf(owner);
        uint256 liquidShares = RayMath.convertToSharesDown(availableSettlementAssets(), navRay);
        return ownerShares < liquidShares ? ownerShares : liquidShares;
    }

    function decimals() public view override(ERC20, ERC4626) returns (uint8) {
        return super.decimals();
    }

    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view override returns (uint256) {
        uint256 navRay = navController.currentNAVRay();
        if (rounding == Math.Rounding.Ceil) {
            return RayMath.mulDivUp(assets, RayMath.RAY, navRay);
        }
        return RayMath.mulDivDown(assets, RayMath.RAY, navRay);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view override returns (uint256) {
        uint256 navRay = navController.currentNAVRay();
        if (rounding == Math.Rounding.Ceil) {
            return RayMath.mulDivUp(shares, navRay, RayMath.RAY);
        }
        return RayMath.mulDivDown(shares, navRay, RayMath.RAY);
    }

    function _update(address from, address to, uint256 value) internal override {
        uint256 fromBalanceBefore = from == address(0) ? 0 : balanceOf(from);
        super._update(from, to, value);

        if (value == 0 || from == address(0) || from == to) {
            return;
        }

        uint256 bridgedValue;
        if (to == address(0)) {
            bridgedValue = _bridgedSharesPortion(from, value);
        } else {
            // Bridged provenance follows transfers proportionally to the sender's pre-transfer mix.
            uint256 fromBridged = bridgedSharesBalance[from];
            if (fromBridged == 0 || fromBalanceBefore == 0) {
                return;
            }
            bridgedValue = Math.mulDiv(fromBridged, value, fromBalanceBefore);
        }
        if (bridgedValue == 0) {
            return;
        }

        unchecked {
            bridgedSharesBalance[from] -= bridgedValue;
        }

        if (to == address(0)) {
            unchecked {
                bridgedSharesSupply -= bridgedValue;
            }
            return;
        }

        unchecked {
            bridgedSharesBalance[to] += bridgedValue;
        }
    }

    function _requireMintRedeemActive() internal view {
        if (mintRedeemPaused) {
            revert MINT_REDEEM_PAUSED();
        }
    }

    function _requireGatewayIfEnabled() internal view {
        if (gatewayRequired && !hasRole(GATEWAY_ROLE, msg.sender)) {
            revert GATEWAY_ONLY();
        }
    }

    function _usableNAV() internal view returns (uint256 navRay, bool usable) {
        bool stale;
        (navRay, stale) = navController.tryCurrentNAVRay();
        usable = !stale && navRay != 0;
    }

    function _accountingNAVRay() internal view returns (uint256 navRay) {
        bool usable;
        (navRay, usable) = _usableNAV();
        if (!usable) {
            return navController.nav0Ray();
        }
    }

    function _riskCheckNAVRay() internal view returns (uint256) {
        return navController.currentNAVRay();
    }

    function _bridgedSharesPortion(address account, uint256 shares) internal view returns (uint256 bridgedShares) {
        bridgedShares = bridgedSharesBalance[account];
        if (bridgedShares > shares) {
            bridgedShares = shares;
        }
    }

}
