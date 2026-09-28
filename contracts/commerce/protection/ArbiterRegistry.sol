// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ArbiterRegistry
/// @notice Governing layer for payment disputes. Governance approves arbiters;
///         each arbiter keeps a slashable bond, and dispute contracts holding
///         COURT_ROLE open/close cases and slash arbiters that miss deadlines.
contract ArbiterRegistry is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant COURT_ROLE = keccak256("COURT_ROLE");

    enum CaseOutcome {
        RESOLVED,
        WITHDRAWN,
        MISSED
    }

    struct Arbiter {
        bool approved;
        uint128 bond;
        uint32 openCases;
        uint32 casesResolved;
        uint32 casesMissed;
        uint64 exitRequestedAt;
        bytes32 metadataHash;
    }

    IERC20 public immutable bondToken;
    uint128 public minBond;
    uint128 public slashAmount;
    uint64 public unbondingPeriod;
    address public slashRecipient;

    mapping(address => Arbiter) public arbiters;

    error ZeroAddress();
    error NotApproved();
    error OpenCases();
    error ExitPending();
    error ExitNotRequested();
    error UnbondingActive();
    error InsufficientBond();
    error UnsupportedTokenTransfer(uint256 expected, uint256 received);

    event ArbiterApproved(address indexed arbiter, bool approved);
    event ArbiterMetadataSet(address indexed arbiter, bytes32 metadataHash);
    event BondDeposited(address indexed arbiter, uint256 amount, uint256 bond);
    event BondWithdrawn(address indexed arbiter, uint256 amount, uint256 bond);
    event ExitRequested(address indexed arbiter, uint64 availableAt);
    event CaseOpened(address indexed arbiter, uint32 openCases);
    event CaseClosed(address indexed arbiter, CaseOutcome outcome, uint32 openCases);
    event ArbiterSlashed(address indexed arbiter, uint256 amount, address indexed recipient);
    event ParamsUpdated(uint128 minBond, uint128 slashAmount, uint64 unbondingPeriod, address slashRecipient);

    constructor(
        IERC20 bondToken_,
        address admin,
        uint128 minBond_,
        uint128 slashAmount_,
        uint64 unbondingPeriod_,
        address slashRecipient_
    ) {
        if (address(bondToken_) == address(0) || admin == address(0) || slashRecipient_ == address(0)) {
            revert ZeroAddress();
        }
        bondToken = bondToken_;
        _setParams(minBond_, slashAmount_, unbondingPeriod_, slashRecipient_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // ─── governance ────────────────────────────────────────────────────────

    function setParams(uint128 minBond_, uint128 slashAmount_, uint64 unbondingPeriod_, address slashRecipient_)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (slashRecipient_ == address(0)) revert ZeroAddress();
        _setParams(minBond_, slashAmount_, unbondingPeriod_, slashRecipient_);
    }

    function setApproved(address arbiter, bool approved) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (arbiter == address(0)) revert ZeroAddress();
        arbiters[arbiter].approved = approved;
        emit ArbiterApproved(arbiter, approved);
    }

    // ─── arbiter self-service ──────────────────────────────────────────────

    function setMetadata(bytes32 metadataHash) external {
        arbiters[msg.sender].metadataHash = metadataHash;
        emit ArbiterMetadataSet(msg.sender, metadataHash);
    }

    function depositBond(uint128 amount) external nonReentrant {
        Arbiter storage a = arbiters[msg.sender];
        if (a.exitRequestedAt != 0) revert ExitPending();
        uint256 before = bondToken.balanceOf(address(this));
        bondToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = bondToken.balanceOf(address(this)) - before;
        if (received != amount) revert UnsupportedTokenTransfer(amount, received);
        a.bond += amount;
        emit BondDeposited(msg.sender, amount, a.bond);
    }

    /// @notice Withdraw bond above `minBond`. Requires no open cases.
    function withdrawExcessBond(uint128 amount) external nonReentrant {
        Arbiter storage a = arbiters[msg.sender];
        if (a.openCases != 0) revert OpenCases();
        if (a.bond < amount || a.bond - amount < minBond) revert InsufficientBond();
        a.bond -= amount;
        bondToken.safeTransfer(msg.sender, amount);
        emit BondWithdrawn(msg.sender, amount, a.bond);
    }

    /// @notice Stop taking new cases. The full bond unlocks after `unbondingPeriod`
    ///         once every open case is closed.
    function requestExit() external {
        Arbiter storage a = arbiters[msg.sender];
        if (a.exitRequestedAt != 0) revert ExitPending();
        a.exitRequestedAt = uint64(block.timestamp);
        emit ExitRequested(msg.sender, uint64(block.timestamp) + unbondingPeriod);
    }

    function completeExit() external nonReentrant {
        Arbiter storage a = arbiters[msg.sender];
        if (a.exitRequestedAt == 0) revert ExitNotRequested();
        if (a.openCases != 0) revert OpenCases();
        if (block.timestamp < uint256(a.exitRequestedAt) + unbondingPeriod) revert UnbondingActive();
        uint128 amount = a.bond;
        a.bond = 0;
        a.exitRequestedAt = 0;
        a.approved = false;
        if (amount > 0) bondToken.safeTransfer(msg.sender, amount);
        emit BondWithdrawn(msg.sender, amount, 0);
    }

    // ─── court hooks ───────────────────────────────────────────────────────

    function openCase(address arbiter) external onlyRole(COURT_ROLE) {
        if (!isEligible(arbiter)) revert NotApproved();
        Arbiter storage a = arbiters[arbiter];
        a.openCases += 1;
        emit CaseOpened(arbiter, a.openCases);
    }

    /// @notice Close a case. RESOLVED counts toward the arbiter's record, WITHDRAWN
    ///         (parties settled) is neutral, and MISSED slashes up to `slashAmount`.
    function closeCase(address arbiter, CaseOutcome outcome) external onlyRole(COURT_ROLE) nonReentrant {
        Arbiter storage a = arbiters[arbiter];
        if (a.openCases > 0) a.openCases -= 1;
        if (outcome == CaseOutcome.RESOLVED) {
            a.casesResolved += 1;
        } else if (outcome == CaseOutcome.MISSED) {
            a.casesMissed += 1;
            uint128 slashed = a.bond < slashAmount ? a.bond : slashAmount;
            if (slashed > 0) {
                a.bond -= slashed;
                bondToken.safeTransfer(slashRecipient, slashed);
                emit ArbiterSlashed(arbiter, slashed, slashRecipient);
            }
        }
        emit CaseClosed(arbiter, outcome, a.openCases);
    }

    // ─── views ─────────────────────────────────────────────────────────────

    /// @notice Approved, not exiting, and bonded at or above `minBond`.
    function isEligible(address arbiter) public view returns (bool) {
        Arbiter storage a = arbiters[arbiter];
        return a.approved && a.exitRequestedAt == 0 && a.bond >= minBond && a.bond > 0;
    }

    function _setParams(uint128 minBond_, uint128 slashAmount_, uint64 unbondingPeriod_, address slashRecipient_)
        internal
    {
        minBond = minBond_;
        slashAmount = slashAmount_;
        unbondingPeriod = unbondingPeriod_;
        slashRecipient = slashRecipient_;
        emit ParamsUpdated(minBond_, slashAmount_, unbondingPeriod_, slashRecipient_);
    }
}
