// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract SSDCPolicyModuleV2 is AccessControl {
    bytes32 public constant POLICY_CONSUMER_ROLE = keccak256("POLICY_CONSUMER_ROLE");

    /// @dev Packed from 7 slots to 4:
    ///   Slot 1: perTxLimitAssets(16) + dailyLimitAssets(16) = 32
    ///   Slot 2: spentTodayAssets(16) + minAssetsFloor(16) = 32
    ///   Slot 3: committedAssets(16) + dayStart(5) + sessionExpiry(5) + flags(2) = 28
    struct AgentPolicy {
        uint128 perTxLimitAssets;
        uint128 dailyLimitAssets;
        uint128 spentTodayAssets;
        uint128 minAssetsFloor;
        uint128 committedAssets;
        uint40 dayStart;
        uint40 sessionExpiry;
        bool enforceMerchantAllowlist;
        bool exists;
    }

    mapping(address => AgentPolicy) public policies;
    mapping(address => mapping(address => bool)) public merchantAllowlist;

    error ZeroAddress();
    error POLICY_NOT_SET();
    error POLICY_LIMIT();
    error POLICY_DAILY_LIMIT();
    error POLICY_ALLOWLIST();
    error POLICY_SESSION_EXPIRED();
    error POLICY_COMMITMENT();

    event PolicyUpdated(
        address indexed agent,
        uint256 perTxLimitAssets,
        uint256 dailyLimitAssets,
        uint256 minAssetsFloor,
        uint40 sessionExpiry,
        bool enforceMerchantAllowlist
    );

    event MerchantAllowlistUpdated(address indexed agent, address indexed merchant, bool allowed);
    event PolicySpendConsumed(address indexed agent, uint256 assetsConsumed, uint256 spentTodayAssets);
    event PolicyGasSpendConsumed(address indexed agent, uint256 assetsConsumed, uint256 spentTodayAssets);
    event PolicyCommitmentReserved(address indexed agent, uint256 assetsReserved, uint256 committedAssets);
    event PolicyCommitmentReleased(address indexed agent, uint256 assetsReleased, uint256 committedAssets);

    constructor(address admin) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(POLICY_CONSUMER_ROLE, admin);
    }

    function setPolicy(
        address agent,
        uint256 perTxLimitAssets,
        uint256 dailyLimitAssets,
        uint256 minAssetsFloor,
        uint40 sessionExpiry,
        bool enforceMerchantAllowlist
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (agent == address(0)) revert ZeroAddress();
        AgentPolicy storage policy = policies[agent];
        policy.perTxLimitAssets = uint128(perTxLimitAssets);
        policy.dailyLimitAssets = uint128(dailyLimitAssets);
        policy.minAssetsFloor = uint128(minAssetsFloor);
        policy.sessionExpiry = sessionExpiry;
        policy.enforceMerchantAllowlist = enforceMerchantAllowlist;
        policy.exists = true;

        if (policy.dayStart == 0) {
            policy.dayStart = uint40(block.timestamp);
        }

        emit PolicyUpdated(
            agent,
            perTxLimitAssets,
            dailyLimitAssets,
            minAssetsFloor,
            sessionExpiry,
            enforceMerchantAllowlist
        );
    }

    function setMerchantAllowed(address agent, address merchant, bool allowed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (agent == address(0)) revert ZeroAddress();
        if (merchant == address(0)) revert ZeroAddress();
        merchantAllowlist[agent][merchant] = allowed;
        emit MerchantAllowlistUpdated(agent, merchant, allowed);
    }

    function getConfiguredMinAssetsFloor(address agent) external view returns (uint256) {
        AgentPolicy storage policy = policies[agent];
        if (!policy.exists) {
            return 0;
        }
        return policy.minAssetsFloor;
    }

    function getCommittedAssets(address agent) external view returns (uint256) {
        AgentPolicy storage policy = policies[agent];
        if (!policy.exists) {
            return 0;
        }
        return policy.committedAssets;
    }

    function getMinAssetsFloor(address agent) external view returns (uint256) {
        AgentPolicy storage policy = policies[agent];
        if (!policy.exists) {
            return 0;
        }
        return policy.minAssetsFloor + policy.committedAssets;
    }

    function canSpend(address agent, address merchant, uint256 assets) external view returns (bool) {
        return _canSpend(policies[agent], agent, merchant, assets);
    }

    function canGasSpend(address agent, uint256 assets) external view returns (bool) {
        return _canGasSpend(policies[agent], assets);
    }

    function requireGasSpendAllowed(address agent, uint256 assets) external view {
        AgentPolicy storage policy = policies[agent];
        if (!policy.exists) {
            revert POLICY_NOT_SET();
        }

        if (!_canGasSpend(policy, assets)) {
            if (policy.sessionExpiry > 0 && block.timestamp > policy.sessionExpiry) {
                revert POLICY_SESSION_EXPIRED();
            }
            if (policy.perTxLimitAssets > 0 && assets > policy.perTxLimitAssets) {
                revert POLICY_LIMIT();
            }
            if (policy.dailyLimitAssets > 0 && _effectiveSpentToday(policy) + assets > policy.dailyLimitAssets) {
                revert POLICY_DAILY_LIMIT();
            }
            revert POLICY_LIMIT();
        }
    }

    function consumeSpend(address agent, address merchant, uint256 assets) external onlyRole(POLICY_CONSUMER_ROLE) {
        AgentPolicy storage policy = policies[agent];
        if (!policy.exists) {
            revert POLICY_NOT_SET();
        }

        _rollDay(policy);

        if (!_canSpend(policy, agent, merchant, assets)) {
            if (policy.sessionExpiry > 0 && block.timestamp > policy.sessionExpiry) {
                revert POLICY_SESSION_EXPIRED();
            }
            if (policy.enforceMerchantAllowlist && !merchantAllowlist[agent][merchant]) {
                revert POLICY_ALLOWLIST();
            }
            if (policy.perTxLimitAssets > 0 && assets > policy.perTxLimitAssets) {
                revert POLICY_LIMIT();
            }
            if (policy.dailyLimitAssets > 0 && _effectiveSpentToday(policy) + assets > policy.dailyLimitAssets) {
                revert POLICY_DAILY_LIMIT();
            }
            revert POLICY_LIMIT();
        }

        policy.spentTodayAssets += uint128(assets);

        emit PolicySpendConsumed(agent, assets, policy.spentTodayAssets);
    }

    /// @notice Consume gas spend for an agent. Skips merchant allowlist check since
    ///         gas payments go to infrastructure, not commerce counterparties.
    function consumeGasSpend(address agent, uint256 assets) external onlyRole(POLICY_CONSUMER_ROLE) {
        AgentPolicy storage policy = policies[agent];
        if (!policy.exists) {
            revert POLICY_NOT_SET();
        }

        _rollDay(policy);

        if (!_canGasSpend(policy, assets)) {
            if (policy.sessionExpiry > 0 && block.timestamp > policy.sessionExpiry) {
                revert POLICY_SESSION_EXPIRED();
            }
            if (policy.perTxLimitAssets > 0 && assets > policy.perTxLimitAssets) {
                revert POLICY_LIMIT();
            }
            if (policy.dailyLimitAssets > 0 && _effectiveSpentToday(policy) + assets > policy.dailyLimitAssets) {
                revert POLICY_DAILY_LIMIT();
            }
            revert POLICY_LIMIT();
        }

        policy.spentTodayAssets += uint128(assets);

        emit PolicyGasSpendConsumed(agent, assets, policy.spentTodayAssets);
    }

    function reserveCommittedSpend(address agent, uint256 assets) external onlyRole(POLICY_CONSUMER_ROLE) {
        AgentPolicy storage policy = policies[agent];
        if (!policy.exists) {
            revert POLICY_NOT_SET();
        }

        policy.committedAssets += uint128(assets);

        emit PolicyCommitmentReserved(agent, assets, policy.committedAssets);
    }

    function releaseCommittedSpend(address agent, uint256 assets) external onlyRole(POLICY_CONSUMER_ROLE) {
        AgentPolicy storage policy = policies[agent];
        if (!policy.exists) {
            revert POLICY_NOT_SET();
        }

        uint256 committedAssets = policy.committedAssets;
        if (assets > committedAssets) {
            revert POLICY_COMMITMENT();
        }

        unchecked {
            policy.committedAssets = uint128(committedAssets - assets);
        }

        emit PolicyCommitmentReleased(agent, assets, policy.committedAssets);
    }

    function _canSpend(
        AgentPolicy storage policy,
        address agent,
        address merchant,
        uint256 assets
    ) internal view returns (bool) {
        uint256 spentTodayAssets = _effectiveSpentToday(policy);

        if (!policy.exists) {
            return false;
        }
        if (policy.perTxLimitAssets > 0 && assets > policy.perTxLimitAssets) {
            return false;
        }
        if (policy.dailyLimitAssets > 0 && spentTodayAssets + assets > policy.dailyLimitAssets) {
            return false;
        }
        if (policy.enforceMerchantAllowlist && !merchantAllowlist[agent][merchant]) {
            return false;
        }
        if (policy.sessionExpiry > 0 && block.timestamp > policy.sessionExpiry) {
            return false;
        }
        return true;
    }

    function _rollDay(AgentPolicy storage policy) internal {
        if (block.timestamp >= uint256(policy.dayStart) + 1 days) {
            policy.dayStart = uint40(block.timestamp);
            policy.spentTodayAssets = 0;
        }
    }

    function _canGasSpend(
        AgentPolicy storage policy,
        uint256 assets
    ) internal view returns (bool) {
        uint256 spentTodayAssets = _effectiveSpentToday(policy);

        if (!policy.exists) {
            return false;
        }
        if (policy.perTxLimitAssets > 0 && assets > policy.perTxLimitAssets) {
            return false;
        }
        if (policy.dailyLimitAssets > 0 && spentTodayAssets + assets > policy.dailyLimitAssets) {
            return false;
        }
        // NOTE: merchant allowlist intentionally NOT checked for gas spend
        if (policy.sessionExpiry > 0 && block.timestamp > policy.sessionExpiry) {
            return false;
        }
        return true;
    }

    function _effectiveSpentToday(AgentPolicy storage policy) internal view returns (uint256) {
        if (policy.dayStart == 0 || block.timestamp >= uint256(policy.dayStart) + 1 days) {
            return 0;
        }

        return policy.spentTodayAssets;
    }
}
