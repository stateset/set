// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SSDCPolicyModuleV2} from "./SSDCPolicyModuleV2.sol";
import {NAVControllerV2} from "./NAVControllerV2.sol";
import {RayMath} from "./RayMath.sol";
import {wSSDCVaultV2} from "./wSSDCVaultV2.sol";
import {ICollateralProviderV2} from "./interfaces/ICollateralProviderV2.sol";

contract GroundingRegistryV2 is AccessControl {
    uint256 public constant MAX_PROVIDERS = 16;

    SSDCPolicyModuleV2 public immutable policyModule;
    NAVControllerV2 public immutable navController;
    wSSDCVaultV2 public immutable vault;

    mapping(address => bool) public isGrounded;
    mapping(address => uint256) private collateralProviderIndexPlusOne;
    address[] public collateralProviders;

    error ZeroAddress();
    error MaxProvidersReached();

    event AgentGrounded(
        address indexed agent,
        uint256 assetsNow,
        uint256 minAssetsFloor,
        uint256 currentNAVRay
    );

    event AgentUngrounded(
        address indexed agent,
        uint256 assetsNow,
        uint256 minAssetsFloor,
        uint256 currentNAVRay
    );

    event CollateralProviderSet(address indexed provider, bool enabled);

    constructor(
        SSDCPolicyModuleV2 policyModule_,
        NAVControllerV2 navController_,
        wSSDCVaultV2 vault_,
        address admin
    ) {
        if (address(policyModule_) == address(0)) revert ZeroAddress();
        if (address(navController_) == address(0)) revert ZeroAddress();
        if (address(vault_) == address(0)) revert ZeroAddress();
        if (admin == address(0)) revert ZeroAddress();

        policyModule = policyModule_;
        navController = navController_;
        vault = vault_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function setCollateralProvider(address provider, bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (provider == address(0)) revert ZeroAddress();

        uint256 indexPlusOne = collateralProviderIndexPlusOne[provider];
        if (enabled) {
            if (indexPlusOne == 0) {
                if (collateralProviders.length >= MAX_PROVIDERS) revert MaxProvidersReached();
                collateralProviders.push(provider);
                collateralProviderIndexPlusOne[provider] = collateralProviders.length;
            }
        } else if (indexPlusOne != 0) {
            uint256 index = indexPlusOne - 1;
            uint256 lastIndex = collateralProviders.length - 1;

            if (index != lastIndex) {
                address lastProvider = collateralProviders[lastIndex];
                collateralProviders[index] = lastProvider;
                collateralProviderIndexPlusOne[lastProvider] = index + 1;
            }

            collateralProviders.pop();
            collateralProviderIndexPlusOne[provider] = 0;
        }

        emit CollateralProviderSet(provider, enabled);
    }

    function totalShares(address agent) public view returns (uint256 shares) {
        shares = vault.balanceOf(agent);

        uint256 providerCount = collateralProviders.length;
        for (uint256 i = 0; i < providerCount; ) {
            try ICollateralProviderV2(collateralProviders[i]).collateralSharesOf(agent) returns (uint256 providerShares) {
                shares += providerShares;
            } catch {
                // Reverting provider treated as 0 shares (conservative assumption).
                // Governance should disable faulty providers via setCollateralProvider().
            }
            unchecked {
                ++i;
            }
        }
    }

    function currentAssets(address agent) public view returns (uint256 assetsNow, uint256 minAssetsFloor, uint256 navRay) {
        navRay = navController.currentNAVRay();
        minAssetsFloor = policyModule.getMinAssetsFloor(agent);
        assetsNow = RayMath.convertToAssetsDown(totalShares(agent), navRay);
    }

    /// @notice Returns true when agent is BELOW collateral floor (restricted from operations).
    /// @dev Grounded = true means the agent has insufficient collateral. The name derives from
    /// "grounded" as in "grounded from flying" (restricted), NOT "well-grounded" (stable).
    function isGroundedNow(address agent) public view returns (bool grounded) {
        (uint256 assetsNow, uint256 minAssetsFloor, ) = currentAssets(agent);
        return assetsNow < minAssetsFloor;
    }

    function poke(address agent) external {
        (uint256 assetsNow, uint256 minAssetsFloor, uint256 navRay) = currentAssets(agent);
        bool groundedNow = assetsNow < minAssetsFloor;

        if (groundedNow && !isGrounded[agent]) {
            isGrounded[agent] = true;
            emit AgentGrounded(agent, assetsNow, minAssetsFloor, navRay);
            return;
        }

        if (!groundedNow && isGrounded[agent]) {
            isGrounded[agent] = false;
            emit AgentUngrounded(agent, assetsNow, minAssetsFloor, navRay);
        }
    }
}
