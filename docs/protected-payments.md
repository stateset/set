# Protected payments

Stablecoin transfers are final. Card networks are not: a buyer can dispute a
purchase weeks after the merchant was paid, and the network's rules decide who
bears the loss. `ProtectedPayments` brings that protection model to Set Chain
without making the ledger reversible. Transfers stay final; *settlement terms*
carry the dispute rights.

Contracts: `contracts/commerce/protection/ProtectedPayments.sol` and
`contracts/commerce/protection/ArbiterRegistry.sol`.

## What it adds over OrderEscrow and YieldEscrowV2

| Capability | OrderEscrow | YieldEscrowV2 | ProtectedPayments |
|---|---|---|---|
| Buyer dispute while funds are held | yes | yes | yes |
| Merchant-signed terms (EIP-712 / ERC-1271) | no | no | yes |
| Merchant response stage (accept or contest) | no | no | yes |
| Negotiated partial settlements | no | no | yes |
| Partial arbiter rulings | no | no | yes |
| Instant merchant settlement | no | no | yes, reserve-backed |
| Chargebacks after the merchant was paid | no | no | yes |
| Protection pool for merchant shortfalls | no | no | yes |
| Bonded, slashable arbiters with fallback | no | no | yes |
| Anchored VES events as evidence | no | no | yes |
| Voluntary refunds and returns | no | no | yes |

## Lifecycle

```
pay ──► OPEN ──(merchant markFulfilled)──► protection window ──► COMPLETED
         │                                    │   (finalize / buyer confirm)
         │                                    │
         ├─(fulfillBy passes, unfulfilled)─► REFUNDED (cancelUnfulfilled)
         │
         └─(buyer openDispute, bond)──► DISPUTED
                 │
                 ├─ AWAITING_MERCHANT ─ acceptDispute ────────────► refund, close
                 │        │           ─ silence past deadline ───► refund, close (default)
                 │        │           ─ contest (pays arb fee) ──┐
                 │        └─ proposeSettlement / acceptSettlement (either stage)
                 │                                               ▼
                 └─ ARBITRATION ─ resolve(refundAmount) ─────────► split, close
                          └─ arbiter misses deadline ─ slash, reassign once,
                                                       then refund buyer
```

A payment can be disputed once, until `fulfilledAt + protectionWindow` (or at any
time while unfulfilled). When a dispute closes, whatever was not refunded goes to
the merchant and the payment is `COMPLETED` (or `REFUNDED` if nothing remains).

## Settlement modes

**Held.** Funds stay in the contract until the protection window closes, then go
to the merchant minus fees. Refunds come out of held funds. No merchant capital
is needed.

**Instant (reserve-backed).** An underwriter enables instant settlement for a
merchant and sets a reserve ratio. On `pay`, the contract locks
`amount × reserveRatioBps / 10_000` of the merchant's deposited reserve and pays
the merchant immediately. The payment is still disputable for the full
protection window. A buyer-won refund is funded, in order, from:

1. the reserve locked for that payment,
2. the merchant's free reserve,
3. the protection pool (the merchant now owes the pool this amount as debt),
4. a pending claim the buyer collects with `claimPending` as the pool refills.

Merchant deposits repay debt first. Debt blocks reserve withdrawals and new
instant settlements. The buyer's full refund is always *owed*; whether it is
*immediately payable* depends on reserve and pool liquidity. That limit is real
and deliberate: this contract does not mint or borrow.

## Fees

- `protocolFeeBps` accrues to the protocol; `protectionFeeBps` funds the pool.
  Both apply only to the amount the merchant keeps. Together they are capped at
  10%.
- Held payments pay fees at completion, on the non-refunded amount.
- Instant payments pay fees upfront. A later refund comes from merchant reserve
  at full value, so the merchant bears the fee on refunded instant sales (as with
  card interchange).
- Buyers post `buyerDisputeBond` to dispute. It is returned unless the dispute
  is lost outright (refund of zero), in which case it goes to the merchant.
- A merchant that contests posts `arbitrationFee`, paid to the arbiter who rules.
  It is returned if the case settles by agreement or the arbiter times out.
  Governance should set `buyerDisputeBond ≥ arbitrationFee` so a merchant who
  wins is made whole.

## Arbiters

`ArbiterRegistry` is the governing layer. Governance approves arbiters. Each
arbiter keeps a bond of at least `minBond` in the registry's bond token, has a
public count of open cases, and has resolved/missed statistics. Merchants name an
arbiter in the signed terms, so the buyer sees it before paying. If that arbiter
is no longer eligible when a case opens, the network default arbiter takes it.
Missing a ruling deadline slashes `slashAmount` to the registry's slash
recipient and reassigns the case once to the default arbiter. A second miss
refunds the buyer. Bond withdrawal needs zero open cases; a full exit waits out
`unbondingPeriod`.

## Dispute monitoring

Every payment and dispute is counted on-chain per merchant and per buyer
(`merchantStats`, `buyerStats`). For merchants, `lost` counts disputes that
closed with a refund other than a negotiated settlement. For buyers, it counts
arbitration losses with a zero award, which signals friendly fraud.

Governance sets `maxDisputeRatioBps` and `minPaymentsForRatio`. Once a merchant
has at least that many payments and its disputes-to-payments ratio exceeds the
threshold, instant settlement is revoked automatically. New payments are held
instead, and `instantCapacity` reports zero. Clean volume brings the ratio back
under the threshold and restores instant settlement with no underwriter action.
The deploy script uses 0.9% after 100 payments, mirroring card-network dispute
monitoring. Zero disables the check. The ratio is judged on the merchant's
record *before* the incoming payment, so a payment cannot dilute its own gate.

## SDK

`@setchain/sdk` exports `protection`:

- `buildProtectedPaymentTypedData` builds the EIP-712 terms a merchant signs.
- `ProtectedPaymentsClient` provides typed reads (payment, dispute, stats,
  reserve, credits) and writes that approve exact shortfalls, never unlimited
  allowances.
- `derivePaymentActions` is a pure function listing what an account can do at a
  given timestamp. It mirrors the contract's timing and authorization guards so
  agents only offer transactions that will not revert on those grounds.
  `client.actionsFor(id, account)` evaluates it at the latest block.

`sdk/examples/protected-payments-e2e.mjs` deploys the contracts on a throwaway
Anvil chain and runs an instant-settlement chargeback, an arbitrated partial
refund and a merchant default.

## Evidence

Parties commit evidence hashes when they file and respond. Either party or the
arbiter can also attach **anchored VES events**: `attachVerifiedEvidence` checks a
Merkle inclusion proof against `SetRegistry.verifyInclusion` and records the
batch and leaf on-chain. The contract proves the event was anchored. It does not
interpret the event; the arbiter decides what it shows.

## Trust boundaries

- Governance (`DEFAULT_ADMIN_ROLE`) sets network parameters, token allowlist,
  fee recipient and default arbiter, and grants underwriters. It cannot move
  held funds, reserves, bonds or the pool.
- Underwriters set merchant instant-settlement terms. A bad ratio exposes the
  pool, not buyers' held funds.
- Pausing blocks new payments only. Refunds, disputes, completions, reserve
  deposits (debt repayment) and withdrawals keep working so a pause cannot trap
  funds.
- Every settlement output (refunds, merchant proceeds, bonds, arbiter fees) is
  credited and pulled with `withdraw(token)`, so a recipient that cannot receive
  tokens (for example a blocklisted address) cannot block the other party.
- Tokens that charge a fee on transfer are rejected. Rebasing tokens are not
  supported.

## Not yet covered

Multi-round appeals, arbiter juries, reason-code-specific evidence rules, and a
pool yield strategy. `ProtectedPayments` is 22.0 KB under via_ir, so appeals
should live in a separate contract. No deployment has been performed and the contracts have not
been independently audited.
