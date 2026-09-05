# Restricted agent payment account (local integration candidate)

`AgentPaymentAccountV2` is an opt-in custody contract for direct wSSDC payments.
It does not change `AgentClient.pay()` or protect funds left in an unrestricted
agent wallet. No instance has been deployed by this change. Sepolia remains on hold.

## Trust and setup

1. Deploy locally with the intended vault, policy module and a trusted owner
   (prefer a separately controlled multisig). Review dependency code and addresses.
2. Configure policy for the **account address**, not its owner/session key, and
   grant only this trusted account its required `POLICY_CONSUMER_ROLE`.
3. Configure merchant allowlists, daily/per-payment limits and minimum collateral.
4. The owner grants a key one fixed merchant, a finite expiry and a lifetime asset
   budget. Use different keys for different merchants. Fund the account with vault
   shares; do not give the agent the owner key.
5. The session key submits only `pay` transactions to this account. Transaction
   signing binds chain, destination, order ID, session epoch, nonce, amount,
   maximum shares and deadline. There is no arbitrary call, approval, bridging,
   escrow funding or gas-sponsorship path in this contract.

The owner can replace/revoke sessions and recover shares subject to the account's
minimum collateral plus commitments. Owner recovery bypasses purchase budgets;
the owner is explicitly trusted. Vault/policy administrators and NAV inputs are
also trusted. This is not an ERC-4337 account, ERC-1271 signing adapter or HSM.

## Payment semantics

- Payments consume session budget and the shared account policy counter in the
  same transaction as the share transfer. Any failure rolls all three back.
- A fresh NAV is required. Shares round up to cover the requested assets; the
  charged budget also rounds up to cover the full value of those shares.
- The remaining wallet shares alone must cover policy collateral and commitments;
  external collateral providers are deliberately not credited by this account.
- `nextNonce` is global across sessions. Competing transactions can revert on
  stale nonce; reconcile the original order before explicitly rebuilding a retry.
- An order ID can be paid once per account, across all sessions and merchants.
  Use a domain-separated merchant/order identifier. This does not authenticate
  an invoice, prevent payment by another account, or guarantee fulfillment.
- Session replacement and revocation increment its epoch. Old transactions cannot
  become valid again when a key is restored. Expiry/deadline equality is expired.
- Revocation prevents payments executed after the revocation transaction; it
  cannot undo payments ordered before that transaction or finalized earlier.

## SDK access

```ts
import { Contract } from "ethers";
import { agent } from "@setchain/sdk";

const account = new Contract(accountAddress, agent.agentPaymentAccountV2Abi, sessionSigner);
const session = await account.sessions(await sessionSigner.getAddress());
const nonce = await account.nextNonce();
const tx = await account.pay(
  orderId, session.epoch, nonce, assets, maxShares, deadline,
);
const receipt = await tx.wait();
if (!receipt || receipt.status !== 1) throw new Error("Payment failed");
// Apply the merchant's explicit safe/finalized fulfillment requirement next.
```

The connected signer needs transaction gas. Bound `maxShares` and `deadline`
explicitly; do not silently refresh authorization after a failed submission.
This low-level ABI is separate from the legacy advisory `AgentClient.pay()`.

## Acceptance still required

Independent review/audit, deployed dependency and role verification, real local
rollup finality/reorg/recovery exercises, and durable merchant reconciliation are
not established by these unit tests. Refunds are merchant transfers back to the
account; they do not restore consumed purchase/session budget automatically.
Do not advertise the system as A+ or production-certified from this addition.
