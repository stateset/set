# MEV Protection Design

This document defines the MEV (Maximal Extractable Value) protection strategy for
Set Chain, a commerce-optimized L2.

## Executive Summary

Set Chain processes commerce transactions (orders, payments, inventory updates)
that are vulnerable to MEV extraction. This document proposes a **tiered MEV
protection strategy** combining:

1. **Encrypted mempool** for transaction privacy
2. **Fair ordering policy** (FCFS with threshold encryption)
3. **Forced inclusion mechanism** for censorship resistance
4. **MEV-aware fee structure** to align incentives

Target: Eliminate sandwich attacks, minimize frontrunning, ensure fair ordering.

---

## Table of Contents

1. [Threat Model](#threat-model)
2. [MEV Attack Vectors](#mev-attack-vectors)
3. [Protection Mechanisms](#protection-mechanisms)
4. [Recommended Architecture](#recommended-architecture)
5. [Implementation Phases](#implementation-phases)
6. [Economic Considerations](#economic-considerations)
7. [Monitoring & Metrics](#monitoring--metrics)

---

## Threat Model

### Assets at Risk

| Asset | MEV Risk | Impact |
|-------|----------|--------|
| Order transactions | Frontrunning | Price manipulation, failed orders |
| Payment processing | Sandwich attacks | Inflated gas, failed payments |
| Inventory updates | Reordering | Stale inventory, overselling |
| Token swaps (future) | Sandwich + frontrun | Direct value extraction |
| NFT mints (future) | Frontrunning | Sniping, failed mints |

### Threat Actors

| Actor | Capability | Motivation |
|-------|------------|------------|
| **Sequencer operator** | Full ordering control | Profit extraction |
| **MEV searchers** | Mempool observation | Arbitrage profit |
| **Competing merchants** | Transaction timing | Competitive advantage |
| **Malicious validators** | Block building (future) | Value extraction |

### Trust Assumptions

Current (Phase 0 - Centralized Sequencer):
- Single sequencer operated by Set Chain team
- Sequencer is trusted not to extract MEV
- No external mempool visibility

Future (Phase 2+ - Decentralized):
- Multiple sequencers with rotation
- Public mempool or shared sequencing
- MEV protection becomes critical

---

## MEV Attack Vectors

### 1. Frontrunning

**Description:** Observing a pending transaction and inserting a transaction
before it to profit from the price impact.

**Commerce Example:**
```
1. Merchant submits: createOrder(item=Widget, price=$100)
2. Attacker sees pending tx in mempool
3. Attacker frontruns: buyAllWidgets() at current price
4. Merchant's order fails or pays higher price
```

**Risk Level:** HIGH for token swaps, MEDIUM for commerce

### 2. Sandwich Attacks

**Description:** Placing transactions before AND after a victim transaction
to extract value from price movement.

**Commerce Example:**
```
1. Attacker sees: swapUSDC(1000 USDC → ETH)
2. Attacker frontruns: buy ETH (price goes up)
3. Victim's swap executes at worse rate
4. Attacker backruns: sell ETH (pocket difference)
```

**Risk Level:** HIGH for any DEX/swap activity on L2

### 3. Transaction Reordering

**Description:** Sequencer reorders transactions for profit or favoritism.

**Commerce Example:**
```
1. Two merchants submit orders for last inventory item
2. Sequencer reorders to favor paying customer
3. Fair ordering violated
```

**Risk Level:** MEDIUM (requires malicious sequencer)

### 4. Censorship

**Description:** Sequencer refuses to include certain transactions.

**Commerce Example:**
```
1. Competitor's payment transaction not included
2. Order times out, customer goes elsewhere
```

**Risk Level:** LOW currently (single trusted sequencer), HIGH when decentralized

### 5. Time-Bandit Attacks

**Description:** Reorging the chain to extract past MEV.

**Risk Level:** LOW (OP Stack fault proofs protect against this)

---

## Protection Mechanisms

### Option 1: Encrypted Mempool (Recommended)

**How it works:**
1. Users encrypt transactions with sequencer's threshold public key
2. Encrypted txs submitted to mempool (contents hidden)
3. Sequencer commits to ordering (by encrypted tx hash)
4. Decryption key revealed after ordering committed
5. Transactions executed in committed order

**Architecture:**
```
┌─────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   User Tx   │────►│  Encrypt with   │────►│   Encrypted     │
│  (plaintext)│     │  threshold key  │     │   Mempool       │
└─────────────┘     └─────────────────┘     └────────┬────────┘
                                                     │
                    ┌─────────────────┐              │
                    │  Sequencer      │◄─────────────┘
                    │  commits order  │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  Threshold      │
                    │  decrypt        │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  Execute in     │
                    │  committed order│
                    └─────────────────┘
```

**Pros:**
- Transaction contents invisible until ordering committed
- Eliminates frontrunning and sandwich attacks
- Compatible with existing OP Stack

**Cons:**
- Added latency (~100-500ms for encryption/decryption)
- Requires threshold encryption infrastructure
- Key management complexity

**Implementation Options:**
- **Shutter Network**: Production-ready threshold encryption
- **Flashbots SUAVE**: MEV-aware block building (in development)
- **Custom implementation**: BLS-based encryption keys with ECDSA attestations

### Option 2: Commit-Reveal Scheme

**How it works:**
1. User submits hash of transaction (commit)
2. After inclusion in block, user reveals transaction
3. Revealed transactions execute in commit order

**Pros:**
- Simple to implement
- No external dependencies

**Cons:**
- Requires two transactions (higher cost)
- User must be online to reveal
- Griefing attacks possible (commit without reveal)

### Option 3: Private Mempool (Current State)

**How it works:**
1. Transactions sent directly to sequencer
2. No public mempool visibility
3. Trust sequencer not to extract MEV

**Pros:**
- Already implemented (default OP Stack)
- No additional infrastructure

**Cons:**
- Requires trusting sequencer
- Doesn't scale to decentralized sequencing
- No verifiable fairness

### Option 4: MEV-Share / OFA (Order Flow Auctions)

**How it works:**
1. Users send transactions to MEV-Share
2. Searchers bid for inclusion rights
3. Users receive portion of MEV extracted
4. Reduces MEV harm by redistributing value

**Pros:**
- Users compensated for MEV
- Compatible with existing infrastructure

**Cons:**
- Doesn't prevent MEV, just redistributes
- Complexity of auction mechanism
- May not suit commerce use case

### Option 5: Fair Ordering Protocols

**How it works:**
1. Multiple sequencers observe transactions
2. Transactions ordered by median timestamp
3. Majority agreement on ordering

**Examples:**
- Chainlink Fair Sequencing Services (FSS)
- Espresso Sequencer
- Astria Shared Sequencing

**Pros:**
- Decentralized fairness guarantee
- Censorship resistant

**Cons:**
- Requires multiple sequencers
- Added latency for consensus
- External dependency

---

## Recommended Architecture

For Set Chain, we recommend a **phased approach**:

### Phase 1: Enhanced Private Mempool (Now)

Strengthen the current private mempool with:

1. **Direct submission only** - No public RPC mempool
2. **Sequencer attestation** - Sign ordering commitments
3. **Ordering transparency** - Publish ordering proofs
4. **FCFS policy** - First-come-first-served with timestamp

```solidity
// SequencerAttestation.sol
contract SequencerAttestation {
    event OrderingCommitment(
        bytes32 indexed blockHash,
        bytes32 txOrderingRoot,  // Merkle root of tx order
        uint256 timestamp,
        bytes sequencerSignature
    );

    function verifyOrdering(
        bytes32 blockHash,
        bytes32[] calldata txHashes,
        bytes calldata proof
    ) external view returns (bool);
}
```

### Phase 2: Threshold Encrypted Mempool (3-6 months)

Implement threshold encryption for transaction privacy:

1. **Integration with Shutter Network** or custom threshold encryption
2. **Encryption at SDK level** - Transparent to users
3. **Delayed decryption** - After ordering committed

```
User → SDK encrypts → Sequencer orders → Threshold decrypt → Execute
         │                    │                  │
         ▼                    ▼                  ▼
   ~50ms latency        ~100ms commit       ~200ms decrypt
```

### Phase 3: Shared Sequencing (6-12 months)

Integrate with shared sequencing for decentralization:

1. **Espresso Sequencer** or **Astria** integration
2. **Multiple sequencer nodes** with BFT consensus
3. **Cross-L2 atomic inclusion** (Superchain compatibility)

---

## Implementation Phases

### Phase 1: Ordering Transparency (2-4 weeks)

**Goal:** Verifiable FCFS ordering with sequencer attestations

**Deliverables:**
- [ ] SequencerAttestation contract
- [ ] Ordering proof generation in op-node
- [ ] SDK method to verify ordering
- [ ] Monitoring dashboard for ordering fairness

**Contract:**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title SequencerAttestation
 * @notice Provides verifiable ordering commitments from sequencer
 */
contract SequencerAttestation {
    using ECDSA for bytes32;

    address public sequencer;

    struct OrderingCommitment {
        bytes32 blockHash;
        bytes32 txOrderingRoot;
        uint64 timestamp;
        uint64 txCount;
    }

    mapping(bytes32 => OrderingCommitment) public commitments;

    event OrderingCommitted(
        bytes32 indexed blockHash,
        bytes32 txOrderingRoot,
        uint64 timestamp,
        uint64 txCount
    );

    error InvalidSignature();
    error CommitmentExists();

    constructor(address _sequencer) {
        sequencer = _sequencer;
    }

    function commitOrdering(
        bytes32 blockHash,
        bytes32 txOrderingRoot,
        uint64 timestamp,
        uint64 txCount,
        bytes calldata signature
    ) external {
        if (commitments[blockHash].timestamp != 0) {
            revert CommitmentExists();
        }

        bytes32 messageHash = keccak256(abi.encodePacked(
            blockHash, txOrderingRoot, timestamp, txCount
        ));

        if (messageHash.toEthSignedMessageHash().recover(signature) != sequencer) {
            revert InvalidSignature();
        }

        commitments[blockHash] = OrderingCommitment({
            blockHash: blockHash,
            txOrderingRoot: txOrderingRoot,
            timestamp: timestamp,
            txCount: txCount
        });

        emit OrderingCommitted(blockHash, txOrderingRoot, timestamp, txCount);
    }

    function verifyTxPosition(
        bytes32 blockHash,
        bytes32 txHash,
        uint256 position,
        bytes32[] calldata proof
    ) external view returns (bool) {
        OrderingCommitment storage commitment = commitments[blockHash];
        if (commitment.timestamp == 0) return false;

        bytes32 leaf = keccak256(abi.encodePacked(position, txHash));
        return _verifyMerkleProof(proof, commitment.txOrderingRoot, leaf, position);
    }

    function _verifyMerkleProof(
        bytes32[] calldata proof,
        bytes32 root,
        bytes32 leaf,
        uint256 index
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            if (index % 2 == 0) {
                computedHash = keccak256(abi.encodePacked(computedHash, proof[i]));
            } else {
                computedHash = keccak256(abi.encodePacked(proof[i], computedHash));
            }
            index = index / 2;
        }
        return computedHash == root;
    }
}
```

### Phase 2: Threshold Encryption (IMPLEMENTED)

**Goal:** Transaction privacy via threshold encryption

**Status:** Core contracts and SDK implemented

**Deliverables:**
- [x] ThresholdKeyRegistry contract (`contracts/mev/ThresholdKeyRegistry.sol`)
- [x] EncryptedMempool contract (`contracts/mev/EncryptedMempool.sol`)
- [x] SDK encryption module (`sdk/src/encryption.ts`)
- [x] Keyper network Docker configuration (`docker/docker-compose.keypers.yml`)
- [x] Comprehensive test suite
- [ ] Production keyper network deployment
- [ ] Threshold key generation ceremony

#### ThresholdKeyRegistry Contract

Manages the keyper network and distributed key generation (DKG):

```solidity
// contracts/mev/ThresholdKeyRegistry.sol
contract ThresholdKeyRegistry {
    // Keyper management
    function registerKeyper(bytes calldata _publicKey, string calldata _endpoint) external payable;
    function deactivateKeyper(address _keyper, string calldata _reason) external;
    function slashKeyper(address _keyper, uint256 _amount, string calldata _reason) external;

    // DKG coordination
    function startDKG() external;
    function registerForDKG() external;
    function submitDealing(bytes32 _dealingHash) external;
    function finalizeDKG(bytes calldata _aggregatedPubKey, bytes32 _keyCommitment) external;

    // Key queries
    function getCurrentPublicKey() external view returns (bytes memory);
    function isEpochKeyValid(uint256 _epoch) external view returns (bool);
}
```

Key features:
- **Keyper registration**: Stake-based (minimum 1 ETH) with BLS public key
- **DKG phases**: Registration → Dealing → Finalization
- **Epoch-based keys**: Keys rotate with configurable epochs (~1 week)
- **Slashing**: Keypers can be slashed for misbehavior

#### EncryptedMempool Contract

Handles encrypted transaction submission and execution:

```solidity
// contracts/mev/EncryptedMempool.sol
contract EncryptedMempool {
    // User functions
    function submitEncryptedTx(
        bytes calldata _encryptedPayload,
        uint256 _epoch,
        uint256 _gasLimit,
        uint256 _maxFeePerGas
    ) external payable returns (bytes32 txId);

    function cancelEncryptedTx(bytes32 _txId) external;

    // Sequencer functions
    function commitOrdering(
        bytes32 _batchId,
        bytes32[] calldata _txIds,
        bytes32 _orderingRoot,
        bytes calldata _signature
    ) external;

    function submitDecryption(
        bytes32 _txId,
        address _to,
        bytes calldata _data,
        uint256 _value,
        bytes calldata _decryptionProof
    ) external;

    // Execution
    function executeDecryptedTx(bytes32 _txId) external;
}
```

Note: `submitEncryptedTx` treats any `msg.value` above `gasLimit * maxFeePerGas`
as a `valueDeposit` reserved to cover the decrypted call value. Unused value is
refunded to the sender after execution or expiry.

Transaction lifecycle:
1. **Pending** - User submits encrypted tx
2. **Ordered** - Sequencer commits to ordering
3. **Decrypted** - Keypers provide decryption
4. **Executed** - Transaction executed in order

#### SDK Integration

```typescript
// sdk/src/encryption.ts
import { createMEVProtectionClient } from '@setchain/sdk';

// Initialize client
const mevClient = createMEVProtectionClient(
  ENCRYPTED_MEMPOOL_ADDRESS,
  KEY_REGISTRY_ADDRESS,
  PRIVATE_KEY,
  RPC_URL
);

// Check if MEV protection is available
const available = await mevClient.isAvailable();

// Submit MEV-protected transaction
const { txId, waitForExecution } = await mevClient.submit(
  targetAddress,
  calldata,
  value,
  { gasLimit: 200000n }
);

// Wait for execution
const result = await waitForExecution();
console.log(`Success: ${result.success}`);
```

#### Keyper Network Infrastructure

Run a development keyper network:

```bash
# Start 3 keypers + coordinator
docker compose -f docker/docker-compose.keypers.yml --profile dev up -d

# Run DKG ceremony
docker compose -f docker/docker-compose.keypers.yml --profile dkg up
```

Configuration (`docker/keyper-config/keyper.example.toml`):
- Network settings (P2P, RPC, metrics)
- Chain connection (L2 RPC, contract addresses)
- Key management (stake, BLS keys)
- DKG parameters (timeout, retries)
- Decryption settings (workers, batch size)

### Phase 3: Forced Inclusion (1-2 months)

**Goal:** Censorship resistance via L1 forced inclusion

**Mechanism:**
1. User submits tx to L1 inclusion contract
2. After timeout, sequencer MUST include or face slashing
3. Provides escape hatch for censored users

**Contract:**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ForcedInclusion
 * @notice L1 contract for censorship-resistant transaction inclusion
 * @dev Deployed on L1, forces L2 sequencer to include transactions
 */
contract ForcedInclusion {
    uint256 public constant INCLUSION_DEADLINE = 24 hours;
    uint256 public constant BOND_AMOUNT = 0.1 ether;

    struct ForcedTx {
        address sender;
        bytes txData;
        uint256 gasLimit;
        uint256 deadline;
        bool included;
    }

    mapping(bytes32 => ForcedTx) public forcedTransactions;

    event TransactionForced(
        bytes32 indexed txId,
        address indexed sender,
        uint256 deadline
    );

    event TransactionIncluded(bytes32 indexed txId);

    function forceTransaction(
        bytes calldata txData,
        uint256 gasLimit
    ) external payable returns (bytes32 txId) {
        require(msg.value >= BOND_AMOUNT, "Insufficient bond");

        txId = keccak256(abi.encodePacked(msg.sender, txData, block.timestamp));

        forcedTransactions[txId] = ForcedTx({
            sender: msg.sender,
            txData: txData,
            gasLimit: gasLimit,
            deadline: block.timestamp + INCLUSION_DEADLINE,
            included: false
        });

        emit TransactionForced(txId, msg.sender, block.timestamp + INCLUSION_DEADLINE);
    }

    function confirmInclusion(
        bytes32 txId,
        bytes calldata inclusionProof
    ) external {
        ForcedTx storage forcedTx = forcedTransactions[txId];
        require(!forcedTx.included, "Already included");
        require(_verifyInclusion(txId, inclusionProof), "Invalid proof");

        forcedTx.included = true;

        // Return bond
        payable(forcedTx.sender).transfer(BOND_AMOUNT);

        emit TransactionIncluded(txId);
    }

    function _verifyInclusion(
        bytes32 txId,
        bytes calldata proof
    ) internal view returns (bool) {
        // Verify against L2 state root posted to L1
        // Implementation depends on L2OutputOracle
        return true; // Placeholder
    }
}
```

### Phase 4: Shared Sequencing Integration (3-6 months)

**Goal:** Decentralized sequencing with MEV protection

**Options:**
1. **Espresso Sequencer** - HotShot consensus, threshold encryption built-in
2. **Astria** - Shared sequencing layer, rollup agnostic
3. **Custom BFT** - In-house sequencer rotation

**Integration Points:**
- Sequencer selection/rotation
- Cross-L2 atomic bundles
- MEV auction mechanism

---

## Economic Considerations

### MEV Revenue Distribution

If MEV is captured (via MEV-Share or auction):

| Recipient | Share | Rationale |
|-----------|-------|-----------|
| Users (victims) | 50% | Compensation for extracted value |
| Protocol treasury | 30% | Sustainability fund |
| Sequencer operators | 20% | Operational incentive |

### Fee Adjustments

MEV protection adds costs:

| Component | Latency | Cost |
|-----------|---------|------|
| Threshold encryption | +100-200ms | +5-10% gas |
| Ordering attestation | +10ms | +1% gas |
| Forced inclusion | N/A | 0.1 ETH bond |

### Incentive Alignment

```
User: Pays slightly higher fee → Gets MEV protection
Sequencer: Can't extract MEV → Gets ordering fee + reputation
Protocol: Less MEV complaints → More adoption + fee revenue
```

---

## Monitoring & Metrics

### Key Metrics

| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| Ordering fairness score | >99% FCFS | <95% |
| Sandwich attack rate | 0% | >0.1% |
| Frontrunning incidents | 0/day | >1/day |
| Forced inclusion usage | <0.1% | >1% |
| Encryption latency | <200ms | >500ms |

### Dashboard Components

1. **Ordering Analysis**
   - Transaction timestamp vs inclusion order
   - Out-of-order transaction detection
   - Sequencer attestation verification rate

2. **MEV Detection**
   - Sandwich pattern detector
   - Frontrun pattern detector
   - Unusual profit transactions

3. **Encryption Health**
   - Threshold key availability
   - Decryption success rate
   - Encryption latency percentiles

### Alerting Rules

```yaml
# prometheus/alerts/mev.yml
groups:
  - name: mev_protection
    rules:
      - alert: HighOutOfOrderRate
        expr: rate(ordering_violations_total[5m]) > 0.01
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High transaction out-of-order rate"

      - alert: SandwichDetected
        expr: sandwich_attacks_total > 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Sandwich attack detected"

      - alert: EncryptionLatencyHigh
        expr: histogram_quantile(0.99, encryption_latency_seconds) > 0.5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Encryption latency above 500ms"
```

---

## Security Considerations

### Threshold Key Management

- **Key generation ceremony** with at least 5 participants
- **Geographic distribution** of key shares
- **Rotation schedule** every 6 months
- **Backup and recovery** procedures documented

### Attack Vectors on MEV Protection

| Attack | Mitigation |
|--------|------------|
| Sequencer collusion | Threshold encryption (t-of-n) |
| Key share leakage | HSM storage, rotation |
| Timing attacks | Constant-time operations |
| DoS on decryption | Multiple decrypt nodes |

### Fallback Mechanisms

If threshold decryption fails:
1. Timeout after 30 seconds
2. Fall back to plaintext submission
3. Alert operations team
4. Investigate root cause

### Security Assumptions for Proof Verification

#### ForcedInclusion Contract

The `confirmInclusion` function verifies that a forced transaction was included on L2.

**Assumptions:**
1. **L2OutputOracle is trusted**: The contract queries the L2OutputOracle for output roots. We assume the oracle correctly posts L2 state roots and is not compromised.
2. **Output roots are finalized**: Proofs should only be accepted for finalized (not disputed) output roots. The dispute game should have completed before claiming inclusion.
3. **Transaction hash binding**: The proof must demonstrate inclusion of a transaction with the exact parameters (sender, target, data, gasLimit) stored at request time. This prevents proof reuse attacks.
4. **Merkle proof validity**: The storage proof must correctly demonstrate that the transaction hash exists in the L2 block's transaction trie.

**Proof Structure:**
```solidity
// ABI-encoded proof
(
    bytes32 claimedOutputRoot,   // Must match L2OutputOracle
    bytes32 txRoot,              // Transactions root for the L2 block
    bytes32[] storageProof,      // Merkle proof path
    uint256 txIndex              // Index in transaction trie
)
```

#### EncryptedMempool Contract

The `submitDecryption` function verifies that decrypted data correctly corresponds to an encrypted payload.

**Assumptions:**
1. **Decryption commitment binding**: The proof must include a commitment that binds the decrypted data (to, data, value) to the original encrypted payload hash. This prevents the sequencer from substituting different transaction data.
2. **Threshold signature validity**: Keypers provide ECDSA signatures over the decryption commitment. The threshold (t-of-n) ensures no single keyper can forge a decryption proof.
3. **Epoch key validity**: The decryption must use the key from the correct epoch. Proofs from invalid or revoked epochs are rejected.
4. **No duplicate signers**: The proof must not contain duplicate keyper addresses to prevent signature replay.

**Proof Structure:**
```solidity
// ABI-encoded proof
(
    bytes signature,            // Concatenated 65-byte ECDSA signatures
    bytes32 decryptionCommitment, // keccak256(payloadHash, to, data, value)
    uint256 epoch,              // Must match tx.epoch
    address[] signers           // Keypers who signed (>= threshold, no duplicates)
)
```

**Commitment Verification:**
```
expectedCommitment = keccak256(abi.encodePacked(
    encryptedTx.payloadHash,  // From stored encrypted tx
    _to,                       // Decrypted target
    _data,                     // Decrypted calldata
    _value                     // Decrypted ETH value
))
```

This ensures that any modification to the decrypted transaction data will result in a commitment mismatch and proof rejection.

---

## References

- [Flashbots MEV-Share](https://docs.flashbots.net/flashbots-mev-share/overview)
- [Shutter Network](https://shutter.network/)
- [Espresso Sequencer](https://docs.espressosys.com/)
- [Chainlink FSS](https://blog.chain.link/chainlink-fair-sequencing-services-enabling-a-provably-fair-defi-ecosystem/)
- [OP Stack Sequencer](https://docs.optimism.io/stack/components/sequencer)
- [MEV on L2s Research](https://arxiv.org/abs/2303.04430)

---

## Appendix: Decision Matrix

| Criterion | Private Mempool | Commit-Reveal | Threshold Encrypt | Shared Sequencing |
|-----------|-----------------|---------------|-------------------|-------------------|
| MEV Protection | Low | Medium | High | High |
| Latency | None | +2 blocks | +200ms | +500ms |
| Complexity | None | Low | Medium | High |
| Decentralization | None | None | Medium | High |
| Commerce Fit | Good | Poor | Good | Good |
| Implementation | Done | 2 weeks | 2-3 months | 6+ months |

**Recommendation:** Start with Phase 1 (Ordering Transparency), then Phase 2
(Threshold Encryption) for production-grade MEV protection.
