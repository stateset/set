// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {MockAsset} from "./SSDCV2TestBase.sol";
import {NAVControllerV2} from "../../../stablecoin/v2/NAVControllerV2.sol";
import {SSDCClaimQueueV2} from "../../../stablecoin/v2/SSDCClaimQueueV2.sol";
import {wSSDCVaultV2} from "../../../stablecoin/v2/wSSDCVaultV2.sol";

contract SSDCClaimQueueHandler {
    SSDCClaimQueueV2 public immutable queue;
    MockAsset public immutable asset;
    wSSDCVaultV2 public immutable vault;

    uint256 public lastHead;
    uint256 public maxKnownClaimId;

    constructor(SSDCClaimQueueV2 queue_, MockAsset asset_, wSSDCVaultV2 vault_) {
        queue = queue_;
        asset = asset_;
        vault = vault_;

        asset.mint(address(this), 1_000_000 ether);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(500_000 ether, address(this));
        vault.approve(address(queue), type(uint256).max);

        asset.approve(address(queue), type(uint256).max);

        lastHead = queue.head();
    }

    function opRequestRedeem(uint256 sharesRaw) external {
        if (maxKnownClaimId >= 200) {
            _trackHead();
            return;
        }

        uint256 balance = vault.balanceOf(address(this));
        if (balance == 0) {
            _trackHead();
            return;
        }

        uint256 shares = (sharesRaw % balance) + 1;

        try queue.requestRedeem(shares, address(this)) returns (uint256 claimId) {
            if (claimId > maxKnownClaimId) {
                maxKnownClaimId = claimId;
            }
        } catch {}

        _trackHead();
    }

    function opCancel(uint256 claimIdRaw) external {
        if (maxKnownClaimId == 0) {
            _trackHead();
            return;
        }

        uint256 claimId = (claimIdRaw % maxKnownClaimId) + 1;
        try queue.cancel(claimId, address(this)) {} catch {}

        _trackHead();
    }

    function opProcess(uint256 maxClaimsRaw) external {
        uint256 maxClaims = (maxClaimsRaw % 20) + 1;
        try queue.processQueue(maxClaims) {} catch {}

        _trackHead();
    }

    function opClaim(uint256 claimIdRaw) external {
        if (maxKnownClaimId == 0) {
            _trackHead();
            return;
        }

        uint256 claimId = (claimIdRaw % maxKnownClaimId) + 1;
        try queue.claim(claimId) {} catch {}

        _trackHead();
    }

    function opRefill(uint256 amountRaw) external {
        uint256 amount = (amountRaw % 10_000 ether) + 1;
        uint256 balance = asset.balanceOf(address(this));
        if (balance == 0) {
            _trackHead();
            return;
        }

        if (amount > balance) {
            amount = balance;
        }

        try queue.refill(amount) {} catch {}

        _trackHead();
    }

    function _trackHead() internal {
        uint256 h = queue.head();
        require(h >= lastHead, "HEAD_REGRESSED");
        lastHead = h;

        uint256 latest = queue.nextClaimId();
        if (latest > 1 && latest - 1 > maxKnownClaimId) {
            maxKnownClaimId = latest - 1;
        }
    }
}

contract SSDCClaimQueueV2InvariantTest is StdInvariant, Test {
    uint256 internal constant RAY = 1e27;
    address internal admin = address(0xA11CE);
    address internal oracle = address(0x0A11);

    MockAsset internal asset;
    NAVControllerV2 internal nav;
    wSSDCVaultV2 internal vault;
    SSDCClaimQueueV2 internal queue;
    SSDCClaimQueueHandler internal handler;

    function setUp() public {
        vm.startPrank(admin);

        asset = new MockAsset();
        nav = new NAVControllerV2(
            admin,
            RAY,
            9e26,
            1e23,
            48 hours,
            24 hours,
            2_000
        );
        vault = new wSSDCVaultV2(asset, nav, admin);
        nav.grantRole(nav.ORACLE_ROLE(), oracle);

        queue = new SSDCClaimQueueV2(vault, asset, admin);
        vault.grantRole(vault.QUEUE_ROLE(), address(queue));
        vm.stopPrank();

        handler = new SSDCClaimQueueHandler(queue, asset, vault);

        bytes32 bufferRole = queue.BUFFER_ROLE();
        vm.prank(admin);
        queue.grantRole(bufferRole, address(handler));

        targetContract(address(handler));
    }

    function invariant_reservedEqualsClaimableOwed() public view {
        uint256 sum;
        uint256 maxId = queue.nextClaimId();

        for (uint256 i = 1; i < maxId; i++) {
            (, , uint256 assetsOwed, , SSDCClaimQueueV2.Status status) = queue.claims(i);
            if (status == SSDCClaimQueueV2.Status.CLAIMABLE) {
                sum += assetsOwed;
            }
        }

        assertEq(queue.reservedAssets(), sum);
    }

    function invariant_headMonotonic() public view {
        assertGe(queue.head(), handler.lastHead());
    }

    function invariant_reservedBackedByQueueAssets() public view {
        assertGe(asset.balanceOf(address(queue)), queue.reservedAssets());
    }
}
