// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../SetRegistry.sol";
import "../commerce/SetPaymentBatch.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployX402Arc
 * @notice Deploys x402 Payment contracts to Arc Testnet
 *
 * Arc Testnet Configuration:
 *   - RPC URL: https://rpc.testnet.arc.network
 *   - Chain ID: 5042002
 *   - Native Gas: USDC (18 decimals for gas, 6 decimals ERC-20)
 *   - USDC Address: 0x3600000000000000000000000000000000000000
 *   - Explorer: https://testnet.arcscan.app
 *   - Faucet: https://faucet.circle.com
 *
 * Usage:
 *   # Set environment variables
 *   export PRIVATE_KEY="0x..."
 *   export ARC_TESTNET_RPC_URL="https://rpc.testnet.arc.network"
 *
 *   # Deploy
 *   forge script script/DeployX402Arc.s.sol:DeployX402ArcScript \
 *     --rpc-url $ARC_TESTNET_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast
 *
 *   # With verification
 *   forge script script/DeployX402Arc.s.sol:DeployX402ArcScript \
 *     --rpc-url $ARC_TESTNET_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify
 */
contract DeployX402ArcScript is Script {
    // Arc Testnet USDC (native gas token with ERC-20 interface)
    address constant ARC_USDC = 0x3600000000000000000000000000000000000000;

    // Arc Testnet EURC
    address constant ARC_EURC = 0x89B50855Aa3bE2F677cD6303Cec089B5F319D72a;

    // Chain ID for Arc Testnet
    uint256 constant ARC_CHAIN_ID = 5042002;

    // Deployed addresses
    address public registryProxy;
    address public registryImpl;
    address public paymentBatchProxy;
    address public paymentBatchImpl;

    function run() external {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Sequencer address (can be same as deployer for testing)
        address sequencer = vm.envOr("SEQUENCER_ADDRESS", deployer);

        console.log("===========================================");
        console.log("  x402 Payment Deployment - Arc Testnet");
        console.log("===========================================");
        console.log("");
        console.log("Chain ID:      ", block.chainid);
        console.log("Deployer:      ", deployer);
        console.log("Sequencer:     ", sequencer);
        console.log("USDC Address:  ", ARC_USDC);
        console.log("");

        // Verify we're on Arc Testnet
        require(
            block.chainid == ARC_CHAIN_ID,
            "Not on Arc Testnet (expected chain ID 5042002)"
        );

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy SetRegistry
        console.log("Deploying SetRegistry...");
        registryImpl = address(new SetRegistry());
        console.log("  Implementation: ", registryImpl);

        bytes memory registryInitData = abi.encodeCall(
            SetRegistry.initialize,
            (deployer, sequencer)
        );
        registryProxy = address(new ERC1967Proxy(registryImpl, registryInitData));
        console.log("  Proxy:          ", registryProxy);

        // 2. Deploy SetPaymentBatch
        console.log("");
        console.log("Deploying SetPaymentBatch...");
        paymentBatchImpl = address(new SetPaymentBatch());
        console.log("  Implementation: ", paymentBatchImpl);

        // Initialize with Arc's native USDC and EURC as ssUSD placeholder
        bytes memory paymentBatchInitData = abi.encodeCall(
            SetPaymentBatch.initialize,
            (
                deployer,      // owner
                sequencer,     // authorized sequencer
                ARC_USDC,      // USDC token
                ARC_EURC,      // ssUSD placeholder (using EURC)
                registryProxy  // registry
            )
        );
        paymentBatchProxy = address(new ERC1967Proxy(paymentBatchImpl, paymentBatchInitData));
        console.log("  Proxy:          ", paymentBatchProxy);

        vm.stopBroadcast();

        // Verify deployment
        console.log("");
        console.log("===========================================");
        console.log("  Verifying Deployment");
        console.log("===========================================");

        SetRegistry registry = SetRegistry(registryProxy);
        SetPaymentBatch paymentBatch = SetPaymentBatch(paymentBatchProxy);

        console.log("");
        console.log("SetRegistry:");
        console.log("  Owner:               ", registry.owner());
        console.log("  Sequencer authorized:", registry.authorizedSequencers(sequencer));

        console.log("");
        console.log("SetPaymentBatch:");
        console.log("  Owner:               ", paymentBatch.owner());
        console.log("  Sequencer authorized:", paymentBatch.authorizedSequencers(sequencer));

        // Print environment variables for sequencer
        console.log("");
        console.log("===========================================");
        console.log("  Deployment Complete!");
        console.log("===========================================");
        console.log("");
        console.log("# Add these to your sequencer .env file:");
        console.log("");
        console.log("ARC_TESTNET_RPC_URL=https://rpc.testnet.arc.network");
        console.log("ARC_CHAIN_ID=5042002");
        console.log("SET_REGISTRY_ADDRESS=", registryProxy);
        console.log("SET_PAYMENT_BATCH_ADDRESS=", paymentBatchProxy);
        console.log("ARC_USDC_ADDRESS=", ARC_USDC);
        console.log("");
        console.log("# View on Arc Explorer:");
        console.log("https://testnet.arcscan.app/address/", registryProxy);
        console.log("https://testnet.arcscan.app/address/", paymentBatchProxy);
        console.log("");
    }
}

/**
 * @title VerifyX402Arc
 * @notice Verifies x402 contracts on Arc Testnet after deployment
 */
contract VerifyX402ArcScript is Script {
    function run() external view {
        address registryProxy = vm.envAddress("SET_REGISTRY_ADDRESS");
        address paymentBatchProxy = vm.envAddress("SET_PAYMENT_BATCH_ADDRESS");

        console.log("Verifying x402 contracts on Arc Testnet...");
        console.log("");

        SetRegistry registry = SetRegistry(registryProxy);
        SetPaymentBatch paymentBatch = SetPaymentBatch(paymentBatchProxy);

        console.log("SetRegistry at ", registryProxy);
        console.log("  Owner:    ", registry.owner());

        console.log("");
        console.log("SetPaymentBatch at ", paymentBatchProxy);
        console.log("  Owner:    ", paymentBatch.owner());
        console.log("  Sequencer count: ", paymentBatch.sequencerCount());
    }
}
