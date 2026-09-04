// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @dev Minimal view surface of wSSDCVaultV2 needed for coverage math.
///      All values are denominated in settlement-asset smallest units (USDC, 6 decimals).
interface IVaultReservesV2 {
    /// @notice Liquid settlement assets currently held on-chain by the vault.
    function availableSettlementAssets() external view returns (uint256);

    /// @notice Vault liabilities: total shares converted to assets at the accounting NAV.
    function totalAssets() external view returns (uint256);

    /// @notice Book value of assets deployed off-chain to the reserve manager.
    function deployedReserveAssets() external view returns (uint128);
}

/// @title ProofOfReservesV2
/// @notice On-chain attestation registry for the off-chain Treasury portfolio backing SSDC V2.
/// @dev The NAVControllerV2 attests *price per share*; this contract attests the *market value of
///      the off-chain reserves* that back those shares. Together they let any party verify, on-chain,
///      that backing (on-chain liquid USDC + attested off-chain reserves) covers vault liabilities.
///
///      Closes the gap documented in the yellow paper threat model: "The NAV oracle is an
///      attestation, not a proof... off-chain Treasury assets are not verifiable on-chain in
///      real-time." This contract does not change the economic design — it is an additive,
///      read-mostly accountability layer that the circuit breaker, status lens, and off-chain
///      monitors can consume.
///
///      Separation of duties: the reserve attestor (ATTESTOR_ROLE here) is intentionally a
///      distinct role from the NAV oracle (ORACLE_ROLE on NAVControllerV2), so a single
///      compromised key cannot both move the share price and fake the reserves behind it.
contract ProofOfReservesV2 is AccessControl {
    bytes32 public constant ATTESTOR_ROLE = keccak256("ATTESTOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 private constant BPS = 10_000;

    /// @notice Vault whose liabilities and on-chain liquidity this contract reconciles against.
    IVaultReservesV2 public immutable vault;

    struct Attestation {
        uint256 reserveValue; // market value of off-chain reserves, settlement-asset units
        bytes32 portfolioHash; // hash of the off-chain custodian/holdings statement (e.g. CUSIP-level)
        uint64 epoch; // monotonically increasing attestation epoch
        uint40 timestamp; // block time the attestation was recorded
        address attestor; // submitter of this attestation
    }

    /// @dev Latest attestation, plus config packed alongside.
    Attestation public latest;
    mapping(uint64 => Attestation) public attestationByEpoch;

    uint40 public maxStaleness; // seconds after which the attestation is considered stale
    uint16 public minCoverageBps; // solvency floor, e.g. 10_000 = 100% backed
    uint16 public maxDeviationBps; // max change in reserveValue per attestation; 0 disables the guard

    error ZERO_ADDRESS();
    error INVALID_CONFIG();
    error EPOCH();
    error PAUSED();
    error DEVIATION();
    error NOT_ATTESTED();

    bool public paused;

    event ReserveAttested(
        uint64 indexed epoch,
        uint256 reserveValue,
        bytes32 portfolioHash,
        address indexed attestor,
        uint256 coverageRatioBps
    );
    event ReserveForceAttested(
        uint64 indexed epoch, uint256 reserveValue, bytes32 portfolioHash, address indexed attestor
    );
    event ConfigUpdated(uint256 maxStaleness, uint256 minCoverageBps, uint256 maxDeviationBps);
    event PausedSet(bool paused);

    constructor(
        address admin,
        IVaultReservesV2 vault_,
        uint256 maxStaleness_,
        uint256 minCoverageBps_,
        uint256 maxDeviationBps_
    ) {
        if (admin == address(0) || address(vault_) == address(0)) {
            revert ZERO_ADDRESS();
        }
        if (
            maxStaleness_ == 0 || maxStaleness_ > type(uint40).max || minCoverageBps_ == 0
                || minCoverageBps_ > type(uint16).max || maxDeviationBps_ > BPS
        ) {
            revert INVALID_CONFIG();
        }

        vault = vault_;
        maxStaleness = uint40(maxStaleness_);
        minCoverageBps = uint16(minCoverageBps_);
        maxDeviationBps = uint16(maxDeviationBps_);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ATTESTOR_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    // ---------------------------------------------------------------------
    // Attestation
    // ---------------------------------------------------------------------

    /// @notice Record a new reserve attestation.
    /// @param reserveValue Market value of the off-chain reserve portfolio (settlement-asset units).
    /// @param portfolioHash Hash binding the on-chain figure to the off-chain custodian statement.
    /// @param newEpoch Monotonically increasing epoch (must exceed the current epoch).
    function submitAttestation(
        uint256 reserveValue,
        bytes32 portfolioHash,
        uint64 newEpoch
    ) external onlyRole(ATTESTOR_ROLE) {
        if (paused) {
            revert PAUSED();
        }
        if (newEpoch <= latest.epoch) {
            revert EPOCH();
        }

        // Deviation guard: bound how far reserveValue can move in a single attestation, so a
        // fat-fingered or compromised attestor cannot silently zero out (or inflate) reserves.
        // Governance can override via forceAttestation. Skipped on the first attestation.
        if (maxDeviationBps > 0 && latest.epoch != 0 && latest.reserveValue != 0) {
            uint256 prev = latest.reserveValue;
            uint256 diff = reserveValue > prev ? reserveValue - prev : prev - reserveValue;
            uint256 deviationBps = Math.mulDiv(diff, BPS, prev, Math.Rounding.Ceil);
            if (deviationBps > maxDeviationBps) {
                revert DEVIATION();
            }
        }

        _record(reserveValue, portfolioHash, newEpoch);
        emit ReserveAttested(newEpoch, reserveValue, portfolioHash, msg.sender, coverageRatioBps());
    }

    /// @notice Governance recovery path for legitimate large reserve discontinuities (e.g. a real
    ///         loss event or a custodian restatement) that exceed the deviation guard or land while
    ///         paused. Mirrors NAVControllerV2.forceUpdateNAV.
    function forceAttestation(
        uint256 reserveValue,
        bytes32 portfolioHash,
        uint64 newEpoch
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newEpoch <= latest.epoch) {
            revert EPOCH();
        }
        _record(reserveValue, portfolioHash, newEpoch);
        emit ReserveForceAttested(newEpoch, reserveValue, portfolioHash, msg.sender);
    }

    function _record(
        uint256 reserveValue,
        bytes32 portfolioHash,
        uint64 newEpoch
    ) internal {
        Attestation memory a = Attestation({
            reserveValue: reserveValue,
            portfolioHash: portfolioHash,
            epoch: newEpoch,
            timestamp: uint40(block.timestamp),
            attestor: msg.sender
        });
        latest = a;
        attestationByEpoch[newEpoch] = a;
    }

    // ---------------------------------------------------------------------
    // Config
    // ---------------------------------------------------------------------

    function setConfig(
        uint256 maxStaleness_,
        uint256 minCoverageBps_,
        uint256 maxDeviationBps_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (
            maxStaleness_ == 0 || maxStaleness_ > type(uint40).max || minCoverageBps_ == 0
                || minCoverageBps_ > type(uint16).max || maxDeviationBps_ > BPS
        ) {
            revert INVALID_CONFIG();
        }
        maxStaleness = uint40(maxStaleness_);
        minCoverageBps = uint16(minCoverageBps_);
        maxDeviationBps = uint16(maxDeviationBps_);
        emit ConfigUpdated(maxStaleness_, minCoverageBps_, maxDeviationBps_);
    }

    function setPaused(
        bool paused_
    ) external onlyRole(PAUSER_ROLE) {
        paused = paused_;
        emit PausedSet(paused_);
    }

    // ---------------------------------------------------------------------
    // Views — consumable by the circuit breaker, status lens, and monitors
    // ---------------------------------------------------------------------

    /// @notice True once at least one attestation has been recorded.
    function hasAttestation() public view returns (bool) {
        return latest.epoch != 0;
    }

    /// @notice Seconds elapsed since the latest attestation (type(uint256).max if none yet).
    function attestationAge() public view returns (uint256) {
        if (latest.epoch == 0) {
            return type(uint256).max;
        }
        return block.timestamp - uint256(latest.timestamp);
    }

    /// @notice True if there is no fresh attestation backing the current state.
    function isStale() public view returns (bool) {
        return attestationAge() >= maxStaleness;
    }

    /// @notice Off-chain reserve market value as last attested.
    function attestedReserveValue() public view returns (uint256) {
        return latest.reserveValue;
    }

    /// @notice On-chain liquid settlement assets held by the vault.
    function onchainLiquidValue() public view returns (uint256) {
        return vault.availableSettlementAssets();
    }

    /// @notice Total backing = on-chain liquid assets + attested off-chain reserves.
    function totalBackingValue() public view returns (uint256) {
        return onchainLiquidValue() + latest.reserveValue;
    }

    /// @notice Vault liabilities (what holders' shares are collectively worth at NAV).
    function liabilities() public view returns (uint256) {
        return vault.totalAssets();
    }

    /// @notice Backing-to-liabilities ratio in basis points. 10_000 = fully backed.
    ///         Returns 10_000 when there are no liabilities.
    function coverageRatioBps() public view returns (uint256) {
        uint256 liab = liabilities();
        if (liab == 0) {
            return BPS;
        }
        return Math.mulDiv(totalBackingValue(), BPS, liab);
    }

    /// @notice Attested reserve value vs the vault's recorded book value of deployed reserves, in
    ///         basis points. Below 10_000 means the off-chain portfolio is worth less than what was
    ///         deployed to it — a reserve loss the book value alone would not reveal. 10_000 when
    ///         nothing is deployed.
    function reserveMarkBps() public view returns (uint256) {
        uint256 deployed = uint256(vault.deployedReserveAssets());
        if (deployed == 0) {
            return BPS;
        }
        return Math.mulDiv(latest.reserveValue, BPS, deployed);
    }

    /// @notice Solvent iff there is a fresh attestation and backing meets the coverage floor.
    function isSolvent() public view returns (bool) {
        if (isStale()) {
            return false;
        }
        return coverageRatioBps() >= minCoverageBps;
    }

    /// @notice One-call snapshot for status lenses / circuit breakers.
    function solvencyStatus()
        external
        view
        returns (
            bool solvent,
            bool stale,
            uint256 coverageBps,
            uint256 backing,
            uint256 liab,
            uint256 age
        )
    {
        solvent = isSolvent();
        stale = isStale();
        coverageBps = coverageRatioBps();
        backing = totalBackingValue();
        liab = liabilities();
        age = attestationAge();
    }
}
