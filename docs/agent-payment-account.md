# Restricted agent payment account (local integration candidate)

`AgentPaymentAccountV2` is an opt-in custody contract for direct wSSDC payments.
It does not change `AgentClient.pay()` or protect funds left in an unrestricted
agent wallet. No instance has been deployed by this change. Sepolia remains on hold.

**v0.4.0 compatibility change:** `pay` now requires a seventh argument,
`bytes merchantSignature`. The six-argument v0.3.12 entry point is removed, not
retained as an unsigned fallback. The new SDK ABI/helper must be used with a new,
reviewed deployment of this source; already deployed v0.3.12 accounts do not gain
invoice verification. No deployed account has been upgraded or migrated here.

## Trust and setup

1. Deploy locally with the intended vault, policy module and a trusted owner
   (prefer a separately controlled multisig). Review dependency code and addresses.
2. Configure policy for the **account address**, not its owner/session key, and
   grant only this trusted account its required `POLICY_CONSUMER_ROLE`.
3. Configure merchant allowlists, daily/per-payment limits and minimum collateral.
4. The owner grants a key one fixed merchant, a finite expiry and a lifetime asset
   budget. Use different keys for different merchants. Fund the account with vault
   shares; do not give the agent the owner key.
5. Obtain a merchant-signed invoice using the exact typed-data schema below.
   Authenticate the merchant's checkout service; never expose a signing endpoint
   that blindly signs agent-supplied orders or amounts.
6. The session key submits only `pay` transactions to this account. Transaction
   signing binds chain, destination, order ID, session epoch, nonce, amount,
   maximum shares and deadline. There is no arbitrary call, approval, bridging,
   escrow funding or gas-sponsorship path in this contract.

The owner can replace/revoke sessions and recover shares subject to the account's
minimum collateral plus commitments. Owner recovery bypasses purchase budgets;
the owner is explicitly trusted. Vault/policy administrators and NAV inputs are
also trusted. This is not an ERC-4337 account, ERC-1271 signing adapter or HSM.
Merchant smart-contract signatures are verified through ERC-1271; the account
itself does not implement ERC-1271 signing.

## Invoice authentication

The merchant signs EIP-712 data with domain name `AgentPaymentAccountV2`, version
`1`, the actual chain ID and this account as `verifyingContract`. The exact type is:

```text
Invoice(bytes32 orderId,address merchant,address vault,uint256 assets,uint40 deadline)
```

The merchant must equal the session's configured recipient and the vault must
equal the account's immutable vault. Amounts are vault accounting asset units,
not a fiat price string. The deadline is a Unix timestamp in seconds; equality
is expired. `invoiceDigest` exposes the contract's signing digest for comparison.

Ordinary merchant wallets sign typed data; contract merchants return ERC-1271's
magic value for the digest. Invalid, revoked or reverting contract signatures
fail closed. EOA signatures remain usable until expiry or account/session/policy
restrictions block them; there is no separate EOA invoice-cancellation method.

This authenticates the merchant's offer, **not user approval of specific goods**.
User authority still comes from the owner's merchant-scoped session and policy.
The signed order ID must reference immutable checkout terms in the merchant system.
No product metadata or personal information needs to be placed on-chain. This is
not AP2/x402 certification, a proof of delivery, or an independently verified
merchant identity. Do not let an agent control an allowlisted merchant's signer.

References: [EIP-712](https://eips.ethereum.org/EIPS/eip-712) and
[ERC-1271](https://eips.ethereum.org/EIPS/eip-1271). EIP-712 alone does not prevent
replay; account nonces, order uniqueness, session epochs and deadlines do that here.

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
  Use a domain-separated merchant/order identifier. A signature for this account
  cannot be replayed on another account or chain, but separately issued invoices
  still require merchant-wide order reconciliation. Fulfillment is not guaranteed.
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
// merchantSignature was issued by the authenticated merchant checkout service.
const tx = await account.pay(
  orderId, session.epoch, nonce, assets, maxShares, deadline, merchantSignature,
);
const receipt = await tx.wait();
if (!receipt || receipt.status !== 1) throw new Error("Payment failed");
// Apply the merchant's explicit safe/finalized fulfillment requirement next.
```

The connected signer needs transaction gas. Bound `maxShares` and `deadline`
explicitly; do not silently refresh authorization after a failed submission.
This low-level ABI is separate from the legacy advisory `AgentClient.pay()`.

On the trusted merchant backend, with reviewed account/vault/chain information:

```ts
const data = agent.buildMerchantInvoiceTypedData({
  chainId, accountAddress, merchant: merchantAddress, vault: vaultAddress,
  orderId, assets, deadline,
});
// EOA merchant example. Contract wallets use their own ERC-1271 signing flow.
const merchantSignature = await merchantSigner.signTypedData(data.domain, data.types, data.value);
```

The helper validates encodings and bounds but does not fetch deployment metadata,
validate an order, enforce clock freshness or contact a signing service. All integer
inputs are bigint. Nonce, session epoch and maxShares are bound by the session's
transaction, not the invoice; a valid invoice may survive an explicitly reviewed
nonce retry, but can only be paid once by the account.

## Acceptance still required

Independent review/audit, deployed dependency and role verification, real local
rollup finality/reorg/recovery exercises, and durable merchant reconciliation are
not established by these unit tests. Refunds are merchant transfers back to the
account; they do not restore consumed purchase/session budget automatically.
Do not advertise the system as A+ or production-certified from this addition.
