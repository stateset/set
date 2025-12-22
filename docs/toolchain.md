# Toolchain Versions

Pinned tool versions for reproducible builds:

- Rust: 1.78.0 (see `rust-toolchain.toml`)
- Foundry: nightly-2024-05-20 (see `.foundry-version`)
  - Docker: `ghcr.io/foundry-rs/foundry:nightly-2024-05-20`

## Updating Versions
1. Update `rust-toolchain.toml` and `.foundry-version`.
2. Update `.github/workflows/devnet-smoke.yml` to match.
3. Re-run CI to confirm compatibility.
