// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {NAVControllerV2} from "./NAVControllerV2.sol";
import {SSDCClaimQueueV2} from "./SSDCClaimQueueV2.sol";
import {WSSDCCrossChainBridgeV2} from "./WSSDCCrossChainBridgeV2.sol";
import {wSSDCVaultV2} from "./wSSDCVaultV2.sol";

contract SSDCStatusLensV2 {
    struct Status {
        bool transfersAllowed;
        bool navFresh;
        bool navConversionsAllowed;
        bool mintDepositAllowed;
        bool redeemWithdrawAllowed;
        bool requestRedeemAllowed;
        bool processQueueAllowed;
        bool bridgingAllowed;
        uint256 navRay;
    }

    NAVControllerV2 public immutable navController;
    wSSDCVaultV2 public immutable vault;
    SSDCClaimQueueV2 public immutable queue;
    WSSDCCrossChainBridgeV2 public immutable bridge;

    constructor(
        NAVControllerV2 navController_,
        wSSDCVaultV2 vault_,
        SSDCClaimQueueV2 queue_,
        WSSDCCrossChainBridgeV2 bridge_
    ) {
        navController = navController_;
        vault = vault_;
        queue = queue_;
        bridge = bridge_;
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
        status.mintDepositAllowed = navUsable && !mintRedeemPaused;
        status.redeemWithdrawAllowed = navUsable && !mintRedeemPaused;
        status.requestRedeemAllowed = navUsable && !mintRedeemPaused && !queuePaused;
        status.processQueueAllowed = navUsable && !mintRedeemPaused && !queuePaused;
        status.bridgingAllowed = !bridgePaused;
        status.navRay = navUsable ? navRay : 0;
    }
}
