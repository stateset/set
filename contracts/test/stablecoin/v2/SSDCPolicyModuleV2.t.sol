// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SSDCPolicyModuleV2} from "../../../stablecoin/v2/SSDCPolicyModuleV2.sol";

contract SSDCPolicyModuleV2Test is Test {
    SSDCPolicyModuleV2 internal policy;

    address internal admin = address(0xA11CE);
    address internal consumer = address(0xC01A);
    address internal agent = address(0xA637);
    address internal merchant = address(0xBEEF);

    function setUp() public {
        vm.startPrank(admin);
        policy = new SSDCPolicyModuleV2(admin);
        policy.grantRole(policy.POLICY_CONSUMER_ROLE(), consumer);
        vm.stopPrank();
    }

    function test_CanSpendUsesRolledDailyWindow() public {
        vm.prank(admin);
        policy.setPolicy(agent, 0, 100 ether, 0, 0, false);

        vm.prank(consumer);
        policy.consumeSpend(agent, merchant, 100 ether);

        assertFalse(policy.canSpend(agent, merchant, 1));

        vm.warp(block.timestamp + 1 days + 1);

        assertTrue(policy.canSpend(agent, merchant, 1 ether));
    }

    function test_CanSpendRespectsMerchantAllowlist() public {
        vm.prank(admin);
        policy.setPolicy(agent, 100 ether, 100 ether, 0, 0, true);

        assertFalse(policy.canSpend(agent, merchant, 1 ether));

        vm.prank(admin);
        policy.setMerchantAllowed(agent, merchant, true);

        assertTrue(policy.canSpend(agent, merchant, 1 ether));
    }

    function test_CanSpendRespectsSessionExpiry() public {
        vm.prank(admin);
        policy.setPolicy(agent, 100 ether, 100 ether, 0, uint40(block.timestamp + 1 hours), false);

        assertTrue(policy.canSpend(agent, merchant, 1 ether));

        vm.warp(block.timestamp + 1 hours + 1);

        assertFalse(policy.canSpend(agent, merchant, 1 ether));
    }
}
