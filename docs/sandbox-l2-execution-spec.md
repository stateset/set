# SET L2 Sandbox Execution Network Specification (v0.1)

## 1. Problem Statement

Today, `stateset-sandbox` runs untrusted code in Kubernetes pods (warm pools + runtime classes like gVisor/Firecracker/Kata).

Question: can we move from centralized K8s warm pods to a globally operated SET L2 network where agents execute untrusted code "on SET chain"?

## 2. Short Answer

Yes, with an important constraint:

- We cannot run full Linux containers directly inside the OP Stack EVM execution layer.
- We can run sandbox workloads off-chain on a decentralized worker network and settle coordination, payments, attestations, and disputes on SET L2.

This is the practical path to "execution on SET".

## 3. Design Goals

1. Preserve current agent UX (`create`, `execute`, `files`, `stop`, sessions).
2. Decentralize execution supply (independent operators globally).
3. Keep strong isolation for untrusted code (gVisor/microVM/Kata/Wasm).
4. Add crypto-economic guarantees (stake, slashing, disputes, receipts).
5. Keep latency close to warm-pod UX (sub-second control plane where possible).

## 4. Non-Goals

1. Running arbitrary containers directly in EVM bytecode.
2. Putting stdout/stderr/artifacts fully on-chain.
3. Eliminating off-chain infrastructure (workers, storage, networking).

## 5. Feasibility Boundaries

## 5.1 What is not feasible now

1. "Container runtime inside OP Stack block execution" for general workloads.
2. Deterministic replay of arbitrary networked jobs without additional constraints.
3. Interactive command-by-command UX if every operation requires L2 inclusion first.

## 5.2 What is feasible now

1. Off-chain execution with on-chain commitments.
2. Staked operator network with receipts and slashing.
3. Hybrid verification:
   - deterministic profiles: reproducible replay and/or zk proofs;
   - non-deterministic profiles: TEE attestations + quorum re-execution + optimistic dispute windows.

## 6. Reference Architecture

## 6.1 Components

### Existing (reuse)

1. SET L2 (OP Stack chain).
2. `SetPaymaster` for gas abstraction.
3. `SetRegistry` style anchoring pattern for commitments.
4. Existing `stateset-sandbox` API/SDK shape.

### New on-chain contracts

1. `ExecutorRegistry`
   - Operator registration and stake.
   - Capability advertisement (regions, runtimes, cpu/memory classes, GPU).
   - Liveness heartbeats and reputation pointers.

2. `JobManager`
   - Job intent posting (`jobSpecHash`, budget, SLA, verification profile).
   - Escrow in `ssUSD`/ETH.
   - Assignment finalization and payout triggers.

3. `ExecutionReceiptRegistry`
   - Records `resultHash`, `logsHash`, `artifactRoot`, `usageDigest`, `teeQuoteHash`.
   - Stores status transitions (`assigned`, `running`, `completed`, `challenged`, `finalized`).

4. `DisputeManager`
   - Challenge window and bonds.
   - Slashing and reward distribution.
   - Optional linkage to fault/dispute game patterns.

5. `MarketPolicy`
   - Min stake, max parallel jobs per stake unit, region rules, allow/deny policies.

### New off-chain services

1. `Execution Gateway`
   - Keeps current API compatibility.
   - Converts API calls to signed job intents.
   - Uses fast path assignment and async on-chain settlement.

2. `Scheduler Network`
   - Matches jobs to executors based on capability, price, locality, reputation.
   - Can be permissioned initially, open later.

3. `Worker Nodes` (operator-run)
   - Run runtime stack (`gVisor`, `Firecracker`, `Kata`, `Wasm`).
   - Maintain local warm pools for low startup latency.
   - Emit signed execution receipts.

4. `Verifier Nodes`
   - Re-run deterministic jobs.
   - Validate TEE quotes / policy compliance.
   - Submit challenges on mismatch.

5. `Artifact DA Layer`
   - Object store/IPFS/Blob-backed retention for outputs.
   - On-chain only keeps content-addressed digests.

## 6.2 Control and Data Flow

1. Client calls `POST /sandbox/create` or `POST /sandbox/:id/execute`.
2. Gateway creates canonical `JobSpec` and signs intent.
3. Scheduler assigns to an executor with compatible profile.
4. Executor runs workload in isolated runtime, streams output to client (fast path).
5. Executor publishes signed `ExecutionReceipt` to gateway and L2.
6. Receipt is challengeable for `T` seconds.
7. If unchallenged, payout releases from escrow.
8. If challenged and challenger wins, executor stake is slashed.

## 7. Job and Receipt Schemas

## 7.1 JobSpec (canonical hash input)

1. `job_id`, `org_id`, `tenant_id`
2. `runtime_profile` (`container|gvisor|microvm|kata|wasm`)
3. `resource_profile` (`cpu`, `memory`, `gpu`, `ephemeral_storage`)
4. `timeout`, `network_policy`, `filesystem_policy`, `secrets_policy`
5. `command`, `argv`, `env_allowlist`, `artifact_inputs`
6. `verification_profile` (`optimistic|quorum|tee|zk|hybrid`)
7. `max_price`, `billing_token`, `sla_class`

`jobSpecHash = keccak256(canonical_encoding(JobSpec))`

## 7.2 ExecutionReceipt

1. `job_id`, `executor_id`, `session_id`
2. `start_ts`, `end_ts`, `exit_code`
3. `stdout_hash`, `stderr_hash`
4. `artifact_root` (Merkle root of produced artifacts)
5. `resource_usage_digest` (cpu, mem, net egress, duration)
6. `attestation`:
   - TEE quote hash and PCR set, or
   - deterministic trace/proof reference
7. `executor_signature`

`receiptHash = keccak256(canonical_encoding(ExecutionReceipt))`

## 8. Verification Profiles

## 8.1 Profile A: Optimistic (default for general workloads)

1. Executor posts receipt.
2. Watchers may challenge during window `T`.
3. Dispute resolved by policy-defined evidence and optional replay.

Pros: fastest, lowest cost.
Cons: trust is economic, not absolute.

## 8.2 Profile B: Quorum Re-execution

1. Same job runs on `N` independent executors.
2. Result accepted if quorum (e.g., 2/3) matches digest.
3. Outliers penalized.

Pros: stronger correctness for non-deterministic jobs.
Cons: higher cost and latency.

## 8.3 Profile C: TEE Attested

1. Job executes in TEE-backed environment.
2. Receipt includes quote bound to job hash and output hash.
3. Verifiers check quote chain and policy constraints.

Pros: strong integrity guarantees.
Cons: hardware trust assumptions and operational complexity.

## 8.4 Profile D: ZK Verifiable (deterministic subset)

1. Restrict runtime to deterministic VM (typically Wasm/zkVM profile).
2. Executor posts proof with output digest.
3. On-chain verifier contract validates.

Pros: strongest cryptographic guarantees.
Cons: narrow workload class, highest proving cost today.

## 9. Latency and UX Model

To preserve current `stateset-sandbox` behavior, use dual-path execution:

1. Fast path (off-chain): assignment, startup, streaming output immediately.
2. Settlement path (on-chain): receipts, payouts, and disputes within seconds to minutes.

Rationale: SET L2 block time (~2s) is too slow to gate every interactive command.

## 10. Economics and Incentives

1. Executors stake to join `ExecutorRegistry`.
2. Jobs escrow budget in `JobManager`.
3. Successful completion releases payout.
4. Failed SLA and invalid receipts slash stake.
5. Challengers earn a portion of slashed stake when correct.
6. Reputation score affects assignment priority and pricing.

## 11. Security Model for Untrusted Code

1. Runtime isolation remains off-chain (`gVisor`, `Firecracker`, `Kata`, `Wasm`).
2. Mandatory policy envelope per job:
   - default-deny egress with explicit allowlist,
   - filesystem sandboxing,
   - secrets scope and TTL,
   - CPU/memory/pid limits.
3. Signed audit trail for every lifecycle event.
4. Emergency controls:
   - disable executor,
   - raise stake requirements,
   - pause verification profile/class,
   - circuit-break assignment market.

## 12. Migration Plan

## Phase 0: Chain-anchored receipts on current K8s

1. Keep existing warm-pod architecture.
2. Add receipt posting to SET L2.
3. Add escrow + payout flows for internal operators.

Exit criteria:
1. >95% job receipts finalized on-chain.
2. Dispute pipeline functional in staging.

## Phase 1: Permissioned multi-operator network

1. Onboard a small set of external operators.
2. Enable staking, slashing, and reputation.
3. Keep scheduler permissioned.

Exit criteria:
1. >=3 independent operators in production.
2. No single operator >50% assigned workload.

## Phase 2: Open execution market

1. Open registration with stake + compliance checks.
2. Add locality-aware and price-aware routing.
3. Enable challenge bots by third parties.

Exit criteria:
1. Decentralization targets met (operator count/geography).
2. Stable p95 startup/exec latency against SLO.

## Phase 3: Verifiable compute tiers

1. Add TEE-backed premium profile.
2. Add deterministic zk profile for selected tasks.
3. Let orgs choose verification profile per job.

## 13. API Compatibility Strategy

Keep current endpoints stable and map internally:

1. `POST /sandbox/create` -> creates a long-lived session + initial job intent.
2. `POST /sandbox/:id/execute` -> submits execution job under same session.
3. `POST /sandbox/:id/stop` -> cancels active jobs and settles remaining escrow.
4. Existing SDKs remain valid while backend shifts from K8s-only to network mode.

## 14. Open Decisions

1. Settlement token default: `ssUSD` vs ETH.
2. Initial dispute window: 30s, 2m, or 10m by SLA class.
3. TEE vendor baseline and attestation verifier implementation.
4. Artifact DA default: managed object storage first, then optional decentralized DA.
5. Governance boundary: protocol-level vs enterprise policy overlays.

## 15. Recommendation

Adopt the execution-network architecture, not literal "container execution inside EVM".

This gives:

1. Global operator network for untrusted code execution.
2. On-chain accountability (settlement, disputes, slashing).
3. Compatibility with your existing sandbox runtime and warm-pool optimizations.
4. A credible path from current K8s operations to decentralized execution.

