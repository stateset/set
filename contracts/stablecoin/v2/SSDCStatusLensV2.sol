// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {NAVControllerV2} from "./NAVControllerV2.sol";
import {SSDCClaimQueueV2} from "./SSDCClaimQueueV2.sol";
import {WSSDCCrossChainBridgeV2} from "./WSSDCCrossChainBridgeV2.sol";
import {YieldEscrowV2} from "./YieldEscrowV2.sol";
import {YieldPaymasterV2} from "./YieldPaymasterV2.sol";
import {wSSDCVaultV2} from "./wSSDCVaultV2.sol";

contract SSDCStatusLensV2 {
    error ZeroAddress();

    struct Status {
        bool transfersAllowed;
        bool navFresh;
        bool navConversionsAllowed;
        bool navUpdatesPaused;
        bool mintDepositAllowed;
        bool redeemWithdrawAllowed;
        bool requestRedeemAllowed;
        bool processQueueAllowed;
        bool queueSkipsBlockedClaims;
        bool bridgingAllowed;
        bool bridgeMintAllowed;
        bool gatewayRequired;
        bool escrowOpsPaused;
        bool paymasterPaused;
        uint256 bridgeOutstandingShares;
        uint256 bridgeOutstandingLimitShares;
        uint256 bridgeRemainingCapacityShares;
        uint256 minBridgeLiquidityCoverageBps;
        uint256 liabilityAssets;
        uint256 settlementAssetsAvailable;
        uint256 queueBufferAvailable;
        uint256 queueReservedAssets;
        uint256 queueDepth;
        uint256 liquidityCoverageBps;
        uint256 navRay;
        uint64 navEpoch;
        uint40 navLastUpdate;
        uint256 totalShareSupply;
        address reserveManager;
        uint256 reserveFloor;
        uint256 reserveMaxDeployBps;
        uint256 reserveDeployedAssets;
    }

    NAVControllerV2 public immutable navController;
    wSSDCVaultV2 public immutable vault;
    SSDCClaimQueueV2 public immutable queue;
    WSSDCCrossChainBridgeV2 public immutable bridge;
    YieldEscrowV2 public immutable escrow;
    YieldPaymasterV2 public immutable paymaster;

    constructor(
        NAVControllerV2 navController_,
        wSSDCVaultV2 vault_,
        SSDCClaimQueueV2 queue_,
        WSSDCCrossChainBridgeV2 bridge_,
        YieldEscrowV2 escrow_,
        YieldPaymasterV2 paymaster_
    ) {
        if (address(navController_) == address(0)) revert ZeroAddress();
        if (address(vault_) == address(0)) revert ZeroAddress();
        if (address(queue_) == address(0)) revert ZeroAddress();
        if (address(bridge_) == address(0)) revert ZeroAddress();
        if (address(escrow_) == address(0)) revert ZeroAddress();
        if (address(paymaster_) == address(0)) revert ZeroAddress();
        navController = navController_;
        vault = vault_;
        queue = queue_;
        bridge = bridge_;
        escrow = escrow_;
        paymaster = paymaster_;
    }

    function getStatus() external view returns (Status memory status) {
        (uint256 navRay, bool stale) = navController.tryCurrentNAVRay();
        bool navFresh = !stale;
        bool navUsable = navFresh && navRay != 0;

        bool mintRedeemPaused = vault.mintRedeemPaused();
        bool queuePaused = queue.queueOpsPaused();
        bool bridgePaused = bridge.bridgePaused();

        status.transfersAllowed = true;
        status.navFresh = navFresh;
        status.navConversionsAllowed = navUsable;
        status.navUpdatesPaused = navController.navUpdatesPaused();
        status.mintDepositAllowed = navUsable && !mintRedeemPaused;
        status.redeemWithdrawAllowed = navUsable && !mintRedeemPaused;
        status.requestRedeemAllowed = navUsable && !mintRedeemPaused && !queuePaused;
        status.processQueueAllowed = navUsable && !mintRedeemPaused && !queuePaused;
        status.queueSkipsBlockedClaims = queue.skipBlockedClaims();
        status.bridgingAllowed = !bridgePaused;
        status.escrowOpsPaused = escrow.escrowOpsPaused();
        status.paymasterPaused = paymaster.paymasterPaused();
        status.bridgeOutstandingShares = bridge.outstandingShares();
        status.bridgeOutstandingLimitShares = bridge.maxOutstandingShares();
        status.bridgeRemainingCapacityShares = bridge.remainingMintCapacityShares();
        status.minBridgeLiquidityCoverageBps = vault.minBridgeLiquidityCoverageBps();
        status.gatewayRequired = vault.gatewayRequired();
        status.liabilityAssets = vault.totalAssets();
        status.settlementAssetsAvailable = vault.availableSettlementAssets();
        status.queueBufferAvailable = queue.availableAssets();
        status.queueReservedAssets = queue.reservedAssets();
        status.queueDepth = queue.queueDepth();
        status.liquidityCoverageBps = vault.liquidityCoverageBps();
        bool bridgeCoverageSatisfied = status.minBridgeLiquidityCoverageBps == 0
            || (navUsable && status.liquidityCoverageBps >= status.minBridgeLiquidityCoverageBps);
        status.bridgeMintAllowed = !bridgePaused
            && (
                status.bridgeOutstandingLimitShares == 0
                    || status.bridgeOutstandingShares < status.bridgeOutstandingLimitShares
            )
            && bridgeCoverageSatisfied;
        status.navRay = navUsable ? navRay : 0;
        status.navEpoch = navController.navEpoch();
        status.navLastUpdate = navController.lastUpdateTs();
        status.totalShareSupply = vault.totalSupply();
        status.reserveManager = vault.reserveManager();
        status.reserveFloor = vault.reserveFloor();
        status.reserveMaxDeployBps = vault.maxDeployBps();
        status.reserveDeployedAssets = vault.deployedReserveAssets();
    }

    function reserveDeployed() external view returns (uint256) {
        return vault.deployedReserveAssets();
    }
}
