# Release Process

Set releases are certified builds. Creating an annotated `v*` tag starts the release workflow;
artifacts are published only after the complete contract, invariant, Rust, Anvil, SDK, lint,
coverage, and dependency-audit gates pass.

## Prepare and verify

1. Update the SDK and service versions and their lockfiles.
2. Run `./scripts/check-release-readiness.sh vX.Y.Z` against an annotated local tag.
3. Run the critical smoke suite and the language-specific test suites.
4. Push the branch and annotated tag without force.

The release workflow produces the SDK package, Linux anchor binaries, an SPDX SBOM, SHA-256
checksums, and GitHub build-provenance attestations. GitHub Actions are pinned to immutable commit
SHAs, and runtime secret files are rejected by the readiness check.
Documented dependency exceptions are time-bound in `docs/security-exceptions.md`; the audit gate
still fails on every new RustSec advisory classified as unsound.

## External launch gates

Release certification does not authorize a network deployment. Sepolia or mainnet deployment
requires a separate explicit decision and all of the following evidence:

- an independent audit covering the exact release commit;
- deployed and verified multisig/timelock ownership;
- a recorded public-testnet soak and monitoring exercise;
- a completed fault-proof exercise;
- an approved rollback and incident-response review.

Until those records exist, the system may be described as engineering-release ready, but not as
production-launch certified.

Repository enforcement recommendations are recorded in `docs/repository-settings.md`. Applying
them is a separate maintainer-authorized administrative action.
