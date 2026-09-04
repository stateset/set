# Security Exceptions

Security exceptions are narrow, time-bound, and fail closed: CI denies every RustSec advisory
classified as unsound except the identifiers listed here.

## Alloy 0.8 / lru 0.12.5

| Field | Value |
|---|---|
| Advisories | `RUSTSEC-2026-0002`, `RUSTSEC-2026-0253` |
| Dependency path | `set-anchor -> alloy-provider 0.8.3 -> lru 0.12.5` |
| Patched line | `lru >=0.16.3` (`pop` issue requires `>=0.18.2`) |
| Owner | Anchor maintainers |
| Review deadline | 2026-11-30 |
| Removal condition | Complete and validate the Alloy major-version migration |

`alloy-provider` uses `LruCache::pop` in its block-stream cache. The anchor and reserve-attestor
use HTTP request/transaction providers and do not construct or consume that block stream. The
cache key is the primitive `BlockNumber`, and the cached response types do not have panicking
destructors, which removes the panic-safety preconditions described by the `pop` advisory in the
current execution paths. `alloy-provider 0.8.3` does not call the affected `iter_mut` API.

This is not a claim that the dependency is patched. CI invokes `scripts/cargo-audit.sh`, which
allows only these two IDs and rejects any new unsound advisory. The exception must be removed or
renewed with fresh evidence by the review deadline.
