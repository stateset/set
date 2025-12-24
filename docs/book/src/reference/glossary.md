# Glossary

Key terms and concepts used in Set Chain documentation.

## A

### Anchor Service
A Rust service that bridges the off-chain stateset-sequencer to on-chain SetRegistry by polling pending commitments and submitting them to the blockchain.

### APY (Annual Percentage Yield)
The annualized rate of return including compound interest. ssUSD targets approximately 5% APY from T-Bill yield.

### Attestor
An authorized entity that submits NAV (Net Asset Value) updates to the NAVOracle contract. Currently operated by the Set Chain team.

## B

### Batch Commitment
A cryptographic commitment to a set of commerce events, including Merkle root, state roots, and sequence numbers. Stored on-chain in SetRegistry.

### BLS (Boneh-Lynn-Shacham)
A signature scheme used for threshold cryptography in the encrypted mempool system.

## C

### Censorship Resistance
The property ensuring transactions cannot be permanently excluded by the sequencer. Achieved via forced inclusion through L1.

### Collateral
Assets deposited to mint ssUSD. Currently accepts USDC and USDT.

### Commitment
See [Batch Commitment](#batch-commitment).

## D

### DKG (Distributed Key Generation)
The ceremony through which keypers generate a shared threshold encryption key without any single party knowing the full private key.

## E

### EIP-4844
Ethereum improvement proposal introducing blob transactions for cheaper L2 data availability. Used by Set Chain for batch submission.

### Encrypted Mempool
A system where transactions are encrypted until ordering is committed, preventing frontrunning and sandwich attacks.

### ERC-4626
The tokenized vault standard. wssUSD implements ERC-4626 for DeFi compatibility.

### Event Sourcing
A pattern where state changes are stored as a sequence of events. Set Chain anchors commerce events using this pattern.

## F

### Fault Proof
A cryptographic proof that demonstrates incorrect state transition, enabling trustless L2 verification.

### Forced Inclusion
A mechanism allowing users to submit transactions via L1 if the sequencer censors them.

### Frontrunning
An MEV attack where an attacker sees a pending transaction and inserts their own transaction before it.

## G

### Gas Sponsorship
A feature where merchants pay gas fees on behalf of their customers. Implemented via SetPaymaster.

## K

### Keyper
A participant in the threshold encryption network who holds a share of the decryption key.

## L

### L1 (Layer 1)
The base layer blockchain (Ethereum) that provides security and data availability for Set Chain.

### L2 (Layer 2)
A scaling solution built on top of L1. Set Chain is an L2 on Ethereum.

## M

### Merkle Proof
A cryptographic proof that a specific data element is included in a Merkle tree.

### Merkle Root
The top hash of a Merkle tree, representing a commitment to all leaves in the tree.

### MEV (Maximal Extractable Value)
The maximum value that can be extracted by reordering, inserting, or censoring transactions.

## N

### NAV (Net Asset Value)
The per-share value of ssUSD, calculated as total assets divided by total shares.

### NAVOracle
The contract that receives and stores daily NAV attestations for the ssUSD system.

## O

### OP Stack
Optimism's modular L2 framework that Set Chain is built upon.

### Ordering Commitment
A cryptographic commitment to transaction ordering made by the sequencer.

## P

### Pause Mechanism
Emergency controls that allow pausing deposits or redemptions during security incidents.

### Proxy (UUPS)
Universal Upgradeable Proxy Standard - the upgrade pattern used by Set Chain contracts.

## R

### Rebasing
A mechanism where token balances automatically adjust based on underlying value changes. ssUSD is a rebasing token.

### Redemption
The process of exchanging ssUSD for underlying collateral (USDC/USDT).

### Rollup
An L2 scaling solution that posts transaction data to L1. Set Chain is an optimistic rollup.

## S

### Sandwich Attack
An MEV attack placing transactions before AND after a victim transaction to extract value.

### Sequencer
The entity responsible for ordering and executing transactions on L2.

### SetPaymaster
The contract managing gas sponsorship for merchants.

### SetRegistry
The core contract for anchoring batch commitments and verifying Merkle proofs.

### SetTimelock
The governance contract enforcing time delays on upgrades and admin actions.

### Shares
The internal unit of ownership in ssUSD. Balance = Shares × NAV per Share.

### ssUSD
Set Stablecoin USD - the rebasing, yield-bearing stablecoin native to Set Chain.

### Staleness
The condition where NAV data is too old (>24 hours), potentially restricting operations.

### STARK Proof
A type of zero-knowledge proof used for compliance attestation in Set Chain.

### State Root
A cryptographic commitment to the entire state of a system at a point in time.

### Strict Mode
A SetRegistry configuration requiring state root continuity between batches.

## T

### T-Bills (Treasury Bills)
U.S. government short-term debt securities that back ssUSD's yield.

### Tenant
A top-level entity in the multi-tenant SetRegistry system.

### Threshold Encryption
A cryptographic system requiring multiple parties to cooperate for decryption.

### Timelock
A smart contract that enforces waiting periods before executing sensitive operations.

### TokenRegistry
The contract maintaining the whitelist of approved tokens and collateral.

### TreasuryVault
The contract managing collateral deposits, ssUSD minting, and redemptions.

## U

### UUPS
See [Proxy (UUPS)](#proxy-uups).

## V

### Validium
An L2 scaling solution with off-chain data availability. VES combines validium concepts with event sourcing.

### VES (Validium-style Event Sourcing)
Set Chain's anchoring system that commits Merkle roots of off-chain events on-chain.

### Verification
The process of proving event inclusion using Merkle proofs against on-chain commitments.

## W

### wssUSD
Wrapped ssUSD - an ERC-4626 token that doesn't rebase, suitable for DeFi.

### Wrap
Convert ssUSD to wssUSD for DeFi compatibility.

## Y

### Yield
The return earned on ssUSD from underlying T-Bill holdings, distributed via rebasing.

---

## Related

- [Architecture Overview](../architecture/overview.md)
- [ssUSD Overview](../stablecoin/overview.md)
- [MEV Protection](../mev/overview.md)
