// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {RayMath} from "./RayMath.sol";

contract NAVControllerV2 is AccessControl {
    using RayMath for uint256;

    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public maxStaleness;
    uint256 public targetSmoothingWindow;
    uint256 public minNavRay;
    int256 public maxRateAbsRay;
    uint256 public maxNavJumpBps;

    uint256 public nav0Ray;
    uint40 public t0;
    int256 public ratePerSecondRay;
    uint64 public navEpoch;
    uint40 public lastUpdateTs;

    bool public navUpdatesPaused;

    error NAV_STALE();
    error NAV_BELOW_MIN();
    error NAV_OVERFLOW();
    error EPOCH();
    error NAV_JUMP();
    error INVALID_CONFIG();
    error UPDATES_PAUSED();
    error NAV_T0_IN_FUTURE();
    error RATE_OUT_OF_BOUNDS();

    event NAVUpdated(
        uint64 indexed navEpoch,
        uint256 nav0Ray,
        uint40 t0,
        int256 ratePerSecondRay,
        uint256 attestedNAVRay
    );

    event NAVRelayed(uint64 indexed navEpoch, uint256 nav0Ray, uint40 t0, int256 ratePerSecondRay);
    event NavBoundsUpdated(uint256 minNavRay, int256 maxRateAbsRay, uint256 maxNavJumpBps);
    event TimingConfigUpdated(uint256 maxStaleness, uint256 targetSmoothingWindow);
    event NavUpdatesPausedSet(bool paused);

    constructor(
        address admin,
        uint256 initialNavRay,
        uint256 minNavRay_,
        int256 maxRateAbsRay_,
        uint256 maxStaleness_,
        uint256 targetSmoothingWindow_,
        uint256 maxNavJumpBps_
    ) {
        if (
            admin == address(0) ||
            initialNavRay == 0 ||
            minNavRay_ == 0 ||
            maxStaleness_ == 0 ||
            targetSmoothingWindow_ == 0 ||
            maxRateAbsRay_ <= 0
        ) {
            revert INVALID_CONFIG();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ORACLE_ROLE, admin);
        _grantRole(BRIDGE_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        nav0Ray = initialNavRay;
        t0 = uint40(block.timestamp);
        lastUpdateTs = uint40(block.timestamp);
        navEpoch = 1;

        minNavRay = minNavRay_;
        maxRateAbsRay = maxRateAbsRay_;
        maxStaleness = maxStaleness_;
        targetSmoothingWindow = targetSmoothingWindow_;
        maxNavJumpBps = maxNavJumpBps_;
    }

    function currentNAVRay() public view returns (uint256) {
        (uint256 navRay, bool stale, bool belowMin) = _projectNAV(nav0Ray, t0, ratePerSecondRay);

        if (stale) {
            revert NAV_STALE();
        }
        if (belowMin) {
            revert NAV_BELOW_MIN();
        }
        return navRay;
    }

    function tryCurrentNAVRay() external view returns (uint256 navRay, bool stale) {
        bool belowMin;
        (navRay, stale, belowMin) = _projectNAV(nav0Ray, t0, ratePerSecondRay);
        if (belowMin) {
            return (0, stale);
        }
    }

    function updateNAV(uint256 attestedNAVRay, uint64 newEpoch) external onlyRole(ORACLE_ROLE) {
        if (navUpdatesPaused) {
            revert UPDATES_PAUSED();
        }
        if (newEpoch <= navEpoch) {
            revert EPOCH();
        }
        if (attestedNAVRay < minNavRay) {
            revert NAV_BELOW_MIN();
        }

        (uint256 navCurrent, bool stale, bool belowMin) = _projectNAV(nav0Ray, t0, ratePerSecondRay);

        if (stale || belowMin) {
            nav0Ray = attestedNAVRay;
            t0 = uint40(block.timestamp);
            ratePerSecondRay = 0;
            navEpoch = newEpoch;
            lastUpdateTs = uint40(block.timestamp);

            emit NAVUpdated(newEpoch, attestedNAVRay, t0, 0, attestedNAVRay);
            return;
        }

        if (maxNavJumpBps > 0) {
            uint256 diff = attestedNAVRay > navCurrent ? attestedNAVRay - navCurrent : navCurrent - attestedNAVRay;
            uint256 jumpBps = Math.mulDiv(diff, 10_000, navCurrent, Math.Rounding.Ceil);
            if (jumpBps > maxNavJumpBps) {
                revert NAV_JUMP();
            }
        }

        nav0Ray = navCurrent;
        t0 = uint40(block.timestamp);

        int256 delta = int256(attestedNAVRay) - int256(navCurrent);
        int256 nextRate = delta / int256(targetSmoothingWindow);
        if (nextRate > maxRateAbsRay) {
            nextRate = maxRateAbsRay;
        } else if (nextRate < -maxRateAbsRay) {
            nextRate = -maxRateAbsRay;
        }

        ratePerSecondRay = nextRate;
        navEpoch = newEpoch;
        lastUpdateTs = uint40(block.timestamp);

        emit NAVUpdated(newEpoch, nav0Ray, t0, ratePerSecondRay, attestedNAVRay);
    }

    function relayNAV(uint256 nav0Ray_, uint40 t0_, int256 ratePerSecondRay_, uint64 newEpoch) external onlyRole(BRIDGE_ROLE) {
        if (navUpdatesPaused) {
            revert UPDATES_PAUSED();
        }
        if (newEpoch <= navEpoch) {
            revert EPOCH();
        }
        if (t0_ > block.timestamp) {
            revert NAV_T0_IN_FUTURE();
        }
        if (nav0Ray_ < minNavRay) {
            revert NAV_BELOW_MIN();
        }
        if (ratePerSecondRay_ > maxRateAbsRay || ratePerSecondRay_ < -maxRateAbsRay) {
            revert RATE_OUT_OF_BOUNDS();
        }

        (uint256 relayedNavRay, bool stale, bool belowMin) = _projectNAV(nav0Ray_, t0_, ratePerSecondRay_);
        if (stale) {
            revert NAV_STALE();
        }
        if (belowMin) {
            revert NAV_BELOW_MIN();
        }

        (uint256 localNavRay, bool localStale, bool localBelowMin) = _projectNAV(nav0Ray, t0, ratePerSecondRay);
        if (!localStale && !localBelowMin && maxNavJumpBps > 0) {
            uint256 diff = relayedNavRay > localNavRay ? relayedNavRay - localNavRay : localNavRay - relayedNavRay;
            uint256 jumpBps = Math.mulDiv(diff, 10_000, localNavRay, Math.Rounding.Ceil);
            if (jumpBps > maxNavJumpBps) {
                revert NAV_JUMP();
            }
        }

        nav0Ray = nav0Ray_;
        t0 = t0_;
        ratePerSecondRay = ratePerSecondRay_;
        navEpoch = newEpoch;
        lastUpdateTs = uint40(block.timestamp);

        emit NAVRelayed(newEpoch, nav0Ray_, t0_, ratePerSecondRay_);
    }

    function setNavBounds(uint256 minNavRay_, int256 maxRateAbsRay_, uint256 maxNavJumpBps_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (minNavRay_ == 0 || maxRateAbsRay_ <= 0) {
            revert INVALID_CONFIG();
        }

        minNavRay = minNavRay_;
        maxRateAbsRay = maxRateAbsRay_;
        maxNavJumpBps = maxNavJumpBps_;

        emit NavBoundsUpdated(minNavRay_, maxRateAbsRay_, maxNavJumpBps_);
    }

    function setTimingConfig(uint256 maxStaleness_, uint256 targetSmoothingWindow_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (maxStaleness_ == 0 || targetSmoothingWindow_ == 0) {
            revert INVALID_CONFIG();
        }

        maxStaleness = maxStaleness_;
        targetSmoothingWindow = targetSmoothingWindow_;

        emit TimingConfigUpdated(maxStaleness_, targetSmoothingWindow_);
    }

    function setNavUpdatesPaused(bool paused_) external onlyRole(PAUSER_ROLE) {
        navUpdatesPaused = paused_;
        emit NavUpdatesPausedSet(paused_);
    }

    function _projectNAV(
        uint256 nav0Ray_,
        uint40 t0_,
        int256 ratePerSecondRay_
    ) internal view returns (uint256 navRay, bool stale, bool belowMin) {
        if (t0_ > block.timestamp) {
            revert NAV_T0_IN_FUTURE();
        }

        uint256 dt = block.timestamp - uint256(t0_);
        stale = dt > maxStaleness;
        if (stale) {
            dt = maxStaleness;
        }

        if (nav0Ray_ > uint256(type(int256).max)) {
            revert NAV_OVERFLOW();
        }
        int256 rateDelta = ratePerSecondRay_ * int256(dt);
        int256 projectedNav = int256(nav0Ray_) + rateDelta;
        if (projectedNav < int256(minNavRay)) {
            return (0, stale, true);
        }
        if (projectedNav < 0) {
            return (0, stale, true);
        }

        return (uint256(projectedNav), stale, false);
    }
}
