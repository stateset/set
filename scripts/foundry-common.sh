#!/bin/bash
# Shared helpers for resolving Foundry tooling across host and Docker backends.

foundry_root_dir() {
    if [ -n "${ROOT_DIR:-}" ]; then
        echo "$ROOT_DIR"
        return
    fi

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    dirname "$script_dir"
}

foundry_contracts_dir() {
    if [ -n "${CONTRACTS_DIR:-}" ]; then
        echo "$CONTRACTS_DIR"
        return
    fi

    echo "$(foundry_root_dir)/contracts"
}

foundry_version() {
    if [ -n "${FOUNDRY_VERSION:-}" ]; then
        echo "$FOUNDRY_VERSION"
        return
    fi

    local version_file
    version_file="$(foundry_root_dir)/.foundry-version"

    if [ -f "$version_file" ]; then
        tr -d '[:space:]' < "$version_file"
        return
    fi

    echo "nightly-2024-05-20"
}

foundry_image() {
    if [ -n "${FOUNDRY_DOCKER_IMAGE:-}" ]; then
        echo "$FOUNDRY_DOCKER_IMAGE"
        return
    fi

    local version
    version="$(foundry_version)"

    if echo "$version" | grep -Eq '^(stable|latest|nightly|nightly-[0-9a-f]{40})$'; then
        echo "ghcr.io/foundry-rs/foundry:${version}"
        return
    fi

    echo "${FOUNDRY_DOCKER_IMAGE_DEFAULT:-ghcr.io/foundry-rs/foundry:nightly}"
}

has_valid_foundry_tool() {
    local tool="$1"
    local version_output

    if ! command -v "$tool" >/dev/null 2>&1; then
        return 1
    fi

    if ! version_output="$("$tool" --version 2>/dev/null)"; then
        return 1
    fi

    echo "$version_output" | grep -Eiq "^${tool}( | Version:)"
}

foundry_backend() {
    local tool="$1"

    if [ "${FOUNDRY_USE_DOCKER:-0}" = "1" ]; then
        if command -v docker >/dev/null 2>&1; then
            echo "docker"
        else
            echo "none"
        fi
        return
    fi

    if has_valid_foundry_tool "$tool"; then
        echo "host"
        return
    fi

    if command -v docker >/dev/null 2>&1; then
        echo "docker"
        return
    fi

    echo "none"
}

foundry_require_backend() {
    local tool="$1"
    local backend

    backend="$(foundry_backend "$tool")"
    if [ "$backend" != "none" ]; then
        return 0
    fi

    echo "No usable ${tool} backend found. Install Foundry, install Docker, or set FOUNDRY_USE_DOCKER=1." >&2
    return 1
}

run_foundry_tool() {
    local tool="$1"
    shift

    local backend
    backend="$(foundry_backend "$tool")"

    case "$backend" in
        host)
            "$tool" "$@"
            ;;
        docker)
            local image
            local workdir
            local uid
            local gid
            local -a cmd

            image="$(foundry_image)"
            workdir="$(foundry_contracts_dir)"
            uid="$(id -u)"
            gid="$(id -g)"

            cmd=(docker run --rm -u "${uid}:${gid}" -e HOME=/tmp/foundry)

            if [ -t 0 ] && [ -t 1 ]; then
                cmd+=(-it)
            fi

            case "$tool" in
                forge|cast)
                    cmd+=(--network=host -v "${workdir}:/workspace" -w /workspace)
                    ;;
            esac

            cmd+=(--entrypoint "$tool" "$image" "$@")
            "${cmd[@]}"
            ;;
        *)
            foundry_require_backend "$tool"
            return 1
            ;;
    esac
}
