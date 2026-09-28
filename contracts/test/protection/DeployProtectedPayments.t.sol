// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../script/DeployProtectedPayments.s.sol";
import "../MockSsUSD.sol";

contract DeployProtectedPaymentsTest is Test {
    function test_script_wires_roles_and_hands_off_admin() public {
        MockSsUSD token = new MockSsUSD();
        address admin = address(0xAD);
        address fallbackArbiter = address(0xA2);
        vm.setEnv("STABLECOIN_ADDRESS", vm.toString(address(token)));
        vm.setEnv("ADMIN_ADDRESS", vm.toString(admin));
        vm.setEnv("DEFAULT_ARBITER", vm.toString(fallbackArbiter));
        vm.setEnv("SET_REGISTRY_ADDRESS", vm.toString(address(0)));

        (ArbiterRegistry registry, ProtectedPayments pp) = new DeployProtectedPayments().run();
        address deployer = vm.addr(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80);

        assertTrue(registry.hasRole(registry.COURT_ROLE(), address(pp)));
        assertEq(address(pp.arbiterRegistry()), address(registry));
        (bool enabled,,,,) = pp.tokenConfig(address(token));
        assertTrue(enabled);
        assertEq(pp.defaultArbiter(), fallbackArbiter);
        (bool approved,,,,,,) = registry.arbiters(fallbackArbiter);
        assertTrue(approved);
        assertEq(address(pp.evidenceVerifier()), address(0));

        assertTrue(pp.hasRole(pp.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(pp.hasRole(pp.UNDERWRITER_ROLE(), admin));
        assertTrue(pp.hasRole(pp.PAUSER_ROLE(), admin));
        assertTrue(registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), admin));
        assertFalse(pp.hasRole(pp.DEFAULT_ADMIN_ROLE(), deployer));
        assertFalse(pp.hasRole(pp.UNDERWRITER_ROLE(), deployer));
        assertFalse(pp.hasRole(pp.PAUSER_ROLE(), deployer));
        assertFalse(registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), deployer));
    }
}
