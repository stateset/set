#!/usr/bin/env bash
set -euo pipefail

# A skipped scanner must never become a successful certification.
for dependency in dirname node sed head git rg; do
    command -v "$dependency" >/dev/null 2>&1 || {
        echo "release check requires ${dependency}" >&2
        exit 1
    }
done

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

locked_dependencies="$(node -e '
    const fs = require("node:fs");
    const lock = JSON.parse(fs.readFileSync("./contracts/foundry.lock", "utf8"));
    if (!lock || typeof lock !== "object" || Array.isArray(lock) || Object.keys(lock).length === 0) {
        throw new Error("foundry.lock must contain dependency pins");
    }
    for (const [dependency, metadata] of Object.entries(lock)) {
        if (!/^lib\/[a-zA-Z0-9_-]+$/.test(dependency) ||
            !metadata || !/^[0-9a-f]{40}$/.test(metadata.rev)) {
            throw new Error("invalid Foundry dependency pin");
        }
        process.stdout.write(`${dependency}\t${metadata.rev}\n`);
    }
')"

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
done <<< "$locked_dependencies"

# rg exit 1 means no matches; exit 2 (or a crashed scanner) is a check failure.
reject_matches() {
    local message="$1"
    shift
    local result=0
    rg "$@" || result=$?
    if [ "$result" -eq 0 ]; then
        echo "$message" >&2
        exit 1
    elif [ "$result" -ne 1 ]; then
        echo "release scanner failed (exit ${result})" >&2
        exit 1
    fi
}

tracked_files="$(git ls-files)"
reject_matches "tracked runtime secret file detected" \
    '(^|/)(\.env|secrets\.ya?ml)$' <<< "$tracked_files"

reject_matches "GitHub Actions must be pinned to immutable commit SHAs" \
    --pcre2 -n 'uses:\s+[^[:space:]#]+@(?![0-9a-f]{40}(?:["\x27]?\s*(?:#.*)?$))' .github/workflows
reject_matches "release workflows must pin the runner image" \
    -n 'runs-on:\s+[^#]*latest' .github/workflows

git diff --check
printf 'release metadata verified: tag=%s sdk=%s anchor=%s\n' \
    "${release_tag:-none}" "$sdk_version" "$anchor_version"
