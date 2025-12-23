# Set Chain Glossary

A comprehensive glossary of terms used in Set Chain documentation and codebase.

## Core Concepts

### Batch Commitment
A cryptographic commitment to a set of off-chain commerce events. Contains a Merkle root (`eventsRoot`), state roots (`prevStateRoot`, `newStateRoot`), and sequence information. Anchored on-chain via `SetRegistry.commitBatch()`.

### State Root
A Merkle root representing the complete state of a tenant/store at a specific point in time. Used for state chain continuity verification.

### Events Root
A Merkle root of all commerce events included in a batch. Enables on-chain verification that specific events were included in a committed batch.

### Tenant/Store Isolation
Multi-tenant architecture where each tenant (merchant) and store has isolated state tracking. Key derived as `keccak256(tenantId, storeId)`.

### Strict Mode
When enabled, SetRegistry enforces state chain continuity - batches must build on the previous state root with no gaps.

### Merkle Inclusion Proof
Cryptographic proof that a specific leaf (event) is included in a Merkle tree. Used with `verifyInclusion()` to prove event membership.

## Layer 2 / OP Stack

### OP Stack
Optimism's modular framework for building Layer 2 rollups. Set Chain is built on OP Stack v1.8.0+.

### Optimistic Rollup
A Layer 2 scaling solution where transactions are assumed valid by default, with a dispute period during which fraud proofs can be submitted.

### Sequencer
The entity responsible for ordering transactions and producing L2 blocks. In Set Chain, also anchors batch commitments.

### Batcher (op-batcher)
OP Stack component that batches L2 transactions and submits them to L1 for data availability.

### Proposer (op-proposer)
OP Stack component that submits L2 state root proposals to L1.

### Fault Proof / Dispute Game
Mechanism to challenge incorrect state transitions. Allows anyone to prove the sequencer submitted invalid state.

### Safe Head
The latest L2 block that has been verified safe (all L1 data available). Used for finality calculations.

### Unsafe Head
The latest L2 block produced by the sequencer, not yet confirmed by L1 data.

### Finalized Head
The latest L2 block that cannot be reorganized (L1 finality reached).

## MEV Protection

### MEV (Maximal Extractable Value)
Value extracted by reordering, inserting, or censoring transactions. Set Chain protects against MEV via ordering commitments and encrypted mempool.

### Frontrunning
MEV attack where a malicious actor observes a pending transaction and submits their own transaction first to profit.

### Sandwich Attack
MEV attack that places transactions before and after a victim's transaction to extract value (common in DEX trades).

### Censorship Resistance
Guarantee that valid transactions will be included, preventing sequencers from selectively excluding transactions.

### FCFS (First-Come-First-Serve) Policy
Ordering policy where transactions are processed in the order they arrive. Set Chain commits to FCFS ordering.

### Ordering Commitment
On-chain commitment by the sequencer to a specific transaction ordering. Enables verification that ordering was not manipulated.

### Sequencer Attestation
Cryptographic signature from the sequencer attesting to the ordering of transactions in a block.

### Encrypted Mempool
Phase 2 MEV protection where transactions are encrypted until ordering is committed, preventing frontrunning.

### Threshold Encryption
Encryption scheme where multiple parties (keypers) must cooperate to decrypt. No single party can access plaintext.

### DKG (Distributed Key Generation)
Cryptographic protocol where multiple parties jointly generate a public key and key shares without any single party knowing the full private key.

### Keyper
A participant in the threshold encryption network. Holds a share of the decryption key and participates in DKG.

### Epoch
A period during which a specific threshold public key is valid. New epochs are created through DKG.

### Key Share
A fragment of the decryption key held by a single keyper. Threshold number of shares needed to decrypt.

### Decryption Proof
Cryptographic proof that decryption was performed correctly using valid key shares.

### Forced Inclusion
L1 mechanism allowing users to force transaction inclusion on L2 if the sequencer censors them.

## Stablecoin (ssUSD)

### ssUSD
Set Chain's native rebasing stablecoin backed by T-Bill holdings. 18 decimals.

### wssUSD
Wrapped ssUSD - a non-rebasing ERC4626 wrapper for DeFi compatibility. Share price increases with yield instead of balance.

### Rebasing
Mechanism where token balances automatically adjust to reflect yield. ssUSD balances grow over time.

### NAV (Net Asset Value)
The total value of underlying assets (T-Bills) per share. Used to calculate ssUSD exchange rates.

### NAV Oracle
Contract that receives and validates NAV attestations from authorized attestors.

### NAV Attestor
Authorized entity that submits NAV updates based on off-chain T-Bill valuations.

### Collateral Token
Tokens accepted as deposit collateral for minting ssUSD (USDC, USDT).

### Token Registry
Contract managing the whitelist of approved tokens and their metadata.

### Treasury Vault
Contract managing collateral deposits, redemption queue, and ssUSD minting/burning.

### Redemption Queue
Queue of pending ssUSD redemption requests. Subject to T+1 settlement delay.

### Shares (Internal)
Internal accounting unit for ssUSD. Balance = shares × NAV per share.

## Gas Sponsorship

### SetPaymaster
Contract enabling merchants to sponsor gas fees for their users.

### Sponsorship Tier
Predefined spending limit configuration (Starter, Growth, Enterprise).

### Sponsored Transaction
A transaction where gas fees are paid by the merchant instead of the user.

### Operation Type
Category of sponsored operation (ORDER_CREATE, PAYMENT_PROCESS, INVENTORY_UPDATE, etc.).

### Daily/Monthly Limit
Maximum sponsorship amount per merchant per day/month.

### Operator
Authorized address that can execute sponsorships on behalf of merchants.

## Governance

### SetTimelock
OpenZeppelin-based timelock contract for governance operations.

### Timelock Delay
Minimum waiting period between proposing and executing governance actions. 24h mainnet, 1h testnet.

### Multisig (Safe)
Multi-signature wallet requiring multiple signers to approve transactions. Used for admin keys.

### Proposer Role
Governance role that can propose timelock operations.

### Executor Role
Governance role that can execute queued timelock operations after delay.

### Admin Renunciation
Removing direct admin access, leaving only timelock-gated operations.

## Contract Architecture

### UUPS (Universal Upgradeable Proxy Standard)
Proxy pattern where upgrade logic lives in the implementation contract. Used by SetRegistry, SetPaymaster.

### Proxy
Contract that delegates all calls to an implementation contract. Enables upgrades.

### Implementation
The actual contract logic behind a proxy. Can be upgraded.

### Initializer
Function replacing constructor in upgradeable contracts. Called once after proxy deployment.

### ReentrancyGuard
Security pattern preventing recursive calls to vulnerable functions.

## Infrastructure

### RPC (Remote Procedure Call)
API for interacting with blockchain nodes. Set Chain: port 8545 (HTTP), 8546 (WebSocket).

### Engine API
Consensus client API for L2 nodes. Port 8551, JWT-authenticated.

### Blockscout
Open-source block explorer used for Set Chain.

### Prometheus
Metrics collection system for monitoring node health.

### Grafana
Visualization platform for Prometheus metrics.

## SDK Terms

### Provider
ethers.js class for read-only blockchain access.

### Signer/Wallet
ethers.js class for signing transactions.

### ABI (Application Binary Interface)
JSON specification of contract function signatures and types.

### Gas Estimation
Process of predicting gas usage before transaction submission.

### Gas Buffer
Safety margin added to gas estimates (typically 20%).

### Retry with Backoff
Strategy for handling transient failures by retrying with increasing delays.

## Cryptography

### BLS Signature
Boneh-Lynn-Shacham signature scheme used for threshold signatures.

### Merkle Tree
Binary tree structure enabling efficient inclusion proofs. Used for events and state roots.

### keccak256
Ethereum's hash function. Used for content addressing and Merkle trees.

### Domain Separator (EIP-712)
Chain-specific prefix for structured data signing, preventing cross-chain replay.

### Signature (v, r, s)
ECDSA signature components. v is recovery ID, r and s are signature values.
