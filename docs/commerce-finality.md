# Commerce transaction finality

## Transaction-flow results are not settlement evidence

Transaction helpers in `tx/flows` report the transaction builder's confirmation
outcome, not independent payment verification or L1 finality. Redemption request,
encrypted transaction and forced-inclusion identifiers are extracted only from
non-removed logs whose emitter matches the resolved target contract. A matching
ABI signature from another contract is ignored.

A confirmed transaction with no matching event still returns `success: true`,
with the optional identifier absent. Investigate the receipt; do not automatically
resubmit and risk a duplicate action. A successful forced-inclusion request only
confirms the request transaction, not eventual inclusion or execution on L2.
Emitter matching does not independently establish canonicality or finality.

## Independent finality observations

The SDK exposes `inspectTransactionFinality` to observe a transaction against one
or more OP Stack execution RPCs. It checks chain identity, canonical receipt block,
safe/finalized heads and receipt stability across the observation. With multiple
sources it reports the weakest observed finality and rejects conflicting inclusions.

```ts
import { JsonRpcProvider } from "ethers";
import { inspectTransactionFinality } from "@setchain/sdk";

const sources = [
  new JsonRpcProvider(sequencerRpc, undefined, { cacheTimeout: -1 }),
  new JsonRpcProvider(independentVerifierRpc, undefined, { cacheTimeout: -1 }),
];
const observation = await inspectTransactionFinality(sources, paymentTxHash, 84532001n);
```

| Result | Application meaning |
|---|---|
| pending | At least one source has no receipt; wait and retry |
| reorged | Receipt no longer matches the canonical block or changed during observation |
| unsafe | Included by the sequencer; do not describe as Ethereum-finalized |
| safe | All sources report the block at or below their safe head |
| finalized | All sources report the block at or below their finalized head |

`execution` is independent: a reverted transaction can be finalized. Before
fulfillment, verify successful execution **and** the expected payment event's
token, recipient, amount and order identity. Persist an idempotency key scoped to
chain, transaction and event index. This observer does not perform those checks,
authorize shipment, prove a withdrawal or attest to reserve backing.

Unsupported finality tags, unavailable RPCs, malformed data and inconsistent heads
reject the observation. Retry against healthy sources; never substitute `latest`
or a fixed count of L2 confirmations for `safe` or `finalized`.

Both `inspectTransactionFinality` and `verifyERC20Payment` accept an optional fourth
argument `{ timeoutMs, signal }`. The default deadline is 30,000 ms for the entire
operation, including all sources and payment rechecks, not 30 seconds per RPC.
`timeoutMs` must be an integer from 1 to 300,000. For example:

```ts
const controller = new AbortController();
const observation = await inspectTransactionFinality(sources, paymentTxHash, 84532001n, {
  timeoutMs: 10_000,
  signal: controller.signal,
});
```

Timeout or cancellation throws `VerificationInterruptedError`, with `reason` set
to `"timeout"` or `"aborted"`; neither permits fulfillment. No automatic retries or
weaker-finality fallback are performed. The SDK stops scheduling further RPC calls
and ignores late results, but the minimal `send` transport cannot cancel in-flight
network I/O. Configure transport-level timeouts and bound checkout concurrency too.
Deadlines use JavaScript timers and cannot interrupt a blocked event loop.

RPC agreement is an observation, not a cryptographic proof. Independently operated
nodes provide useful corroboration; two URLs behind the same provider do not
establish independence. Observations are not atomic snapshots and must be refreshed
before a consequential action. Use uncached providers when observing state changes.

`observedAt` records the start of the entire SDK operation, before any RPC source
is queried. Payment finality rechecks do not refresh that timestamp: all earlier
event evidence retains its original age, regardless of source ordering or latency.
This is a local wall-clock timestamp, not a chain timestamp or signed attestation;
keep backend clocks synchronized. With a longer configured deadline, verification
can succeed yet already be too old for the ledger's 60-second credit policy.
Reverify rather than replacing the timestamp. Payment expectations and deadline
options are snapshotted at entry; later caller mutations do not change that check.
Aborting the supplied signal remains effective throughout the operation.

## Local diagnostic

After `npm run build` in `sdk/`:

```sh
node sdk/scripts/observe-local-finality.mjs TX_HASH 84532001 \
  http://127.0.0.1:8547 http://127.0.0.1:8647
```

The diagnostic only accepts two distinct numeric loopback HTTP endpoints, refuses
redirects, uses request timeouts and submits no transactions. It emits JSON evidence
and exits zero only for successful finalized inclusion reported by both endpoints.
That exit code does not certify a commerce payment or complete L1 withdrawal.

Tests include simulated local JSON-RPC servers; these test transport compatibility,
not an independently deriving OP Stack network. Full rollup lifecycle exercises
remain tracked in [L2 readiness evidence](l2-readiness-gaps.md).

Protocol reference: [OP Stack transaction finality](https://docs.optimism.io/op-stack/transactions/transaction-finality).

## Verify an expected ERC-20 payment

```ts
import { verifyERC20Payment } from "@setchain/sdk";

const result = await verifyERC20Payment(sources, {
  chainId: 84532001n,
  transactionHash: paymentTxHash,
  logIndex: paymentLogIndex, // bigint, block-wide RPC logIndex
  token: approvedTokenAddress,
  payer: expectedPayer,
  recipient: merchantAddress,
  amount: 1_000_000n, // exact raw units; no assumed token decimals
});
if (result.status === "verified") {
  // Atomically claim result.eventKey and transition the authenticated order to paid.
  // Schedule fulfillment via a transactional outbox in the same database transaction.
}
```

This requires at least two distinct RPC source objects and defaults to finalized
inclusion. Passing `"safe"` as the third argument explicitly accepts L1 reorg risk.
Missing or changing receipts produce `waiting`; a reverted transaction or mismatched
transfer produces `rejected`. RPC failures and malformed evidence throw. Only
`verified` returns an `eventKey`. The receipt and finality are checked again after
event inspection; observations remain non-atomic RPC evidence.

The event key contains chain ID, transaction hash and **receipt-local event ordinal**.
Unlike the block-wide log index used to locate an event, that ordinal does not shift
when preceding transactions in a block change. Persist a unique constraint on this
key across all orders handled by your payment ledger. Do not include order ID in
the uniqueness constraint: doing so would allow the same payment to pay two orders.
Store both order and event key, and enqueue fulfillment in the same database
transaction. Retrying a verification does not itself consume the payment.

Before assigning that ordinal, the verifier requires the full receipt log sequence
to have contiguous, increasing block-wide indexes and consistent transaction/block
metadata, with no removed events. Unrelated event types are allowed. Malformed
ordering rejects verification; stale metadata returns `waiting`. Sources must agree
on the selected event's ordinal. These checks detect inconsistent RPC data, not a
consistently fabricated or truncated receipt; independently operated sources and
the RPC trust assumptions above still apply.

An ERC-20 Transfer event contains no order ID. Bind expected payer, recipient,
token and amount to an authenticated checkout before verification. Restrict tokens
to an audited allowlist: a malicious token can emit fabricated events, and fee-on-
transfer or rebasing tokens may not produce the expected net credit. This helper
verifies one exact standard Transfer, not net balances, reserve backing, withdrawal
completion, or intent. Mint events and self-transfers are not accepted as payments.

Event layout reference: [ERC-20 specification](https://eips.ethereum.org/EIPS/eip-20).

## Durable order credit and fulfillment reference

[`sdk/examples/payment_ledger.py`](../sdk/examples/payment_ledger.py) is a runnable
server-side SQLite reference using only the Python standard library. It is not an
HTTP endpoint or an automatically configured merchant backend.

1. Create the order using authenticated checkout expectations and approved tokens.
   Amounts and chain IDs are canonical decimal strings; amounts use raw token units.
2. Run `verifyERC20Payment` inside the trusted backend and serialize its result.
   Never pass customer-provided verification JSON directly to the ledger: the
   result is not signed and the ledger does not repeat the RPC verification.
3. Call `ledger.credit(order_id, verified_result)`. It requires successful finalized
   evidence from at least two sources, observed within 60 seconds. Stored order
   expectations must match. The ledger atomically claims the globally unique event
   key, transitions the order to paid and creates one fulfillment outbox item.
4. Workers call `claim_fulfillment()` for a bounded lease, use the returned event key
   as the downstream fulfillment idempotency key, then acknowledge with the lease
   token only after fulfillment succeeds.

A repeated credit to the same order returns `already_credited`; reuse across orders
or a second payment for an already paid order raises `PaymentConflict`. Failed
transactions roll back all three writes. Expired worker leases can be reclaimed;
superseded workers cannot acknowledge the new lease.

Matching retries can return the existing credit even after evidence expires; they
do not rewrite stored evidence or enqueue fulfillment again. New credits still
require freshness at entry and after acquiring the database lock. The ledger
validates a JSON snapshot, required observation fields, inclusion block metadata
and canonical bounded event ordinals before writes. Invalid shapes raise
`ValueError`. This validation does not authenticate the evidence: only pass results
produced inside the trusted backend, never customer-supplied verification JSON.

Delivery is **at least once**. A crash after shipment but before acknowledgment can
cause a retry, so the downstream fulfillment system must honor the event key.
This reference does not ship orders, reconcile overpayments, handle refunds or
perform token allowlist management. Add authenticated tenant routing and business
policies at the application layer. Keep the ledger on a local filesystem supporting
SQLite locking; multi-host deployments should implement the same constraints and
transaction boundaries in their shared database.

Real database tests, including concurrent connections and rollback injection:

```sh
python3 -m unittest discover -s scripts/tests -p test_payment_ledger.py -v
```

End-to-end commerce regression (from `sdk/`, with Node 20+ and Python 3):

```sh
npm test -- finality-rpc
```

This drives the real SDK over two simulated loopback JSON-RPC servers, passes its
JSON result through a fresh Python process per ledger operation, and persists to
a temporary SQLite database. It checks duplicate and cross-order payment reuse,
underpayment rejection, and a simulated crash after fulfillment but before
acknowledgment. Retried delivery uses a durable, idempotent test sink. The RPC
responses and downstream fulfillment are simulated: this is not an OP Stack
settlement test, a real shipment, or proof of production crash durability.
