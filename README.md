# Set

[![Release](https://img.shields.io/badge/release-v0.4.0-blue)](https://github.com/stateset/set/tree/v0.4.0)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

Set is commerce infrastructure being developed around the OP Stack: Solidity
contracts for payments, escrow and spending policies, a TypeScript agent SDK, and
a Rust service that anchors commerce-event commitments on-chain.

**Status: application development and local testing. Full rollup production
readiness is not yet established. Sepolia deployment is on hold.** A release tag,
passing unit tests or a running execution node does not certify L1 settlement,
withdrawals, fault proofs or recovery.

## Contents

- [Current release](#current-release)
- [Commerce capabilities](#commerce-capabilities)
- [Architecture and trust boundaries](#architecture-and-trust-boundaries)
- [Local quick start](#local-quick-start)
- [Restricted agent payments](#restricted-agent-payments)
- [Testing](#testing)
- [Full rollup readiness](#full-rollup-readiness)
- [Repository guide](#repository-guide)
- [Operations and security](#operations-and-security)
- [Contributing and releases](#contributing-and-releases)

## Current release

**v0.4.0** adds mandatory merchant-signed invoices to the restricted payment account.
The SDK package is `@setchain/sdk@0.4.0`; the Rust anchor package remains `0.2.5`.
These are repository release versions, not a claim of package-registry publication.

- Merchant-scoped session keys with expiry, revocation epochs and asset budgets.
- Atomic session/policy budget consumption and vault-share transfer.
- Account-wide nonces and duplicate-order protection.
- Fresh-NAV valuation, conservative rounding and collateral-floor checks.
- No arbitrary execution or token approvals exposed to session keys.
- EIP-712 invoice binding and ERC-1271 merchant signature verification.

Breaking change: `pay` requires a seventh signature argument. v0.3.12 accounts
cannot use the new API without an explicit migration to a reviewed new deployment.

The account must hold the funds to enforce these controls. Existing
`AgentClient.pay()` remains an advisory preflight followed by a normal transfer;
it does **not** atomically consume the on-chain policy budget. This release does
not deploy contracts or migrate existing balances.

See the [changelog](CHANGELOG.md), [account integration guide](docs/agent-payment-account.md)
and [agent spending security](docs/agent-spending-security.md).

## Commerce capabilities

| Component | Implemented scope | Important boundary |
|-----------|-------------------|--------------------|
| `AgentPaymentAccountV2` | Restricted direct payments from account-held wSSDC shares | Trusted owner; not an ERC-4337 account or an escrow/bridge adapter |
| `SSDCPolicyModuleV2` | Merchant allowlists, spending limits, revocation and commitment accounting | Only trusted policy consumers enforce accounting; ordinary token transfers bypass it |
| `YieldEscrowV2` | Fund, fulfill, release, dispute and refund workflows | Contract state is not proof of external fulfillment |
| `wSSDCVaultV2` and NAV modules | Vault shares, asset conversion and collateral-related checks | NAV, reserves and administrative controls remain trust dependencies |
| `SetRegistry` | Tenant/store-scoped batch commitments and Merkle inclusion verification | Event inclusion is not proof of event truth or rollup settlement |
| `SetPaymaster` | Operator-managed gas sponsorship | Not an ERC-4337 paymaster |
| TypeScript SDK | Contract access, agent workflows and finality observations | Receipt success is distinct from L1 finality |
| Rust anchor service | Submit sequencer commitments to `SetRegistry` | Anchors commerce events; it is not the OP Stack batcher |

## Architecture and trust boundaries

Set has three distinct layers:

1. **Commerce applications:** agents and merchant services use the SDK and
   contracts for payments, escrow and event verification.
2. **Commerce anchoring:** `stateset-sequencer` supplies pending commitments to the
   Rust anchor service, which submits them to `SetRegistry` and reports anchoring
   results back to the sequencer. UUID batch IDs are encoded into `bytes32`.
3. **Rollup infrastructure:** OP Stack execution, derivation, batching, proposals,
   verification and challenges require a compatible deployment and independent
   lifecycle evidence. Commerce-event anchoring does not replace those mechanisms.

STARK submissions in `SetRegistry` store proof metadata and state-root bindings;
proof validity is verified off-chain. The custom forced-inclusion request queue
must not be confused with canonical OP Stack L1 forced inclusion.

Repository configuration includes L2 chain ID `84532001`, a two-second block-time
target and a 30M gas/block setting. These are configuration values, not measured
production throughput or finality guarantees. Sepolia configuration is retained
for future authorized work; it is not the local-development default.

## Local quick start

Use the [pinned toolchain](docs/toolchain.md): Foundry v1.8.1, Rust 1.90.0 and
Node.js 20.20.0 for SDK/release checks. Use Python 3.9+ for local process-safety
tests. Initialize the repository's pinned submodules in a fresh checkout:

```bash
git submodule update --init --recursive

# Start local Anvil and deploy the helper's application contracts.
./scripts/dev.sh start
./scripts/dev.sh deploy
./scripts/dev.sh status

# Run focused security-critical contract suites.
./scripts/dev.sh test-critical
```

Anvil is an application test chain, **not a complete OP Stack rollup**. The helper
does not automatically deploy or configure the new restricted payment account;
follow its [setup instructions](docs/agent-payment-account.md).

The helper prefers usable host Foundry binaries and otherwise supports the
official Docker fallback documented in the toolchain guide. Local Anvil RPC binds
to loopback. Startup will not stop another process or container to claim a port.
Test-account keys are public development keys: never use them on public networks
or for valuable assets.

Reset requires the node to be stopped explicitly and archives scoped artifacts
instead of deleting them. That archive is not a chain-state backup. See the
[local testing guide](docs/local_testing_guide.md) and
[local lifecycle safeguards](docs/l2-readiness-gaps.md).

### Docker and full-stack configurations

- `docker/docker-compose.local.yml` is an isolated **standalone execution client**,
  not a complete rollup.
- `docker/docker-compose.yml` is a legacy multi-service configuration. It is not a
  certified full-devnet quick start; review compatibility, artifacts and exposed
  ports before use.
- `docker/docker-compose.sepolia.yml` targets a public network. **Do not launch it
  while the Sepolia hold remains in effect.**

The legacy `start-devnet.sh` requires separately provisioned local rollup artifacts
and `config/local-rollup.env`. Do not use the Sepolia-oriented genesis/deployment
scripts as implicit local provisioning steps. See [full rollup readiness](#full-rollup-readiness).

## Restricted agent payments

**v0.4.0:** the current source now requires merchant-signed invoices. Its
seven-argument `pay` API and typed-data helper are not compatible with v0.3.12
accounts. No deployed account was upgraded. See the
[migration and signing guide](docs/agent-payment-account.md).

The intended custody boundary is a separately controlled owner and an agent that
has only a merchant-scoped session key. Configure policy for the **account
address**, grant the account its policy-consumer role, and fund it with vault
shares. Keep the owner key outside the agent's control.

The SDK exports `agent.agentPaymentAccountV2Abi` for explicit account interaction:

```ts
import { Contract } from "ethers";
import { agent } from "@setchain/sdk";

// Values come from your reviewed local deployment and order workflow.
const account = new Contract(accountAddress, agent.agentPaymentAccountV2Abi, sessionSigner);
const session = await account.sessions(await sessionSigner.getAddress());
const nonce = await account.nextNonce();
// Obtain merchantSignature from the authenticated merchant checkout service.
const tx = await account.pay(orderId, session.epoch, nonce, assets, maxShares, deadline, merchantSignature);
const receipt = await tx.wait();
if (!receipt || receipt.status !== 1) throw new Error("Payment failed");
// Apply the merchant's explicit finality requirement before fulfillment.
```

Supply bounded slippage and deadlines. A stale nonce or epoch must be reconciled,
not silently refreshed and resubmitted. Order uniqueness is per account, not global
merchant deduplication or user approval of specific goods. The merchant signature
authenticates the invoice's payment terms. Owner recovery is privileged
and preserves collateral requirements; refunds do not automatically replenish
purchase budgets. The session signer needs transaction gas.

The v0.3.11+ SDK requires the updated V2 policy getter and `policyRevoked` API.
Older policy deployments without that method fail status queries rather than
assuming spending is allowed. See [compatibility and setup](docs/agent-spending-security.md)
before adopting these APIs.

## Testing

Local validation for v0.4.0 recorded:

| Check | Result and scope |
|-------|------------------|
| SDK | 539 tests across 40 files passed with one worker; typecheck, lint and build passed |
| Targeted Solidity | 111 tests across eight suites, including 17 account tests and two 256-run account fuzz tests |
| ABI consistency | Exported account functions and events checked against the compiled Solidity ABI |
| Release metadata | Version/tag and dependency-pin checks passed |

The initial parallel SDK run hit the existing RPC-to-ledger test's 20-second
timeout on the shared host; the full single-worker rerun passed without changing
that test or its timeout. The targeted Solidity run used local Foundry and Solc 0.8.24; it was not a full
pinned-toolchain release certification or invariant-suite run. These results are
application-level evidence, not a deployed-rollup or independent-audit report.
Check the [CI runs](https://github.com/stateset/set/actions) for commit-specific
workflow results rather than assuming every tagged release is fully certified.

```bash
# From the repository root: critical contract suites.
./scripts/dev.sh test-critical

# Local lifecycle and readiness regressions (some tests bind loopback listeners).
python3 -m unittest discover -s scripts/tests -v

# Release metadata checks; no deployment.
bash scripts/check-release-readiness.sh
```

SDK checks:

```bash
cd sdk
npm ci
npm run typecheck
npm run lint
npm test
npm run build
```

Full contract and Rust checks, each from the repository root:

```bash
(cd contracts && forge test)
(cd anchor && cargo test --locked)
```

Do not run `forge update` merely to fix a failing test: dependency revisions are
pinned in `contracts/foundry.lock` and Git submodules. Inspect failures and consult
the [toolchain guide](docs/toolchain.md) before changing dependencies.

## Full rollup readiness

**A+ and production readiness remain unproven.** The next acceptance gates require
execution evidence tied to source revisions and the actual deployment:

1. Pin a compatible local L1 and OP Stack with a sequencer, batcher, proposer,
   independent verifier and challenger; reconcile legacy proposer/dispute wiring.
2. Execute deposits, L2 payments, L1 batch submission, independent derivation and
   proven/finalized withdrawals.
3. Resolve valid and invalid output disputes, and demonstrate that invalid claims
   cannot authorize withdrawals.
4. Exercise canonical forced inclusion during sequencer downtime, L1 reorgs,
   batcher/RPC failures, backup restoration and key rotation.
5. Connect durable merchant reconciliation and idempotent fulfillment to explicit
   payment-finality policies; measure latency, costs and recovery against agreed targets.
6. Verify deployed governance, proxy implementations and fault-proof wiring, and
   obtain an independent audit before claiming production assurance.

Public-network exercises require explicit authorization. Local success does not
lift the Sepolia hold. The [readiness evidence](docs/l2-readiness-gaps.md) is the
primary gap list; the [scorecard](docs/scorecard.md) is a rubric with historical,
version-specific assessments—not certification of this release.

## Repository guide

- [contracts/](contracts/): registry, commerce, governance and stablecoin contracts.
- [contracts/stablecoin/v2/](contracts/stablecoin/v2/): policy, vault, escrow,
  paymaster and restricted account implementations.
- [sdk/](sdk/README.md): TypeScript SDK and tests.
- [anchor/](anchor/): Rust anchoring service and reserve attestor.
- [op-stack/](op-stack/): node, batcher, proposer, challenger and deployment configuration.
- [scripts/](scripts/): local tooling, checks, tests and deployment helpers.
- [docker/](docker/): separate execution, legacy rollup and public-network profiles.
- [docs/](docs/): architecture, operational guidance and readiness evidence.

## Operations and security

Use separately controlled administrative roles, reviewed multisig/timelock
configuration, least-privilege policy consumers and protected signing services.
Do not expose unrestricted keys or arbitrary signing to agents. Treat NAV,
reserve management, bridge controls and governance as explicit trust boundaries.

The anchor service exposes `/health`, `/ready`, `/metrics` and `/stats`.
Service readiness does not establish rollup settlement correctness. Monitoring
thresholds are operating targets to validate, not achieved service guarantees.

- [Agent spending security](docs/agent-spending-security.md)
- [Restricted account integration](docs/agent-payment-account.md)
- [Commerce finality](docs/commerce-finality.md)
- [Architecture](docs/architecture.md)
- [Integration example](docs/integration-example.md)
- [Monitoring and SLOs](docs/monitoring.md)
- [Security and governance](docs/security.md)
- [Threat model](docs/threat-model.md)
- [Operations runbook](docs/runbook.md)
- [Node operator guide](docs/node-operators.md)
- [Decentralization roadmap](docs/decentralization.md)
- [Fault-proof operations](docs/fault-proofs.md)
- [Audit status](docs/audit-report.md)
- [Governance evidence](docs/governance-evidence.md)
- [Fault-proof exercise status](docs/fault-proof-exercise.md)

## Contributing and releases

Keep changes scoped, preserve unrelated work and accompany security changes with
adversarial tests. Distinguish implementation, local execution, deployed evidence
and independent verification in documentation.

See the [release process](docs/release-process.md), [changelog](CHANGELOG.md) and
[pinned toolchain](docs/toolchain.md). Version bumps, tags and pushes do not authorize
contract deployment or public-network operations.

## License

MIT — see [LICENSE](LICENSE).
