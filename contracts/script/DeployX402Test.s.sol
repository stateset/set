// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../SetRegistry.sol";
import "../commerce/SetPaymentBatch.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @notice Simple ERC20 for testing x402 payments
 */
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title DeployX402Test
 * @notice Deploys full x402 test environment including mock tokens
 *
 * Usage:
 *   forge script script/DeployX402Test.s.sol --rpc-url http://localhost:8545 --broadcast
 */
contract DeployX402TestScript is Script {
    // Deployed addresses
    address public registryProxy;
    address public paymentBatchProxy;
    address public mockUsdc;
    address public mockSsUsd;

    // Test accounts (Anvil defaults)
    address constant DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address constant SEQUENCER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address constant PAYER = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address constant PAYEE = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;

    function run() external {
        uint256 deployerPrivateKey = vm.envOr(
            "DEPLOYER_PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );

        address deployer = vm.addr(deployerPrivateKey);

        console.log("===========================================");
        console.log("  x402 Test Environment Deployment");
        console.log("===========================================");
        console.log("");
        console.log("Deployer:  ", deployer);
        console.log("Sequencer: ", SEQUENCER);
        console.log("Payer:     ", PAYER);
        console.log("Payee:     ", PAYEE);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Mock Tokens
        console.log("Deploying Mock USDC...");
        MockERC20 usdc = new MockERC20("Mock USDC", "USDC", 6);
        mockUsdc = address(usdc);
        console.log("  USDC:    ", mockUsdc);

        console.log("Deploying Mock ssUSD...");
        MockERC20 ssUsd = new MockERC20("StateSet USD", "ssUSD", 18);
        mockSsUsd = address(ssUsd);
        console.log("  ssUSD:   ", mockSsUsd);

        // 2. Mint tokens to payer
        console.log("");
        console.log("Minting tokens to payer...");
        usdc.mint(PAYER, 1_000_000 * 1e6);  // 1M USDC
        ssUsd.mint(PAYER, 1_000_000 * 1e18); // 1M ssUSD
        console.log("  Payer USDC balance:  ", usdc.balanceOf(PAYER));
        console.log("  Payer ssUSD balance: ", ssUsd.balanceOf(PAYER));

        // 3. Deploy SetRegistry
        console.log("");
        console.log("Deploying SetRegistry...");
        address registryImpl = address(new SetRegistry());
        bytes memory registryInitData = abi.encodeCall(
            SetRegistry.initialize,
            (deployer, SEQUENCER)
        );
        registryProxy = address(new ERC1967Proxy(registryImpl, registryInitData));
        console.log("  Registry: ", registryProxy);

        // 4. Deploy SetPaymentBatch
        console.log("");
        console.log("Deploying SetPaymentBatch...");
        address paymentBatchImpl = address(new SetPaymentBatch());
        bytes memory paymentBatchInitData = abi.encodeCall(
            SetPaymentBatch.initialize,
            (deployer, SEQUENCER, mockUsdc, mockSsUsd, registryProxy)
        );
        paymentBatchProxy = address(new ERC1967Proxy(paymentBatchImpl, paymentBatchInitData));
        console.log("  PaymentBatch: ", paymentBatchProxy);

        vm.stopBroadcast();

        // Need to approve PaymentBatch to spend payer's tokens
        // This requires payer's private key
        uint256 payerPrivateKey = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
        vm.startBroadcast(payerPrivateKey);

        console.log("");
        console.log("Setting up payer approvals...");
        usdc.approve(paymentBatchProxy, type(uint256).max);
        ssUsd.approve(paymentBatchProxy, type(uint256).max);
        console.log("  Payer approved PaymentBatch for USDC and ssUSD");

        vm.stopBroadcast();

        // Summary
        console.log("");
        console.log("===========================================");
        console.log("  Deployment Complete!");
        console.log("===========================================");
        console.log("");
        console.log("# Environment Variables for Sequencer:");
        console.log("export SET_REGISTRY_ADDRESS=", registryProxy);
        console.log("export SET_PAYMENT_BATCH_ADDRESS=", paymentBatchProxy);
        console.log("export MOCK_USDC_ADDRESS=", mockUsdc);
        console.log("export MOCK_SSUSD_ADDRESS=", mockSsUsd);
        console.log("");
        console.log("# Test Accounts:");
        console.log("DEPLOYER=", DEPLOYER);
        console.log("SEQUENCER=", SEQUENCER);
        console.log("PAYER=", PAYER);
        console.log("PAYEE=", PAYEE);
        console.log("");
    }
}
