// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2TestBase, MockETHUSDOracle} from "./SSDCV2TestBase.sol";
import {GroundingRegistryV2} from "../../../stablecoin/v2/GroundingRegistryV2.sol";
import {SSDCPolicyModuleV2} from "../../../stablecoin/v2/SSDCPolicyModuleV2.sol";
import {YieldPaymasterV2} from "../../../stablecoin/v2/YieldPaymasterV2.sol";
import {IETHUSDOracleV2} from "../../../stablecoin/v2/interfaces/IETHUSDOracleV2.sol";

contract EntryPointMockV2 {
    function callValidate(
        YieldPaymasterV2 paymaster,
        bytes32 opKey,
        address agent,
        uint256 maxGasCostWei,
        address merchant
    ) external returns (uint256) {
        return paymaster.validatePaymasterUserOp(opKey, agent, maxGasCostWei, merchant);
    }

    function callPostOp(
        YieldPaymasterV2 paymaster,
        bytes32 opKey,
        address agent,
        uint256 gasUsed,
        uint256 effectiveGasPrice,
        address merchant
    ) external returns (uint256) {
        return paymaster.postOp(opKey, agent, gasUsed, effectiveGasPrice, merchant);
    }

    function validateAndPost(
        YieldPaymasterV2 paymaster,
        bytes32 opKey,
        address agent,
        uint256 maxGasCostWei,
        uint256 gasUsed,
        uint256 effectiveGasPrice,
        address merchant
    ) external returns (uint256 previewShares, uint256 chargedShares) {
        previewShares = paymaster.validatePaymasterUserOp(opKey, agent, maxGasCostWei, merchant);
        chargedShares = paymaster.postOp(opKey, agent, gasUsed, effectiveGasPrice, merchant);
    }
}

contract YieldPaymasterV2EntryPointTest is SSDCV2TestBase {
    SSDCPolicyModuleV2 internal policy;
    GroundingRegistryV2 internal grounding;
    MockETHUSDOracle internal priceOracle;
    YieldPaymasterV2 internal paymaster;
    EntryPointMockV2 internal entryPoint;

    function setUp() public override {
        super.setUp();

        entryPoint = new EntryPointMockV2();

        vm.startPrank(admin);
        policy = new SSDCPolicyModuleV2(admin);
        grounding = new GroundingRegistryV2(policy, nav, vault, admin);

        priceOracle = new MockETHUSDOracle();
        priceOracle.setPrice(3_000e18);

        paymaster = new YieldPaymasterV2(
            vault,
            nav,
            policy,
            grounding,
            IETHUSDOracleV2(address(priceOracle)),
            address(entryPoint),
            admin,
            user3
        );

        policy.grantRole(policy.POLICY_CONSUMER_ROLE(), address(paymaster));
        grounding.setCollateralProvider(address(paymaster), true);
        policy.setPolicy(
            user1,
            type(uint256).max,
            type(uint256).max,
            20 ether,
            uint40(block.timestamp + 2 days),
            false
        );
        vm.stopPrank();

        _mintAndDeposit(user1, 200 ether);

        vm.startPrank(user1);
        vault.approve(address(paymaster), type(uint256).max);
        paymaster.topUpGasTank(100 ether);
        vm.stopPrank();
    }

    function test_EntryPointValidateAndPostFlow() public {
        uint256 gasUsed = 250_000;
        uint256 gasPrice = 12 gwei;
        uint256 gasCostWei = gasUsed * gasPrice;
        bytes32 opKey = keccak256("entrypoint-flow");

        uint256 feeBefore = vault.balanceOf(user3);

        (uint256 previewShares, uint256 chargedShares) = entryPoint.validateAndPost(
            paymaster,
            opKey,
            user1,
            gasCostWei,
            gasUsed,
            gasPrice,
            user2
        );

        assertEq(chargedShares, previewShares);
        assertEq(vault.balanceOf(user3), feeBefore + chargedShares);
    }

    function test_PostOpCanFailIfActualExceedsValidatedBudget() public {
        uint256 validatedCost = 50_000 * 10 gwei;
        bytes32 opKey = keccak256("budget");
        entryPoint.callValidate(paymaster, opKey, user1, validatedCost, user2);

        vm.prank(admin);
        policy.setPolicy(
            user1,
            type(uint256).max,
            type(uint256).max,
            195 ether,
            uint40(block.timestamp + 2 days),
            false
        );

        vm.expectRevert(YieldPaymasterV2.GAS_BUDGET.selector);
        entryPoint.callPostOp(paymaster, opKey, user1, 100_000, 20 gwei, user2);
    }

    function test_PostOpRequiresValidation() public {
        vm.expectRevert(YieldPaymasterV2.VALIDATION_MISSING.selector);
        entryPoint.callPostOp(paymaster, keccak256("missing"), user1, 100_000, 20 gwei, user2);
    }

    function test_EntryPointRotationInvalidatesOldEntryPoint() public {
        EntryPointMockV2 newEntryPoint = new EntryPointMockV2();

        vm.prank(admin);
        paymaster.setEntryPoint(address(newEntryPoint));

        vm.expectRevert(YieldPaymasterV2.NOT_ENTRYPOINT.selector);
        entryPoint.callValidate(paymaster, keccak256("old-entry"), user1, 0.001 ether, user2);

        uint256 shares = newEntryPoint.callValidate(paymaster, keccak256("new-entry"), user1, 0.001 ether, user2);
        assertGt(shares, 0);
    }

    function test_SameAgentBatchUsesIndependentPendingCharges() public {
        uint256 gasPrice = 12 gwei;
        bytes32 opKey1 = keccak256("batch-1");
        bytes32 opKey2 = keccak256("batch-2");

        uint256 preview1 = entryPoint.callValidate(paymaster, opKey1, user1, 120_000 * gasPrice, user2);
        uint256 preview2 = entryPoint.callValidate(paymaster, opKey2, user1, 180_000 * gasPrice, user3);

        uint256 charged1 = entryPoint.callPostOp(paymaster, opKey1, user1, 100_000, gasPrice, user2);
        uint256 charged2 = entryPoint.callPostOp(paymaster, opKey2, user1, 150_000, gasPrice, user3);

        assertLe(charged1, preview1);
        assertLe(charged2, preview2);
        assertGt(charged1, 0);
        assertGt(charged2, 0);
    }
}
