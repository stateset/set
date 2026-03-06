// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SSDCV2TestBase, MockETHUSDOracle} from "./SSDCV2TestBase.sol";
import {GroundingRegistryV2} from "../../../stablecoin/v2/GroundingRegistryV2.sol";
import {SSDCClaimQueueV2} from "../../../stablecoin/v2/SSDCClaimQueueV2.sol";
import {SSDCPolicyModuleV2} from "../../../stablecoin/v2/SSDCPolicyModuleV2.sol";
import {YieldEscrowV2} from "../../../stablecoin/v2/YieldEscrowV2.sol";
import {YieldPaymasterV2} from "../../../stablecoin/v2/YieldPaymasterV2.sol";
import {IETHUSDOracleV2} from "../../../stablecoin/v2/interfaces/IETHUSDOracleV2.sol";

contract AgentCommerceFlowV2Test is SSDCV2TestBase {
    SSDCClaimQueueV2 internal queue;
    YieldEscrowV2 internal escrow;
    SSDCPolicyModuleV2 internal policy;
    GroundingRegistryV2 internal grounding;
    YieldPaymasterV2 internal paymaster;
    MockETHUSDOracle internal priceOracle;

    address internal merchant = address(0xBEEF);
    address internal protocolFeeCollector = address(0xFEE0);
    address internal entryPoint = address(0x4337);

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        queue = new SSDCClaimQueueV2(vault, asset, admin);
        escrow = new YieldEscrowV2(vault, nav, admin, protocolFeeCollector);
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
            entryPoint,
            admin,
            protocolFeeCollector
        );

        vault.grantRole(vault.QUEUE_ROLE(), address(queue));
        policy.grantRole(policy.POLICY_CONSUMER_ROLE(), address(paymaster));
        grounding.setCollateralProvider(address(paymaster), true);

        policy.setPolicy(
            user1,
            type(uint256).max,
            type(uint256).max,
            50 ether,
            uint40(block.timestamp + 7 days),
            false
        );

        vm.stopPrank();
    }

    function test_EndToEndAgentCommerceFlow() public {
        // 1) Buyer agent acquires shares
        _mintAndDeposit(user1, 1_000 ether);

        // 2) Buyer funds invoice escrow in shares
        YieldEscrowV2.InvoiceTerms memory terms = YieldEscrowV2.InvoiceTerms({
            assetsDue: 400 ether,
            expiry: uint40(block.timestamp + 1 days),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max
        });

        vm.startPrank(user1);
        vault.approve(address(escrow), type(uint256).max);
        uint256 escrowId = escrow.fundEscrow(merchant, terms, 2_000);
        vm.stopPrank();

        // 3) NAV moves up smoothly (yield accrual period)
        uint64 nextEpoch = nav.navEpoch() + 1;
        vm.prank(oracle);
        nav.updateNAV(105e25, nextEpoch); // 1.05
        vm.warp(block.timestamp + 12 hours);
        priceOracle.setPrice(3_000e18);

        // 4) Release escrow (principal + yield split)
        escrow.release(escrowId);
        assertGt(vault.balanceOf(merchant), 0);

        // 5) Merchant requests redemption via async queue
        vm.startPrank(merchant);
        vault.approve(address(queue), type(uint256).max);
        uint256 merchantShares = vault.balanceOf(merchant);
        uint256 requestShares = merchantShares / 2;
        uint256 claimId = queue.requestRedeem(requestShares, merchant);
        vm.stopPrank();

        // 6) Buffer refilled and queue processed to claimable
        asset.mint(admin, 1_000 ether);
        vm.startPrank(admin);
        asset.approve(address(queue), type(uint256).max);
        queue.refill(1_000 ether);
        queue.processQueue(10);
        vm.stopPrank();

        (, , uint256 assetsOwed, , SSDCClaimQueueV2.Status status) = queue.claims(claimId);
        assertEq(uint256(status), uint256(SSDCClaimQueueV2.Status.CLAIMABLE));
        assertGt(assetsOwed, 0);

        // 7) Merchant claims settlement asset
        uint256 beforeAssets = asset.balanceOf(merchant);
        vm.prank(merchant);
        queue.claim(claimId);
        assertEq(asset.balanceOf(merchant), beforeAssets + assetsOwed);

        // 8) Buyer tops up gas tank from remaining shares; entrypoint charges gas in shares
        vm.startPrank(user1);
        vault.approve(address(paymaster), type(uint256).max);
        paymaster.topUpGasTank(100 ether);
        vm.stopPrank();

        uint256 feeBefore = vault.balanceOf(protocolFeeCollector);
        vm.prank(entryPoint);
        uint256 chargedShares = paymaster.postOp(user1, 200_000, 12 gwei, merchant);

        assertGt(chargedShares, 0);
        assertEq(vault.balanceOf(protocolFeeCollector), feeBefore + chargedShares);

        // 9) Grounding remains healthy above floor after charge
        assertFalse(grounding.isGroundedNow(user1));
    }
}
