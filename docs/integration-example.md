# Merchant Integration Example

This example shows how an app can verify inclusion proofs for commerce events
using the SetRegistry contract.

## Local Devnet Flow
1. Start Anvil and deploy contracts:

```bash
./scripts/dev.sh start
./scripts/dev.sh deploy
```

2. Run the smoke test to create a commitment and verify proofs:

```bash
./scripts/dev.sh smoke
```

3. Query the latest state root for a tenant/store pair:

```bash
# Replace TENANT_ID and STORE_ID as needed
cast call $SET_REGISTRY_ADDRESS \
  "getLatestStateRoot(bytes32,bytes32)(bytes32)" \
  $TENANT_ID $STORE_ID \
  --rpc-url http://localhost:8545
```

## Application-Level Verification
A merchant app should store the event leaf and Merkle proof returned by the
sequencer API, then call `verifyInclusion` on-chain to confirm the event is
anchored in SetRegistry.

```bash
cast call $SET_REGISTRY_ADDRESS \
  "verifyInclusion(bytes32,bytes32,bytes32[],uint256)(bool)" \
  $BATCH_ID $EVENT_LEAF "[$PROOF_0,$PROOF_1]" $INDEX \
  --rpc-url http://localhost:8545
```

## Notes
- For production, use the real sequencer API and store proofs alongside your
  order metadata.
- The anchor service ensures commitments are persisted on L2 for verification.
