#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

release_tag="${1:-${GITHUB_REF_NAME:-}}"
sdk_version="$(node -p "require('./sdk/package.json').version")"
anchor_version="$(sed -n 's/^version = "\([^"]*\)"/\1/p' anchor/Cargo.toml | head -n 1)"

if [[ -n "$release_tag" ]]; then
    expected_tag="v${sdk_version}"
    if [[ "$release_tag" != "$expected_tag" ]]; then
        echo "release tag ${release_tag} does not match SDK version ${sdk_version}" >&2
        exit 1
    fi

    if ! git rev-parse --verify --quiet "refs/tags/${release_tag}" >/dev/null; then
        echo "release tag ${release_tag} is not present in the checkout" >&2
        exit 1
    fi

    if [[ "$(git cat-file -t "refs/tags/${release_tag}")" != "tag" ]]; then
        echo "release tag ${release_tag} must be annotated" >&2
        exit 1
    fi
fi

while IFS=$'\t' read -r dependency expected_revision; do
    index_entry="$(git ls-files -s "contracts/${dependency}")"
    read -r file_mode tracked_revision stage tracked_path <<< "$index_entry"

    if [[ "$file_mode" != "160000" || "$stage" != "0" || \
          "$tracked_path" != "contracts/${dependency}" ]]; then
        echo "contracts/${dependency} must be a tracked direct submodule" >&2
        exit 1
    fi

    if [[ "$tracked_revision" != "$expected_revision" ]]; then
        echo "contracts/${dependency} does not match contracts/foundry.lock" >&2
        exit 1
    fi

    if [[ ! -d "contracts/${dependency}" || \
          "$(git -C "contracts/${dependency}" rev-parse HEAD 2>/dev/null || true)" != "$expected_revision" ]]; then
        echo "contracts/${dependency} is not initialized at ${expected_revision}" >&2
        exit 1
    fi
done < <(node -e '
    const fs = require("node:fs");
    const lock = JSON.parse(fs.readFileSync("./contracts/foundry.lock", "utf8"));
    for (const [dependency, metadata] of Object.entries(lock)) {
        process.stdout.write(`${dependency}\t${metadata.rev}\n`);
    }
')

if git ls-files | rg -q '(^|/)(\.env|secrets\.ya?ml)$'; then
    echo "tracked runtime secret file detected" >&2
    git ls-files | rg '(^|/)(\.env|secrets\.ya?ml)$' >&2
    exit 1
fi

if rg -n 'uses:\s+[^[:space:]#]+@(v[0-9]+|main|master|stable|latest)(\s|$)' .github/workflows; then
    echo "GitHub Actions must be pinned to immutable commit SHAs" >&2
    exit 1
fi

if rg -n 'runs-on:\s+[^#]*latest' .github/workflows; then
    echo "release workflows must pin the runner image" >&2
    exit 1
fi

git diff --check
printf 'release metadata verified: tag=%s sdk=%s anchor=%s\n' \
    "${release_tag:-none}" "$sdk_version" "$anchor_version"
