# OP Stack Integration

Set Chain is built on Optimism's OP Stack, inheriting its battle-tested rollup architecture while adding commerce-specific features.

## OP Stack Overview

The OP Stack is a modular, open-source framework for building L2 blockchains. Set Chain uses these core components:

```
┌─────────────────────────────────────────────────────────┐
│                    Set Chain L2                         │
├─────────────────────────────────────────────────────────┤
│  Set-Specific Components                                │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐       │
│  │ SetRegistry │ │   ssUSD     │ │ MEV Protect │       │
│  └─────────────┘ └─────────────┘ └─────────────┘       │
├─────────────────────────────────────────────────────────┤
│  OP Stack Components                                    │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐       │
│  │  op-node   │ │  op-geth    │ │  op-batcher │       │
│  └─────────────┘ └─────────────┘ └─────────────┘       │
│  ┌─────────────┐ ┌─────────────┐                       │
│  │ op-proposer │ │ Fault Proof │                       │
│  └─────────────┘ └─────────────┘                       │
├─────────────────────────────────────────────────────────┤
│                 Ethereum L1                             │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐       │
│  │ OptimismPortal│ L2OutputOracle│ SystemConfig │       │
│  └─────────────┘ └─────────────┘ └─────────────┘       │
└─────────────────────────────────────────────────────────┘
```

## Core OP Stack Components

### op-node

The consensus client that:
- Derives L2 blocks from L1 data
- Maintains the canonical chain
- Handles reorgs and finalization

Set Chain runs a customized op-node with:
- MEV protection hooks
- Enhanced mempool management
- VES batch coordination

### op-geth

Modified go-ethereum execution client:
- Executes L2 transactions
- Maintains state
- Provides RPC interface

Set Chain additions:
- Encrypted transaction support
- Gas sponsorship integration
- Custom precompiles (future)

### op-batcher

Batches L2 transactions to L1:
- Compresses transaction data
- Submits to L1 in batches
- Optimizes gas costs

### op-proposer

Proposes L2 output roots to L1:
- Periodic state root submissions
- Enables withdrawals
- Supports fault proofs

## L1 Contracts

### OptimismPortal

The main entry point for L1↔L2 messaging:

```solidity
interface IOptimismPortal {
    // Deposit ETH/tokens to L2
    function depositTransaction(
        address _to,
        uint256 _value,
        uint64 _gasLimit,
        bool _isCreation,
        bytes memory _data
    ) external payable;

    // Finalize L2→L1 withdrawal
    function finalizeWithdrawalTransaction(
        Types.WithdrawalTransaction memory _tx
    ) external;
}
```

### L2OutputOracle

Stores L2 state commitments:

```solidity
interface IL2OutputOracle {
    // Get output at index
    function getL2Output(uint256 _l2OutputIndex)
        external view returns (Types.OutputProposal memory);

    // Get output for block
    function getL2OutputAfter(uint256 _l2BlockNumber)
        external view returns (Types.OutputProposal memory);
}
```

Used by Set Chain's ForcedInclusion for censorship resistance proofs.

### SystemConfig

L2 system parameters stored on L1:

```solidity
interface ISystemConfig {
    function batcherHash() external view returns (bytes32);
    function gasLimit() external view returns (uint64);
    function basefeeScalar() external view returns (uint32);
    function blobbasefeeScalar() external view returns (uint32);
}
```

## Data Availability

Set Chain uses Ethereum L1 for data availability (DA):

```
Transaction Flow:
1. User submits tx to Set Chain sequencer
2. Sequencer executes and batches
3. Batcher compresses and posts to L1
4. Anyone can reconstruct L2 state from L1 data
```

### Blob Transactions (EIP-4844)

Set Chain supports blob transactions for cheaper DA:

```
Cost Comparison (approximate):
- Calldata: ~16 gas/byte
- Blobs: ~1 gas/byte equivalent

Savings: ~90% reduction in DA costs
```

## Deposits (L1 → L2)

### Standard Bridge

```typescript
import { Contract } from "ethers";

// On L1
const bridge = new Contract(L1_BRIDGE_ADDRESS, L1BridgeABI, l1Signer);

// Deposit ETH
await bridge.depositETH(200000, "0x", { value: parseEther("1.0") });

// Deposit ERC20
await token.approve(bridge.address, amount);
await bridge.depositERC20(tokenL1, tokenL2, amount, 200000, "0x");
```

### Custom Messages

```typescript
// Send arbitrary message L1→L2
const messenger = new Contract(L1_MESSENGER, MessengerABI, l1Signer);

await messenger.sendMessage(
    targetL2Contract,
    calldata,
    gasLimit
);
```

## Withdrawals (L2 → L1)

Withdrawals require a waiting period for fault proof finalization:

```
L2 Withdrawal Flow:
1. Initiate withdrawal on L2 (instant)
2. Wait for output proposal (~1 hour)
3. Wait for challenge period (7 days)
4. Prove withdrawal on L1
5. Finalize and receive funds
```

### Initiating Withdrawal

```typescript
// On L2
const bridge = new Contract(L2_BRIDGE_ADDRESS, L2BridgeABI, l2Signer);

// Withdraw ETH
await bridge.withdraw(
    ETH_ADDRESS,
    amount,
    0,  // extra data
    { value: amount }
);

// Withdraw ERC20
await bridge.withdrawTo(
    tokenL2,
    recipient,
    amount,
    0,
    "0x"
);
```

### Proving & Finalizing

```typescript
// After challenge period, on L1
const portal = new Contract(PORTAL_ADDRESS, PortalABI, l1Signer);

// Prove withdrawal
await portal.proveWithdrawalTransaction(
    withdrawalTx,
    outputIndex,
    outputProof,
    withdrawalProof
);

// Wait additional finalization period...

// Finalize
await portal.finalizeWithdrawalTransaction(withdrawalTx);
```

## Set Chain Customizations

### Enhanced Sequencer

Set Chain's sequencer includes:

1. **Encrypted Mempool Support**
   - Accepts encrypted transactions
   - Coordinates with keyper network
   - Commits ordering before decryption

2. **VES Batch Coordination**
   - Monitors SetRegistry submissions
   - Ensures proper sequencing
   - Handles state root transitions

3. **Gas Sponsorship Integration**
   - Checks SetPaymaster policies
   - Sponsors eligible transactions
   - Tracks merchant balances

### Custom Precompiles (Planned)

Future precompiles for:
- Efficient Merkle proof verification
- Threshold signature verification
- NAV calculations

### Modified Fee Structure

Set Chain uses custom gas pricing:

```solidity
// L2 gas price = base fee + priority fee
// Base fee adjusts based on congestion
// L1 data fee based on blob/calldata costs

totalFee = (gasUsed * gasPrice) + (dataSize * l1DataFee)
```

## Network Parameters

| Parameter | Testnet | Mainnet (Planned) |
|-----------|---------|-------------------|
| Chain ID | 84532001 | TBD |
| Block Time | 2 seconds | 2 seconds |
| Gas Limit | 30M | 30M |
| Challenge Period | 7 days | 7 days |
| Output Proposal Interval | 1 hour | 1 hour |

## Running a Node

### Full Node

```bash
# Clone op-geth
git clone https://github.com/setchain/op-geth.git
cd op-geth && make geth

# Clone op-node
git clone https://github.com/setchain/op-node.git
cd op-node && make op-node

# Start op-geth
./geth \
    --datadir=/data/geth \
    --http \
    --http.addr=0.0.0.0 \
    --http.port=8545 \
    --ws \
    --ws.addr=0.0.0.0 \
    --ws.port=8546 \
    --rollup.sequencerhttp=https://sequencer.setchain.io \
    --rollup.disabletxpoolgossip

# Start op-node
./op-node \
    --l1=https://eth-mainnet.example.com \
    --l2=http://localhost:8551 \
    --network=setchain-mainnet \
    --rpc.addr=0.0.0.0 \
    --rpc.port=9545
```

### Archive Node

Add to geth flags:
```bash
--gcmode=archive \
--syncmode=full
```

## Upgrades

Set Chain follows OP Stack upgrade cycles:

1. **Bedrock** - Current base
2. **Canyon** - EIP-1153, 4788, 5656, 6780
3. **Delta** - Span batches
4. **Ecotone** - Blob support (EIP-4844)
5. **Fjord** - Further optimizations

Upgrade schedule aligns with Optimism mainnet, typically 2-4 weeks after OP mainnet activation.

## Related

- [Architecture Overview](./overview.md)
- [Data Flow](./data-flow.md)
- [Trust Model](./trust-model.md)
- [Optimism Docs](https://docs.optimism.io)
