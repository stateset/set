// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../SetRegistry.sol";
import "../commerce/SetPaymaster.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title Deploy
 * @notice Deploys SetRegistry and SetPaymaster contracts to Set Chain
 *
 * Usage:
 *   # Local Anvil
 *   forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
 *
 *   # With private key
 *   forge script script/Deploy.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
 *
 *   # Verify on explorer
 *   forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
 */
contract DeployScript is Script {
    // Deployment addresses (set after deployment)
    address public registryProxy;
    address public registryImpl;
    address public paymasterProxy;
    address public paymasterImpl;

    function run() external {
        // Get deployer from environment or use default Anvil account
        uint256 deployerPrivateKey = vm.envOr(
            "DEPLOYER_PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );

        address deployer = vm.addr(deployerPrivateKey);

        // Get sequencer address (defaults to second Anvil account)
        address sequencer = vm.envOr(
            "SEQUENCER_ADDRESS",
            address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8)
        );

        // Get treasury address (defaults to deployer)
        address treasury = vm.envOr("TREASURY_ADDRESS", deployer);

        console.log("===========================================");
        console.log("  Set Chain Contract Deployment");
        console.log("===========================================");
        console.log("");
        console.log("Deployer:  ", deployer);
        console.log("Sequencer: ", sequencer);
        console.log("Treasury:  ", treasury);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy SetRegistry
        console.log("Deploying SetRegistry...");
        registryImpl = address(new SetRegistry());
        console.log("  Implementation:", registryImpl);

        bytes memory registryInitData = abi.encodeCall(
            SetRegistry.initialize,
            (deployer, sequencer)
        );
        registryProxy = address(new ERC1967Proxy(registryImpl, registryInitData));
        console.log("  Proxy:         ", registryProxy);

        // Deploy SetPaymaster
        console.log("");
        console.log("Deploying SetPaymaster...");
        paymasterImpl = address(new SetPaymaster());
        console.log("  Implementation:", paymasterImpl);

        bytes memory paymasterInitData = abi.encodeCall(
            SetPaymaster.initialize,
            (deployer, treasury)
        );
        paymasterProxy = address(new ERC1967Proxy(paymasterImpl, paymasterInitData));
        console.log("  Proxy:         ", paymasterProxy);

        vm.stopBroadcast();

        // Verify deployment
        console.log("");
        console.log("===========================================");
        console.log("  Verifying Deployment");
        console.log("===========================================");

        SetRegistry registry = SetRegistry(registryProxy);
        SetPaymaster paymaster = SetPaymaster(payable(paymasterProxy));

        console.log("");
        console.log("SetRegistry:");
        console.log("  Owner:              ", registry.owner());
        console.log("  Sequencer authorized:", registry.authorizedSequencers(sequencer));
        console.log("  Strict mode:        ", registry.strictModeEnabled());

        console.log("");
        console.log("SetPaymaster:");
        console.log("  Owner:              ", paymaster.owner());
        console.log("  Treasury:           ", paymaster.treasury());
        console.log("  Tiers configured:   ", paymaster.nextTierId());

        console.log("");
        console.log("===========================================");
        console.log("  Deployment Complete!");
        console.log("===========================================");
        console.log("");
        console.log("SET_REGISTRY_ADDRESS=", registryProxy);
        console.log("SET_PAYMASTER_ADDRESS=", paymasterProxy);
        console.log("");
    }
}

/**
 * @title DeployRegistry
 * @notice Deploys only SetRegistry (for minimal deployment)
 */
contract DeployRegistryScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envOr(
            "DEPLOYER_PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address deployer = vm.addr(deployerPrivateKey);
        address sequencer = vm.envOr(
            "SEQUENCER_ADDRESS",
            address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8)
        );

        console.log("Deploying SetRegistry...");
        console.log("Deployer: ", deployer);
        console.log("Sequencer:", sequencer);

        vm.startBroadcast(deployerPrivateKey);

        address impl = address(new SetRegistry());
        bytes memory initData = abi.encodeCall(SetRegistry.initialize, (deployer, sequencer));
        address proxy = address(new ERC1967Proxy(impl, initData));

        vm.stopBroadcast();

        console.log("");
        console.log("SetRegistry deployed:");
        console.log("  Proxy:         ", proxy);
        console.log("  Implementation:", impl);
    }
}

/**
 * @title DeployPaymaster
 * @notice Deploys only SetPaymaster
 */
contract DeployPaymasterScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envOr(
            "DEPLOYER_PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address deployer = vm.addr(deployerPrivateKey);
        address treasury = vm.envOr("TREASURY_ADDRESS", deployer);

        console.log("Deploying SetPaymaster...");
        console.log("Deployer:", deployer);
        console.log("Treasury:", treasury);

        vm.startBroadcast(deployerPrivateKey);

        address impl = address(new SetPaymaster());
        bytes memory initData = abi.encodeCall(SetPaymaster.initialize, (deployer, treasury));
        address proxy = address(new ERC1967Proxy(impl, initData));

        vm.stopBroadcast();

        console.log("");
        console.log("SetPaymaster deployed:");
        console.log("  Proxy:         ", proxy);
        console.log("  Implementation:", impl);
    }
}
