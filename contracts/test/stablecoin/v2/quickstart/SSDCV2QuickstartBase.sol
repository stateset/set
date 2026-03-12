// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title SSDC V2 Quickstart Base — Shared Scaffold for All Quickstart Examples
/// @notice Provides a fully-wired SSDC V2 deployment with 3 AI agent wallets,
///         a circuit breaker, cross-chain bridge, status lens, and claim queue.
///         Extend this in your own tests to get a ready-to-go environment.

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {GroundingRegistryV2} from "../../../../stablecoin/v2/GroundingRegistryV2.sol";
import {NAVControllerV2} from "../../../../stablecoin/v2/NAVControllerV2.sol";
import {SSDCClaimQueueV2} from "../../../../stablecoin/v2/SSDCClaimQueueV2.sol";
import {SSDCPolicyModuleV2} from "../../../../stablecoin/v2/SSDCPolicyModuleV2.sol";
import {SSDCStatusLensV2} from "../../../../stablecoin/v2/SSDCStatusLensV2.sol";
import {SSDCVaultGatewayV2} from "../../../../stablecoin/v2/SSDCVaultGatewayV2.sol";
import {SSDCV2CircuitBreaker} from "../../../../stablecoin/v2/SSDCV2CircuitBreaker.sol";
import {WSSDCCrossChainBridgeV2} from "../../../../stablecoin/v2/WSSDCCrossChainBridgeV2.sol";
import {YieldEscrowV2} from "../../../../stablecoin/v2/YieldEscrowV2.sol";
import {YieldPaymasterV2} from "../../../../stablecoin/v2/YieldPaymasterV2.sol";
import {wSSDCVaultV2} from "../../../../stablecoin/v2/wSSDCVaultV2.sol";
import {IETHUSDOracleV2} from "../../../../stablecoin/v2/interfaces/IETHUSDOracleV2.sol";

// ─── Mocks ──────────────────────────────────────────────────────────────────

contract MockUSD is ERC20 {
    constructor() ERC20("Mock Settlement USD", "mUSD") {}
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract MockOracle {
    uint256 public priceE18;
    uint256 public updatedAt;
    function setPrice(uint256 p) external { priceE18 = p; updatedAt = block.timestamp; }
    function latestPrice() external view returns (uint256, uint256) { return (priceE18, updatedAt); }
}

// ─── Base ───────────────────────────────────────────────────────────────────

contract SSDCV2QuickstartBase is Test {

    // ─── Glossary ───────────────────────────────────────────────────────
    //
    //  RAY            1e27 - fixed-point unit for NAV values (e.g. 1.0 = 1e27, 1.05 = 105e25)
    //  NAV            Net Asset Value - the price of 1 wSSDC share in settlement assets
    //  buyerBps       Basis points (1 bp = 0.01%) of escrow yield allocated to the buyer
    //                 e.g. 3000 = 30% of net yield goes to buyer, rest to merchant
    //  perTxLimit     Maximum settlement-asset value a single escrow can lock
    //  dailyLimit     Maximum cumulative settlement-asset value an agent can spend in 24h
    //  floor          Minimum wSSDC balance the agent must maintain (collateral floor)
    //  sessionExpiry  Timestamp after which the agent's policy is no longer valid
    //  challengeWindow  Seconds the buyer has to dispute after merchant submits fulfillment
    //  arbiterDeadline  Seconds the arbiter has to resolve a dispute before timeout kicks in
    //  grounded       An agent whose total collateral (wallet + gas tank) < floor
    //  shares         wSSDC vault shares - yield-bearing ERC-20 tokens backed by settlement assets
    //  settlement assets  The underlying USD stablecoin (mUSD, 6 decimals in tests)
    //
    // ─────────────────────────────────────────────────────────────────────

    uint256 internal constant RAY = 1e27;

    // ── Roles ───────────────────────────────────────────────────────────
    address internal admin      = address(0xA11CE);
    address internal oracleAddr = address(0x0A11);
    address internal arbiter    = address(0xA4B1);
    address internal feeCollector = address(0xFEE0);
    address internal entryPoint = address(0x4337);

    // ── AI Agents ───────────────────────────────────────────────────────
    address internal agentAlpha = address(0xA1FA);  // procurement AI
    address internal agentBeta  = address(0xBE7A);  // supplier AI
    address internal agentGamma = address(0x6A3A);  // logistics AI

    // ── Contracts ───────────────────────────────────────────────────────
    MockUSD internal asset;
    MockOracle internal priceOracle;
    NAVControllerV2 internal nav;
    wSSDCVaultV2 internal vault;
    SSDCVaultGatewayV2 internal gateway;
    SSDCClaimQueueV2 internal queue;
    SSDCPolicyModuleV2 internal policy;
    GroundingRegistryV2 internal grounding;
    YieldEscrowV2 internal escrow;
    YieldPaymasterV2 internal paymaster;
    WSSDCCrossChainBridgeV2 internal bridge;
    SSDCV2CircuitBreaker internal breaker;
    SSDCStatusLensV2 internal lens;

    function setUp() public virtual {
        vm.startPrank(admin);

        // ── Core ────────────────────────────────────────────────────────
        asset = new MockUSD();
        nav = new NAVControllerV2(
            admin,
            RAY,       // initial NAV = 1.0
            9e26,      // minNavRay
            1e23,      // maxRateAbsRay
            48 hours,  // maxStaleness
            2_000,     // maxNavJumpBps (20%)
            3          // staleRecoveryJumpMultiplier
        );
        vault = new wSSDCVaultV2(asset, nav, admin);

        priceOracle = new MockOracle();
        priceOracle.setPrice(3_000e18); // ETH = $3,000

        // ── Modules ─────────────────────────────────────────────────────
        gateway = new SSDCVaultGatewayV2(vault, admin);
        queue = new SSDCClaimQueueV2(vault, IERC20(address(asset)), admin);
        policy = new SSDCPolicyModuleV2(admin);
        grounding = new GroundingRegistryV2(policy, nav, vault, admin);
        escrow = new YieldEscrowV2(vault, nav, policy, grounding, admin, feeCollector);
        paymaster = new YieldPaymasterV2(
            vault, nav, policy, grounding,
            IETHUSDOracleV2(address(priceOracle)),
            entryPoint, admin, feeCollector
        );
        bridge = new WSSDCCrossChainBridgeV2(vault, nav, admin);
        breaker = new SSDCV2CircuitBreaker(nav, vault, queue, bridge, escrow, paymaster, admin);
        lens = new SSDCStatusLensV2(nav, vault, queue, bridge, escrow, paymaster);

        // ── Wiring ──────────────────────────────────────────────────────
        nav.grantRole(nav.ORACLE_ROLE(), oracleAddr);
        nav.grantRole(nav.BRIDGE_ROLE(), address(bridge));

        vault.grantRole(vault.GATEWAY_ROLE(), address(gateway));
        vault.grantRole(vault.GATEWAY_ROLE(), address(queue));
        vault.grantRole(vault.QUEUE_ROLE(), address(queue));
        vault.grantRole(vault.BRIDGE_ROLE(), address(bridge));
        vault.grantRole(vault.PAUSER_ROLE(), address(breaker));
        vault.setGatewayRequired(true);

        escrow.grantRole(escrow.FUNDER_ROLE(), address(gateway));
        escrow.grantRole(escrow.ARBITER_ROLE(), arbiter);
        escrow.grantRole(escrow.PAUSER_ROLE(), address(breaker));
        escrow.setProtocolFee(100, feeCollector);   // 1%
        escrow.setReserveConfig(200, feeCollector);  // 2%

        policy.grantRole(policy.POLICY_CONSUMER_ROLE(), address(escrow));
        policy.grantRole(policy.POLICY_CONSUMER_ROLE(), address(paymaster));
        grounding.setCollateralProvider(address(paymaster), true);

        queue.grantRole(queue.PAUSER_ROLE(), address(breaker));

        bridge.grantRole(bridge.PAUSER_ROLE(), address(breaker));

        nav.grantRole(nav.PAUSER_ROLE(), address(breaker));

        paymaster.grantRole(paymaster.PAUSER_ROLE(), address(breaker));

        vm.stopPrank();
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    /// @notice Mint settlement assets, deposit via gateway, return shares.
    function _fundAgent(address agent, uint256 assets) internal returns (uint256 shares) {
        asset.mint(agent, assets);
        vm.startPrank(agent);
        asset.approve(address(gateway), type(uint256).max);
        shares = gateway.deposit(assets, agent, 0);
        vm.stopPrank();
    }

    /// @notice Configure an agent's spend policy and merchant allowlist.
    function _configureAgent(
        address agent,
        uint256 perTx,
        uint256 daily,
        uint256 floor,
        uint40 sessionExpiry,
        bool enforceAllowlist,
        address[] memory allowedMerchants
    ) internal {
        vm.startPrank(admin);
        policy.setPolicy(agent, perTx, daily, floor, sessionExpiry, enforceAllowlist);
        for (uint256 i = 0; i < allowedMerchants.length; i++) {
            policy.setMerchantAllowed(agent, allowedMerchants[i], true);
        }
        vm.stopPrank();
    }

    /// @notice Update NAV to a new value with zero forward rate.
    function _updateNAV(uint256 navRay) internal {
        uint64 epoch = nav.navEpoch() + 1;
        vm.prank(oracleAddr);
        nav.updateNAV(navRay, int256(0), epoch);
    }

    /// @notice Update NAV with a forward rate (ray-precision per second).
    function _updateNAVWithRate(uint256 navRay, int256 ratePerSecond) internal {
        uint64 epoch = nav.navEpoch() + 1;
        vm.prank(oracleAddr);
        nav.updateNAV(navRay, ratePerSecond, epoch);
    }

    /// @notice Simulate the EntryPoint charging gas for an agent operation.
    function _chargeGas(address agent, bytes32 opKey, uint256 gasCostWei) internal returns (uint256 charged) {
        priceOracle.setPrice(3_000e18);
        vm.prank(entryPoint);
        paymaster.validatePaymasterUserOp(opKey, agent, gasCostWei);
        vm.prank(entryPoint);
        charged = paymaster.postOp(opKey, agent, gasCostWei);
    }

    /// @notice Build simple invoice terms for a non-fulfillment escrow.
    function _simpleInvoice(uint256 assetsDue) internal view returns (YieldEscrowV2.InvoiceTerms memory) {
        return YieldEscrowV2.InvoiceTerms({
            assetsDue: assetsDue,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp + 1 hours),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: false,
            fulfillmentType: YieldEscrowV2.FulfillmentType.NONE,
            requiredMilestones: 0,
            challengeWindow: 0,
            arbiterDeadline: 0,
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.NONE
        });
    }

    /// @notice Build invoice terms with fulfillment milestones.
    function _milestoneInvoice(
        uint256 assetsDue,
        YieldEscrowV2.FulfillmentType fType,
        uint8 milestones,
        uint40 challengeWindow,
        uint40 arbiterDeadline
    ) internal view returns (YieldEscrowV2.InvoiceTerms memory) {
        return YieldEscrowV2.InvoiceTerms({
            assetsDue: assetsDue,
            expiry: uint40(block.timestamp + 1 days),
            releaseAfter: uint40(block.timestamp + 1 hours),
            maxNavAge: uint40(48 hours),
            maxSharesIn: type(uint256).max,
            requiresFulfillment: true,
            fulfillmentType: fType,
            requiredMilestones: milestones,
            challengeWindow: challengeWindow,
            arbiterDeadline: arbiterDeadline,
            disputeTimeoutResolution: YieldEscrowV2.DisputeResolution.REFUND
        });
    }
}
