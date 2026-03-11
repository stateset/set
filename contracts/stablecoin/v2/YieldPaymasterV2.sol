// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {GroundingRegistryV2} from "./GroundingRegistryV2.sol";
import {NAVControllerV2} from "./NAVControllerV2.sol";
import {RayMath} from "./RayMath.sol";
import {SSDCPolicyModuleV2} from "./SSDCPolicyModuleV2.sol";
import {wSSDCVaultV2} from "./wSSDCVaultV2.sol";
import {ICollateralProviderV2} from "./interfaces/ICollateralProviderV2.sol";
import {IETHUSDOracleV2} from "./interfaces/IETHUSDOracleV2.sol";

contract YieldPaymasterV2 is AccessControl, ReentrancyGuard, ICollateralProviderV2 {
    bytes32 public constant PAYMASTER_ADMIN_ROLE = keccak256("PAYMASTER_ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    struct PendingCharge {
        address agent;
        uint256 maxGasCostWei;
        uint256 maxShares;
        address merchant;
        uint64 preparedAtBlock;
    }

    wSSDCVaultV2 public immutable vault;
    NAVControllerV2 public immutable navController;
    SSDCPolicyModuleV2 public immutable policyModule;
    GroundingRegistryV2 public immutable groundingRegistry;

    IETHUSDOracleV2 public ethUsdOracle;
    address public entryPoint;

    bool public paymasterPaused;
    uint256 public maxPriceStaleness;
    address public feeCollector;

    mapping(address => uint256) public gasTankShares;
    mapping(bytes32 => PendingCharge) public pendingCharges;

    error PAYMASTER_PAUSED();
    error GROUNDED();
    error PRICE_STALE();
    error PRICE_ZERO();
    error FLOOR();
    error INSUFFICIENT_SHARES();
    error NOT_ENTRYPOINT();
    error VALIDATION_MISSING();
    error VALIDATION_EXPIRED();
    error AGENT_MISMATCH();
    error MERCHANT_MISMATCH();
    error GAS_BUDGET();

    event GasCharged(
        address indexed agent,
        uint256 sharesCharged,
        uint256 gasUsed,
        uint256 effectiveGasPrice
    );

    event GasTankToppedUp(address indexed agent, uint256 shares);
    event GasTankWithdrawn(address indexed agent, address indexed to, uint256 shares);
    event MaxPriceStalenessUpdated(uint256 maxPriceStaleness);
    event FeeCollectorUpdated(address feeCollector);
    event EthUsdOracleUpdated(address oracle);
    event PaymasterPausedSet(bool paused);
    event EntryPointUpdated(address entryPoint);

    constructor(
        wSSDCVaultV2 vault_,
        NAVControllerV2 navController_,
        SSDCPolicyModuleV2 policyModule_,
        GroundingRegistryV2 groundingRegistry_,
        IETHUSDOracleV2 ethUsdOracle_,
        address entryPoint_,
        address admin,
        address feeCollector_
    ) {
        require(admin != address(0), "admin=0");
        require(feeCollector_ != address(0), "fee=0");
        require(entryPoint_ != address(0), "entry=0");

        vault = vault_;
        navController = navController_;
        policyModule = policyModule_;
        groundingRegistry = groundingRegistry_;
        ethUsdOracle = ethUsdOracle_;
        entryPoint = entryPoint_;

        maxPriceStaleness = 60 minutes;
        feeCollector = feeCollector_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAYMASTER_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    modifier onlyEntryPoint() {
        if (msg.sender != entryPoint) {
            revert NOT_ENTRYPOINT();
        }
        _;
    }

    function setEthUsdOracle(IETHUSDOracleV2 oracle) external onlyRole(PAYMASTER_ADMIN_ROLE) {
        require(address(oracle) != address(0), "oracle=0");
        ethUsdOracle = oracle;
        emit EthUsdOracleUpdated(address(oracle));
    }

    function setPaymasterPaused(bool paused) external onlyRole(PAUSER_ROLE) {
        paymasterPaused = paused;
        emit PaymasterPausedSet(paused);
    }

    function setMaxPriceStaleness(uint256 staleness) external onlyRole(PAYMASTER_ADMIN_ROLE) {
        require(staleness > 0, "staleness=0");
        maxPriceStaleness = staleness;
        emit MaxPriceStalenessUpdated(staleness);
    }

    function setFeeCollector(address collector) external onlyRole(PAYMASTER_ADMIN_ROLE) {
        require(collector != address(0), "collector=0");
        feeCollector = collector;
        emit FeeCollectorUpdated(collector);
    }

    function setEntryPoint(address entryPoint_) external onlyRole(PAYMASTER_ADMIN_ROLE) {
        require(entryPoint_ != address(0), "entry=0");
        entryPoint = entryPoint_;
        emit EntryPointUpdated(entryPoint_);
    }

    function topUpGasTank(uint256 shares) external nonReentrant {
        if (paymasterPaused) revert PAYMASTER_PAUSED();
        _topUpGasTank(msg.sender, shares);
    }

    function topUpGasTankFor(address agent, uint256 shares) external nonReentrant {
        if (paymasterPaused) revert PAYMASTER_PAUSED();
        require(agent != address(0), "agent=0");
        _topUpGasTank(agent, shares);
    }

    function withdrawGasTank(uint256 shares, address to) external nonReentrant {
        uint256 tank = gasTankShares[msg.sender];
        require(shares <= tank, "tank<shares");

        unchecked {
            gasTankShares[msg.sender] = tank - shares;
        }

        vault.transfer(to, shares);
        emit GasTankWithdrawn(msg.sender, to, shares);
    }

    function validatePaymasterUserOp(
        bytes32 opKey,
        address agent,
        uint256 maxGasCostWei,
        address merchant
    ) external onlyEntryPoint returns (uint256 chargeShares) {
        if (paymasterPaused) revert PAYMASTER_PAUSED();
        if (groundingRegistry.isGroundedNow(agent)) {
            revert GROUNDED();
        }

        uint256 assetsCost = _ethWeiToUsdAssets(maxGasCostWei);
        uint256 nav = navController.currentNAVRay();

        chargeShares = RayMath.convertToSharesUp(assetsCost, nav);

        uint256 tankShares = gasTankShares[agent];
        if (chargeShares > tankShares) {
            revert INSUFFICIENT_SHARES();
        }

        uint256 totalShares = tankShares + vault.balanceOf(agent);
        uint256 minAssetsFloor = policyModule.getMinAssetsFloor(agent);
        uint256 postAssets = RayMath.convertToAssetsDown(totalShares - chargeShares, nav);
        if (postAssets < minAssetsFloor) {
            revert FLOOR();
        }

        bool canSpend = policyModule.canSpend(agent, merchant, assetsCost);
        require(canSpend, "POLICY");

        pendingCharges[opKey] = PendingCharge({
            agent: agent,
            maxGasCostWei: maxGasCostWei,
            maxShares: chargeShares,
            merchant: merchant,
            preparedAtBlock: uint64(block.number)
        });
    }

    function postOp(
        bytes32 opKey,
        address agent,
        uint256 gasUsed,
        uint256 effectiveGasPrice,
        address merchant
    ) external onlyEntryPoint nonReentrant returns (uint256 sharesCharged) {
        PendingCharge memory pending = pendingCharges[opKey];
        if (pending.preparedAtBlock == 0) {
            revert VALIDATION_MISSING();
        }
        if (pending.preparedAtBlock != block.number) {
            revert VALIDATION_EXPIRED();
        }
        if (pending.agent != agent) {
            revert AGENT_MISMATCH();
        }
        if (pending.merchant != merchant) {
            revert MERCHANT_MISMATCH();
        }
        delete pendingCharges[opKey];

        if (groundingRegistry.isGroundedNow(agent)) {
            revert GROUNDED();
        }

        uint256 gasCostWei = gasUsed * effectiveGasPrice;
        if (gasCostWei > pending.maxGasCostWei) {
            revert GAS_BUDGET();
        }
        uint256 assetsCost = _ethWeiToUsdAssets(gasCostWei);
        uint256 nav = navController.currentNAVRay();

        sharesCharged = RayMath.convertToSharesUp(assetsCost, nav);
        if (sharesCharged > pending.maxShares) {
            revert GAS_BUDGET();
        }

        uint256 tankShares = gasTankShares[agent];
        if (sharesCharged > tankShares) {
            revert INSUFFICIENT_SHARES();
        }

        uint256 totalShares = tankShares + vault.balanceOf(agent);
        uint256 minAssetsFloor = policyModule.getMinAssetsFloor(agent);
        uint256 postAssets = RayMath.convertToAssetsDown(totalShares - sharesCharged, nav);
        if (postAssets < minAssetsFloor) {
            revert FLOOR();
        }

        policyModule.consumeSpend(agent, merchant, assetsCost);

        unchecked {
            gasTankShares[agent] = tankShares - sharesCharged;
        }
        vault.transfer(feeCollector, sharesCharged);

        emit GasCharged(agent, sharesCharged, gasUsed, effectiveGasPrice);
    }

    function collateralSharesOf(address agent) external view override returns (uint256 shares) {
        return gasTankShares[agent];
    }

    function _ethWeiToUsdAssets(uint256 weiAmount) internal view returns (uint256 assets) {
        (uint256 ethUsdPriceE18, uint256 updatedAt) = ethUsdOracle.latestPrice();
        if (ethUsdPriceE18 == 0) {
            revert PRICE_ZERO();
        }
        if (block.timestamp - updatedAt > maxPriceStaleness) {
            revert PRICE_STALE();
        }
        assets = Math.mulDiv(weiAmount, ethUsdPriceE18, 1e18, Math.Rounding.Ceil);
    }

    function previewChargeShares(uint256 gasCostWei) external view returns (uint256 shares) {
        uint256 assetsCost = _ethWeiToUsdAssets(gasCostWei);
        uint256 nav = navController.currentNAVRay();
        return RayMath.convertToSharesUp(assetsCost, nav);
    }

    function _topUpGasTank(address agent, uint256 shares) internal {
        vault.transferFrom(msg.sender, address(this), shares);
        unchecked {
            gasTankShares[agent] += shares;
        }
        emit GasTankToppedUp(agent, shares);
    }
}
