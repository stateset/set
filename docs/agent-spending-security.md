# Agent spending security and remaining integration gates

## Implemented protections

The V2 policy module rejects configuration limits, individual spend amounts and
commitment totals that cannot be represented by its packed uint128 accounting.
Commerce and gas consumers share one daily spend counter. Capacity checks apply
even when a configured limit is zero (zero means no configured limit, not an
infinite accounting representation). Combined minimum collateral and commitments
are added as uint256 values.

Administrators can call `setPolicyRevoked(agent, true)` to stop new commerce/gas
consumption and new commitments. Revocation does not erase daily usage, merchant
allowlists or existing commitments. `setPolicy` does not implicitly restore a
revoked policy; restoration requires `setPolicyRevoked(agent, false)`. Releasing
an existing commitment remains permitted for authorized consumers after revocation
or session expiry so refund/settlement cleanup is not trapped by a spending stop.

Only trusted contracts should receive `POLICY_CONSUMER_ROLE`. A consumer must bind
the debited agent, recipient and amount to its actual authorized transfer and
consume the budget in the same transaction. The policy module does not move funds
or authenticate a buyer's purchase intent by itself.

## SDK and signer boundary

`AgentClient` and `createAgentClient` accept an ethers `Signer` with a connected
provider. Applications can use an external signing service or a policy-enforcing
wallet rather than pass a raw private key into the SDK:

```ts
const agent = createAgentClient({ addresses, signer: approvedBackendSigner });
```

The signer implementation is supplied by the application; this change is not a
built-in HSM/KMS integration or a session-key wallet. Keep it behind authenticated
server-side controls. Never expose arbitrary signing, approvals, calldata or an
unrestricted wallet key to the model. The legacy privateKey/rpcUrl constructor
remains available for controlled environments; mixed signer/key options reject.
Deployment addresses are copied at construction, preventing later mutations to
the caller's configuration object from changing the client's approval targets.

The SDK decodes `policies` in the packed Solidity declaration order and queries
revocation when computing status. A revoked policy reports zero available spend
and fails the SDK payment preflight. Receipt confirmation is not L1 finality.

## Critical limit: raw transfers are not policy-enforced

An opt-in [restricted payment account](agent-payment-account.md) now provides a
separate atomic direct-payment path for funds held by that account. It is a local
integration candidate, not a deployed replacement for the methods below.

`transfer()` is an ordinary token transfer. `pay()` adds an advisory SDK preflight
but then calls that transfer; it does not atomically consume the policy budget.
Two independent clients can both pass a preflight before either submits. Neither
path is an autonomous-agent spending boundary when the agent controls an
unrestricted wallet. Use a constrained signing/account execution boundary and
tested policy-consuming commerce paths. Revocation cannot revoke an independently
controlled token owner's ability to send ERC20 transfers.

## Compatibility and rollout

- This SDK requires the updated V2 policy getter layout and `policyRevoked` API.
  Older deployments without that method fail the status query; there is no
  permissive fallback that assumes an unknown policy is active.
- Previously passing uint256 maximum values to `setPolicy` relied on truncation.
  Use an explicit limit within uint128, or zero only when unlimited policy spend
  is genuinely intended. Updated fixtures use uint128 maximum to preserve their
  prior stored values.
- Policy contracts and their dependent deployment wiring need coordinated review.
  No existing deployment has been upgraded, and no Sepolia deployment is authorized.

## Still required before production agent commerce

1. Enforce scoped signing/session permissions across every exposed operation,
   including raw transfers, approvals, bridging and gas sponsorship. Test concurrent
   spend attempts and revocation during in-flight operations at that boundary.
2. Connect a single order lifecycle to durable payment consumption, fulfillment,
   refund/dispute handling and reconciliation. Mocked module tests are not a
   complete merchant-service deployment or exactly-once external fulfillment.
3. Build and run the pinned full local OP Stack with independent verifier and
   challenger; retain deposit, batching, derivation, withdrawal and dispute evidence.
4. Implement and test x402/AP2 adapters against explicitly selected protocol
   versions, networks and signing semantics. Contract names or payment structs
   alone do not certify interoperability.
5. Complete recovery drills, deployed-governance verification and an independent
   audit. These remain acceptance gates, not claims satisfied by this patch.
