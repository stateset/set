// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {MockAsset, MockETHUSDOracle} from "./SSDCV2TestBase.sol";
import {GroundingRegistryV2} from "../../../stablecoin/v2/GroundingRegistryV2.sol";
import {NAVControllerV2} from "../../../stablecoin/v2/NAVControllerV2.sol";
import {SSDCPolicyModuleV2} from "../../../stablecoin/v2/SSDCPolicyModuleV2.sol";
import {YieldPaymasterV2} from "../../../stablecoin/v2/YieldPaymasterV2.sol";
import {wSSDCVaultV2} from "../../../stablecoin/v2/wSSDCVaultV2.sol";
import {IETHUSDOracleV2} from "../../../stablecoin/v2/interfaces/IETHUSDOracleV2.sol";

contract YieldPaymasterHandlerV2 {
    YieldPaymasterV2 public immutable paymaster;
    wSSDCVaultV2 public immutable vault;
    MockAsset public immutable asset;

    address public immutable merchant = address(0xBEEF);

    constructor(YieldPaymasterV2 paymaster_, wSSDCVaultV2 vault_, MockAsset asset_) {
        paymaster = paymaster_;
        vault = vault_;
        asset = asset_;

        asset.mint(address(this), 1_000_000 ether);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(600_000 ether, address(this));
        vault.approve(address(paymaster), type(uint256).max);

        paymaster.topUpGasTank(300_000 ether);
    }

    function opTopUp(uint256 sharesRaw) external {
        uint256 sharesBalance = vault.balanceOf(address(this));
        if (sharesBalance == 0) {
            return;
        }

        uint256 shares = (sharesRaw % sharesBalance) + 1;
        try paymaster.topUpGasTank(shares) {} catch {}
    }

    function opPostOp(uint256 gasUsedRaw, uint256 gasPriceWeiRaw) external {
        uint256 gasUsed = (gasUsedRaw % 3_000_000) + 21_000;
        uint256 gasPriceWei = (gasPriceWeiRaw % 500 gwei) + 1;
        try paymaster.postOp(address(this), gasUsed, gasPriceWei, merchant) {} catch {}
    }
}

contract YieldPaymasterV2InvariantTest is StdInvariant, Test {
    uint256 internal constant RAY = 1e27;

    address internal admin = address(0xA11CE);
    address internal oracle = address(0x0A11);
    address internal feeCollector = address(0xFEE);

    MockAsset internal asset;
    NAVControllerV2 internal nav;
    wSSDCVaultV2 internal vault;
    SSDCPolicyModuleV2 internal policy;
    GroundingRegistryV2 internal grounding;
    MockETHUSDOracle internal ethUsdOracle;
    YieldPaymasterV2 internal paymaster;
    YieldPaymasterHandlerV2 internal handler;

    uint256 internal minAssetsFloor = 100_000 ether;

    function setUp() public {
        vm.startPrank(admin);
        asset = new MockAsset();
        nav = new NAVControllerV2(
            admin,
            RAY,
            9e26,
            1e23,
            48 hours,
            24 hours,
            2_000
        );
        vault = new wSSDCVaultV2(asset, nav, admin);
        policy = new SSDCPolicyModuleV2(admin);
        grounding = new GroundingRegistryV2(policy, nav, vault, admin);

        ethUsdOracle = new MockETHUSDOracle();
        ethUsdOracle.setPrice(3_000e18);

        paymaster = new YieldPaymasterV2(
            vault,
            nav,
            policy,
            grounding,
            IETHUSDOracleV2(address(ethUsdOracle)),
            admin,
            admin,
            feeCollector
        );
        policy.grantRole(policy.POLICY_CONSUMER_ROLE(), address(paymaster));
        grounding.setCollateralProvider(address(paymaster), true);
        vm.stopPrank();

        handler = new YieldPaymasterHandlerV2(paymaster, vault, asset);

        vm.startPrank(admin);
        paymaster.setEntryPoint(address(handler));
        policy.setPolicy(
            address(handler),
            type(uint256).max,
            type(uint256).max,
            minAssetsFloor,
            0,
            false
        );
        vm.stopPrank();

        targetContract(address(handler));
    }

    function invariant_postOpCannotBreakPolicyFloorUnderStableNav() public view {
        uint256 totalShares = paymaster.gasTankShares(address(handler)) + vault.balanceOf(address(handler));
        uint256 totalAssets = vault.convertToAssets(totalShares);
        uint256 floor = policy.getMinAssetsFloor(address(handler));

        assertGe(totalAssets, floor);
    }
}
