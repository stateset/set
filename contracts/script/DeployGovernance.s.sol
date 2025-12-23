// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../governance/SetTimelock.sol";
import "../SetRegistry.sol";
import "../commerce/SetPaymaster.sol";

/**
 * @title DeployGovernance
 * @notice Deploys governance infrastructure and transfers ownership
 *
 * This script:
 * 1. Deploys SetTimelock with configured delay
 * 2. Transfers ownership of SetRegistry and SetPaymaster to timelock
 * 3. Optionally renounces admin on timelock (for production)
 *
 * Usage:
 *   # Deploy with Safe multisig as proposer/executor
 *   MULTISIG_ADDRESS=0x... \
 *   SET_REGISTRY_ADDRESS=0x... \
 *   SET_PAYMASTER_ADDRESS=0x... \
 *   TIMELOCK_DELAY=86400 \
 *   forge script script/DeployGovernance.s.sol --rpc-url $RPC_URL --broadcast
 *
 * Environment Variables:
 *   - DEPLOYER_PRIVATE_KEY: Key to sign transactions
 *   - MULTISIG_ADDRESS: Safe multisig address (proposer/executor)
 *   - SET_REGISTRY_ADDRESS: Deployed SetRegistry proxy
 *   - SET_PAYMASTER_ADDRESS: Deployed SetPaymaster proxy
 *   - TIMELOCK_DELAY: Delay in seconds (default: 86400 = 24 hours)
 *   - RENOUNCE_ADMIN: Set to "true" to renounce admin (production only)
 */
contract DeployGovernanceScript is Script {
    address public timelock;

    function run() external {
        // Get deployer
        uint256 deployerPrivateKey = vm.envOr(
            "DEPLOYER_PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address deployer = vm.addr(deployerPrivateKey);

        // Get multisig address (required for production)
        address multisig = vm.envOr(
            "MULTISIG_ADDRESS",
            deployer // Default to deployer for testing
        );

        // Get existing contract addresses
        address registryProxy = vm.envOr("SET_REGISTRY_ADDRESS", address(0));
        address paymasterProxy = vm.envOr("SET_PAYMASTER_ADDRESS", address(0));

        // Get timelock delay (default 24 hours for production)
        uint256 timelockDelay = vm.envOr("TIMELOCK_DELAY", uint256(86400));

        // Whether to renounce admin (only for production)
        bool renounceAdmin = vm.envOr("RENOUNCE_ADMIN", false);

        console.log("===========================================");
        console.log("  Set Chain Governance Deployment");
        console.log("===========================================");
        console.log("");
        console.log("Deployer:       ", deployer);
        console.log("Multisig:       ", multisig);
        console.log("Registry:       ", registryProxy);
        console.log("Paymaster:      ", paymasterProxy);
        console.log("Timelock Delay: ", timelockDelay, "seconds");
        console.log("Renounce Admin: ", renounceAdmin);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Timelock
        console.log("Deploying SetTimelock...");

        address[] memory proposers = new address[](1);
        proposers[0] = multisig;

        address[] memory executors = new address[](1);
        executors[0] = multisig;

        // Admin is deployer initially for setup, then renounced
        SetTimelock timelockContract = new SetTimelock(
            timelockDelay,
            proposers,
            executors,
            renounceAdmin ? address(0) : deployer
        );
        timelock = address(timelockContract);
        console.log("  Timelock:     ", timelock);

        // 2. Transfer ownership of contracts to timelock
        if (registryProxy != address(0)) {
            console.log("");
            console.log("Transferring SetRegistry ownership...");
            SetRegistry registry = SetRegistry(registryProxy);

            address currentOwner = registry.owner();
            console.log("  Current owner:", currentOwner);

            if (currentOwner == deployer) {
                registry.transferOwnership(timelock);
                console.log("  New owner:    ", registry.owner());
            } else {
                console.log("  SKIPPED: Deployer is not owner");
            }
        }

        if (paymasterProxy != address(0)) {
            console.log("");
            console.log("Transferring SetPaymaster ownership...");
            SetPaymaster paymaster = SetPaymaster(payable(paymasterProxy));

            address currentOwner = paymaster.owner();
            console.log("  Current owner:", currentOwner);

            if (currentOwner == deployer) {
                paymaster.transferOwnership(timelock);
                console.log("  New owner:    ", paymaster.owner());
            } else {
                console.log("  SKIPPED: Deployer is not owner");
            }
        }

        // 3. Optionally renounce admin role on timelock
        if (renounceAdmin && timelockContract.hasRole(timelockContract.DEFAULT_ADMIN_ROLE(), deployer)) {
            console.log("");
            console.log("Renouncing admin role on timelock...");
            timelockContract.renounceRole(timelockContract.DEFAULT_ADMIN_ROLE(), deployer);
            console.log("  Admin renounced: ", !timelockContract.hasAdminRole(deployer));
        }

        vm.stopBroadcast();

        // Summary
        console.log("");
        console.log("===========================================");
        console.log("  Governance Deployment Complete!");
        console.log("===========================================");
        console.log("");
        console.log("SET_TIMELOCK_ADDRESS=", timelock);
        console.log("");
        console.log("Next steps:");
        console.log("  1. Verify timelock on block explorer");
        console.log("  2. Test proposal/execution flow with multisig");
        console.log("  3. Document addresses in docs/governance-evidence.md");
        if (!renounceAdmin) {
            console.log("  4. Renounce admin role when ready for production");
        }
        console.log("");
    }
}

/**
 * @title TransferToTimelock
 * @notice Transfer existing contracts to a deployed timelock
 */
contract TransferToTimelockScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address timelockAddress = vm.envAddress("SET_TIMELOCK_ADDRESS");
        address registryProxy = vm.envOr("SET_REGISTRY_ADDRESS", address(0));
        address paymasterProxy = vm.envOr("SET_PAYMASTER_ADDRESS", address(0));

        console.log("Transferring ownership to timelock:", timelockAddress);

        vm.startBroadcast(deployerPrivateKey);

        if (registryProxy != address(0)) {
            SetRegistry registry = SetRegistry(registryProxy);
            if (registry.owner() == deployer) {
                registry.transferOwnership(timelockAddress);
                console.log("SetRegistry ownership transferred");
            }
        }

        if (paymasterProxy != address(0)) {
            SetPaymaster paymaster = SetPaymaster(payable(paymasterProxy));
            if (paymaster.owner() == deployer) {
                paymaster.transferOwnership(timelockAddress);
                console.log("SetPaymaster ownership transferred");
            }
        }

        vm.stopBroadcast();
    }
}
