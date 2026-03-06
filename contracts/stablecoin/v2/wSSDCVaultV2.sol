// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {NAVControllerV2} from "./NAVControllerV2.sol";
import {RayMath} from "./RayMath.sol";

contract wSSDCVaultV2 is ERC20, ERC4626, AccessControl {
    bytes32 public constant GATEWAY_ROLE = keccak256("GATEWAY_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");
    bytes32 public constant QUEUE_ROLE = keccak256("QUEUE_ROLE");

    NAVControllerV2 public immutable navController;

    bool public mintRedeemPaused;
    bool public gatewayRequired;

    error MINT_REDEEM_PAUSED();
    error GATEWAY_ONLY();

    event MintRedeemPauseSet(bool paused);
    event GatewayRequirementSet(bool required);

    constructor(
        ERC20 settlementAsset,
        NAVControllerV2 navController_,
        address admin
    ) ERC20("Wrapped SSDC", "wSSDC") ERC4626(settlementAsset) {
        require(admin != address(0), "admin=0");

        navController = navController_;
        gatewayRequired = false;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(BRIDGE_ROLE, admin);
        _grantRole(GATEWAY_ROLE, admin);
        _grantRole(QUEUE_ROLE, admin);
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

    function mintBridgeShares(address to, uint256 shares) external onlyRole(BRIDGE_ROLE) {
        _mint(to, shares);
    }

    function burnBridgeShares(address from, uint256 shares) external onlyRole(BRIDGE_ROLE) {
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
        if (mintRedeemPaused) {
            return 0;
        }
        return super.maxDeposit(receiver);
    }

    function maxMint(address receiver) public view override returns (uint256) {
        if (mintRedeemPaused) {
            return 0;
        }
        return super.maxMint(receiver);
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        if (mintRedeemPaused) {
            return 0;
        }
        return super.maxWithdraw(owner);
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        if (mintRedeemPaused) {
            return 0;
        }
        return super.maxRedeem(owner);
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

}
