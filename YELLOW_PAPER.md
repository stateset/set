# Set Chain SSDC V2: A Commerce-Optimized Stablecoin System for Autonomous Agents

**Yellow Paper v2.3 — March 2026**

---

## Abstract

Set Chain is a commerce-optimized Ethereum Layer 2 (OP Stack, chain ID 84532001) with 2-second block times designed for merchant settlement. The Set Stablecoin Dollar Commerce (SSDC) V2 system implements a NAV-priced share vault backed by short-duration U.S. Treasury instruments, with yield-bearing escrow, agent spending policies, collateral grounding, gasless execution via account abstraction, and cross-chain bridging. This paper specifies the complete protocol: contract interfaces, state machines, mathematical foundations, safety invariants, threat model, and the agent commerce protocol that enables AI agents to autonomously hold value, transact, and earn yield.

---

## Table of Contents

1. [System Architecture](#1-system-architecture)
2. [Asset Backing & Yield Generation](#2-asset-backing--yield-generation)
3. [NAV Controller](#3-nav-controller)
4. [Share Vault (wSSDC)](#4-share-vault-wssdc)
5. [Yield Escrow](#5-yield-escrow)
6. [Claim Queue](#6-claim-queue)
7. [Policy Module](#7-policy-module)
8. [Grounding Registry](#8-grounding-registry)
9. [Yield Paymaster](#9-yield-paymaster)
10. [Cross-Chain Bridge](#10-cross-chain-bridge)
11. [Circuit Breaker](#11-circuit-breaker)
12. [Threat Model & Security Analysis](#12-threat-model--security-analysis)
13. [Mathematical Reference](#13-mathematical-reference)
14. [Appendix A: Agent Commerce Protocol](#appendix-a-agent-commerce-protocol)
15. [Appendix B: Deployment & Upgrade Strategy](#appendix-b-deployment--upgrade-strategy)
16. [Appendix C: Error Code Reference](#appendix-c-error-code-reference)
17. [Appendix D: V3 Roadmap](#appendix-d-v3-roadmap)

---

## 1. System Architecture

### 1.1 Overview

The SSDC V2 system comprises 11 interacting contracts organized around a central ERC-4626 share vault. All value in the system is denominated in **shares** — fungible ERC-20 tokens whose price in settlement assets (USDC) is determined by a continuously-projected Net Asset Value (NAV). The NAV reflects the mark-to-market value of the vault's underlying reserve portfolio, predominantly short-duration U.S. Treasury instruments.

```
                       TREASURY RESERVE (off-chain)
                            |
                       NAV ATTESTOR (oracle)
                            |
                            v
                     NAV_CONTROLLER <─────── CROSS_CHAIN_BRIDGE
                            |                         |
                            v                         |
              ┌──────── SHARE VAULT ──────────────────┘
              |             |
              |    convertToShares()
              |    convertToAssets()
              |             |
              v             v
     GROUNDING_REGISTRY   POLICY_MODULE
              |             |
              |      ┌──────┴──────┐
              |      |             |
              v      v             v
         YIELD_ESCROW        YIELD_PAYMASTER ──> COLLATERAL_PROVIDER
              |                    |
              v                    v
         CLAIM_QUEUE          ENTRY_POINT (ERC-4337)
              |
              v
         VAULT_GATEWAY ──> User / Agent
              |
              v
         STATUS_LENS (read-only)
              |
              v
         CIRCUIT_BREAKER (emergency)
```

### 1.2 Contract Roles

| Contract | Key Roles | Purpose |
|----------|-----------|---------|
| `NAVControllerV2` | ORACLE, BRIDGE, PAUSER | NAV projection and attestation |
| `wSSDCVaultV2` | GATEWAY, BRIDGE, QUEUE, RESERVE, PAUSER | ERC-4626 share vault |
| `YieldEscrowV2` | FUNDER, ARBITER, PAUSER | Invoice escrow with yield splits |
| `SSDCClaimQueueV2` | BUFFER, QUEUE, PAUSER | Async redemption with NFT claims |
| `SSDCPolicyModuleV2` | ADMIN, POLICY_CONSUMER | Per-agent spend limits |
| `GroundingRegistryV2` | ADMIN | Collateral sufficiency checks |
| `YieldPaymasterV2` | PAYMASTER_ADMIN, PAUSER | ERC-4337 gas sponsorship |
| `SSDCVaultGatewayV2` | ADMIN | Convenience router with slippage |
| `WSSDCCrossChainBridgeV2` | BRIDGE, PAUSER | Mint/burn bridge with NAV relay |
| `SSDCStatusLensV2` | (none) | Read-only system health |
| `SSDCV2CircuitBreaker` | BREAKER | Global emergency pause |

### 1.3 Fixed-Point Arithmetic

All NAV calculations use **ray precision** (1e27) via the `RayMath` library. This provides 27 decimal places of precision for share/asset conversions, eliminating rounding drift across operations.

```
RAY = 1e27
1 RAY = 1 USDC at genesis NAV
```

Note: The system is denominated in the settlement asset (USDC), not fiat dollars. If USDC depegs from USD, share pricing follows USDC — the system makes no claim about fiat dollar equivalence.

### 1.4 Rounding Convention

The system enforces a strict rounding convention to prevent extraction of value through rounding:

| Operation | Rounding | Rationale |
|-----------|----------|-----------|
| Deposit (assets to shares) | Down | Vault receives more per share |
| Withdraw (assets to shares burned) | Up | User burns more shares per asset |
| Invoice funding (assets to shares) | Up | Escrow locks more shares for principal |
| Redemption preview | Down | User receives conservative estimate |

The vault always wins on rounding. This is the correct defensive posture for any tokenized vault — it prevents systematic extraction of value through repeated small rounding-favorable operations.

### 1.5 Canonical Units and Decimals

The system uses exactly three numeric domains. Every field, event parameter, oracle input, and SDK method operates in one of these:

| Domain | Decimals | Base Unit | Examples |
|--------|----------|-----------|----------|
| **Settlement assets** | 6 | 1 = 1e-6 USDC | `assetsDue`, `perTxLimitAssets`, `assetsOwed`, `availableAssets` |
| **Vault shares** | 6 | 1 = 1e-6 wSSDC | `sharesLocked`, `gasTankShares`, `totalSupply()`, `balanceOf()` |
| **NAV (ray)** | 27 | 1 RAY = 1e27 | `nav0Ray`, `ratePerSecondRay`, `minNavRay` |

**Invariant**: `wSSDC.decimals() == settlementAsset.decimals() == 6`. The vault inherits decimals from the settlement asset (USDC). All asset amounts and share amounts use 6-decimal raw integer representation. There is no 18-decimal scaling anywhere in the protocol.

**Conversion formulas** (using 6-decimal assets and shares, 27-decimal NAV):
```
assets = floor(shares × navRay / RAY)         // convertToAssetsDown
shares = ceil(assets × RAY / navRay)           // convertToSharesUp
```

At genesis NAV (1 RAY = 1e27):
```
1,000,000 asset units (= 1.000000 USDC) × RAY / RAY = 1,000,000 share units (= 1.000000 wSSDC)
```

**Oracle inputs**: The ETH/USD oracle returns price in 18-decimal fixed-point (`ethUsdPriceE18`). The NAV oracle inputs are in ray precision (27 decimals). Settlement asset amounts entering or leaving the system are always 6-decimal USDC.

**SDK convention**: All `bigint` amounts in the SDK represent raw 6-decimal integers. `1_000_000n` = 1.000000 USDC. The SDK provides `parseUnits(amount, 6)` for human-readable conversion.

### 1.6 Contract Mutability

All V2 contracts are **non-upgradeable**. They use standard constructors (not initializers), store critical dependencies as `immutable` state variables, and do not employ proxy patterns (no ERC-1967, UUPS, or Transparent Proxy). This is a deliberate design choice: the system prioritizes auditability and immutability over hot-patching.

**Migration strategy**: Protocol upgrades require deploying a new contract set and migrating state. The admin can pause the old system via the circuit breaker, deploy V3 contracts, and users redeem shares from the old vault and deposit into the new one. The bridge's trusted peer mechanism allows the admin to redirect cross-chain traffic to new contracts. See [Appendix B](#appendix-b-deployment--upgrade-strategy) for the full migration procedure.

---

## 2. Asset Backing & Yield Generation

### 2.1 The Reserve Model

The SSDC stablecoin is backed by a reserve portfolio managed off-chain. When users deposit USDC into the vault, those settlement assets are deployed into short-duration U.S. Treasury instruments (T-bills, overnight reverse repo, money market funds) by an authorized reserve manager. The yield from these instruments is what drives NAV appreciation.

```
On-Chain                              Off-Chain
─────────                             ─────────
User deposits USDC                    Reserve manager withdraws USDC
  → Vault holds USDC                    → Purchases T-bills / overnight repo
  → Shares minted to user               → Yield accrues daily

NAV oracle attests new NAV            Reserve manager marks portfolio
  ← Based on off-chain portfolio         → Computes NAV per share
  ← Published on-chain                   → Signs attestation

User redeems shares                   Reserve manager liquidates position
  → Shares burned                       → Returns USDC to vault
  → USDC returned from vault            → Vault sends to user
```

### 2.2 NAV as an Attestation

The `NAVControllerV2` does **not** compute yield on-chain. The NAV oracle is an off-chain attestor that periodically publishes the mark-to-market value of the reserve portfolio. The on-chain NAV controller then projects this value forward using a linear rate until the next attestation.

This means the NAV is fundamentally an **attestation of off-chain asset value**, not a computation from on-chain state. The trust assumption is that the reserve manager and NAV attestor accurately report the portfolio's value. This is the same trust model used by tokenized Treasury products (e.g., BUIDL, USDY, sDAI's DSR).

### 2.3 Liquidity Buffer

The vault maintains a **liquidity buffer** — a fraction of settlement assets held on-chain (not deployed to Treasuries) to service immediate withdrawals and claim queue processing. The `liquidityCoverageBps()` function reports the ratio of on-chain settlement assets to total share liabilities:

```
coverage = availableSettlementAssets * 10000 / liabilityAssets
```

When coverage drops below operational thresholds, the reserve manager must inject USDC back into the vault (by transferring settlement assets directly to the vault contract address). This increases `availableSettlementAssets` without minting new shares, restoring liquidity coverage.

### 2.4 Yield Injection Mechanism

The vault does not have an explicit `injectYield()` function. Instead, the yield mechanism operates through the NAV oracle:

1. Reserve portfolio earns yield from T-bills (e.g., 4.5% APY)
2. NAV oracle attests a higher NAV (e.g., 1.00 USDC → 1.000123 USDC per share daily)
3. Existing shares are now worth more USDC
4. When users redeem, the reserve manager liquidates Treasury positions and sends USDC to the vault
5. The vault's `totalAssets()` is computed as `convertToAssetsDown(totalSupply, NAV)` — it reflects the attested portfolio value, not the on-chain USDC balance

**Key insight**: The on-chain USDC balance may be less than `totalAssets()` at any given time. This is expected — the difference represents USDC deployed off-chain into Treasuries. The `liquidityCoverageBps()` metric tracks the ratio, and the claim queue handles redemptions when immediate liquidity is insufficient.

### 2.5 Undercollateralization Scenarios

If the reserve portfolio suffers a loss (e.g., T-bill default, operational error), the NAV oracle would attest a lower NAV. The NAV controller's `maxNavJumpBps` bounds the per-update decline, and `ratePerSecondRay` can be negative, causing gradual NAV drawdown. In this scenario:

- Share holders absorb the loss proportionally (each share is worth less USDC)
- The `minNavRay` floor prevents NAV from going to zero — if breached, NAV-dependent operations halt
- The reserve fund (from escrow yield splits) can serve as a first-loss buffer **only if** those shares are explicitly subordinated via a recapitalization policy (see [Section 12.4](#124-residual-risks))
- The circuit breaker can halt all operations if losses are severe

### 2.6 Reserve Management Protocol

The vault requires an explicit mechanism for the reserve manager to deploy settlement assets off-chain and recall them. V2 introduces a `RESERVE_ROLE`:

```
FUNCTION deployReserve(amount):   [RESERVE_ROLE]
  REQUIRE amount <= availableSettlementAssets - reserveFloor
  REQUIRE !mintRedeemPaused
  settlementAsset.transfer(reserveManager, amount)
  EMIT ReserveDeployed(reserveManager, amount)

FUNCTION recallReserve(amount):   [RESERVE_ROLE]
  settlementAsset.transferFrom(reserveManager, vault, amount)
  EMIT ReserveRecalled(reserveManager, amount)
```

**Constraints**:

| Parameter | Purpose | Default |
|-----------|---------|---------|
| `reserveFloor` | Minimum on-chain USDC the vault must retain | Configurable by admin |
| `maxDeployBps` | Maximum % of total assets deployable per call | 2000 (20%) |
| `reserveManager` | Address authorized to receive/return assets | Set at construction |

**Liquidity buffer floor**: `deployReserve()` enforces `postDeployBalance >= reserveFloor`. This guarantees a minimum liquidity buffer for instant withdrawals and claim queue processing. The admin sets `reserveFloor` based on expected redemption volume.

**Blast radius**: A compromised `RESERVE_ROLE` can extract at most `availableSettlementAssets - reserveFloor` per call, bounded by `maxDeployBps` per transaction. The admin can revoke `RESERVE_ROLE` and pause the vault. The NAV oracle continues to attest the true portfolio value, so share pricing remains correct even during a reserve incident.

**Pause integration**: `deployReserve()` is blocked when `mintRedeemPaused = true`. The circuit breaker prevents reserve deployment during emergencies.

**Events**: All deploy/recall operations emit events for off-chain audit. The `SSDCStatusLensV2` includes `reserveDeployed()` for monitoring on-chain vs off-chain ratios.

---

## 3. NAV Controller

### 3.1 Purpose

`NAVControllerV2` maintains the Net Asset Value — the exchange rate between vault shares and settlement assets. Rather than storing a static price, it stores a **linear projection**: a base value, a timestamp, and a rate of change per second. This allows the NAV to accrue yield continuously between oracle attestations.

### 3.2 State

```solidity
uint256 nav0Ray;              // Base NAV at time t0 (ray precision)
uint40  t0;                   // Timestamp of last update
int256  ratePerSecondRay;     // Forward rate per second (can be negative)
uint64  navEpoch;             // Monotonically increasing version
uint256 lastKnownGoodNAV;    // Last accepted attested NAV (for stale recovery)
uint256 minNavRay;            // Floor below which NAV is invalid
int256  maxRateAbsRay;        // Maximum |rate| allowed
uint256 maxNavJumpBps;        // Max single-update jump (basis points)
uint256 maxStaleness;         // Seconds before NAV becomes stale
bool    navUpdatesPaused;     // Pause flag
```

### 3.3 NAV Projection Formula

At any time `t`:

```
dt = min(t - t0, maxStaleness)

projectedNAV = nav0Ray + (ratePerSecondRay * dt)

stale = (t - t0) >= maxStaleness
belowMin = projectedNAV < minNavRay
```

The projection is **linear**, not compounding. This is a deliberate design choice: linear projection is simpler to verify, cheaper to compute on-chain, and for short intervals (< 24h between attestations) the difference from compound accrual is negligible. At 5% APY with daily updates, the linear vs. compound difference is ~0.00003%.

### 3.4 Oracle Update

When the oracle submits a new attested NAV, the controller **snaps immediately** to the attested current value and uses a **forward rate** for inter-attestation projection:

```
FUNCTION updateNAV(attestedCurrentNAVRay, forwardRateRay, newEpoch):
  REQUIRE !navUpdatesPaused
  REQUIRE newEpoch > navEpoch
  REQUIRE attestedCurrentNAVRay >= minNavRay

  previousNAV = project(nav0Ray, t0, ratePerSecondRay, now)

  IF stale OR belowMin:
    // Hard reset — still subject to jump limit from last known-good NAV
    IF maxNavJumpBps > 0 AND lastKnownGoodNAV > 0:
      jumpBps = |attestedCurrentNAVRay - lastKnownGoodNAV| * 10000 / lastKnownGoodNAV
      REQUIRE jumpBps <= maxNavJumpBps * MAX_STALE_JUMP_MULTIPLIER
    nav0Ray = attestedCurrentNAVRay
    t0 = now
    ratePerSecondRay = clamp(forwardRateRay, -maxRateAbsRay, +maxRateAbsRay)
    navEpoch = newEpoch
    lastKnownGoodNAV = attestedCurrentNAVRay
    RETURN

  // Validate jump threshold against current projected NAV
  IF maxNavJumpBps > 0:
    jumpBps = |attestedCurrentNAVRay - previousNAV| * 10000 / previousNAV
    REQUIRE jumpBps <= maxNavJumpBps

  // Snap to attested current value — this IS the truth, not a target
  nav0Ray = attestedCurrentNAVRay
  t0 = now
  ratePerSecondRay = clamp(forwardRateRay, -maxRateAbsRay, +maxRateAbsRay)
  navEpoch = newEpoch
  lastKnownGoodNAV = attestedCurrentNAVRay
```

**Design rationale — snap, don't smooth**: The attested NAV represents the reserve manager's mark-to-market of the actual portfolio *right now*. Smoothing toward it would mean the execution NAV is knowingly wrong during the window, creating real value transfer:

- On **positive** deltas: new depositors buy stale-cheap shares, capturing yield earned by existing holders
- On **negative** deltas: early redeemers exit above fair value, socializing the loss to remaining holders

Both are economically unsound for a reserve-backed system. The correct model is: snap to current truth, then project forward using the oracle's attested forward rate (expected yield rate for the next period).

**Forward rate**: The oracle provides `forwardRateRay` as a separate input — the expected rate of NAV change until the next attestation (e.g., the T-bill yield rate). This is clamped by `maxRateAbsRay`. The forward rate is a projection, not a guarantee; the next attestation corrects any divergence.

**Stale recovery safety**: The hard-reset path no longer bypasses jump limits entirely. Instead, it validates against `lastKnownGoodNAV` with a relaxed multiplier (`MAX_STALE_JUMP_MULTIPLIER`, e.g., 3x). This prevents a compromised oracle from waiting for staleness and then submitting an unbounded reset. If the jump exceeds even the relaxed limit, governance must intervene via `forceUpdateNAV()`.

**Smoothing window tuning**: The `forwardRateRay` should reflect the expected yield for the attestation interval. If the oracle attests every 24 hours, the forward rate should be the daily T-bill yield rate expressed per second. This naturally calibrates inter-attestation projection to attestation frequency without a separate smoothing window parameter.

**Worked example — Normal update (snap + forward rate)**:
```
State:  nav0Ray = 1.000000e27, t0 = T, forwardRate = +1.585e17/s (~5% APY)

At T+86400 (24h later):
  projectedNAV = 1.000000e27 + 1.585e17 * 86400 = 1.000014e27
  Oracle attests: currentNAV = 1.000014e27, forwardRate = +1.590e17/s

  jumpBps = |1.000014e27 - 1.000014e27| * 10000 / 1.000014e27 = 0 bps ✓
  Result: nav0 = 1.000014e27 (snapped), rate = +1.590e17/s (new forward rate)

  → No stale-price exploitation window. Shares are priced at truth from this block.
```

**Worked example — Negative attestation (reserve loss)**:
```
State:  nav0Ray = 1.050000e27, forwardRate = +1.585e17/s
        maxNavJumpBps = 100 (1%)

Oracle attests: currentNAV = 1.042000e27, forwardRate = 0
  previousNAV = projected value at current time
  jumpBps = |1.042000e27 - previousNAV| * 10000 / previousNAV
  If jumpBps <= 100: accepted, snap to 1.042000e27

  → Share price drops immediately. No smoothing window where redeemers can exit above fair value.
```

**Worked example — Oracle goes offline (staleness)**:
```
State:  nav0Ray = 1.050e27, rate = +1.585e17/s, maxStaleness = 86400

If oracle stays offline for 48h:
  dt = min(172800, 86400) = 86400 (capped)
  projectedNAV = 1.050e27 + 1.585e17 * 86400 = 1.05137e27
  stale = true → all NAV-dependent operations halt (deposits, redeems, escrows, paymaster)

  On next updateNAV():
    jumpBps checked against lastKnownGoodNAV with relaxed multiplier
    If within bounds: snap to attested value
    If exceeds bounds: requires governance forceUpdateNAV()
```

### 3.5 Bridge NAV Relay

Cross-chain NAV synchronization bypasses smoothing — the remote chain receives the exact `(nav0, t0, rate)` triple from the canonical chain:

```
FUNCTION relayNAV(nav0Ray_, t0_, ratePerSecondRay_, newEpoch):
  REQUIRE !navUpdatesPaused
  REQUIRE newEpoch > navEpoch
  REQUIRE t0_ <= now                    // No future timestamps
  REQUIRE nav0Ray_ >= minNavRay
  REQUIRE |ratePerSecondRay_| <= maxRateAbsRay

  // Jump check against local NAV (if not stale)
  IF !stale AND maxNavJumpBps > 0:
    localNAV = project(nav0Ray, t0, ratePerSecondRay, now)
    remoteNAV = nav0Ray_ + ratePerSecondRay_ * (now - t0_)
    jumpBps = |remoteNAV - localNAV| * 10000 / localNAV
    REQUIRE jumpBps <= maxNavJumpBps

  nav0Ray = nav0Ray_
  t0 = t0_
  ratePerSecondRay = ratePerSecondRay_
  navEpoch = newEpoch
```

Both chains now produce the same `currentNAVRay()` at the same wall-clock time, ensuring share/asset conversions are consistent cross-chain.

---

## 4. Share Vault (wSSDC)

### 4.1 Purpose

`wSSDCVaultV2` is an ERC-4626 tokenized vault that holds settlement assets (USDC) and issues yield-bearing shares. Shares are the universal unit of account in the SSDC system — they are used for escrow, gas payment, bridging, and direct transfers.

### 4.2 Share Pricing

```
assetsForShares(shares) = (shares * currentNAVRay()) / RAY      [round down]
sharesForAssets(assets) = (assets * RAY) / currentNAVRay()       [round varies by operation]
```

As NAV increases over time, each share is worth more settlement assets. Holders earn yield simply by holding shares — no rebasing, no claiming.

### 4.3 totalAssets() and the Backing Model

The vault's `totalAssets()` is computed as:

```solidity
function totalAssets() public view returns (uint256) {
    return RayMath.convertToAssetsDown(totalSupply(), _accountingNAVRay());
}
```

This returns the **attested value** of all outstanding shares, not the on-chain USDC balance. The on-chain USDC balance (`settlementAsset.balanceOf(vault)`) may be less than `totalAssets()` when a portion of the reserve is deployed off-chain into Treasury instruments. The difference between `totalAssets()` and on-chain balance represents the off-chain reserve deployment.

**ERC-4626 composability warning**: Protocols composing with wSSDC should **not** rely solely on `totalAssets()` for solvency assessments. Because `totalAssets()` reflects the attested NAV (which includes off-chain reserves), the vault may report a `totalAssets()` far exceeding on-chain liquidity. Composing protocols should also check `liquidityCoverageBps()` to assess what fraction of reported assets is immediately redeemable. A vault with `totalAssets() = 10M USDC` but `liquidityCoverageBps() = 500` (5%) has only ~500K USDC available for instant withdrawal — the rest is in Treasuries and requires claim queue processing.

### 4.4 Deposit Flow

```
User approves settlementAsset to gateway/vault
  → gateway.deposit(assets, receiver, minSharesOut)
    → vault.deposit(assets, receiver)
      → shares = convertToSharesDeposit(assets)  [round down]
      → _mint(receiver, shares)
      → settlementAsset.transferFrom(gateway, vault, assets)
    → REQUIRE shares >= minSharesOut              [slippage protection]
```

### 4.5 Gateway Enforcement

When `gatewayRequired = true`, only addresses with `GATEWAY_ROLE` can call `deposit`, `mint`, `withdraw`, and `redeem` on the vault directly. This forces all user-facing operations through `SSDCVaultGatewayV2`, which adds slippage protection and atomic multi-step flows (deposit-to-escrow, deposit-to-gas-tank).

### 4.6 Bridge Share Provenance

The vault tracks **bridged shares** separately:

```
bridgedSharesBalance[holder]  // Per-account bridged share count
bridgedSharesSupply            // Total bridged shares in circulation
```

On transfer, bridged shares follow the sender proportionally. On burn, bridged shares are reduced first. This provenance tracking enables the bridge to enforce mint caps — the system knows exactly how many shares originated from cross-chain mints versus native deposits.

### 4.7 Liquidity Coverage

Before minting bridge shares, the vault checks:

```
postLiability = convertToAssets(totalSupply + newShares)
coverage = availableSettlementAssets * 10000 / postLiability

REQUIRE coverage >= minBridgeLiquidityCoverageBps
```

This prevents the bridge from minting shares beyond what the vault can cover with on-chain settlement assets.

### 4.8 Agent Account Model

**Requirement**: Agent addresses MUST be policy-enforcing smart accounts (ERC-4337 compatible), not arbitrary EOAs or generic wallets. This is the foundation of the safety model.

**Problem**: The vault is a standard ERC-20. Any address holding wSSDC shares can call `transfer()`, `approve()`, `withdraw()`, `redeem()`, or `bridgeOut()` directly, bypassing the policy module, grounding checks, merchant allowlists, daily limits, and session expiry. If agents are EOAs, the policy module is advisory, not enforcing.

**Solution**: Agent wallets must implement a **validator module** that intercepts outbound calls and enforces policy:

```
WALLET VALIDATOR (in agent's smart account):

  Before executing any call:
    IF target == vault AND selector in {transfer, approve, withdraw, redeem}:
      assets = convertToAssets(shares)
      REQUIRE policyModule.canSpend(self, to, assets)
      REQUIRE !groundingRegistry.isGroundedNow(self)
      REQUIRE block.timestamp <= policy.sessionExpiry

    IF target == bridge AND selector == bridgeOut:
      REQUIRE policyModule.canSpend(self, address(0), bridgeAssets)
      REQUIRE !groundingRegistry.isGroundedNow(self)

    IF target == vault AND selector == approve:
      // Only allow approved spenders (gateway, escrow, paymaster)
      REQUIRE approvedSpender[spender]
```

**Enforcement guarantee**: With this model, the only way for an agent to move value is through its smart account, and the smart account enforces policy on every outbound path. The policy module is no longer advisory — it is a hard constraint.

**Operator responsibility**: The entity deploying agent wallets (orchestrator, platform) is responsible for using wallet implementations with the correct validator. The protocol cannot prevent someone from deploying a wallet without a validator, but such a wallet would not be eligible for policy protections and grounding guarantees.

**EOA compatibility**: EOAs can still hold wSSDC and interact with the vault (they are standard ERC-20 holders). They simply do not benefit from policy enforcement. The policy module's spend limits and grounding checks only provide guarantees for compliant smart account wallets.

### 4.9 Async Redemption and ERC-7540

The vault's redemption flow is asynchronous: `requestRedeem()` → queue processing → `claim()`. This deviates from standard ERC-4626, where `redeem()` is atomic and synchronous. Standard ERC-4626 `preview` functions may return values that cannot be realized in the same transaction.

**ERC-7540 alignment**: The claim queue implements a request-based async redemption pattern similar to [ERC-7540](https://eips.ethereum.org/EIPS/eip-7540) (Asynchronous Tokenized Vaults). Integrators expecting standard ERC-4626 semantics should be aware:

- `maxRedeem()` returns the shares redeemable from on-chain liquidity, not total holdings
- `previewRedeem()` returns asset value at current NAV, but actual payout occurs at processing-time NAV (see [Section 6.4](#64-redemption-economics))
- `redeem()` on the vault is synchronous but limited to available on-chain liquidity
- The claim queue handles the async path for amounts exceeding instant liquidity

A future version may expose an ERC-7540-compliant adapter wrapping `requestRedeem()` and `claim()` with standard `requestRedeem(shares, controller, owner)` → `claimableRedeemRequest()` → `redeem()` semantics.

---

## 5. Yield Escrow

### 5.1 Purpose

`YieldEscrowV2` is the core commerce primitive. It locks vault shares in escrow for invoice-based payments, with milestone-tracked fulfillment, dispute resolution, and automatic yield splitting. The key innovation: **funds earn yield while in escrow**, and that yield is split between buyer, merchant, protocol, and reserve.

### 5.2 Invoice Terms

Every escrow is created with an `InvoiceTerms` struct:

```solidity
struct InvoiceTerms {
    uint256 assetsDue;                  // Principal amount owed
    uint40  expiry;                     // Deadline to fund the escrow
    uint40  releaseAfter;               // Earliest possible release
    uint40  maxNavAge;                  // Max NAV staleness at funding
    uint256 maxSharesIn;               // Slippage protection
    bool    requiresFulfillment;        // Must merchant prove delivery?
    FulfillmentType fulfillmentType;    // DELIVERY | SERVICE | DIGITAL | OTHER
    uint8   requiredMilestones;         // Sequential proof steps
    uint40  challengeWindow;            // Seconds for buyer to dispute after fulfillment
    uint40  arbiterDeadline;            // Seconds for arbiter to resolve after dispute
    DisputeResolution disputeTimeoutResolution;  // Auto-resolution on challenge/arbiter timeout
}
```

**Note on `maxSharesIn`**: Setting this to `type(uint256).max` disables slippage protection entirely. Callers should set a realistic bound (e.g., `expectedShares * 110 / 100` for 10% tolerance).

**NAV staleness interaction**: Between invoice creation and funding, the NAV may advance (via the linear projection), causing `convertToSharesUp(assetsDue)` to return a different share count than at invoice time. If the buyer sets `maxSharesIn` tightly and the NAV drops (negative rate or oracle downward attestation), the share cost increases and the transaction reverts with `SHARES_SLIPPAGE`. SDK consumers should pad `maxSharesIn` to account for the maximum projected NAV change over the expected funding delay: `maxSharesIn = expectedShares * (1 + |ratePerSecondRay| * maxFundingDelay / NAV)`.

### 5.3 Escrow State Machine

```
                              fundEscrow()
                    ┌───────────────────────────────┐
                    │                               │
                    v                               │
                 FUNDED ────────────────────────────┘
                    │
          ┌────────┼────────┐
          │        │        │
    submitFulfillment()  dispute()
          │        │        │
          │        │        v
          │        │    DISPUTED ──── resolveDispute() ──→ RESOLVED
          │        │        │                                  │
          │        │        └──── (timeout) ───────────────────┤
          │        │                                           │
          │        └───────────────────────────────────────────┤
          │                                                    │
          ├─── release() ──→ RELEASED (yield split)            │
          │                                                    │
          └─── refund() ──→ REFUNDED (full return to buyer)    │
                    ^                                          │
                    └──────────────────────────────────────────┘
```

**Terminal states**: RELEASED, REFUNDED. Once settled, shares are distributed and the escrow is closed.

### 5.4 Settlement Modes

The system tracks exactly *how* an escrow was settled for accounting and auditability:

| Mode | Code | Who Initiated | Conditions |
|------|------|---------------|------------|
| `BUYER_RELEASE` | 1 | Buyer | After `releaseAfter`, no active dispute blocking |
| `MERCHANT_TIMEOUT_RELEASE` | 2 | Merchant | Fulfillment complete + challenge window expired |
| `DISPUTE_TIMEOUT_RELEASE` | 3 | Anyone | Dispute window expired, `timeoutResolution = RELEASE` |
| `ARBITER_RELEASE` | 4 | Arbiter | Arbiter override, any state |
| `BUYER_REFUND` | 5 | Buyer | Before fulfillment, or after dispute resolution |
| `DISPUTE_TIMEOUT_REFUND` | 6 | Anyone | Dispute window expired, `timeoutResolution = REFUND` |
| `ARBITER_REFUND` | 7 | Arbiter | Arbiter override |

### 5.5 Release Authorization Matrix

| Caller | No Dispute | Disputed (unresolved, window open) | Disputed (window expired, timeout=RELEASE) | Disputed (arbiter resolved RELEASE) | Disputed (arbiter resolved REFUND) |
|--------|------------|------|------|------|------|
| **Buyer** | Release (after `releaseAfter` + fulfillment) | Blocked | Release | Release | Blocked |
| **Merchant** | Release only if fulfillment complete + challenge window expired | Blocked | Release | Release | Blocked |
| **Arbiter** | Release (override) | Release (override) | Release | Release | Blocked |

### 5.6 Yield Split on Release

When an escrow is released, the shares held have appreciated due to NAV growth:

```
Given:
  S = sharesHeld (total shares in escrow)
  P = principalAssetsSnapshot (assets locked at funding time)
  NAV = currentNAVRay()
  buyerBps, reserveBps, protocolFeeBps ∈ [0, 10000]

Calculate:
  principalShares = min(convertToSharesUp(P, NAV), S)
  grossYield = S - principalShares

  reserveShares   = grossYield * reserveBps / 10000
  afterReserve    = grossYield - reserveShares

  feeShares       = afterReserve * protocolFeeBps / 10000
  netYield        = afterReserve - feeShares

  buyerYield      = netYield * buyerBps / 10000
  merchantYield   = netYield - buyerYield

Distribution:
  merchant  ← principalShares + merchantYield
  buyer     ← buyerYield
  reserve   ← reserveShares
  protocol  ← feeShares

Invariant:
  principalShares + merchantYield + buyerYield + reserveShares + feeShares = S
```

**Worked example — Positive yield**:

Agent A pays 1000 USDC for a service. NAV at funding: 1.00. NAV at release (30 days later): 1.05 (5% yield). `reserveBps = 500`, `protocolFeeBps = 1000`, `buyerBps = 2000`.

```
S = 1000 shares,  P = 1000 USDC
principalShares = ceil(1000 * RAY / (1.05 * RAY)) = 953 shares
grossYield = 1000 - 953 = 47 shares

reserveShares = floor(47 * 500 / 10000) = 2 shares
afterReserve = 47 - 2 = 45 shares

feeShares = floor(45 * 1000 / 10000) = 4 shares
netYield = 45 - 4 = 41 shares

buyerYield = floor(41 * 2000 / 10000) = 8 shares
merchantYield = 41 - 8 = 33 shares

Final distribution:
  merchant: 953 + 33 = 986 shares  (× 1.05 = 1035.30 USDC)
  buyer:    8 shares               (× 1.05 = 8.40 USDC)
  reserve:  2 shares               (× 1.05 = 2.10 USDC)
  protocol: 4 shares               (× 1.05 = 4.20 USDC)
  total:    1000 shares ✓
```

### 5.7 Negative NAV Scenario (NAV Drawdown During Escrow)

If the NAV decreases while funds are in escrow (e.g., due to a reserve loss), the yield split math handles this gracefully through the `min()` guard:

```
principalShares = min(convertToSharesUp(P, NAV), S)
```

When NAV drops, `convertToSharesUp(P, NAV)` returns a value **larger** than `S` (more shares needed to cover the same principal at a lower price). The `min()` clamps it to `S`.

**Worked example — Negative yield**:

1000 USDC deposited at NAV = 1.00 (1000 shares). NAV drops to 0.95.

```
principalShares = min(ceil(1000 * RAY / (0.95 * RAY)), 1000)
               = min(1053, 1000)
               = 1000

grossYield = 1000 - 1000 = 0

All yield components = 0
merchant receives: 1000 shares × 0.95 = 950 USDC
```

**The merchant absorbs the principal haircut.** This is by design — the escrow's share count is fixed at funding time, and if those shares depreciate, the merchant receives the full share count but at reduced value. The merchant bears NAV downside risk on the principal. The buyer's yield share is zero (no yield to split), but the buyer also bears no additional loss beyond the escrowed amount.

### 5.8 Refund Yield Distribution

On refund, the escrow returns **all shares** to the `refundRecipient` (typically the buyer) without any yield split:

```
FUNCTION refund(escrowId):
  ...
  vault.transfer(refundRecipient, sharesHeld)   // ALL shares, no split
```

**There is no yield split on refund.** The buyer receives 100% of `sharesHeld`, including any yield accrued during the escrow period. The protocol takes no fee. This is deliberate — a refund represents a failed transaction (non-delivery, dispute resolved in buyer's favor), and extracting fees from a failed transaction would penalize the buyer for the merchant's failure.

**Worked example — Refund after yield accrual**:

1000 USDC deposited at NAV = 1.00 (1000 shares). Dispute resolved as REFUND at NAV = 1.03.

```
refundRecipient receives: 1000 shares × 1.03 = 1030 USDC
protocol fee: 0
reserve: 0
merchant: 0
```

The buyer keeps the yield as compensation for their capital being locked during the dispute.

### 5.9 Milestone Fulfillment

For escrows with `requiresFulfillment = true`, the merchant must submit proof for each milestone sequentially:

```
submitFulfillment(escrowId, evidenceHash, milestoneNumber):
  REQUIRE milestoneNumber == completedMilestones + 1
  REQUIRE milestoneNumber <= requiredMilestones
  REQUIRE caller == merchant OR hasRole(ARBITER_ROLE)

  completedMilestones++
  IF completedMilestones == requiredMilestones:
    fulfilledAt = block.timestamp       // Starts the challenge window
```

The buyer (or any party) can dispute a specific milestone, targeting the fulfillment chain from that point.

### 5.10 Dispute Resolution

The escrow uses two separate time windows:

| Window | Field | Starts When | Expires When | Effect of Expiry |
|--------|-------|-------------|--------------|------------------|
| **Challenge window** | `challengeWindow` | Fulfillment complete (`fulfilledAt`) | `fulfilledAt + challengeWindow` | Merchant may self-release |
| **Arbiter deadline** | `arbiterDeadline` | Dispute filed (`disputedAt`) | `disputedAt + arbiterDeadline` | `disputeTimeoutResolution` auto-applies |

**Who may dispute and when**:
- **Buyer**: Any time while escrow is FUNDED, before or after fulfillment
- **Merchant**: Any time while escrow is FUNDED (e.g., to escalate a stalled buyer)
- **Arbiter**: Any time (override)

```
dispute(escrowId, reason, milestoneNumber, reasonHash):
  REQUIRE !escrow.disputed            // One dispute per escrow
  REQUIRE caller ∈ {buyer, merchant, arbiter}
  REQUIRE reason ∈ {NON_DELIVERY, QUALITY, NOT_AS_DESCRIBED, FRAUD_OR_CANCELLED, OTHER}

  escrow.disputed = true
  escrow.disputedAt = now
  // Arbiter deadline clock starts: arbiter has arbiterDeadline seconds to resolve

resolveDispute(escrowId, resolution, evidenceHash):   [ARBITER ONLY]
  REQUIRE escrow.disputed
  REQUIRE resolution ∈ {RELEASE, REFUND}

  escrow.resolution = resolution
  escrow.resolvedAt = now
```

**Challenge window timeout**: After fulfillment, the merchant cannot self-release until `fulfilledAt + challengeWindow`. If the buyer does not dispute within this window, the merchant may call `releaseEscrow()`. If `challengeWindow = 0`, the merchant may release immediately after fulfillment.

**Arbiter deadline timeout**: Once a dispute is filed, the arbiter has `arbiterDeadline` seconds to call `resolveDispute()`. If the arbiter fails to resolve in time, **any party** may call `executeTimeout(escrowId)`, which applies `disputeTimeoutResolution` automatically:

```
executeTimeout(escrowId):
  REQUIRE escrow.disputed
  REQUIRE now > escrow.disputedAt + arbiterDeadline
  REQUIRE escrow.resolution == NONE       // Arbiter hasn't resolved yet

  escrow.resolution = disputeTimeoutResolution
  escrow.resolvedAt = now
```

This bounds the maximum dispute duration. The escrow creator's declared `disputeTimeoutResolution` applies consistently regardless of whether the timeout is buyer/merchant inaction or arbiter liveness failure.

**Terminal states**: An escrow is terminal (no further state changes) once:
- `releaseEscrow()` succeeds → status = RELEASED
- `refundEscrow()` succeeds → status = REFUNDED
- Both are irreversible. No re-opening, no appeal.

---

## 6. Claim Queue

### 6.1 Purpose

`SSDCClaimQueueV2` handles asynchronous redemption of shares back to settlement assets. Unlike direct `vault.withdraw()` which requires immediate liquidity, the queue buffers redemptions and processes them as the reserve manager returns USDC from Treasury positions.

### 6.2 Claim Lifecycle

```
requestRedeem(shares, receiver)
  → PENDING (NFT minted to receiver)
     → processQueue()
        → CLAIMABLE (assets reserved)
           → claim(claimId)
              → CLAIMED (assets transferred, NFT burned)

  → cancel(claimId)
     → CANCELLED (shares returned, NFT burned)
```

### 6.3 Queue Processing

```
processQueue(maxClaims):
  cursor = head
  scansRemaining = maxClaims * 8    // scan budget

  WHILE cursor < nextClaimId AND processed < maxClaims AND scansRemaining > 0:
    claim = claims[cursor]

    IF claim.status != PENDING:
      cursor++; scansRemaining--
      CONTINUE                      // Skip non-pending (cancelled, already processed)

    success = _tryProcessClaim(cursor)

    IF !success AND !canSkipBlockedClaims:
      BREAK                         // Strict FIFO: stall if can't process

    // cursor ALWAYS advances, even if claim was skipped
    cursor++; scansRemaining--

    IF success:
      processed++

  _syncHead()    // Advance head past all non-PENDING claims
```

### 6.4 Redemption Economics

**When is `assetsOwed` determined?** At **processing time** — not at request time or claim time.

```
requestRedeem(shares):
  assetsSnapshot = convertToAssets(shares)    // Recorded for reference only
  assetsOwed = 0                              // Not yet determined

_tryProcessClaim(claimId):
  assetsOwed = convertToAssets(sharesLocked)  // Determined HERE at processing-time NAV
  // Shares are burned, assets reserved

claim(claimId):
  transfer(assetsOwed)                        // Fixed at processing time
```

**Implications**:
- The redeemer is exposed to NAV movement between request and processing. If NAV rises while waiting, they receive more; if it falls, they receive less.
- `assetsSnapshot` (recorded at request time) is stored for audit/UI purposes but has no economic effect.
- Once processing sets `assetsOwed`, that amount is fixed through `claim()` — no further NAV movement affects it.

**Who captures queue-wait NAV movement**: The redeemer. Their shares remain in the queue contract, and the shares-to-assets conversion happens at the processing-time NAV. This means the queue does not create a risk-free arbitrage: redeemers waiting in queue are fully exposed to NAV changes, just as they would be holding shares in their wallet.

**Liquidity path**: `_tryProcessClaim()` sources settlement assets from two places:
1. **Vault**: `vault.withdraw(assetsFromVault, queue, queue)` — pulls on-chain USDC from the vault, burning proportional shares
2. **External buffer**: `availableAssets` in the queue contract, filled via `refill()` by the `BUFFER_ROLE`

The `refill()` function transfers settlement assets directly to the queue contract. This is how the reserve manager returns USDC from liquidated Treasury positions. The flow is: `reserveManager → queue.refill(amount)` → increases `availableAssets` → enables processing of pending claims.

### 6.5 Skipped Claims: Known Behavior

**When `skipBlockedClaims = true`**: If a PENDING claim cannot be processed (insufficient buffer liquidity), the cursor advances past it. Critically, `_syncHead()` only advances the `head` pointer past **non-PENDING** claims (CLAIMABLE, CLAIMED, CANCELLED). It stops at the first PENDING claim it encounters:

```
FUNCTION _syncHead():
  cursor = head
  WHILE cursor < nextClaimId AND claims[cursor].status != PENDING:
    cursor++
  head = cursor
```

This means **skipped PENDING claims are NOT orphaned**. They remain ahead of or at the `head` pointer, and future `processQueue()` calls will encounter them again. A `ClaimSkipped` event is emitted for each skipped claim, providing observability for off-chain monitoring.

**Behavioral modes**:

- **Without skipping** (`skipBlockedClaims = false`, the default): The queue stalls at any blocked claim. Users behind a large blocked claim must wait. The blocked user can `cancel()` their claim to unblock the queue.
- **With skipping** (`skipBlockedClaims = true`): The cursor advances past blocked claims within a single `processQueue()` call, processing smaller claims that have sufficient liquidity. Blocked claims remain PENDING and will be retried when `processQueue()` is called again (after liquidity improves via `refill()` or natural deposits).

**Operational guidance**: The admin should monitor `ClaimSkipped` events. If a claim is repeatedly skipped across multiple `processQueue()` calls, it indicates a persistent liquidity shortfall for that claim size. The admin can either `refill()` the buffer to cover it, or the claim holder can `cancel()` and re-queue for a smaller amount.

### 6.6 Invariants

1. **Reserved backing**: `reservedAssets <= settlementAsset.balanceOf(queue)` — every reserved claim is backed by actual settlement assets
2. **Head monotonicity**: `head` never decreases
3. **Claim sum**: `SUM(claim.assetsOwed WHERE status == CLAIMABLE) == reservedAssets`

---

## 7. Policy Module

### 7.1 Purpose

`SSDCPolicyModuleV2` enforces per-agent spending limits, merchant allowlists, session timeouts, and collateral commitment tracking. Policy enforcement is a **hard constraint** for agents using compliant smart account wallets (see [Section 4.8](#48-agent-account-model)) — the wallet validator intercepts all value-moving calls and enforces policy before execution. For EOAs or non-compliant wallets, the policy module is advisory only.

### 7.2 Agent Policy Structure

```solidity
struct AgentPolicy {
    uint256 perTxLimitAssets;           // Max per single transaction
    uint256 dailyLimitAssets;           // Max per 24-hour rolling window
    uint256 spentTodayAssets;           // Running spend counter
    uint40  dayStart;                   // Start of current 24h window
    uint256 minAssetsFloor;             // Minimum collateral floor
    uint256 committedAssets;            // Assets locked in escrows/paymaster
    uint40  sessionExpiry;              // Policy expires at this timestamp
    bool    enforceMerchantAllowlist;   // Restrict to approved merchants
    bool    exists;                     // Policy has been set
}
```

### 7.3 Spend Validation

```
FUNCTION canSpend(agent, merchant, assets) → bool:
  policy = policies[agent]
  REQUIRE policy.exists

  // Session check
  IF policy.sessionExpiry > 0 AND now > policy.sessionExpiry:
    RETURN false

  // Per-transaction limit
  IF policy.perTxLimitAssets > 0 AND assets > policy.perTxLimitAssets:
    RETURN false

  // Daily limit (sliding 24h window)
  IF now - policy.dayStart >= 1 day:
    effectiveSpent = 0      // Day rolled over
  ELSE:
    effectiveSpent = policy.spentTodayAssets

  IF policy.dailyLimitAssets > 0 AND effectiveSpent + assets > policy.dailyLimitAssets:
    RETURN false

  // Merchant allowlist
  IF policy.enforceMerchantAllowlist AND !merchantAllowlist[agent][merchant]:
    RETURN false

  RETURN true
```

### 7.4 Daily Window Boundary Behavior

The 24-hour window is a **sliding window anchored to `dayStart`**, not a fixed calendar day. The `_rollDay()` function resets the window:

```
FUNCTION _rollDay(policy):
  IF now >= dayStart + 1 day:
    dayStart = now
    spentTodayAssets = 0
```

**Edge case**: An agent can spend its full daily limit at 23:59 (relative to `dayStart`), then trigger a window reset at 00:01 by making another transaction. This effectively allows **2x the daily limit** in a 2-minute burst at window boundaries.

**Worked example**:
```
dailyLimitAssets = 1000 USDC
dayStart = T

At T + 86399 (23h 59m 59s): agent spends 1000 USDC → spentToday = 1000
At T + 86401 (24h 0m 1s):   _rollDay() fires → dayStart = T+86401, spentToday = 0
                              agent spends 1000 USDC → spentToday = 1000

Net: 2000 USDC spent in ~2 seconds
```

This is a **known and accepted behavior**. The daily limit is a guardrail, not a rate limiter. For applications requiring strict throughput limiting, a token-bucket or sliding-window counter should be implemented at the application layer. The per-transaction limit (`perTxLimitAssets`) provides the hard per-operation cap regardless of window state.

### 7.5 Committed Assets

When an escrow is funded by a third party (e.g., gateway funding on behalf of agent), the principal is tracked as **committed assets**:

```
fundEscrow → policy.reserveCommittedSpend(agent, principalAssets)
  → committedAssets += principalAssets

releaseEscrow OR refundEscrow → policy.releaseCommittedSpend(agent, principalAssets)
  → committedAssets -= principalAssets
```

Committed assets are added to the effective floor in the grounding registry, preventing the agent from double-spending collateral already locked in escrows.

### 7.6 Effective Floor

```
effectiveFloor(agent) = configuredMinAssetsFloor + committedAssets
```

This is queried by the grounding registry to determine if the agent has sufficient collateral.

---

## 8. Grounding Registry

### 8.1 Purpose

`GroundingRegistryV2` answers one question: **does this agent have enough collateral?** It aggregates collateral from multiple sources (vault shares, gas tank, external providers) and compares against the effective floor from the policy module.

### 8.2 Collateral Aggregation

```
FUNCTION totalShares(agent) → uint256:
  total = vault.balanceOf(agent)
  FOR EACH provider IN collateralProviders:    // max 16
    total += provider.collateralSharesOf(agent)
  RETURN total
```

The paymaster implements `ICollateralProviderV2`, so gas tank shares count toward collateral.

### 8.3 Grounding Check

```
FUNCTION isGroundedNow(agent) → bool:
  shares = totalShares(agent)          // vault + all providers (wrapped in try/catch)
  navRay = navController.currentNAVRay()  // REVERTS if stale or below min

  assets = convertToAssetsDown(shares, navRay)
  floor = policyModule.getMinAssetsFloor(agent)
    = configuredFloor + committedAssets

  RETURN assets < floor
```

**Fail-closed behavior**: `isGroundedNow()` calls `currentNAVRay()`, which **reverts** if the NAV is stale or below the minimum floor. This means grounding checks are fail-closed: when the NAV is unavailable, all operations that check grounding (escrow funding, gas sponsorship) revert. This is the correct behavior — when collateral cannot be computed, the system must not assume the agent is solvent.

**Collateral provider resilience**: `totalShares()` calls external `ICollateralProviderV2` contracts. A reverting or malicious provider could DoS grounding checks. To prevent this, each provider call is wrapped in `try/catch` — a reverting provider is treated as contributing 0 shares (conservative assumption), and governance can disable it via `setCollateralProvider(provider, false)`.

**Naming note**: `isGroundedNow() = true` means the agent is **below** its collateral floor — i.e., in trouble. The name derives from "grounded" as in "grounded from flying" (restricted), not "grounded" as in "well-grounded" (stable). This is a known source of confusion. SDK consumers should use the `AgentStatus.isGrounded` field which is documented as: *"true if the agent's collateral is insufficient and operations are restricted."*

**Committed assets accounting**: The floor includes `committedAssets`, which represents unsecured obligations — escrow value that has NOT already left the agent's counted collateral. Specifically:
- **Direct funding** (agent pays from own wallet): Shares transfer from agent to escrow, reducing `vault.balanceOf(agent)`. `committedAssets` is NOT incremented — the obligation is already reflected in the reduced balance.
- **Third-party funding** (gateway pays on agent's behalf): Shares transfer from the funder, not the agent. The agent's `vault.balanceOf()` is unchanged, so `committedAssets` IS incremented to reflect the obligation that isn't visible in the balance.

This prevents double-counting: direct funding reduces the numerator (balance), while third-party funding increases the denominator (floor). Both correctly restrict the agent's spending capacity.

Grounded agents cannot:
- Fund new escrows (grounding check in `fundEscrow`)
- Have gas sponsored by the paymaster (grounding check in `validatePaymasterUserOp`)
- Perform operations that would further reduce their collateral

### 8.4 Poke

`poke(agent)` is a permissionless state-changing function that updates the grounding status and emits events:

```
FUNCTION poke(agent):
  grounded = isGroundedNow(agent)
  IF grounded != previousGroundedState[agent]:
    previousGroundedState[agent] = grounded
    IF grounded:
      EMIT AgentGrounded(agent)
    ELSE:
      EMIT AgentUngrounded(agent)
```

**Incentive design**: Currently, `poke()` provides no direct reward to the caller. The gas cost is borne by whoever calls it. In practice, the following parties are incentivized to call `poke()`:

- **The agent itself**: Agents check their own status before transacting (the SDK's `getStatus()` method reads `isGroundedNow()`)
- **Counterparties**: Before accepting a payment request, a buyer agent can poke the merchant to verify solvency
- **Orchestrators**: Swarm orchestrators monitor their workers' grounding status as part of normal operations

A future protocol version may introduce a **keeper bounty** — a small share reward paid from the grounded agent's collateral to the poke caller — to incentivize decentralized enforcement. For V2, the operational overhead of `poke()` is low (single view call + state write) and the primary enforcement happens inline during `fundEscrow()` and `validatePaymasterUserOp()`, which check grounding atomically.

---

## 9. Yield Paymaster

### 9.1 Purpose

`YieldPaymasterV2` enables gasless transactions for agents via ERC-4337 account abstraction. Instead of holding ETH for gas, agents deposit vault shares into a **gas tank**. The paymaster converts gas costs from ETH to share equivalents using an ETH/USD oracle, then deducts from the gas tank.

### 9.2 Gas Tank

```
gasTankShares[agent] → uint256    // Shares deposited for gas credit

topUpGasTank(shares):
  vault.transferFrom(caller, paymaster, shares)
  gasTankShares[caller] += shares

topUpGasTankFor(agent, shares):
  vault.transferFrom(caller, paymaster, shares)
  gasTankShares[agent] += shares
```

The paymaster implements `ICollateralProviderV2.collateralSharesOf(agent)`, returning `gasTankShares[agent]`. This means gas tank shares count toward the agent's total collateral in the grounding registry.

### 9.3 Gas Cost Conversion

The paymaster converts the **total L2 transaction cost** (execution gas + L1 data fee + operator fee) to settlement asset equivalents. On OP Stack chains, the total cost is not simply `gasUsed × gasPrice` — it includes additional fee components:

```
totalCostWei = executionGas × effectiveGasPrice     // L2 execution
             + l1DataFee                             // L1 calldata posting cost
             + operatorFee                           // OP Stack operator fee (if enabled)
```

The paymaster receives `actualGasCost` from the EntryPoint's `postOp()` callback, which includes all fee components. The conversion to settlement assets:

```
FUNCTION _ethToSettlementAssets(weiAmount) → assets:
  (ethUsdcPriceE18, updatedAt) = ethUsdcOracle.latestPrice()
  REQUIRE ethUsdcPriceE18 > 0                             // PRICE_ZERO
  REQUIRE now - updatedAt <= maxPriceStaleness            // PRICE_STALE

  assets = ceil(weiAmount * ethUsdcPriceE18 / 1e30)       // Rounding.Ceil to 6-decimal settlement units
```

**Pricing basis**: The oracle provides **ETH/USDC** price (not ETH/USD). This is consistent with Section 1.5 — the system is denominated in the settlement asset (USDC), not fiat dollars. If USDC depegs from USD, the oracle must track the ETH/USDC pair, not ETH/USD. Operators must select an oracle that quotes ETH in terms of USDC specifically.

**Oracle latency risk**: `Rounding.Ceil` ensures the agent always pays at least the true cost. The `maxPriceStaleness` parameter bounds oracle lag. Operators should set this conservatively (e.g., 15 minutes).

**Share charge formula**:

```
chargedAssets = ceil(totalCostWei × ethUsdcPriceE18 / 1e30)
chargedShares = convertToSharesUp(chargedAssets)
```

V2 applies `Rounding.Ceil` but no configurable markup. A future version may add a markup parameter as an additional buffer against oracle latency and fee volatility.

**Gas vs commerce spend**: Gas charges use `consumeGasSpend(agent, assetsCost)` — a separate spend path that increments `spentTodayAssets` but does **not** check merchant allowlists. Gas payments are infrastructure costs, not commerce transactions, and should not be subject to merchant-level restrictions. The daily limit and per-tx limit still apply as global safety caps.

### 9.4 UserOp Validation (ERC-4337)

When an agent submits a UserOperation:

```
FUNCTION validatePaymasterUserOp(opKey, agent, maxGasCostWei, merchant):
  REQUIRE !paymasterPaused
  REQUIRE !groundingRegistry.isGroundedNow(agent)

  // Convert ETH gas cost to settlement asset cost
  assetsCost = _ethWeiToUsdAssets(maxGasCostWei)

  // Convert asset cost to shares
  chargeShares = convertToSharesUp(assetsCost, navRay)

  // Check gas tank balance
  REQUIRE chargeShares <= gasTankShares[agent]

  // Check post-op collateral floor
  totalShares = gasTankShares[agent] + vault.balanceOf(agent)
  postAssets = convertToAssetsDown(totalShares - chargeShares, navRay)
  REQUIRE postAssets >= policyModule.getMinAssetsFloor(agent)

  // Check policy spend limits
  REQUIRE policyModule.canSpend(agent, merchant, assetsCost)

  // Store pending charge (must complete in same block)
  pendingCharges[opKey] = PendingCharge({
    agent: agent,
    maxGasCostWei: maxGasCostWei,
    maxShares: chargeShares,
    merchant: merchant,
    preparedAtBlock: block.number
  })

  RETURN chargeShares
```

**ERC-7562 storage access rules**: Standard ERC-4337 bundlers enforce strict storage access rules during the validation phase (ERC-7562) to prevent mempool DoS. A Paymaster is generally restricted to reading its own associated storage during `validatePaymasterUserOp`. This Paymaster reads five external contracts (`ethUsdOracle`, `navController`, `vault`, `policyModule`, `groundingRegistry`), which would cause standard public bundlers (Alchemy, Pimlico) to drop the UserOp. Since Set Chain is a purpose-built OP Stack L2 (chain ID 84532001), the bundler is configured with a whitelist of core protocol contracts, exempting them from ERC-7562 storage restrictions during validation. This is an infrastructure-level configuration, not a contract change.

### 9.5 Post-Operation Settlement

After the UserOperation executes, the EntryPoint calls `postOp` with the **actual total gas cost** (including L1 data fee and operator fee):

```
FUNCTION postOp(opKey, agent, actualGasCostWei, merchant):
  pending = pendingCharges[opKey]
  REQUIRE pending.preparedAtBlock == block.number    // Same-block only
  REQUIRE pending.agent == agent
  REQUIRE pending.merchant == merchant

  DELETE pendingCharges[opKey]

  // actualGasCostWei comes from EntryPoint — includes all OP Stack fee components
  REQUIRE actualGasCostWei <= pending.maxGasCostWei

  actualAssetsCost = _ethToSettlementAssets(actualGasCostWei)
  sharesCharged = convertToSharesUp(actualAssetsCost, navRay)
  REQUIRE sharesCharged <= pending.maxShares

  // Deduct from gas tank FIRST, then check floor
  gasTankShares[agent] -= sharesCharged

  // Floor check uses post-deduction balance
  postShares = gasTankShares[agent] + vault.balanceOf(agent)
  postAssets = convertToAssetsDown(postShares, navRay)
  REQUIRE postAssets >= policyModule.getMinAssetsFloor(agent)

  // Record gas spend (no merchant allowlist check — gas is infrastructure)
  policyModule.consumeGasSpend(agent, actualAssetsCost)

  vault.transfer(feeCollector, sharesCharged)
```

**Post-charge floor check**: The floor check occurs **after** deducting `sharesCharged`, using the agent's actual post-deduction balance. This is critical: if the UserOperation itself moved value during execution (e.g., a `transfer()` call within the user op), the pre-deduction balance would be stale. The post-deduction check ensures the agent remains above floor after both the user op's effects and the gas charge.

**Same-block requirement**: The `preparedAtBlock == block.number` check ensures that validation and execution happen atomically. This perfectly aligns with ERC-4337's `validateUserOp` and `postOp` executing in the same bundle.

### 9.6 ETH Replenishment

The paymaster collects shares from agents but must hold ETH to fund the EntryPoint deposit. The replenishment loop:

1. **Paymaster collects shares** → transferred to `feeCollector`
2. **Off-chain operator** redeems shares for USDC (via claim queue or instant redeem)
3. **Operator swaps** USDC for ETH on-chain (DEX or OTC)
4. **Operator calls** `entryPoint.depositTo{value: ethAmount}(paymasterAddress)`

This loop is off-chain and manual in V2. The paymaster contract does not handle ETH acquisition. The operator must monitor the EntryPoint deposit balance and replenish before it reaches zero. A future version may automate this via an on-chain swap integration.

---

## 10. Cross-Chain Bridge

### 10.1 Purpose

`WSSDCCrossChainBridgeV2` enables share transfers between Set Chain deployments on different L2s. It uses a **mint/burn model** with trusted peer gating — shares are burned on the source chain and minted on the destination chain.

### 10.2 Bridge Out (Burn)

```
FUNCTION bridgeOut(dstChain, recipient, shares):
  REQUIRE !bridgePaused
  REQUIRE trustedPeer[dstChain] != bytes32(0)
  REQUIRE shares > 0 AND recipient != 0

  vault.burnBridgeShares(msg.sender, shares)

  nonce = bridgeOutNonce[msg.sender]++
  msgId = keccak256(encode(this, chainId, dstChain, sender, recipient, shares, nonce))

  EMIT BridgeOut(msgId, dstChain, sender, recipient, shares)
```

### 10.3 Bridge In (Mint)

```
FUNCTION receiveBridgeMint(srcChain, srcPeer, msgId, to, shares):  [BRIDGE_ROLE]
  REQUIRE !bridgePaused
  REQUIRE trustedPeer[srcChain] == srcPeer    // Peer verification
  REQUIRE !processed[msgId]                   // Replay protection

  processed[msgId] = true

  // Mint limit enforcement
  IF maxOutstandingShares > 0:
    REQUIRE vault.bridgedSharesSupply() + shares <= maxOutstandingShares

  vault.mintBridgeShares(to, shares)

  EMIT BridgeIn(msgId, srcChain, to, shares)
```

### 10.4 NAV Relay

```
FUNCTION relayNAV(srcChain, srcPeer, msgId, nav0, t0, rate, epoch):  [BRIDGE_ROLE]
  REQUIRE trustedPeer[srcChain] == srcPeer
  REQUIRE !processed[msgId]

  processed[msgId] = true
  navController.relayNAV(nav0, t0, rate, epoch)
```

### 10.5 Safety Properties

1. **Replay protection**: Every `msgId` can only be processed once
2. **Peer gating**: Only messages from trusted peers are accepted
3. **Mint cap**: `bridgedSharesSupply` cannot exceed `maxOutstandingShares`
4. **Liquidity coverage**: Bridge mints cannot violate the vault's liquidity floor
5. **NAV consistency**: Relayed NAV validated against jump thresholds and rate bounds
6. **Epoch monotonicity**: NAV epoch must strictly increase

### 10.6 Burn-Before-Acceptance Risk

The bridge uses a **burn-first** model: shares are burned on the source chain *before* the destination mint is attempted. The destination mint can fail for reasons beyond relayer outage:

| Failure Mode | Cause | Burned shares recoverable? |
|---|---|---|
| Relayer offline | Operational failure | No (without admin intervention) |
| Destination paused | `bridgePaused = true` | No (until unpause + replay) |
| Mint cap exhausted | `bridgedSharesSupply + shares > maxOutstandingShares` | No (until cap increased + replay) |
| Liquidity coverage | Post-mint coverage below floor | No (until coverage restored + replay) |
| Destination state inconsistent | NAV epoch mismatch, contract upgrade | No (requires governance) |

**This is a trusted custodial bridge.** The relayer is a centralized, trusted component. Users must trust that the operator will detect and replay failed mints. The bridge should be labeled accordingly in all user-facing documentation.

**Operational requirements**:
- The relayer MUST perform **preflight checks** before allowing `bridgeOut()`: verify destination is unpaused, mint cap has headroom, and liquidity coverage is sufficient
- The relayer SHOULD expose a `canBridge(dstChain, shares) → bool` view that agents query before initiating a bridge-out
- The operator MUST monitor `BridgeOut` events and confirm corresponding `BridgeIn` events. Unmatched burns must be alerted and replayed.

**Mitigations**:
- **Mint cap limits exposure**: `maxOutstandingShares` bounds total liability per chain
- **Operational redundancy**: Multiple relayer instances with shared key management (AWS KMS with multi-region failover)
- **Admin recovery**: Admin can assign a new `BRIDGE_ROLE` holder and replay missed events from source chain logs

**V3 path**: Replace the trusted relayer with a proof-based user claim path (`claimBridgedShares(proof)`) or integrate with a decentralized message-passing layer (see [Appendix D.3](#d3-bridge-decentralized-message-passing)).

---

## 11. Circuit Breaker

### 11.1 Purpose

`SSDCV2CircuitBreaker` provides global emergency shutdown. When tripped, it atomically pauses all subsystems. When reset, it only unpauses components that the breaker itself paused — preserving any pre-existing manual pauses.

### 11.2 Trip

```
FUNCTION tripBreaker():   [BREAKER_ROLE]
  REQUIRE !breakerTripped

  // Snapshot current pause states BEFORE pausing
  snapshot = {
    navWasPaused: navController.navUpdatesPaused(),
    vaultWasPaused: vault.mintRedeemPaused(),
    queueWasPaused: claimQueue.queueOpsPaused(),
    escrowWasPaused: escrow.escrowOpsPaused(),
    paymasterWasPaused: paymaster.paymasterPaused(),
    bridgeWasPaused: bridge.bridgePaused()
  }

  // Pause everything
  navController.setNavUpdatesPaused(true)
  vault.setMintRedeemPaused(true)
  claimQueue.setQueueOpsPaused(true)
  escrow.setEscrowOpsPaused(true)
  paymaster.setPaymasterPaused(true)
  bridge.setBridgePaused(true)

  breakerTripped = true
```

### 11.3 Reset

```
FUNCTION resetBreaker():   [DEFAULT_ADMIN_ROLE]
  REQUIRE breakerTripped

  // Only unpause what the breaker paused
  IF !snapshot.navWasPaused:       navController.setNavUpdatesPaused(false)
  IF !snapshot.vaultWasPaused:     vault.setMintRedeemPaused(false)
  IF !snapshot.queueWasPaused:     claimQueue.setQueueOpsPaused(false)
  IF !snapshot.escrowWasPaused:    escrow.setEscrowOpsPaused(false)
  IF !snapshot.paymasterWasPaused: paymaster.setPaymasterPaused(false)
  IF !snapshot.bridgeWasPaused:    bridge.setBridgePaused(false)

  breakerTripped = false
```

The snapshot-and-restore pattern ensures clean recovery. If the NAV oracle was manually paused before the breaker tripped (e.g., during scheduled maintenance), resetting the breaker will not inadvertently unpause it.

### 11.4 Pause Hierarchy

```
Circuit Breaker (global)
  ├── NAV Controller (navUpdatesPaused)
  ├── Vault (mintRedeemPaused)
  ├── Claim Queue (queueOpsPaused)
  ├── Escrow (escrowOpsPaused)
  ├── Paymaster (paymasterPaused)
  └── Bridge (bridgePaused)
```

Each subsystem can be paused independently by its PAUSER_ROLE holder. The circuit breaker pauses all at once. Both mechanisms coexist: manual pauses are preserved through breaker cycles.

---

## 12. Threat Model & Security Analysis

### 12.1 Trusted Components & Blast Radius

| Component | Trust Level | Blast Radius if Compromised | Mitigation |
|-----------|-------------|----------------------------|------------|
| **NAV Oracle** | Semi-trusted | Can inflate/deflate share prices within `maxNavJumpBps` per update. Over multiple updates, could gradually drain vault by inflating NAV above true portfolio value. | `maxNavJumpBps` bounds per-update change (e.g., 100 bps = 1%). `maxRateAbsRay` bounds continuous drift. Rate smoothing prevents instant manipulation. Multi-epoch attack is visible on-chain. |
| **Bridge Relayer** | Trusted (highest risk) | Can mint shares up to `maxOutstandingShares` on any chain. If `maxOutstandingShares = 10M shares`, attacker mints 10M shares and redeems for USDC. | Mint cap limits total exposure. Consider timelocked large mints. Operational: HSM key storage, multi-region redundancy. |
| **Arbiter** | Trusted | Can resolve any disputed escrow as RELEASE or REFUND. Can bypass fulfillment requirements. Can force-release any escrow after `releaseAfter`. A rogue arbiter could collude with merchants to release without delivery, or with buyers to refund after receiving goods. | No on-chain timelock or multisig in V2. Operational: use a multisig or governance contract as the ARBITER_ROLE holder. In a future version, consider per-escrow arbiter assignment and mandatory dispute escalation for high-value escrows. |
| **Reserve Manager** | Trusted (off-chain) | Controls the off-chain Treasury portfolio. Could misappropriate reserve assets, report false NAV. | Regular third-party attestation. NAV oracle should be independent from reserve manager. Proof-of-reserves via Merkle proofs or on-chain attestation registry. |
| **Admin** | Trusted (timelocked) | Can pause systems, change policies, set bridge peers, configure parameters. Cannot directly steal funds. | Use a timelock contract or multisig as admin. All admin actions emit events for off-chain monitoring. |
| **ETH/USD Oracle** | Semi-trusted | Stale price could cause paymaster to over/under-charge gas. | `maxPriceStaleness` bounds staleness (default 60 min). `Rounding.Ceil` ensures protocol never undercharges. |
| **Entry Point (4337)** | Trusted | Same-block execution model. If entry point misbehaves, charges could be incorrect. | Standard ERC-4337 EntryPoint (audited). `preparedAtBlock` check prevents cross-block manipulation. |

### 12.2 System Invariants

The system maintains these invariants across all operations:

**I1. Share Conservation** (Escrow): For every escrow release:
```
principalShares + merchantYield + buyerYield + reserveShares + feeShares = sharesHeld
```
No shares are created or destroyed during settlement. For every refund: all `sharesHeld` are returned to `refundRecipient`.

**I2. Collateral Floor**: No operation that reduces an agent's collateral below `minAssetsFloor + committedAssets` will succeed. Enforced at:
- `fundEscrow()`: Checks floor before locking shares
- `validatePaymasterUserOp()`: Checks floor after projected gas charge
- `postOp()`: Re-checks floor after actual gas charge

**I3. NAV Monotonic Epoch**: `navEpoch` strictly increases across updates and relays. Prevents replaying old NAV values.

**I4. Queue Solvency**: `reservedAssets <= settlementAsset.balanceOf(queue)`. Every claimable redemption is backed by actual settlement assets in the queue contract.

**I5. Bridge Mint Cap**: `vault.bridgedSharesSupply() <= bridge.maxOutstandingShares`. Cross-chain liabilities are bounded.

**I6. Head Monotonicity**: The claim queue head pointer never decreases, ensuring FIFO ordering.

**I7. Committed Asset Tracking**: `committedAssets` is incremented on escrow fund and decremented on release/refund. It never goes negative (guarded by `POLICY_COMMITMENT` revert).

### 12.3 Attack Vectors & Mitigations

| Attack Vector | Severity | Likelihood | Mitigation |
|---------------|----------|------------|------------|
| **NAV oracle manipulation** | High | Low (requires oracle key) | `maxNavJumpBps` bounds per-update change. Rate smoothing eliminates instant front-running. Multi-update attack is detectable. |
| **Rounding exploitation** | Low | Medium | Strict rounding convention: vault always wins. Down for deposits, up for withdrawals. |
| **Bridge double-spend** | Critical | Low (requires relayer key) | Per-message replay protection via `processed[msgId]`. Mint cap bounds total exposure. |
| **Agent overspend** | Medium | Medium | Per-tx limit, daily limit, session expiry, merchant allowlist. All checked atomically. |
| **Collateral extraction** | High | Low | Grounding registry checks before every spend. Floor = configured + committed. |
| **Oracle staleness (ETH/USD)** | Medium | Medium | `maxPriceStaleness` auto-rejects stale prices. `Rounding.Ceil` on conversions. No explicit markup buffer in V2. |
| **Claim queue manipulation** | Low | Low | FIFO ordering enforced. Admin-only skip mode. Cancel-and-requeue for blocked claims. |
| **Emergency exploit** | High | Low | Circuit breaker atomically pauses all subsystems. Snapshot-and-restore prevents unpause of pre-paused components. |
| **Arbiter collusion** | High | Low (operational) | No on-chain safeguard in V2. Mitigated by using multisig as arbiter. Future: per-escrow arbiter, escalation paths. |
| **Bridge relayer liveness failure** | Medium | Medium | No on-chain recovery. Mitigated by operational redundancy. Future: self-serve claims with Merkle proofs. |
| **Daily window boundary burst** | Low | High (by design) | Agent can spend 2x daily limit at window boundary. Accepted behavior — per-tx limit provides hard cap. |
| **Negative NAV during escrow** | Medium | Low | Merchant absorbs haircut. `grossYield = 0`, no underflow. Explicitly documented behavior. |

### 12.4 Residual Risks

The following risks are **accepted in V2** and documented for operational awareness:

1. **Reserve custody risk**: Off-chain Treasury assets are not verifiable on-chain in real-time. The NAV oracle is an attestation, not a proof. Proof-of-reserves attestation should be published regularly.

2. **Single arbiter power**: A single ARBITER_ROLE holder can decide any dispute outcome. V2 adds `arbiterDeadline` timeout, but no escalation or appeals. Use a multisig in production.

3. **Bridge burn-before-acceptance**: Shares are burned on the source chain before the destination mint is confirmed. Failed mints (pause, cap, coverage) require operator intervention. This is a trusted custodial bridge (see [Section 10.6](#106-burn-before-acceptance-risk)).

4. **Non-upgradeability**: Bug fixes require full redeployment and state migration. This is a tradeoff for immutability and auditability.

5. **Reserve shares are not automatically subordinated**: The `reserveShares` split from escrow yield creates protocol-owned shares, but these shares have the same pro-rata loss exposure as all other shares. They function as a first-loss buffer only if the operator defines and enforces an explicit recapitalization policy (e.g., burning reserve shares first on NAV decline). Without such a policy, reserve shares are simply protocol-owned equity, not a subordinated tranche.

6. **Breaker snapshot limitations**: The circuit breaker's snapshot-and-restore model preserves only the pre-trip pause state. If governance decides during an active incident that a specific subsystem should remain paused after reset, the snapshot cannot express this. The workaround is: after `resetBreaker()`, immediately call `setPaused(true)` on the subsystem that should stay paused. This is a two-transaction operation, not atomic.

7. **EOA policy bypass**: ERC-20 `transfer()` on the vault bypasses the policy module entirely. The safety model depends on agents using compliant smart account wallets with policy-enforcing validators (see [Section 4.8](#48-agent-account-model)). EOAs can hold shares but receive no policy protection.

---

## 13. Mathematical Reference

### 13.1 Constants

```
RAY = 1e27                    // Fixed-point precision
BPS = 10000                   // Basis point denominator
MAX_PROVIDERS = 16            // Maximum collateral providers
```

### 13.2 Core Formulas

**NAV Projection**:
```
NAV(t) = nav0Ray + ratePerSecondRay × min(t - t0, maxStaleness)
```

**Share/Asset Conversion**:
```
assets = floor(shares × NAV / RAY)           (convertToAssetsDown)
shares = ceil(assets × RAY / NAV)            (convertToSharesUp)
shares = floor(assets × RAY / NAV)           (convertToSharesDown)
```

**NAV Update** (snap-to-current model):
```
nav0Ray = attestedCurrentNAV
t0 = now
ratePerSecondRay = clamp(forwardRateRay, -maxRateAbsRay, +maxRateAbsRay)
```

**Yield Split** (on escrow release):
```
principalShares = min(ceil(P × RAY / NAV), S)
grossYield      = S - principalShares
reserve         = floor(grossYield × reserveBps / BPS)
fee             = floor((grossYield - reserve) × feeBps / BPS)
buyerYield      = floor((grossYield - reserve - fee) × buyerBps / BPS)
merchYield      = grossYield - reserve - fee - buyerYield
```

**Refund** (on escrow refund):
```
refundRecipient receives: S (all shares, no split)
```

**Gas Cost Conversion** (Paymaster):
```
assetsCost = ceil(gasCostWei × ethUsdPrice / 1e30)
chargeShares = ceil(assetsCost × RAY / NAV)
```

**Grounding Check**:
```
totalCollateral = vault.balanceOf(agent) + Σ_i provider_i.collateralSharesOf(agent)
totalAssets = floor(totalCollateral × NAV / RAY)
effectiveFloor = configuredFloor + committedAssets
grounded = totalAssets < effectiveFloor
```

**Liquidity Coverage** (Bridge/Vault):
```
coverage = min(availableSettlement × BPS / liabilityAssets, BPS)
REQUIRE coverage >= minBridgeLiquidityCoverageBps
```

**Daily Spend** (Policy):
```
IF now >= dayStart + 86400:
  spentToday = 0, dayStart = now
REQUIRE spentToday + spend <= dailyLimit
REQUIRE spend <= perTxLimit
spentToday += spend
```

---

## Appendix A: Agent Commerce Protocol

### A.1 Overview

The SSDC V2 system is designed for autonomous AI agents to hold value, transact, and earn yield without human intervention. The contract stack provides the on-chain primitives; the Agent Commerce Protocol defines how agents interact with each other.

### A.2 Agent Lifecycle

```
1. PROVISIONING
   Admin sets policy: setPolicy(agent, perTxLimit, dailyLimit, floor, expiry, allowlist)
   Admin whitelists merchants: setMerchantAllowed(agent, merchant, true)

2. FUNDING
   Agent deposits settlement assets → gateway.deposit() → receives shares
   Agent tops up gas tank → gateway.depositToGasTank() → gasless execution

3. OPERATION
   Agent transacts within policy bounds:
   - Direct transfers: vault.transfer(to, shares)
   - Escrowed payments: gateway.depositToEscrow(merchant, terms, buyerBps)
   - Gas-sponsored UserOps: paymaster validates + charges from gas tank

4. MONITORING
   Grounding registry tracks collateral sufficiency
   Policy module enforces spend limits
   isGroundedNow() checked inline during operations

5. REDEMPTION
   Agent exits: claimQueue.requestRedeem(shares) → processQueue() → claim()
```

### A.3 Agent-to-Agent Payment Protocol

Two AI agents transact using a four-step protocol:

**Step 1**: Service provider agent creates a `PaymentRequest` (off-chain JSON):

```json
{
  "requestId": "pr_a1b2c3d4_lq8f2k_x7y9z1",
  "payee": "0xServiceProviderAgent",
  "amount": "50000000000000000000",
  "description": "Translate 5000 words EN→ES",
  "terms": { "assetsDue": "50e18", "expiry": 1741708800, ... },
  "buyerBps": 1000,
  "expiresAt": 1741712400
}
```

**Step 2**: Buyer agent validates (system status, balance, allowlist) and accepts → `fundEscrow()`

**Step 3**: Provider agent performs work, submits fulfillment → `submitFulfillment()`

**Step 4**: Buyer agent verifies output, releases escrow → `release()`. Yield splits per terms.

**Dispute path**: Buyer calls `dispute()` → arbiter resolves → `refund()` or `release()` per resolution.

### A.4 Agent Swarm Pattern

An orchestrator agent manages a fleet of workers:

- Orchestrator holds primary collateral and sets policies per worker
- Workers operate autonomously within per-tx and daily limits
- Workers cannot transact with non-whitelisted merchants
- Orchestrator monitors grounding status and tops up workers running low
- Gas sponsored from orchestrator's paymaster deposits

### A.5 MCP Tool Interface

The Agent SDK exposes tools compatible with the Model Context Protocol:

| Tool | Input | Output |
|------|-------|--------|
| `ssdc_get_balance` | (none) | `{ shares, asset_value, available_spend, is_grounded }` |
| `ssdc_check_system` | (none) | `{ nav_fresh, deposits_available, escrow_available }` |
| `ssdc_deposit` | `{ amount: string }` | `{ tx_hash, shares_received }` |
| `ssdc_pay` | `{ to: address, amount: string }` | `{ tx_hash, shares_sent }` |
| `ssdc_create_invoice` | `{ merchant, amount, description, fulfillment_type?, milestones? }` | `{ escrow_id, tx_hash }` |
| `ssdc_release_escrow` | `{ escrow_id: string }` | `{ tx_hash, status }` |
| `ssdc_submit_fulfillment` | `{ escrow_id, evidence: string }` | `{ tx_hash, milestones_submitted }` |
| `ssdc_dispute_escrow` | `{ escrow_id, reason: enum, details: string }` | `{ tx_hash, status }` |
| `ssdc_get_escrow` | `{ escrow_id: string }` | `{ buyer, merchant, status, shares_held }` |
| `ssdc_redeem` | `{ amount: string }` | `{ claim_id, tx_hash }` |

All tools return structured JSON. Errors follow the SDK error code system (see [Appendix C](#appendix-c-error-code-reference)).

---

## Appendix B: Deployment & Upgrade Strategy

### B.1 Deployment Order

```
1.  NAVControllerV2(admin, initialNAVRay, minNavRay, maxRateAbsRay,
                    maxStaleness, maxNavJumpBps, staleRecoveryJumpMultiplier)
2.  wSSDCVaultV2(settlementAsset, navController, admin)
3.  SSDCPolicyModuleV2(admin)
4.  GroundingRegistryV2(policyModule, navController, vault, admin)
5.  SSDCClaimQueueV2(vault, settlementAsset, admin)
6.  YieldEscrowV2(vault, navController, policyModule, groundingRegistry,
                  admin, feeRecipient)
7.  YieldPaymasterV2(vault, navController, policyModule, groundingRegistry,
                     ethUsdOracle, entryPoint, admin, feeCollector)
8.  SSDCVaultGatewayV2(vault, admin)
9.  WSSDCCrossChainBridgeV2(vault, navController, admin)
10. SSDCStatusLensV2(navController, vault, claimQueue, bridge, escrow, paymaster)
11. SSDCV2CircuitBreaker(navController, vault, claimQueue, bridge,
                          escrow, paymaster, admin)
```

### B.2 Role Grants

```
vault.grantRole(GATEWAY_ROLE, gateway)
vault.grantRole(BRIDGE_ROLE, bridge)
vault.grantRole(QUEUE_ROLE, claimQueue)
vault.grantRole(RESERVE_ROLE, reserveManager)      // Off-chain reserve deploy/recall
navController.grantRole(BRIDGE_ROLE, bridge)
policyModule.grantRole(POLICY_CONSUMER_ROLE, escrow)
policyModule.grantRole(POLICY_CONSUMER_ROLE, paymaster)
groundingRegistry.setCollateralProvider(paymaster, true)
circuitBreaker.grantRole(BREAKER_ROLE, admin)
escrow.grantRole(ARBITER_ROLE, arbiterMultisig)    // Use multisig!
```

### B.3 Upgrade / Migration Path (V2 → V3)

Since V2 contracts are non-upgradeable, protocol upgrades require a coordinated migration. The following is an operational runbook, not just a vault migration note.

**Phase 1: Preparation**
1. Deploy V3 contracts alongside V2 (both live simultaneously)
2. Configure V3 policies, grounding, gateway, bridge peers
3. Announce migration window to all agents and integrators

**Phase 2: Freeze**
4. **Pause V2** via circuit breaker (atomic halt of all subsystems)
5. **Process remaining V2 claim queue** — call `processQueue()` until queue is drained
6. **Wait for all pending bridge messages** — confirm all `BridgeOut` events have matching `BridgeIn` events

**Phase 3: State Migration**
7. **Live escrows**: Cannot be migrated atomically. Must wait for all FUNDED escrows to reach terminal state (RELEASED or REFUNDED). The migration window must account for escrows with long `releaseAfter` or active disputes. Consider: an admin-callable `forceRefund()` for escrows past a migration deadline.
8. **Gas tanks**: Agents withdraw gas tank shares via `withdrawGasTank()`. Re-deposit into V3 paymaster.
9. **Pending claims**: All pending claims must be processed or cancelled before migration. The admin should `refill()` the queue buffer to ensure full processing.
10. **Bridge state**: Admin redirects bridge trusted peers to V3 contracts. Outstanding bridged shares on remote chains must be accounted for.
11. **Policy state**: Agent policies do not auto-migrate. The orchestrator/admin must re-register policies on V3.

**Phase 4: Vault Migration**
12. **Users redeem** shares from V2 (instant or via claim queue)
13. **Users deposit** settlement assets into V3 vault
14. **Or**: V3 gateway provides `migrateFromV2(v2Vault, shares)` — atomically redeems V2 shares and deposits resulting assets into V3

**Phase 5: Decommission**
15. Verify V2 `totalSupply() == 0`
16. Revoke all V2 admin roles
17. V2 contracts remain on-chain (immutable) but are inert

---

## Appendix C: Error Code Reference

| Contract | Error | Condition |
|----------|-------|-----------|
| NAVControllerV2 | `NAV_STALE` | `dt >= maxStaleness` |
| NAVControllerV2 | `NAV_BELOW_MIN` | `projectedNAV < minNavRay` |
| NAVControllerV2 | `NAV_JUMP` | `jumpBps > maxNavJumpBps` |
| NAVControllerV2 | `EPOCH` | `newEpoch <= navEpoch` |
| NAVControllerV2 | `RATE_OUT_OF_BOUNDS` | abs(rate) > maxRateAbsRay |
| NAVControllerV2 | `NAV_T0_IN_FUTURE` | `t0_ > block.timestamp` |
| NAVControllerV2 | `UPDATES_PAUSED` | `navUpdatesPaused == true` |
| wSSDCVaultV2 | `MINT_REDEEM_PAUSED` | System paused |
| wSSDCVaultV2 | `GATEWAY_ONLY` | Direct access when gateway required |
| wSSDCVaultV2 | `LIQUIDITY_COVERAGE` | Bridge mint violates coverage floor |
| YieldEscrowV2 | `INVOICE_EXPIRED` | `now > terms.expiry` |
| YieldEscrowV2 | `RELEASE_LOCKED` | `now < releaseAfter` |
| YieldEscrowV2 | `FLOOR` | Agent below collateral floor |
| YieldEscrowV2 | `SHARES_SLIPPAGE` | `sharesIn > maxSharesIn` |
| YieldEscrowV2 | `FULFILLMENT_PENDING` | Fulfillment required but not submitted |
| YieldEscrowV2 | `FULFILLMENT_SUBMITTED` | Cannot refund after fulfillment complete |
| YieldEscrowV2 | `DISPUTED` | Already under dispute |
| YieldEscrowV2 | `DISPUTE_PENDING` | Dispute window not yet expired |
| YieldEscrowV2 | `RESOLUTION_MISMATCH` | Action conflicts with arbiter decision |
| YieldEscrowV2 | `ESCROW_COMPLETE` | Escrow already settled |
| YieldEscrowV2 | `INVALID_FULFILLMENT_TYPE` | Type mismatch or NONE with requirement |
| YieldEscrowV2 | `INVALID_MILESTONE_COUNT` | Milestones required but set to 0 |
| YieldEscrowV2 | `INVALID_TIMEOUT_RESOLUTION` | Dispute window > 0 but resolution = NONE |
| SSDCClaimQueueV2 | `NOT_CLAIMABLE` | Claim not yet processed |
| SSDCClaimQueueV2 | `NOT_PENDING` | Claim not in PENDING state |
| SSDCClaimQueueV2 | `BELOW_MIN_CLAIM` | Shares below minimum claim size |
| SSDCClaimQueueV2 | `ClaimSkipped` (event) | Claim skipped due to insufficient buffer |
| SSDCPolicyModuleV2 | `POLICY_NOT_SET` | No policy exists for agent |
| SSDCPolicyModuleV2 | `POLICY_LIMIT` | Exceeds per-tx limit |
| SSDCPolicyModuleV2 | `POLICY_DAILY_LIMIT` | Exceeds daily budget |
| SSDCPolicyModuleV2 | `POLICY_ALLOWLIST` | Merchant not whitelisted |
| SSDCPolicyModuleV2 | `POLICY_SESSION_EXPIRED` | Session timed out |
| SSDCPolicyModuleV2 | `POLICY_COMMITMENT` | Release > committed |
| YieldPaymasterV2 | `GROUNDED` | Agent below collateral floor |
| YieldPaymasterV2 | `INSUFFICIENT_SHARES` | Gas tank insufficient |
| YieldPaymasterV2 | `PRICE_STALE` | ETH/USD oracle too old |
| YieldPaymasterV2 | `PRICE_ZERO` | Oracle returned zero |
| YieldPaymasterV2 | `VALIDATION_EXPIRED` | Cross-block charge attempt |
| YieldPaymasterV2 | `GAS_BUDGET` | Actual cost exceeds estimate |
| WSSDCCrossChainBridgeV2 | `REPLAY` | Message already processed |
| WSSDCCrossChainBridgeV2 | `UNTRUSTED_PEER` | Unknown source chain |
| WSSDCCrossChainBridgeV2 | `MINT_LIMIT` | Outstanding shares at capacity |
| WSSDCCrossChainBridgeV2 | `BRIDGE_PAUSED` | Bridge operations halted |
| SSDCV2CircuitBreaker | `BREAKER_ALREADY_TRIPPED` | Double-trip attempt |
| SSDCV2CircuitBreaker | `BREAKER_NOT_TRIPPED` | Reset without active trip |

---

## Appendix D: V3 Roadmap

The following improvements are identified during V2 design and review but deferred to a future protocol version. They are consolidated here from inline notes throughout the paper.

### D.1 Grounding: Keeper Bounty for `poke()`

Currently `poke()` is permissionless but unpaid. V3 should introduce a **keeper bounty** — a small share reward paid from the grounded agent's collateral to the `poke()` caller — to incentivize decentralized enforcement. This removes the reliance on agents, counterparties, and orchestrators to voluntarily call `poke()`. (See [Section 8.4](#84-poke))

### D.2 Paymaster: `gasMarkupBps` Parameter

V2 hardcodes gas markup to 0, relying solely on `Rounding.Ceil`. V3 should add a configurable `gasMarkupBps` parameter (e.g., 500 = 5% buffer) to the charge formula, providing explicit protection against oracle latency and L2 base-fee volatility. Markup accrues to the paymaster as protocol revenue. (See [Section 9.3](#93-eth-to-settlement-asset-conversion))

### D.3 Bridge: Decentralized Message Passing

Replace the standalone trusted relayer with integration into a decentralized message-passing layer (Optimism's canonical bridge, LayerZero, or Hyperlane). Alternatively, add a `claimBridgedShares(proof)` function enabling users to self-serve by submitting Merkle proofs of `BridgeOut` events from the source chain. (See [Section 10.6](#106-liveness-and-availability))

### D.4 Bridge: Global Per-Destination Nonce

V2 uses per-message replay protection via `processed[msgId]`. V3 should adopt a **global per-destination nonce** (`outboundNonce[destChainId]++`), which provides ordering guarantees in addition to replay protection and simplifies relayer implementation.

### D.5 ~~Arbiter: `resolveTimeout()` for Liveness Failure~~ (Resolved in V2.3)

**Addressed in V2.3**: The `arbiterDeadline` field and `executeTimeout()` function were added to the escrow spec in [Section 5.10](#510-dispute-resolution). The arbiter timeout uses the same `disputeTimeoutResolution` as buyer/merchant timeout.

### D.6 Reserve Attestation Registry

Introduce a `ReserveAttestationRegistry` contract that records off-chain reserve attestations (portfolio composition, T-bill CUSIPs, mark-to-market values) on-chain. This creates an auditable on-chain trail of reserve composition, strengthening the trust model beyond the NAV oracle's single price attestation. The attestation hash should be a **required parameter** in `updateNAV()`, linking each NAV update to a specific reserve snapshot. This creates a causal chain — every on-chain NAV is provably tied to a specific portfolio state — which is far more auditable than two independent data streams.

### D.7 Escrow: Per-Escrow Arbiter Assignment

Allow each escrow to specify a different arbiter address in the `InvoiceTerms`, enabling marketplace-style dispute resolution with specialized arbiters for different commerce categories. Combined with mandatory escalation paths for high-value escrows.

### D.8 Claim Queue: `maxSharesIn` Sentinel

Introduce a sentinel value (e.g., `0`) for `maxSharesIn` that signals "use protocol-recommended slippage tolerance" rather than requiring callers to compute their own bounds. The recommended tolerance would be derived from `|ratePerSecondRay| * estimatedFundingDelay`.

### D.9 Implementation Considerations

- **EIP-170 contract size**: V2 contracts should be monitored for proximity to the 24,576-byte limit. `YieldEscrowV2` and `wSSDCVaultV2` are the largest contracts. If size becomes an issue, consider splitting read-only view functions into satellite contracts or using the library pattern for shared logic.
- **ERC-7562 bundler whitelist**: The Paymaster's `validatePaymasterUserOp` reads five external contracts, violating standard ERC-7562 storage rules. Set Chain's bundler must whitelist `NAVControllerV2`, `wSSDCVaultV2`, `SSDCPolicyModuleV2`, `GroundingRegistryV2`, and the ETH/USD oracle for validation-phase access. This is documented in [Section 9.4](#94-userop-validation-erc-4337).

---

*Set Chain SSDC V2 — Building the financial infrastructure for autonomous commerce.*
