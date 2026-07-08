// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {NAVControllerV2} from "./NAVControllerV2.sol";
import {wSSDCVaultV2} from "./wSSDCVaultV2.sol";
import {SSDCClaimQueueV2} from "./SSDCClaimQueueV2.sol";
import {WSSDCCrossChainBridgeV2} from "./WSSDCCrossChainBridgeV2.sol";
import {YieldEscrowV2} from "./YieldEscrowV2.sol";
import {YieldPaymasterV2} from "./YieldPaymasterV2.sol";
import {ProofOfReservesV2} from "./ProofOfReservesV2.sol";

/// @title SSDCV2CircuitBreaker
/// @notice Global emergency shutdown for the SSDC v2 system.
/// @dev A single call to `tripBreaker()` atomically pauses all subsystems.
///      Recovery requires calling `resetBreaker()` which only unpauses components
///      that were paused by the breaker (not manually paused beforehand).
contract SSDCV2CircuitBreaker is AccessControl {
    bytes32 public constant BREAKER_ROLE = keccak256("BREAKER_ROLE");

    NAVControllerV2 public immutable navController;
    wSSDCVaultV2 public immutable vault;
    SSDCClaimQueueV2 public immutable queue;
    WSSDCCrossChainBridgeV2 public immutable bridge;
    YieldEscrowV2 public immutable escrow;
    YieldPaymasterV2 public immutable paymaster;

    bool public breakerTripped;

    /// @notice Optional reserve-solvency oracle. When set, anyone may trip the breaker via
    ///         `tripIfInsolvent()` if reserves are provably insufficient. Settable so wiring it in
    ///         does not require redeploying the breaker.
    ProofOfReservesV2 public proofOfReserves;

    // Track which components were paused by us vs already paused
    bool public navWasPaused;
    bool public vaultWasPaused;
    bool public queueWasPaused;
    bool public bridgeWasPaused;
    bool public escrowWasPaused;
    bool public paymasterWasPaused;

    error ZeroAddress();
    error BREAKER_ALREADY_TRIPPED();
    error BREAKER_NOT_TRIPPED();
    error PROOF_NOT_SET();
    error RESERVES_SOLVENT();

    event BreakerTripped(address indexed caller, uint256 timestamp);
    event BreakerReset(address indexed caller, uint256 timestamp);
    event ProofOfReservesSet(address indexed proofOfReserves);
    event BreakerTrippedInsolvent(address indexed caller, uint256 coverageRatioBps);

    constructor(
        NAVControllerV2 navController_,
        wSSDCVaultV2 vault_,
        SSDCClaimQueueV2 queue_,
        WSSDCCrossChainBridgeV2 bridge_,
        YieldEscrowV2 escrow_,
        YieldPaymasterV2 paymaster_,
        address admin
    ) {
        if (admin == address(0)) revert ZeroAddress();

        navController = navController_;
        vault = vault_;
        queue = queue_;
        bridge = bridge_;
        escrow = escrow_;
        paymaster = paymaster_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(BREAKER_ROLE, admin);
    }

    /// @notice Atomically pauses all SSDC v2 subsystems.
    /// @dev Saves pre-trip pause state so resetBreaker only unpauses what the breaker paused.
    function tripBreaker() external onlyRole(BREAKER_ROLE) {
        _trip();
        emit BreakerTripped(msg.sender, block.timestamp);
    }

    /// @notice Permissionless emergency trip when reserves are provably insufficient.
    /// @dev Fires only on a FRESH attestation whose coverage is below the configured floor — i.e.
    ///      reserves are demonstrably gone, not merely stale. Staleness is intentionally excluded so
    ///      this cannot be used to grief the system during normal attestation gaps. Requires the
    ///      breaker to hold the pause roles on each subsystem, same as tripBreaker().
    function tripIfInsolvent() external {
        ProofOfReservesV2 por = proofOfReserves;
        if (address(por) == address(0)) {
            revert PROOF_NOT_SET();
        }
        // Must have a fresh attestation that is below the coverage floor.
        if (por.isStale() || !por.hasAttestation() || por.coverageRatioBps() >= por.minCoverageBps()) {
            revert RESERVES_SOLVENT();
        }

        _trip();
        emit BreakerTrippedInsolvent(msg.sender, por.coverageRatioBps());
    }

    /// @notice Wire in (or replace) the reserve-solvency oracle consumed by tripIfInsolvent().
    function setProofOfReserves(ProofOfReservesV2 proofOfReserves_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        proofOfReserves = proofOfReserves_;
        emit ProofOfReservesSet(address(proofOfReserves_));
    }

    /// @dev Atomically pauses all subsystems, recording pre-trip pause state.
    function _trip() internal {
        if (breakerTripped) {
            revert BREAKER_ALREADY_TRIPPED();
        }

        // Snapshot current pause state
        navWasPaused = navController.navUpdatesPaused();
        vaultWasPaused = vault.mintRedeemPaused();
        queueWasPaused = queue.queueOpsPaused();
        bridgeWasPaused = bridge.bridgePaused();
        escrowWasPaused = escrow.escrowOpsPaused();
        paymasterWasPaused = paymaster.paymasterPaused();

        // Pause everything
        if (!navWasPaused) {
            navController.setNavUpdatesPaused(true);
        }
        if (!vaultWasPaused) {
            vault.setMintRedeemPaused(true);
        }
        if (!queueWasPaused) {
            queue.setQueueOpsPaused(true);
        }
        if (!bridgeWasPaused) {
            bridge.setBridgePaused(true);
        }
        if (!escrowWasPaused) {
            escrow.setEscrowOpsPaused(true);
        }
        if (!paymasterWasPaused) {
            paymaster.setPaymasterPaused(true);
        }

        breakerTripped = true;
    }

    /// @notice Unpauses only components that were paused by the breaker.
    function resetBreaker() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!breakerTripped) {
            revert BREAKER_NOT_TRIPPED();
        }

        if (!navWasPaused) {
            navController.setNavUpdatesPaused(false);
        }
        if (!vaultWasPaused) {
            vault.setMintRedeemPaused(false);
        }
        if (!queueWasPaused) {
            queue.setQueueOpsPaused(false);
        }
        if (!bridgeWasPaused) {
            bridge.setBridgePaused(false);
        }
        if (!escrowWasPaused) {
            escrow.setEscrowOpsPaused(false);
        }
        if (!paymasterWasPaused) {
            paymaster.setPaymasterPaused(false);
        }

        breakerTripped = false;
        emit BreakerReset(msg.sender, block.timestamp);
    }
}
