# SSDC v2 Invoice Vault Review

## Current Architecture

SSDC v2 is a NAV-priced share vault, not the older rebasing T-bill stablecoin described elsewhere in this repo.

- `wSSDCVaultV2` is the core share token. Users deposit a settlement asset and receive shares priced off `NAVControllerV2`.
- `YieldEscrowV2` locks shares against an invoice and splits positive carry across merchant, buyer, and protocol on release.
- `SSDCClaimQueueV2` handles async redemptions with an NFT claim receipt plus a queue-side settlement buffer.
- `YieldPaymasterV2` lets agents spend share collateral on gas under policy and grounding checks.
- `GroundingRegistryV2` computes whether an agent has fallen below its required collateral floor.
- `WSSDCCrossChainBridgeV2` burns/mints shares cross-chain and relays NAV snapshots.

## What Improved

The invoice vault now has an explicit minimum maturity.

- `YieldEscrowV2.InvoiceTerms` includes `releaseAfter`.
- Escrows cannot be released before `releaseAfter`.
- Only the buyer or an arbiter can settle an escrow.
- Escrows can optionally require a typed merchant or arbiter fulfillment proof before a buyer can release them.
- Fulfillment-gated escrows can now require sequential fulfillment milestones instead of a single terminal proof, and final settlement readiness only flips once the last milestone is submitted.
- Escrows can now define a dispute window plus explicit timeout resolution even when they do not require fulfillment, so disputes are no longer forced into an arbiter-only indefinite lock path.
- Fulfillment-required escrows use that same dispute window after proof submission, after which the merchant can finalize an undisputed release without waiting on buyer action.
- Buyers, merchants, or arbiters can now raise a typed dispute reason that blocks unilateral buyer settlement until an arbiter resolves the escrow.
- Disputes can now target a specific completed fulfillment milestone instead of only freezing the invoice at a generic reason layer.
- Disputed escrows now carry an explicit arbiter resolution path with a recorded release-or-refund verdict and evidence hash before settlement can execute, and that same dispute window can now act as a bounded arbiter-response SLA with an explicit default timeout resolution across both proof-gated and non-fulfillment invoices instead of an implicit buyer refund bias.
- Escrows now persist their typed fulfillment requirement, dispute reason, and final settlement mode on-chain, so indexers and risk tooling can distinguish buyer release, merchant timeout release, dispute-timeout refund, and arbiter-driven settlement without inferring it from raw hashes.
- Escrow settlement and fulfillment events now surface the acting party plus the typed settlement or evidence mode, so off-chain accounting can consume intent directly instead of reconstructing it from calldata and timestamps.
- `YieldEscrowV2.previewSettlement()` now exposes live settlement readiness, fulfillment progress, targeted dispute milestone, actor permissions, and challenge/dispute deadlines on-chain, so frontends do not have to replay the escrow state machine off-chain just to know who can act next.
- Sponsored and gateway-funded escrows now store an explicit refund recipient instead of assuming the share sender owns the principal risk.
- Sponsored and gateway-funded escrows now reserve committed principal against the buyer's effective floor until settlement or refund.
- Escrows can now be refunded back to that refund recipient if the invoice should not settle.
- Self-funded escrow creation now checks the buyer's post-funding collateral floor through `GroundingRegistryV2`.
- Bridged-share provenance now follows transfers and burns inside `wSSDCVaultV2`, so bridge mint capacity is measured against actual bridged supply rather than any arbitrary share burn.
- The redemption queue now defaults to strict FIFO processing, with skip-ahead behavior available only as an explicit admin toggle.
- Escrow release can now route a configurable first-loss reserve cut from gross positive carry before protocol fee extraction.
- This removes the previous whoever-calls-first release behavior, makes the yield term explicit at funding time, closes the gateway-refund routing bug, and makes sponsored commerce hit collateral headroom instead of bypassing it.

That change improves the tokenomics in one important way: buyers and merchants can now reason about both a minimum accrual window and an explicit settlement-condition path with milestone-aware fulfillment progress, milestone-targeted disputes, bounded buyer response time, bounded dispute lock time, typed settlement outcomes, invoice-specific timeout fallback, and live settlement readiness across both fulfillment-gated and simpler invoice flows instead of having invoice yield shortened, disputed, or released by arbitrary third-party timing.

## Better Tokenomics Model

The strongest version of this design is:

1. Principal is fixed at funding.
2. Positive carry above principal is the only amount that gets split.
3. A release date plus optional typed fulfillment milestones, buyer challenge, typed dispute, arbiter-resolution, and explicit timeout-resolution controls define when that split becomes available, even on invoices that do not use merchant-submitted proof.
4. Liquidity for redemptions is managed separately from NAV growth.

Under that model:

- Merchant gets principal first.
- Buyer receives only the configured share of positive carry.
- Protocol fee should come only from positive carry, never from principal.
- Queue liquidity should be treated as a managed buffer, not as proof that NAV growth is instantly liquid on-chain.

## Remaining Risks

Two architecture gaps still matter:

- Queue liquidity and NAV remain separate systems, so invoice solvency and invoice liquidity are still not the same thing.
- Cross-chain safety still depends on trusted peers plus admin-controlled mint caps and liquidity guards, not a trust-minimized message verification path.

There is also a documentation gap: `docs/stablecoin.md` still describes the older stablecoin system rather than this invoice vault architecture.

## Recommended Next Changes

- Decide whether the new typed fulfillment/dispute/settlement surface should stay at the current enum level or evolve into governed typed milestones with explicit dispute-resolution SLAs and timeout rules.
- Decide whether reserve accrual should stay as a static BPS sink or evolve into a governed insurance pool with explicit draw rules.
- If queue liveness under strict FIFO becomes operationally painful, replace the toggle with a true partial-fill claim model instead of permanent out-of-order settlement.
- Narrow bridge trust assumptions further with stronger peer governance, rate limits, or message attestation.
- Document v2 separately from the legacy stablecoin docs and make the queue/buffer assumptions explicit.
