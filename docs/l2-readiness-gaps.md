# L2 readiness evidence

Updated 2026-09-05. Release certification is application/build evidence, not
certification of the complete rollup. Sepolia deployment remains on hold.

## Implemented hardening

- The legacy `start-devnet.sh` launcher no longer sources Sepolia configuration.
  It requires `config/local-rollup.env`, accepts only numeric loopback execution
  and beacon URLs, and checks the actual L1 chain ID (1337 or 31337) and canonical
  rollup L1 origin before starting nodes. Proxy environment variables and HTTP
  redirects cannot bypass the check. All launched RPC listeners bind to loopback;
  existing PID files require explicit operator review instead of automatic kills.
  This is a safety guard for a legacy launcher, not a working fault-proof devnet.
- Local process startup records executable identity, boot ID, process start time,
  working directory and an argument digest. Stop validates those records and uses
  Linux pidfds for both graceful and forced termination, avoiding bare-PID reuse
  races. Unverified, stale, symlinked or modified records fail closed and are kept
  for operator review. Arguments (which can contain keys) are not stored in plaintext.
- Start and stop share a non-blocking lifecycle lock, acquired before ownership
  records are inspected or changed. Long-running child nodes close the lock file
  descriptor. Startup failure triggers reverse-order stop attempts only for
  components launched by that attempt; unverified records remain for review.
  Status checks validate process identity and return failure for missing required
  nodes or exited processes. They explicitly do not establish RPC readiness.
- Startup now separately probes execution chain identity and genesis, the running
  rollup configuration, and agreement between the reported rollup unsafe head and
  the execution node's canonical block at that height. Each startup probe has a
  30-second deadline and transient failures are retried within that budget. Failure
  triggers identity-checked rollback before batcher/proposer startup. These are
  RPC reachability/consistency checks, not proof of full synchronization, independent
  derivation, block production, batching, withdrawal completion or fault-proof safety.
  The [op-node RPC reference](https://docs.optimism.io/node-operators/reference/op-node-json-rpc)
  documents the `optimism_rollupConfig` and `optimism_syncStatus` methods used here.
- Readiness transport tests run the actual CLI against temporary loopback HTTP
  servers. They cover redirects, proxy bypass, response size/envelope checks,
  ambiguous duplicate JSON fields, non-finite numbers, transient HTTP failures and
  a server that never sends headers. The served chain data is simulated, not live
  OP Stack evidence. Test execution requires permission to bind loopback listeners.
- The SDK provides canonical transaction finality observations with conservative
  agreement across RPC sources, separate execution status and reorg detection.
  A loopback-only diagnostic emits observations without transactions. Its local
  simulated transport tests are not full rollup lifecycle evidence. See
  [commerce finality](commerce-finality.md).
- Settlement checks validate the expected L1 chain ID and fail on transport errors,
  malformed JSON, JSON-RPC errors, null results and invalid bytecode/address encodings.
  These checks prove bytecode presence only, not identity or settlement correctness.
- Shared-network Compose binds public RPCs to loopback, removes debug/engine from
  application RPC APIs and keeps authenticated Engine RPC off host-published ports.
- Generated rollup paths and the execution data directory match Compose mounts.
  Existing installations using the old named volume need a planned data migration;
  no existing volume has been deleted or migrated by this change.
- Genesis generation checks both chain IDs, timestamps, gas limits, origins and
  required addresses before initialization. Missing op-geth fails initialization.
- Production configuration requires governance and fault-proof configuration.
  Address/key encodings and the documented timelock minimum are checked offline.
- Fault-proof walkthroughs return failure because they do not execute a dispute.
- ForcedInclusion documents its request/refund semantics without asserting that
  the request queue enforces canonical rollup transaction inclusion.

## Required for an A+ L2 assessment

Each item needs passing execution evidence tied to the source commit and deployed
configuration. A template or mocked RPC test does not satisfy these requirements.

1. Establish a pinned, compatible OP Stack local deployment with L1, execution,
   rollup node, batcher, proposer, challenger, and a separate verifier. Reconcile
   the legacy L2OutputOracle proposer with the selected dispute-game protocol.
2. Execute a canonical deposit, L2 transaction, L1 batch submission, independent
   derivation, and proven/finalized withdrawal. Record block and transaction hashes.
3. Create and resolve an invalid-output dispute; prove the bad output cannot
   authorize a withdrawal. Run the same checks against a valid output.
4. Stop the sequencer and test canonical L1 forced inclusion; restore an independent
   verifier from L1 data and compare safe/finalized block hashes.
5. Exercise L1 reorgs, batcher restart, RPC failure, backup restoration and key
   rotation. Record recovery time and any data loss against agreed service targets.
6. Verify deployed proxy implementations, Portal/dispute-game wiring, respected
   game type, prestate, multisig threshold, role ownership and timelock delay.
7. Obtain an independent audit covering the selected contract version, oracle and
   bridge trust boundaries, governance, deployment and recovery procedures.
8. Perform public-network exercises only after explicit authorization. No public
   deployment is implied by local test completion.

## Local regression command

```sh
python3 -m unittest discover -s scripts/tests -v
docker compose -f docker/docker-compose.sepolia.yml config --quiet --no-interpolate
```

Neither command connects to Sepolia or starts a node. CI runs these checks in
`L2 Readiness`. They are regression checks for the implemented hardening only.

## Local rollup execution prerequisites

The existing `scripts/dev.sh` starts Anvil for application testing. It is not a
multi-node OP Stack deployment. The legacy `start-devnet.sh` needs separately
generated local genesis/rollup artifacts; `generate-genesis.sh` still belongs to
the Sepolia workflow and must not be used as an implied local provisioning step.
Do not copy Sepolia keys or artifacts into a local configuration.

The legacy start/stop helpers now require Linux and Python 3.9+ with working pidfd
support, plus `flock`. Set `LOCAL_ROLLUP_PYTHON=python3.10` if the system's `python3` is older.
Startup checks this before spawning nodes. Existing PID-only files do not confer
ownership: the new stop helper deliberately refuses to signal them. Inspect the
actual executable, arguments, start time and workspace manually before dealing
with an old process or removing its records. No old process has been stopped or
old record removed by this change. These changes cover the OP Stack launcher, not
the separate Anvil reset script.

For a read-only local RPC check after provisioning matching local artifacts:

```sh
python3.10 scripts/check-local-rpc-ready.py \
  --execution http://127.0.0.1:8547 --rollup-rpc http://127.0.0.1:9545 \
  --config op-stack/sequencer/op-node/rollup.json --timeout 30
```

This Linux CLI accepts only credential-free numeric loopback HTTP endpoints, uses
the transport's no-proxy/no-redirect policy, and submits no transactions. Omit
`--rollup-rpc` for the execution-only startup phase. The process-only `status`
command is still distinct from this RPC check.

The lifecycle lock is advisory and coordinates these start/stop scripts; it does
not protect against manual edits to ownership files or a same-user process that
ignores the lock. Do not delete `lifecycle.lock` to bypass contention: a new file
would create a different lock. On a partial startup failure, review retained
records and logs; an unrecorded or exited component is not blindly signaled or
automatically cleaned up.

Run the full process-safety regressions with Python 3.9+ (for example
`python3.10 -m unittest discover -s scripts/tests -v`). Older interpreters skip
the pidfd-dependent tests; that is not full process-safety validation.

The upstream [Optimism Kurtosis devnet](https://devdocs.optimism.io/kurtosis-devnet/)
provides a route to a real local network. Before adopting it, pin the upstream
package and component revisions, provision sufficient disk/RAM, validate exposure
of every published port, and include a distinct verifier and challenger. Do not
use global Docker pruning or Kurtosis's global cleanup modes on a shared host.

At the latest local inspection, this host had roughly 4 GB free, no Kurtosis CLI,
and no cached OP Stack images. A complete stack was not downloaded or launched.
Full lifecycle evidence remains blocked on suitable local runtime resources and
completion of the pinned deployment integration; an independent audit remains a
separate external requirement for A+ assurance.
