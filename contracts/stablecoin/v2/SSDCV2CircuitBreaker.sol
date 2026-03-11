// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {NAVControllerV2} from "./NAVControllerV2.sol";
import {wSSDCVaultV2} from "./wSSDCVaultV2.sol";
import {SSDCClaimQueueV2} from "./SSDCClaimQueueV2.sol";
import {WSSDCCrossChainBridgeV2} from "./WSSDCCrossChainBridgeV2.sol";
import {YieldEscrowV2} from "./YieldEscrowV2.sol";
import {YieldPaymasterV2} from "./YieldPaymasterV2.sol";

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

    // Track which components were paused by us vs already paused
    bool public navWasPaused;
    bool public vaultWasPaused;
    bool public queueWasPaused;
    bool public bridgeWasPaused;
    bool public escrowWasPaused;
    bool public paymasterWasPaused;

    error BREAKER_ALREADY_TRIPPED();
    error BREAKER_NOT_TRIPPED();

    event BreakerTripped(address indexed caller, uint256 timestamp);
    event BreakerReset(address indexed caller, uint256 timestamp);

    constructor(
        NAVControllerV2 navController_,
        wSSDCVaultV2 vault_,
        SSDCClaimQueueV2 queue_,
        WSSDCCrossChainBridgeV2 bridge_,
        YieldEscrowV2 escrow_,
        YieldPaymasterV2 paymaster_,
        address admin
    ) {
        require(admin != address(0), "admin=0");

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
        emit BreakerTripped(msg.sender, block.timestamp);
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
