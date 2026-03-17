# Toolchain Versions

Pinned tool versions for reproducible builds:

- Rust: 1.85.0 (see `rust-toolchain.toml`)
- Node.js: 20.x for SDK tests and release workflows (see `sdk/package.json`, `.github/workflows/security.yml`)
- Foundry: nightly-2024-05-20 (see `.foundry-version`)
  - Docker fallback defaults to `ghcr.io/foundry-rs/foundry:nightly`
  - Set `FOUNDRY_DOCKER_IMAGE` to pin an exact GHCR tag or digest if you need Docker to match a specific Foundry build

## Updating Versions
1. Update `rust-toolchain.toml`, `.foundry-version`, and any Node engine/workflow pins.
2. Update `.github/workflows/devnet-smoke.yml` and `.github/workflows/security.yml` to match.
3. Re-run CI to confirm compatibility.
