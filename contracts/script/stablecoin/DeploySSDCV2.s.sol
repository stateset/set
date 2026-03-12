// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../../stablecoin/v2/GroundingRegistryV2.sol";
import "../../stablecoin/v2/NAVControllerV2.sol";
import "../../stablecoin/v2/SSDCClaimQueueV2.sol";
import "../../stablecoin/v2/SSDCPolicyModuleV2.sol";
import "../../stablecoin/v2/SSDCStatusLensV2.sol";
import "../../stablecoin/v2/SSDCVaultGatewayV2.sol";
import "../../stablecoin/v2/WSSDCCrossChainBridgeV2.sol";
import "../../stablecoin/v2/YieldEscrowV2.sol";
import "../../stablecoin/v2/YieldPaymasterV2.sol";
import "../../stablecoin/v2/SSDCV2CircuitBreaker.sol";
import "../../stablecoin/v2/interfaces/IETHUSDOracleV2.sol";
import "../../stablecoin/v2/wSSDCVaultV2.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DeploySSDCV2 is Script {
    uint256 internal constant RAY = 1e27;

    NAVControllerV2 public nav;
    wSSDCVaultV2 public vault;
    SSDCVaultGatewayV2 public gateway;
    SSDCClaimQueueV2 public queue;
    YieldEscrowV2 public escrow;
    SSDCPolicyModuleV2 public policy;
    GroundingRegistryV2 public grounding;
    YieldPaymasterV2 public paymaster;
    WSSDCCrossChainBridgeV2 public bridge;
    SSDCStatusLensV2 public lens;
    SSDCV2CircuitBreaker public breaker;

    function run() external {
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);

        address settlementAsset = vm.envAddress("SETTLEMENT_ASSET");
        address ethUsdOracle = vm.envAddress("ETH_USD_ORACLE");
        address entryPoint = vm.envAddress("ENTRY_POINT");

        address admin = vm.envOr("ADMIN", deployer);
        address oracleOperator = vm.envOr("NAV_ORACLE_OPERATOR", admin);
        address arbiterOperator = vm.envOr("ARBITER_OPERATOR", admin);
        address feeCollector = vm.envOr("FEE_COLLECTOR", admin);
        address reserveCollector = vm.envOr("ESCROW_RESERVE_COLLECTOR", feeCollector);
        address bufferOperator = vm.envOr("BUFFER_OPERATOR", admin);
        address gatewayOperator = vm.envOr("GATEWAY_OPERATOR", admin);
        bool gatewayRequired = vm.envOr("GATEWAY_REQUIRED", true);
        uint256 maxBridgeOutstandingShares = vm.envOr("MAX_BRIDGE_OUTSTANDING_SHARES", uint256(0));
        uint256 minBridgeLiquidityCoverageBps = vm.envOr("MIN_BRIDGE_LIQUIDITY_COVERAGE_BPS", uint256(0));
        uint256 escrowReserveBps = vm.envOr("ESCROW_RESERVE_BPS", uint256(0));
        address reserveManager = vm.envOr("RESERVE_MANAGER", address(0));
        uint256 reserveFloor = vm.envOr("RESERVE_FLOOR", uint256(0));
        uint256 reserveMaxDeployBps = vm.envOr("RESERVE_MAX_DEPLOY_BPS", uint256(2_000));

        uint256 minNavRay = vm.envOr("MIN_NAV_RAY", uint256(9e26));
        int256 maxRateAbsRay = int256(vm.envOr("MAX_RATE_ABS", uint256(1e23)));
        uint256 maxStaleness = vm.envOr("MAX_STALENESS", uint256(48 hours));
        uint256 maxNavJumpBps = vm.envOr("MAX_NAV_JUMP_BPS", uint256(2_000));
        uint256 staleRecoveryJumpMultiplier = vm.envOr("STALE_RECOVERY_JUMP_MULTIPLIER", uint256(3));

        console2.log("Deploying SSDC v2 suite");
        console2.log("deployer", deployer);
        console2.log("admin", admin);
        console2.log("arbiterOperator", arbiterOperator);
        console2.log("settlementAsset", settlementAsset);
        console2.log("gatewayOperator", gatewayOperator);
        console2.log("gatewayRequired", gatewayRequired);
        console2.log("maxBridgeOutstandingShares", maxBridgeOutstandingShares);
        console2.log("minBridgeLiquidityCoverageBps", minBridgeLiquidityCoverageBps);
        console2.log("reserveCollector", reserveCollector);
        console2.log("escrowReserveBps", escrowReserveBps);
        console2.log("reserveManager", reserveManager);
        console2.log("reserveFloor", reserveFloor);
        console2.log("reserveMaxDeployBps", reserveMaxDeployBps);

        vm.startBroadcast(deployerPk);

        nav = new NAVControllerV2(
            admin,
            RAY,
            minNavRay,
            maxRateAbsRay,
            maxStaleness,
            maxNavJumpBps,
            staleRecoveryJumpMultiplier
        );

        vault = new wSSDCVaultV2(ERC20(settlementAsset), nav, admin);
        gateway = new SSDCVaultGatewayV2(vault, admin);
        queue = new SSDCClaimQueueV2(vault, ERC20(settlementAsset), admin);
        policy = new SSDCPolicyModuleV2(admin);
        grounding = new GroundingRegistryV2(policy, nav, vault, admin);
        escrow = new YieldEscrowV2(vault, nav, policy, grounding, admin, feeCollector);

        paymaster = new YieldPaymasterV2(
            vault,
            nav,
            policy,
            grounding,
            IETHUSDOracleV2(ethUsdOracle),
            entryPoint,
            admin,
            feeCollector
        );

        bridge = new WSSDCCrossChainBridgeV2(vault, nav, admin);
        lens = new SSDCStatusLensV2(nav, vault, queue, bridge, escrow, paymaster);
        breaker = new SSDCV2CircuitBreaker(nav, vault, queue, bridge, escrow, paymaster, admin);

        if (admin == deployer) {
            nav.grantRole(nav.ORACLE_ROLE(), oracleOperator);
            nav.grantRole(nav.BRIDGE_ROLE(), address(bridge));

            vault.grantRole(vault.GATEWAY_ROLE(), gatewayOperator);
            vault.grantRole(vault.GATEWAY_ROLE(), address(gateway));
            vault.grantRole(vault.GATEWAY_ROLE(), address(queue));
            vault.grantRole(vault.QUEUE_ROLE(), address(queue));
            vault.grantRole(vault.BRIDGE_ROLE(), address(bridge));
            vault.setMinBridgeLiquidityCoverageBps(minBridgeLiquidityCoverageBps);
            bridge.setMintLimit(maxBridgeOutstandingShares);
            if (reserveManager != address(0)) {
                vault.setReserveConfig(reserveManager, reserveFloor, reserveMaxDeployBps);
                if (reserveManager != admin) {
                    vault.grantRole(vault.RESERVE_ROLE(), reserveManager);
                }
            }

            queue.grantRole(queue.BUFFER_ROLE(), bufferOperator);
            escrow.grantRole(escrow.FUNDER_ROLE(), address(gateway));
            if (arbiterOperator != admin) {
                escrow.grantRole(escrow.ARBITER_ROLE(), arbiterOperator);
            }
            if (escrowReserveBps > 0 || reserveCollector != feeCollector) {
                require(escrowReserveBps <= type(uint16).max, "reserve bps overflow");
                // forge-lint: disable-next-line(unsafe-typecast)
                uint16 escrowReserveBps16 = uint16(escrowReserveBps);
                escrow.setReserveConfig(escrowReserveBps16, reserveCollector);
            }
            policy.grantRole(policy.POLICY_CONSUMER_ROLE(), address(escrow));
            policy.grantRole(policy.POLICY_CONSUMER_ROLE(), address(paymaster));
            grounding.setCollateralProvider(address(paymaster), true);
            vault.setGatewayRequired(gatewayRequired);

            // Wire circuit breaker pause roles
            nav.grantRole(nav.PAUSER_ROLE(), address(breaker));
            vault.grantRole(vault.PAUSER_ROLE(), address(breaker));
            queue.grantRole(queue.PAUSER_ROLE(), address(breaker));
            bridge.grantRole(bridge.PAUSER_ROLE(), address(breaker));
            escrow.grantRole(escrow.PAUSER_ROLE(), address(breaker));
            paymaster.grantRole(paymaster.PAUSER_ROLE(), address(breaker));

            console2.log("Role wiring complete (admin == deployer)");
        } else {
            console2.log("Admin differs from deployer; skipping role grants requiring admin privileges");
            console2.log("Run post-deploy role wiring from admin account");
        }

        vm.stopBroadcast();

        console2.log("=== SSDC v2 Addresses ===");
        console2.log("NAVControllerV2", address(nav));
        console2.log("wSSDCVaultV2", address(vault));
        console2.log("SSDCVaultGatewayV2", address(gateway));
        console2.log("SSDCClaimQueueV2", address(queue));
        console2.log("YieldEscrowV2", address(escrow));
        console2.log("SSDCPolicyModuleV2", address(policy));
        console2.log("GroundingRegistryV2", address(grounding));
        console2.log("YieldPaymasterV2", address(paymaster));
        console2.log("WSSDCCrossChainBridgeV2", address(bridge));
        console2.log("SSDCStatusLensV2", address(lens));
        console2.log("SSDCV2CircuitBreaker", address(breaker));
    }
}
