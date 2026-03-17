/**
 * @setchain/sdk - Types Module Tests
 *
 * Validates that all shared interfaces are exported and structurally correct.
 */

import { describe, it, expect } from 'vitest';
import type {
  BatchCommitment,
  StarkProofCommitment,
  RegistryStats,
  MerchantDetails,
  ThresholdRegistryStatus,
  Keyper,
  ThresholdKey,
  DKGStatus,
  NetworkHealth,
  KeyExpirationInfo,
  KeyperSummary,
} from '../src/types';

describe('Types Module', () => {
  it('should define BatchCommitment interface', () => {
    const commitment: BatchCommitment = {
      eventsRoot: '0x1234',
      prevStateRoot: '0x5678',
      newStateRoot: '0x9abc',
      sequenceStart: 1n,
      sequenceEnd: 100n,
      eventCount: 100,
      timestamp: 1700000000n,
      submitter: '0x0000000000000000000000000000000000000001',
    };
    expect(commitment.eventsRoot).toBe('0x1234');
    expect(commitment.sequenceEnd - commitment.sequenceStart + 1n).toBe(100n);
    expect(commitment.eventCount).toBe(100);
  });

  it('should define StarkProofCommitment interface', () => {
    const proof: StarkProofCommitment = {
      proofHash: '0xproof',
      policyHash: '0xpolicy',
      policyLimit: 1000n,
      allCompliant: true,
      proofSize: 2048n,
      provingTimeMs: 500n,
      timestamp: 1700000000n,
      submitter: '0x0000000000000000000000000000000000000001',
    };
    expect(proof.allCompliant).toBe(true);
    expect(proof.proofSize).toBe(2048n);
  });

  it('should define RegistryStats interface', () => {
    const stats: RegistryStats = {
      commitmentCount: 50n,
      proofCount: 45n,
      isPaused: false,
      isStrictMode: true,
    };
    expect(stats.isPaused).toBe(false);
    expect(stats.isStrictMode).toBe(true);
  });

  it('should define MerchantDetails interface', () => {
    const details: MerchantDetails = {
      active: true,
      tierId: 2n,
      spentToday: 100000n,
      spentThisMonth: 500000n,
      totalSponsored: 1000000n,
    };
    expect(details.active).toBe(true);
    expect(details.tierId).toBe(2n);
  });

  it('should define ThresholdRegistryStatus interface', () => {
    const status: ThresholdRegistryStatus = {
      totalKeypers: 10n,
      activeCount: 8n,
      currentThreshold: 5n,
      epoch: 3n,
      dkgPhase: 0n,
      isPaused: false,
    };
    expect(status.activeCount).toBeLessThanOrEqual(Number(status.totalKeypers));
    expect(status.currentThreshold).toBeLessThanOrEqual(Number(status.activeCount));
  });

  it('should define Keyper interface', () => {
    const keyper: Keyper = {
      addr: '0x0000000000000000000000000000000000000001',
      publicKey: '0xpubkey',
      endpoint: 'https://keyper1.example.com',
      registeredAt: 1700000000n,
      active: true,
      slashCount: 0n,
    };
    expect(keyper.active).toBe(true);
    expect(keyper.slashCount).toBe(0n);
  });

  it('should define DKGStatus interface', () => {
    const dkg: DKGStatus = {
      epoch: 5n,
      phase: 2n,
      deadline: 1700100000n,
      participantCount: 7n,
      dealingsCount: 5n,
      blocksUntilDeadline: 100n,
    };
    expect(dkg.phase).toBe(2n);
    expect(dkg.dealingsCount).toBeLessThanOrEqual(Number(dkg.participantCount));
  });

  it('should define NetworkHealth interface', () => {
    const health: NetworkHealth = {
      totalKeypers: 10n,
      activeCount: 8n,
      avgStake: 1000000000000000000n,
      totalSlashed: 0n,
      networkSecure: true,
    };
    expect(health.networkSecure).toBe(true);
  });
});
