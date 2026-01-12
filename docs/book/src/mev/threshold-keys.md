# Threshold Keys

Deep dive into the distributed key generation and management system.

## Overview

Set Chain uses threshold cryptography to enable encrypted transactions without a single point of failure:

```
Traditional Encryption:          Threshold Encryption:
┌─────────────────────┐         ┌─────────────────────┐
│ Single key holder   │         │ 5 keypers           │
│                     │         │ Need 3 to decrypt   │
│ Risk: Single point  │         │                     │
│ of failure          │         │ No single point     │
│                     │         │ of failure          │
└─────────────────────┘         └─────────────────────┘
```

## Threshold Cryptography

### (t, n) Threshold Scheme

Set Chain uses a (3, 5) threshold scheme:
- **n = 5**: Total number of keypers
- **t = 3**: Minimum shares needed to decrypt
- Any 3 of 5 keypers can reconstruct the decryption key
- No single keyper can decrypt alone

### Security Properties

| Property | Guarantee |
|----------|-----------|
| Confidentiality | < t keypers cannot decrypt |
| Availability | System works with n - t + 1 keypers online |
| Non-repudiation | Decryption requires threshold participation |

## Distributed Key Generation (DKG)

### DKG Process

New keys are generated through a distributed ceremony:

```
┌─────────────────────────────────────────────────────────────┐
│                  DKG Ceremony                                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Phase 1: Commitment                                         │
│  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐                   │
│  │ K1  │ │ K2  │ │ K3  │ │ K4  │ │ K5  │                   │
│  └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘                   │
│     │       │       │       │       │                        │
│     └───────┴───────┴───────┴───────┘                        │
│                     │                                         │
│            Commit to polynomial                               │
│                     │                                         │
│  Phase 2: Share Distribution                                  │
│                     │                                         │
│     ┌───────┬───────┼───────┬───────┐                        │
│     ▼       ▼       ▼       ▼       ▼                        │
│  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐                   │
│  │Share│ │Share│ │Share│ │Share│ │Share│                   │
│  │  1  │ │  2  │ │  3  │ │  4  │ │  5  │                   │
│  └─────┘ └─────┘ └─────┘ └─────┘ └─────┘                   │
│                                                              │
│  Phase 3: Verification                                       │
│  Each keyper verifies received shares                        │
│                                                              │
│  Phase 4: Finalization                                       │
│  Aggregate public key computed                               │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### DKG Contract Interface

```solidity
interface IThresholdKeyRegistry {
    // Initiate new DKG ceremony
    function initiateDKG() external returns (uint256 epoch);

    // Phase 1: Submit commitment
    function submitCommitment(
        uint256 epoch,
        bytes32 commitment
    ) external;

    // Phase 2: Submit encrypted shares
    function submitShares(
        uint256 epoch,
        bytes[] calldata encryptedShares
    ) external;

    // Phase 3: Report complaints
    function submitComplaint(
        uint256 epoch,
        address accused,
        bytes calldata proof
    ) external;

    // Phase 4: Finalize DKG
    function finalizeDKG(uint256 epoch) external;

    // Get current public key
    function getCurrentPublicKey() external view returns (bytes memory);
}
```

### DKG Timeline

```
Block N:        initiateDKG()
Block N+10:     Commitment deadline
Block N+30:     Share distribution deadline
Block N+50:     Complaint deadline
Block N+60:     finalizeDKG()
Block N+61:     New key active
```

## Keyper Network

### Keyper Requirements

To become a keyper:
1. **Stake**: Deposit required stake (future: slashing)
2. **Infrastructure**: Run reliable keyper node
3. **Availability**: High uptime requirements
4. **Security**: Hardware security module (recommended)

### Keyper Registration

```solidity
function registerKeyper(
    bytes calldata publicKeyShare
) external payable {
    require(msg.value >= MIN_STAKE, "InsufficientStake");
    require(!isKeyper[msg.sender], "AlreadyKeyper");

    keypers.push(msg.sender);
    keyperPublicKeys[msg.sender] = publicKeyShare;
    isKeyper[msg.sender] = true;
    stakes[msg.sender] = msg.value;

    emit KeyperRegistered(msg.sender, publicKeyShare);
}
```

### Current Keyper Set

```typescript
async function getKeyperInfo() {
    const registry = new Contract(KEY_REGISTRY, ThresholdKeyRegistryABI, provider);

    const keypers = await registry.getKeypers();
    const threshold = await registry.getThreshold();
    const currentEpoch = await registry.getCurrentEpoch();

    return {
        keypers: keypers,
        count: keypers.length,
        threshold: threshold,
        currentEpoch: currentEpoch,
        publicKey: await registry.getCurrentPublicKey()
    };
}
```

## Key Rotation

### Epoch-Based Rotation

Keys rotate periodically for security:

```
Epoch 1: Key A active (blocks 0-10000)
         │
         ▼
Epoch 2: DKG for Key B (blocks 9900-10000)
         │
         ▼
Epoch 2: Key B active (blocks 10000-20000)
         │
         ▼
Epoch 3: DKG for Key C (blocks 19900-20000)
         ...
```

### Rotation Schedule

| Parameter | Value | Description |
|-----------|-------|-------------|
| Epoch length | 10,000 blocks | ~5.5 hours |
| DKG start | 100 blocks before | Time for DKG |
| Transition window | 10 blocks | Both keys valid |

### Handling Rotation

```typescript
// Check if near epoch transition
const currentBlock = await provider.getBlockNumber();
const epochLength = await keyRegistry.epochLength();
const currentEpoch = await keyRegistry.getCurrentEpoch();
const epochStart = currentEpoch * epochLength;
const blocksRemaining = epochStart + epochLength - currentBlock;

if (blocksRemaining < 50) {
    console.warn("Epoch transition soon - submit transactions carefully");

    // Use next epoch's key for new transactions
    const nextPublicKey = await keyRegistry.getPublicKey(currentEpoch + 1n);
    if (nextPublicKey) {
        // Encrypt with next epoch's key
    }
}
```

## Decryption Share Release

### Release Process

After ordering is committed, keypers release shares:

```typescript
// Keyper node logic
async function releaseDecryptionShares(blockNumber: number) {
    // Verify ordering was committed
    const commitment = await attestation.getOrderingCommitment(blockNumber);
    if (!commitment.timestamp) {
        throw new Error("Ordering not committed");
    }

    // Get transactions to decrypt
    const txIds = await encryptedMempool.getOrderedTransactions(blockNumber);

    // Generate decryption shares
    for (const txId of txIds) {
        const share = await generateDecryptionShare(txId, keyperPrivateShare);

        // Submit share on-chain
        await encryptedMempool.releaseKeyShare(blockNumber, share);
    }
}
```

### Share Verification

```solidity
function _verifyKeyShare(
    bytes32 txId,
    address keyper,
    bytes calldata share
) internal view returns (bool) {
    // Verify share is from registered keyper
    require(isKeyper[keyper], "NotKeyper");

    // Verify share is valid for this transaction
    bytes memory publicShare = keyperPublicKeys[keyper];
    return _verifyShareProof(txId, publicShare, share);
}
```

## Threshold Signature Verification

### Signature Aggregation

For some operations, threshold signatures are used:

```solidity
// Verify threshold signature
function verifyThresholdSignature(
    bytes32 messageHash,
    bytes[] calldata signatures,
    address[] calldata signers
) public view returns (bool) {
    require(signatures.length >= threshold, "InsufficientSignatures");
    require(signatures.length == signers.length, "LengthMismatch");

    // Verify each signature is from a keyper
    for (uint256 i = 0; i < signers.length; i++) {
        require(isKeyper[signers[i]], "NotKeyper");
        require(
            _verifySignature(messageHash, signatures[i], signers[i]),
            "InvalidSignature"
        );
    }

    return true;
}
```

## Security Considerations

### Keyper Compromise

If a keyper is compromised:
- **< threshold**: No impact on security
- **= threshold**: Can decrypt (but need coordination)
- **> threshold**: Critical - initiate emergency rotation

### Mitigation Strategies

1. **Geographic Distribution**: Keypers in different jurisdictions
2. **Hardware Security**: HSMs for key storage
3. **Independent Operators**: Different organizations
4. **Regular Rotation**: Limit exposure window
5. **Monitoring**: Detect suspicious activity

### Emergency Procedures

```solidity
// Emergency key rotation (guardian-triggered)
function emergencyRotation(
    bytes[] calldata guardianSignatures
) external {
    require(
        verifyGuardianThreshold(guardianSignatures),
        "InsufficientGuardians"
    );

    // Invalidate current keys
    invalidatedEpochs[currentEpoch] = true;

    // Initiate emergency DKG
    _initiateDKG();

    emit EmergencyRotation(currentEpoch);
}
```

## Monitoring

### Health Checks

```typescript
async function checkKeyperHealth() {
    const registry = new Contract(KEY_REGISTRY, ThresholdKeyRegistryABI, provider);

    const keypers = await registry.getKeypers();
    const threshold = await registry.getThreshold();

    let onlineCount = 0;
    const keyperStatus = [];

    for (const keyper of keypers) {
        const isOnline = await checkKeyperOnline(keyper);
        if (isOnline) onlineCount++;

        keyperStatus.push({
            address: keyper,
            online: isOnline,
            lastActivity: await getLastKeyperActivity(keyper)
        });
    }

    return {
        totalKeypers: keypers.length,
        onlineKeypers: onlineCount,
        threshold: threshold,
        healthy: onlineCount >= threshold,
        keypers: keyperStatus
    };
}
```

### Alerts

```typescript
// Alert if keyper availability drops
if (onlineCount < threshold) {
    alerting.critical("Insufficient keypers online!", {
        online: onlineCount,
        required: threshold
    });
}

// Alert if approaching epoch transition without DKG
if (blocksToTransition < 100 && !dkgInProgress) {
    alerting.warning("DKG not started for next epoch!", {
        currentEpoch,
        blocksRemaining: blocksToTransition
    });
}
```

## Related

- [MEV Protection Overview](./overview.md)
- [Encrypted Mempool](./encrypted-mempool.md)
- [Trust Model](../architecture/trust-model.md)
- [MEV Contracts API](../contracts/mev-contracts.md)
