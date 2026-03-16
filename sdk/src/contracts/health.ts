import { Contract } from "ethers";
import type { RegistryStats, ThresholdRegistryStatus } from "../types.js";
import { fetchRegistryStats } from "./registry.js";
import { getPaymasterHealthSummary } from "./paymaster.js";
import { fetchTreasuryVaultHealth } from "./treasury-vault.js";
import { fetchNAVOracleHealth } from "./nav-oracle.js";
import { getMempoolHealthSummary } from "./encrypted-mempool.js";
import { getForcedInclusionHealthSummary } from "./forced-inclusion.js";
import { getAttestationHealthSummary } from "./sequencer-attestation.js";
import { getTimelockHealthSummary } from "./timelock.js";
import { fetchThresholdRegistryStatus } from "./threshold-key-registry.js";

/**
 * Comprehensive system health status
 */
export interface SystemHealthStatus {
  timestamp: number;
  overallHealthy: boolean;
  components: {
    registry?: { healthy: boolean; stats?: RegistryStats };
    paymaster?: { healthy: boolean; balance?: bigint; tierCount?: bigint };
    treasuryVault?: { healthy: boolean; collateralizationRatio?: bigint };
    navOracle?: { healthy: boolean; isFresh?: boolean; healthScore?: bigint };
    mempool?: { healthy: boolean; pendingCount?: bigint; successRate?: bigint };
    forcedInclusion?: { healthy: boolean; inclusionRate?: bigint; pendingCount?: bigint };
    attestation?: { healthy: boolean; successRate?: bigint; totalCommitments?: bigint };
    timelock?: { healthy: boolean; minDelay?: bigint };
    thresholdRegistry?: { healthy: boolean; activeKeypers?: bigint; threshold?: bigint };
  };
  errors: string[];
}

/**
 * Configuration for system health check
 */
export interface SystemHealthConfig {
  registry?: Contract;
  paymaster?: Contract;
  treasuryVault?: Contract;
  navOracle?: Contract;
  mempool?: Contract;
  forcedInclusion?: Contract;
  attestation?: Contract;
  timelock?: Contract;
  thresholdRegistry?: Contract;
}

/**
 * Perform comprehensive system health check across all contracts
 * @param config Configuration with contract instances to check
 * @returns Comprehensive health status
 */
export async function performSystemHealthCheck(
  config: SystemHealthConfig
): Promise<SystemHealthStatus> {
  const result: SystemHealthStatus = {
    timestamp: Date.now(),
    overallHealthy: true,
    components: {},
    errors: []
  };

  const checks: Promise<void>[] = [];

  // Registry health
  if (config.registry) {
    checks.push((async () => {
      try {
        const stats = await fetchRegistryStats(config.registry!);
        result.components.registry = {
          healthy: !stats.isPaused,
          stats
        };
        if (stats.isPaused) result.overallHealthy = false;
      } catch (e) {
        result.components.registry = { healthy: false };
        result.errors.push(`Registry: ${e instanceof Error ? e.message : 'Unknown error'}`);
        result.overallHealthy = false;
      }
    })());
  }

  // Paymaster health
  if (config.paymaster) {
    checks.push((async () => {
      try {
        const health = await getPaymasterHealthSummary(config.paymaster!);
        result.components.paymaster = {
          healthy: health.isHealthy,
          balance: health.balance,
          tierCount: health.tierCount
        };
        if (!health.isHealthy) result.overallHealthy = false;
      } catch (e) {
        result.components.paymaster = { healthy: false };
        result.errors.push(`Paymaster: ${e instanceof Error ? e.message : 'Unknown error'}`);
        result.overallHealthy = false;
      }
    })());
  }

  // TreasuryVault health
  if (config.treasuryVault) {
    checks.push((async () => {
      try {
        const health = await fetchTreasuryVaultHealth(config.treasuryVault!);
        const isHealthy = health.isDepositsEnabled && health.collateralizationRatio >= BigInt(10000);
        result.components.treasuryVault = {
          healthy: isHealthy,
          collateralizationRatio: health.collateralizationRatio
        };
        if (!isHealthy) result.overallHealthy = false;
      } catch (e) {
        result.components.treasuryVault = { healthy: false };
        result.errors.push(`TreasuryVault: ${e instanceof Error ? e.message : 'Unknown error'}`);
        result.overallHealthy = false;
      }
    })());
  }

  // NAVOracle health
  if (config.navOracle) {
    checks.push((async () => {
      try {
        const health = await fetchNAVOracleHealth(config.navOracle!);
        result.components.navOracle = {
          healthy: health.isFresh && health.healthScore >= BigInt(80),
          isFresh: health.isFresh,
          healthScore: health.healthScore
        };
        if (!health.isFresh) result.overallHealthy = false;
      } catch (e) {
        result.components.navOracle = { healthy: false };
        result.errors.push(`NAVOracle: ${e instanceof Error ? e.message : 'Unknown error'}`);
        result.overallHealthy = false;
      }
    })());
  }

  // EncryptedMempool health
  if (config.mempool) {
    checks.push((async () => {
      try {
        const health = await getMempoolHealthSummary(config.mempool!);
        result.components.mempool = {
          healthy: health.isHealthy,
          pendingCount: health.pendingCount,
          successRate: health.successRate
        };
        if (!health.isHealthy) result.overallHealthy = false;
      } catch (e) {
        result.components.mempool = { healthy: false };
        result.errors.push(`Mempool: ${e instanceof Error ? e.message : 'Unknown error'}`);
        result.overallHealthy = false;
      }
    })());
  }

  // ForcedInclusion health
  if (config.forcedInclusion) {
    checks.push((async () => {
      try {
        const health = await getForcedInclusionHealthSummary(config.forcedInclusion!);
        result.components.forcedInclusion = {
          healthy: health.isHealthy,
          inclusionRate: health.inclusionRate,
          pendingCount: health.pendingCount
        };
        if (!health.isHealthy) result.overallHealthy = false;
      } catch (e) {
        result.components.forcedInclusion = { healthy: false };
        result.errors.push(`ForcedInclusion: ${e instanceof Error ? e.message : 'Unknown error'}`);
        result.overallHealthy = false;
      }
    })());
  }

  // SequencerAttestation health
  if (config.attestation) {
    checks.push((async () => {
      try {
        const health = await getAttestationHealthSummary(config.attestation!);
        result.components.attestation = {
          healthy: health.isHealthy,
          successRate: health.successRate,
          totalCommitments: health.totalCommitments
        };
        if (!health.isHealthy) result.overallHealthy = false;
      } catch (e) {
        result.components.attestation = { healthy: false };
        result.errors.push(`Attestation: ${e instanceof Error ? e.message : 'Unknown error'}`);
        result.overallHealthy = false;
      }
    })());
  }

  // Timelock health
  if (config.timelock) {
    checks.push((async () => {
      try {
        const health = await getTimelockHealthSummary(config.timelock!);
        result.components.timelock = {
          healthy: health.isHealthy,
          minDelay: health.minDelay
        };
        if (!health.isHealthy) result.overallHealthy = false;
      } catch (e) {
        result.components.timelock = { healthy: false };
        result.errors.push(`Timelock: ${e instanceof Error ? e.message : 'Unknown error'}`);
        result.overallHealthy = false;
      }
    })());
  }

  // ThresholdKeyRegistry health
  if (config.thresholdRegistry) {
    checks.push((async () => {
      try {
        const status = await fetchThresholdRegistryStatus(config.thresholdRegistry!);
        const isHealthy = !status.isPaused && status.activeCount >= status.currentThreshold;
        result.components.thresholdRegistry = {
          healthy: isHealthy,
          activeKeypers: status.activeCount,
          threshold: status.currentThreshold
        };
        if (!isHealthy) result.overallHealthy = false;
      } catch (e) {
        result.components.thresholdRegistry = { healthy: false };
        result.errors.push(`ThresholdRegistry: ${e instanceof Error ? e.message : 'Unknown error'}`);
        result.overallHealthy = false;
      }
    })());
  }

  // Wait for all checks to complete
  await Promise.all(checks);

  return result;
}

/**
 * Get a simple health status string
 * @param health System health status
 * @returns Human-readable health summary
 */
export function formatHealthStatus(health: SystemHealthStatus): string {
  const lines: string[] = [];
  lines.push(`System Health Check - ${new Date(health.timestamp).toISOString()}`);
  lines.push(`Overall: ${health.overallHealthy ? 'HEALTHY' : 'UNHEALTHY'}`);
  lines.push('');

  for (const [name, status] of Object.entries(health.components)) {
    if (status) {
      lines.push(`${name}: ${status.healthy ? 'OK' : 'FAIL'}`);
    }
  }

  if (health.errors.length > 0) {
    lines.push('');
    lines.push('Errors:');
    for (const error of health.errors) {
      lines.push(`  - ${error}`);
    }
  }

  return lines.join('\n');
}
