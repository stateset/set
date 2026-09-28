// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../commerce/protection/ArbiterRegistry.sol";
import "../commerce/protection/ProtectedPayments.sol";

/// Deploys the protected-payments dispute network for one stablecoin:
///
///   1. ArbiterRegistry   — bonded, slashable arbiters (governing layer)
///   2. ProtectedPayments — disputes, merchant responses, reserve-backed chargebacks
///
/// Grants the registry's COURT_ROLE to ProtectedPayments, allowlists the token and
/// wires SetRegistry as the VES evidence verifier. Local-devnet defaults only;
/// production needs reviewed parameters and a timelock admin.
///
/// Reads from env:
///   DEPLOYER_PRIVATE_KEY   default: anvil[0]
///   STABLECOIN_ADDRESS     required
///   SET_REGISTRY_ADDRESS   default: 0xe7f1725e7734ce288f8367e1bb143e90bb3f0512
///   ADMIN_ADDRESS          default: deployer
///   FEE_RECIPIENT          default: admin
///   DEFAULT_ARBITER        default: unset (no fallback arbiter)
contract DeployProtectedPayments is Script {
    function run() external returns (ArbiterRegistry registry, ProtectedPayments pp) {
        uint256 deployerKey = vm.envOr(
            "DEPLOYER_PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address deployer = vm.addr(deployerKey);
        address stablecoin = vm.envAddress("STABLECOIN_ADDRESS");
        address setRegistry = vm.envOr("SET_REGISTRY_ADDRESS", address(0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512));
        address admin = vm.envOr("ADMIN_ADDRESS", deployer);
        address feeRecipient = vm.envOr("FEE_RECIPIENT", admin);
        address defaultArbiter = vm.envOr("DEFAULT_ARBITER", address(0));

        vm.startBroadcast(deployerKey);

        // 6-decimal stablecoin units.
        registry = new ArbiterRegistry(IERC20(stablecoin), deployer, 1_000e6, 100e6, 14 days, feeRecipient);
        pp = new ProtectedPayments(
            registry,
            deployer,
            feeRecipient,
            ProtectedPayments.Params({
                minProtectionWindow: 1 days,
                maxProtectionWindow: 120 days,
                merchantResponseWindow: 3 days,
                arbitrationWindow: 7 days,
                // Mirrors card-network dispute monitoring: 0.9% after 100 payments.
                maxDisputeRatioBps: 90,
                minPaymentsForRatio: 100
            })
        );

        registry.grantRole(registry.COURT_ROLE(), address(pp));
        pp.setTokenConfig(
            stablecoin,
            ProtectedPayments.TokenConfig({
                enabled: true,
                protocolFeeBps: 50,
                protectionFeeBps: 50,
                buyerDisputeBond: 10e6,
                arbitrationFee: 10e6
            })
        );
        if (setRegistry.code.length > 0) pp.setEvidenceVerifier(IVesInclusionVerifier(setRegistry));
        if (defaultArbiter != address(0)) {
            registry.setApproved(defaultArbiter, true);
            pp.setDefaultArbiter(defaultArbiter);
        }

        if (admin != deployer) {
            registry.grantRole(registry.DEFAULT_ADMIN_ROLE(), admin);
            pp.grantRole(pp.DEFAULT_ADMIN_ROLE(), admin);
            pp.grantRole(pp.UNDERWRITER_ROLE(), admin);
            pp.grantRole(pp.PAUSER_ROLE(), admin);
            pp.renounceRole(pp.PAUSER_ROLE(), deployer);
            pp.renounceRole(pp.UNDERWRITER_ROLE(), deployer);
            pp.renounceRole(pp.DEFAULT_ADMIN_ROLE(), deployer);
            registry.renounceRole(registry.DEFAULT_ADMIN_ROLE(), deployer);
        }

        vm.stopBroadcast();

        console.log("ArbiterRegistry   ", address(registry));
        console.log("ProtectedPayments ", address(pp));
    }
}
