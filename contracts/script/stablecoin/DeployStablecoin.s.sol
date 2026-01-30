// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../stablecoin/TokenRegistry.sol";
import "../../stablecoin/NAVOracle.sol";
import "../../stablecoin/SSDC.sol";
import "../../stablecoin/wSSDC.sol";
import "../../stablecoin/TreasuryVault.sol";

/**
 * @title DeployStablecoin
 * @notice Deploys the full SSDC stablecoin system
 *
 * Usage:
 *   forge script script/stablecoin/DeployStablecoin.s.sol:DeployStablecoin \
 *     --rpc-url $RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     -vvvv
 *
 * Environment variables:
 *   - OWNER: Owner address (defaults to deployer)
 *   - NAV_ATTESTOR: NAV attestor address (defaults to owner)
 *   - USDC_ADDRESS: Bridged USDC address
 *   - USDT_ADDRESS: Bridged USDT address
 */
contract DeployStablecoin is Script {
    // Deployed contracts
    TokenRegistry public tokenRegistry;
    NAVOracle public navOracle;
    SSDC public ssdc;
    wSSDC public wssdc;
    TreasuryVault public treasury;

    function run() external {
        // Get configuration
        address deployer = msg.sender;
        address owner = vm.envOr("OWNER", deployer);
        address attestor = vm.envOr("NAV_ATTESTOR", owner);
        address usdcAddress = vm.envOr("USDC_ADDRESS", address(0));
        address usdtAddress = vm.envOr("USDT_ADDRESS", address(0));

        console.log("Deploying SSDC Stablecoin System");
        console.log("=================================");
        console.log("Deployer:", deployer);
        console.log("Owner:", owner);
        console.log("NAV Attestor:", attestor);
        console.log("USDC:", usdcAddress);
        console.log("USDT:", usdtAddress);
        console.log("");

        vm.startBroadcast();

        // 1. Deploy TokenRegistry
        console.log("1. Deploying TokenRegistry...");
        TokenRegistry registryImpl = new TokenRegistry();
        tokenRegistry = TokenRegistry(address(new ERC1967Proxy(
            address(registryImpl),
            abi.encodeCall(TokenRegistry.initialize, (owner))
        )));
        console.log("   Implementation:", address(registryImpl));
        console.log("   Proxy:", address(tokenRegistry));

        // 2. Deploy NAVOracle
        console.log("2. Deploying NAVOracle...");
        NAVOracle oracleImpl = new NAVOracle();
        navOracle = NAVOracle(address(new ERC1967Proxy(
            address(oracleImpl),
            abi.encodeCall(NAVOracle.initialize, (owner, attestor, 24 hours))
        )));
        console.log("   Implementation:", address(oracleImpl));
        console.log("   Proxy:", address(navOracle));

        // 3. Deploy SSDC
        console.log("3. Deploying SSDC...");
        SSDC ssdcImpl = new SSDC();
        ssdc = SSDC(address(new ERC1967Proxy(
            address(ssdcImpl),
            abi.encodeCall(SSDC.initialize, (owner, address(navOracle)))
        )));
        console.log("   Implementation:", address(ssdcImpl));
        console.log("   Proxy:", address(ssdc));

        // 4. Deploy wSSDC
        console.log("4. Deploying wSSDC...");
        wSSDC wssdcImpl = new wSSDC();
        wssdc = wSSDC(address(new ERC1967Proxy(
            address(wssdcImpl),
            abi.encodeCall(wSSDC.initialize, (owner, address(ssdc)))
        )));
        console.log("   Implementation:", address(wssdcImpl));
        console.log("   Proxy:", address(wssdc));

        // 5. Deploy TreasuryVault
        console.log("5. Deploying TreasuryVault...");
        TreasuryVault treasuryImpl = new TreasuryVault();
        treasury = TreasuryVault(address(new ERC1967Proxy(
            address(treasuryImpl),
            abi.encodeCall(TreasuryVault.initialize, (
                owner,
                address(tokenRegistry),
                address(navOracle),
                address(ssdc)
            ))
        )));
        console.log("   Implementation:", address(treasuryImpl));
        console.log("   Proxy:", address(treasury));

        // 6. Wire up contracts
        console.log("6. Wiring contracts...");
        ssdc.setTreasuryVault(address(treasury));
        navOracle.setSSDC(address(ssdc));
        console.log("   SSDC.treasuryVault set");
        console.log("   NAVOracle.SSDC set");

        // 7. Register tokens in registry
        console.log("7. Registering tokens...");

        // Register SSDC
        tokenRegistry.registerToken(
            address(ssdc),
            "StateSet Dollar Coin",
            "SSDC",
            18,
            ITokenRegistry.TokenCategory.NATIVE,
            ITokenRegistry.TrustLevel.TRUSTED,
            false,
            ""
        );
        console.log("   Registered SSDC");

        // Register wSSDC
        tokenRegistry.registerToken(
            address(wssdc),
            "Wrapped StateSet Dollar Coin",
            "wSSDC",
            18,
            ITokenRegistry.TokenCategory.NATIVE,
            ITokenRegistry.TrustLevel.TRUSTED,
            false,
            ""
        );
        console.log("   Registered wSSDC");

        // Register USDC if provided
        if (usdcAddress != address(0)) {
            tokenRegistry.registerToken(
                usdcAddress,
                "USD Coin",
                "USDC",
                6,
                ITokenRegistry.TokenCategory.BRIDGED,
                ITokenRegistry.TrustLevel.TRUSTED,
                true,
                ""
            );
            console.log("   Registered USDC as collateral");
        }

        // Register USDT if provided
        if (usdtAddress != address(0)) {
            tokenRegistry.registerToken(
                usdtAddress,
                "Tether USD",
                "USDT",
                6,
                ITokenRegistry.TokenCategory.BRIDGED,
                ITokenRegistry.TrustLevel.TRUSTED,
                true,
                ""
            );
            console.log("   Registered USDT as collateral");
        }

        vm.stopBroadcast();

        // Print summary
        console.log("");
        console.log("=================================");
        console.log("Deployment Complete!");
        console.log("=================================");
        console.log("");
        console.log("Contract Addresses:");
        console.log("  TokenRegistry:", address(tokenRegistry));
        console.log("  NAVOracle:", address(navOracle));
        console.log("  SSDC:", address(ssdc));
        console.log("  wSSDC:", address(wssdc));
        console.log("  TreasuryVault:", address(treasury));
        console.log("");
        console.log("Next Steps:");
        console.log("  1. Transfer ownership to timelock (if not already owner)");
        console.log("  2. Configure NAV attestor(s)");
        console.log("  3. Add collateral tokens if not provided");
        console.log("  4. Submit initial NAV attestation");
        console.log("  5. Verify contracts on block explorer");
    }
}

/**
 * @title ConfigureStablecoin
 * @notice Post-deployment configuration for SSDC system
 */
contract ConfigureStablecoin is Script {
    function run() external {
        address tokenRegistry = vm.envAddress("TOKEN_REGISTRY");
        address treasury = vm.envAddress("TREASURY_VAULT");
        address timelock = vm.envAddress("TIMELOCK");
        address operator = vm.envOr("OPERATOR", address(0));

        vm.startBroadcast();

        // Set operator if provided
        if (operator != address(0)) {
            TreasuryVault(treasury).setOperator(operator, true);
            console.log("Set operator:", operator);
        }

        // Transfer ownership to timelock
        if (timelock != address(0)) {
            TokenRegistry(tokenRegistry).transferOwnership(timelock);
            TreasuryVault(treasury).transferOwnership(timelock);
            console.log("Transferred ownership to timelock:", timelock);
        }

        vm.stopBroadcast();
    }
}
