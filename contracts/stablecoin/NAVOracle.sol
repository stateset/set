// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/INAVOracle.sol";
import "./interfaces/IssUSD.sol";

/**
 * @title NAVOracle
 * @notice Oracle for T-Bill Net Asset Value attestation
 * @dev Company attests daily NAV of T-Bill holdings backing ssUSD
 */
contract NAVOracle is
    INAVOracle,
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // =========================================================================
    // Constants
    // =========================================================================

    /// @notice Precision for NAV calculations (1e18 = $1.00)
    uint256 public constant PRECISION = 1e18;

    /// @notice Initial NAV per share ($1.00)
    uint256 public constant INITIAL_NAV_PER_SHARE = 1e18;

    /// @notice Maximum NAV change per attestation (5%)
    uint256 public constant MAX_NAV_CHANGE_BPS = 500;

    /// @notice Basis points denominator
    uint256 public constant BPS_DENOMINATOR = 10000;

    // =========================================================================
    // Storage
    // =========================================================================

    /// @notice Current NAV report
    NAVReport private _currentNAV;

    /// @notice Historical NAV reports
    NAVReport[] private _navHistory;

    /// @notice Authorized attestors
    mapping(address => bool) public authorizedAttestors;

    /// @notice Maximum staleness for NAV (default 24 hours)
    uint256 public maxStalenessSeconds;

    /// @notice ssUSD token address
    address public ssUSD;

    // =========================================================================
    // Errors
    // =========================================================================

    error NotAuthorizedAttestor();
    error NAVChangeExceedsLimit();
    error InvalidReportDate();
    error ReportDateNotNew();
    error ssUSDNotSet();
    error InvalidTotalAssets();

    // =========================================================================
    // Modifiers
    // =========================================================================

    modifier onlyAttestor() {
        if (!authorizedAttestors[msg.sender]) revert NotAuthorizedAttestor();
        _;
    }

    // =========================================================================
    // Initialization
    // =========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the oracle
     * @param owner_ Owner address
     * @param attestor_ Initial attestor address
     * @param maxStaleness_ Maximum staleness in seconds
     */
    function initialize(
        address owner_,
        address attestor_,
        uint256 maxStaleness_
    ) public initializer {
        __Ownable_init(owner_);
        __UUPSUpgradeable_init();

        authorizedAttestors[attestor_] = true;
        maxStalenessSeconds = maxStaleness_;

        // Initialize with $1.00 NAV
        _currentNAV = NAVReport({
            totalAssets: 0,
            totalShares: 0,
            navPerShare: INITIAL_NAV_PER_SHARE,
            timestamp: block.timestamp,
            reportDate: 0,
            proofHash: bytes32(0),
            attestor: attestor_
        });

        emit AttestorUpdated(attestor_, true);
    }

    // =========================================================================
    // Attestation
    // =========================================================================

    /**
     * @notice Attest T-Bill NAV
     * @param totalAssets Total T-Bill value in USD (18 decimals)
     * @param reportDate Date of valuation (YYYYMMDD format)
     * @param proofHash Hash of off-chain proof documents
     */
    function attestNAV(
        uint256 totalAssets,
        uint256 reportDate,
        bytes32 proofHash
    ) external onlyAttestor {
        if (totalAssets == 0) revert InvalidTotalAssets();
        if (reportDate <= _currentNAV.reportDate) revert ReportDateNotNew();

        // Get total shares from ssUSD
        uint256 totalShares;
        if (ssUSD != address(0)) {
            totalShares = IssUSD(ssUSD).totalShares();
        }

        // Calculate new NAV per share
        uint256 newNavPerShare;
        if (totalShares == 0) {
            newNavPerShare = INITIAL_NAV_PER_SHARE;
        } else {
            newNavPerShare = (totalAssets * PRECISION) / totalShares;
        }

        // Validate NAV change is within limits (only after initial attestation)
        if (_currentNAV.totalAssets > 0 && totalShares > 0) {
            uint256 previousNav = _currentNAV.navPerShare;
            uint256 maxChange = (previousNav * MAX_NAV_CHANGE_BPS) / BPS_DENOMINATOR;

            if (newNavPerShare > previousNav + maxChange) {
                revert NAVChangeExceedsLimit();
            }
            // NAV should not decrease for T-Bills (principal protected)
            // But allow small decreases for fees
            if (newNavPerShare < previousNav - (previousNav * 100 / BPS_DENOMINATOR)) {
                revert NAVChangeExceedsLimit();
            }
        }

        // Store previous NAV in history
        if (_currentNAV.timestamp > 0) {
            _navHistory.push(_currentNAV);
        }

        // Update current NAV
        _currentNAV = NAVReport({
            totalAssets: totalAssets,
            totalShares: totalShares,
            navPerShare: newNavPerShare,
            timestamp: block.timestamp,
            reportDate: reportDate,
            proofHash: proofHash,
            attestor: msg.sender
        });

        emit NAVAttested(totalAssets, newNavPerShare, reportDate, msg.sender);
    }

    // =========================================================================
    // View Functions
    // =========================================================================

    /**
     * @notice Get current NAV per share
     * @return NAV per share (1e18 = $1.00)
     */
    function getCurrentNAVPerShare() external view returns (uint256) {
        return _currentNAV.navPerShare;
    }

    /**
     * @notice Get total assets
     */
    function getTotalAssets() external view returns (uint256) {
        return _currentNAV.totalAssets;
    }

    /**
     * @notice Get last report date
     */
    function getLastReportDate() external view returns (uint256) {
        return _currentNAV.reportDate;
    }

    /**
     * @notice Check if NAV is fresh (not stale)
     */
    function isNAVFresh() external view returns (bool) {
        return block.timestamp <= _currentNAV.timestamp + maxStalenessSeconds;
    }

    /**
     * @notice Get current NAV report
     */
    function getCurrentNAV() external view returns (NAVReport memory) {
        return _currentNAV;
    }

    /**
     * @notice Get NAV history
     * @param count Number of historical reports to return
     */
    function getNAVHistory(uint256 count) external view returns (NAVReport[] memory) {
        uint256 length = _navHistory.length;
        uint256 resultCount = count > length ? length : count;

        NAVReport[] memory result = new NAVReport[](resultCount);

        for (uint256 i = 0; i < resultCount; i++) {
            result[i] = _navHistory[length - resultCount + i];
        }

        return result;
    }

    /**
     * @notice Get total history count
     */
    function getHistoryCount() external view returns (uint256) {
        return _navHistory.length;
    }

    // =========================================================================
    // Admin Functions
    // =========================================================================

    /**
     * @notice Set attestor authorization
     */
    function setAuthorizedAttestor(
        address attestor,
        bool authorized
    ) external onlyOwner {
        authorizedAttestors[attestor] = authorized;
        emit AttestorUpdated(attestor, authorized);
    }

    /**
     * @notice Set maximum staleness period
     */
    function setMaxStaleness(uint256 seconds_) external onlyOwner {
        maxStalenessSeconds = seconds_;
        emit StalenessUpdated(seconds_);
    }

    /**
     * @notice Set ssUSD token address
     */
    function setssUSD(address ssUSD_) external onlyOwner {
        ssUSD = ssUSD_;
        emit ssUSDUpdated(ssUSD_);
    }

    // =========================================================================
    // Upgrade
    // =========================================================================

    /**
     * @dev Authorize upgrade (owner only)
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
