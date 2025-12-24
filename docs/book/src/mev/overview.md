# MEV Protection Overview

Set Chain implements comprehensive **MEV (Maximal Extractable Value) protection** to prevent frontrunning, sandwich attacks, and other forms of value extraction from commerce transactions.

## What is MEV?

MEV refers to the profit that can be extracted by reordering, inserting, or censoring transactions. On public blockchains, this often manifests as:

| Attack | Description | Impact |
|--------|-------------|--------|
| **Frontrunning** | Placing a transaction before a victim's | Worse prices, failed transactions |
| **Sandwich Attack** | Transactions before AND after victim | Direct value extraction |
| **Censorship** | Refusing to include transactions | Transaction delays/failures |
| **Reordering** | Changing transaction order | Unfair execution priority |

## Set Chain's Approach

Set Chain uses a **tiered protection strategy**:

```
┌─────────────────────────────────────────────────────────────────┐
│                    MEV Protection Stack                          │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Layer 4: Forced Inclusion (Censorship Resistance)         │  │
│  │ Submit to L1 if sequencer censors                         │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Layer 3: Sequencer Attestation (Ordering Proofs)          │  │
│  │ Verifiable ordering commitments                           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Layer 2: Threshold Encrypted Mempool (Privacy)            │  │
│  │ Transactions hidden until ordering committed              │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Layer 1: Private Mempool (Basic Protection)               │  │
│  │ No public mempool exposure                                │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Protection Mechanisms

### 1. Private Mempool (Current - Phase 0)

- Transactions sent directly to sequencer
- No public mempool visibility
- Relies on trusted sequencer

**Pros:** Simple, already implemented
**Cons:** Requires trusting sequencer

### 2. Threshold Encrypted Mempool (Phase 2)

Transactions are encrypted until ordering is committed:

```
User Transaction
       │
       ▼
┌─────────────────┐
│   Encrypt with  │
│  threshold key  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Encrypted     │
│   Mempool       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Sequencer     │
│ commits order   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Threshold     │
│   decrypt       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Execute in    │
│ committed order │
└─────────────────┘
```

**How it works:**
1. User encrypts transaction with threshold public key
2. Submits encrypted payload to EncryptedMempool contract
3. Sequencer orders transactions (can't see contents)
4. After ordering committed, keypers release decryption shares
5. Transactions decrypted and executed in committed order

### 3. Sequencer Attestation (Phase 1)

Sequencer commits to transaction ordering:

```solidity
event OrderingCommitted(
    bytes32 indexed blockHash,
    bytes32 txOrderingRoot,
    uint32 txCount,
    bytes signature
);
```

**Benefits:**
- Verifiable ordering history
- Enables dispute resolution
- Foundation for slashing

### 4. Forced Inclusion (Phase 3)

If sequencer censors, users can submit via L1:

```
User Transaction
       │
       ▼
┌─────────────────┐
│ ForcedInclusion │ (L1 contract)
│    contract     │
└────────┬────────┘
         │ L1 → L2 message
         ▼
┌─────────────────┐
│  Set Chain L2   │
│ must include TX │
│ within 24 hours │
└─────────────────┘
```

## Contracts

| Contract | Purpose |
|----------|---------|
| `EncryptedMempool` | Submit/decrypt/execute encrypted txs |
| `ThresholdKeyRegistry` | Manage keyper network and DKG |
| `SequencerAttestation` | Commit and verify ordering |
| `ForcedInclusion` | L1 censorship resistance |

## SDK Usage

### Check MEV Protection Status

```typescript
import { createMEVProtectionClient } from "@setchain/sdk";

const mev = createMEVProtectionClient(addresses, signer);

// Check availability
const available = await mev.isAvailable();
const status = await mev.getStatus();
console.log("MEV Protection:", status.phase);
console.log("Encryption enabled:", status.encryptionEnabled);
```

### Submit Protected Transaction

```typescript
// Submit encrypted transaction
const { txId } = await mev.submit(
    targetContract,
    calldata,
    parseEther("0.1"),
    {
        gasLimit: 200000n,
        maxFeePerGas: parseGwei("10")
    }
);

// Wait for execution
const result = await mev.waitForExecution(txId);
console.log("Executed:", result.success);
```

### Force Inclusion via L1

```typescript
import { createForcedInclusionClient } from "@setchain/sdk";

const forced = createForcedInclusionClient(l1Address, l1Signer);

// Submit to L1 (costs bond + gas)
const { txId } = await forced.forceTransaction(
    targetContract,
    calldata,
    gasLimit,
    { value: parseEther("0.01") } // Bond
);

// Monitor inclusion
const status = await forced.getStatus(txId);
if (status.included) {
    console.log("Included at L2 block:", status.l2BlockNumber);
} else if (status.expired) {
    // Sequencer censored - claim bond + penalty
    await forced.claimExpired(txId);
}
```

## Protection Levels

| Level | Protection | Latency | Cost |
|-------|------------|---------|------|
| **Standard** | Private mempool | ~2s | Normal |
| **Enhanced** | + Sequencer attestation | ~2s | Normal |
| **Maximum** | + Threshold encryption | ~3-5s | +50% gas |
| **Censorship-resistant** | Forced inclusion via L1 | ~15 min | Bond + L1 gas |

## Threat Coverage

| Attack | Phase 0 | Phase 1 | Phase 2 | Phase 3 |
|--------|---------|---------|---------|---------|
| Frontrunning | Partial | Partial | Full | Full |
| Sandwich | Partial | Partial | Full | Full |
| Censorship | None | None | None | Full |
| Reordering | None | Verifiable | Full | Full |

## Implementation Status

| Phase | Status | Target |
|-------|--------|--------|
| Phase 0: Private Mempool | ✅ Complete | Current |
| Phase 1: Sequencer Attestation | ✅ Complete | Current |
| Phase 2: Encrypted Mempool | 🟡 Contracts ready | Q1 2025 |
| Phase 3: Forced Inclusion | 🟡 Contracts ready | Q1 2025 |
| Phase 4: Shared Sequencing | ⬜ Planned | Q2 2025 |

## Next Steps

- [Encrypted Mempool](./encrypted-mempool.md) - Threshold encryption details
- [Threshold Key Registry](./threshold-keys.md) - Keyper network and DKG
- [Sequencer Attestation](./sequencer-attestation.md) - Ordering commitments
- [Forced Inclusion](./forced-inclusion.md) - L1 censorship resistance
