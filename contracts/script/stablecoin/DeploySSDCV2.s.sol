// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../../stablecoin/v2/GroundingRegistryV2.sol";
import "../../stablecoin/v2/NAVControllerV2.sol";
import "../../stablecoin/v2/SSDCClaimQueueV2.sol";
import "../../stablecoin/v2/SSDCPolicyModuleV2.sol";
import "../../stablecoin/v2/SSDCStatusLensV2.sol";
import "../../stablecoin/v2/WSSDCCrossChainBridgeV2.sol";
import "../../stablecoin/v2/YieldEscrowV2.sol";
import "../../stablecoin/v2/YieldPaymasterV2.sol";
import "../../stablecoin/v2/interfaces/IETHUSDOracleV2.sol";
import "../../stablecoin/v2/wSSDCVaultV2.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DeploySSDCV2 is Script {
    uint256 internal constant RAY = 1e27;

    NAVControllerV2 public nav;
    wSSDCVaultV2 public vault;
    SSDCClaimQueueV2 public queue;
    YieldEscrowV2 public escrow;
    SSDCPolicyModuleV2 public policy;
    GroundingRegistryV2 public grounding;
    YieldPaymasterV2 public paymaster;
    WSSDCCrossChainBridgeV2 public bridge;
    SSDCStatusLensV2 public lens;

    function run() external {
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);

        address settlementAsset = vm.envAddress("SETTLEMENT_ASSET");
        address ethUsdOracle = vm.envAddress("ETH_USD_ORACLE");
        address entryPoint = vm.envAddress("ENTRY_POINT");

        address admin = vm.envOr("ADMIN", deployer);
        address oracleOperator = vm.envOr("NAV_ORACLE_OPERATOR", admin);
        address feeCollector = vm.envOr("FEE_COLLECTOR", admin);
        address bufferOperator = vm.envOr("BUFFER_OPERATOR", admin);

        uint256 minNavRay = vm.envOr("MIN_NAV_RAY", uint256(9e26));
        int256 maxRateAbsRay = int256(vm.envOr("MAX_RATE_ABS", uint256(1e23)));
        uint256 maxNavJumpBps = vm.envOr("MAX_NAV_JUMP_BPS", uint256(2_000));

        console2.log("Deploying SSDC v2 suite");
        console2.log("deployer", deployer);
        console2.log("admin", admin);
        console2.log("settlementAsset", settlementAsset);

        vm.startBroadcast(deployerPk);

        nav = new NAVControllerV2(
            admin,
            RAY,
            minNavRay,
            maxRateAbsRay,
            48 hours,
            24 hours,
            maxNavJumpBps
        );

        vault = new wSSDCVaultV2(ERC20(settlementAsset), nav, admin);
        queue = new SSDCClaimQueueV2(vault, ERC20(settlementAsset), admin);
        escrow = new YieldEscrowV2(vault, nav, admin, feeCollector);
        policy = new SSDCPolicyModuleV2(admin);
        grounding = new GroundingRegistryV2(policy, nav, vault, admin);

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
        lens = new SSDCStatusLensV2(nav, vault, queue, bridge);

        if (admin == deployer) {
            nav.grantRole(nav.ORACLE_ROLE(), oracleOperator);
            nav.grantRole(nav.BRIDGE_ROLE(), address(bridge));

            vault.grantRole(vault.QUEUE_ROLE(), address(queue));
            vault.grantRole(vault.BRIDGE_ROLE(), address(bridge));

            queue.grantRole(queue.BUFFER_ROLE(), bufferOperator);
            policy.grantRole(policy.POLICY_CONSUMER_ROLE(), address(paymaster));
            grounding.setCollateralProvider(address(paymaster), true);

            console2.log("Role wiring complete (admin == deployer)");
        } else {
            console2.log("Admin differs from deployer; skipping role grants requiring admin privileges");
            console2.log("Run post-deploy role wiring from admin account");
        }

        vm.stopBroadcast();

        console2.log("=== SSDC v2 Addresses ===");
        console2.log("NAVControllerV2", address(nav));
        console2.log("wSSDCVaultV2", address(vault));
        console2.log("SSDCClaimQueueV2", address(queue));
        console2.log("YieldEscrowV2", address(escrow));
        console2.log("SSDCPolicyModuleV2", address(policy));
        console2.log("GroundingRegistryV2", address(grounding));
        console2.log("YieldPaymasterV2", address(paymaster));
        console2.log("WSSDCCrossChainBridgeV2", address(bridge));
        console2.log("SSDCStatusLensV2", address(lens));
    }
}
