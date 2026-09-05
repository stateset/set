#!/usr/bin/env python3
"""Archive idle Anvil artifacts without identifying or signaling other processes."""
import argparse
from contextlib import ExitStack
import errno
import json
import os
from pathlib import Path
import re
import socket
import stat
import sys
import tempfile


def require_directory(path, optional=False):
    try:
        info = path.lstat()
    except FileNotFoundError:
        if optional:
            return False
        raise
    if not stat.S_ISDIR(info.st_mode):
        raise ValueError(f"Not a real directory (symlinks refused): {path}")
    return True


def select_artifacts(root, chain_id):
    if not re.fullmatch(r"[1-9][0-9]{0,19}", chain_id) or int(chain_id) >= 2**64:
        raise ValueError("Chain ID must be a canonical positive uint64")
    contracts = root / "contracts"
    require_directory(contracts)
    targets = []
    for name in ("cache", "out"):
        path = contracts / name
        if require_directory(path, optional=True):
            targets.append(path)
    broadcast = contracts / "broadcast"
    if require_directory(broadcast, optional=True):
        for script in sorted(broadcast.iterdir()):
            # Do not follow script-directory symlinks, even if their target is local.
            if script.is_symlink():
                raise ValueError(f"Symlinked broadcast entry refused: {script}")
            if not script.is_dir():
                continue
            path = script / chain_id
            if require_directory(path, optional=True):
                targets.append(path)
    return targets


def reserve_rpc_port(stack, port=8545):
    """Keep 8545 reserved throughout archival; never connect to an existing node."""
    for family, address in ((socket.AF_INET, "127.0.0.1"), (socket.AF_INET6, "::1")):
        try:
            listener = stack.enter_context(socket.socket(family, socket.SOCK_STREAM))
            if family == socket.AF_INET6:
                listener.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
            listener.bind((address, port))
        except OSError as error:
            # IPv6 can be disabled locally. All other failures are fail-closed.
            if family == socket.AF_INET6 and error.errno in (errno.EAFNOSUPPORT, errno.EADDRNOTAVAIL):
                continue
            raise RuntimeError(f"Cannot reserve local RPC port {port}; stop the intended node explicitly first") from error


def archive_artifacts(root, chain_id):
    """Caller must hold the RPC-port reservation. No recursive deletion occurs."""
    root = root.resolve(strict=True)
    targets = select_artifacts(root, chain_id)
    archive_parent = root / ".devnet-reset-archive"
    if not targets:
        return None
    if not require_directory(archive_parent, optional=True):
        archive_parent.mkdir(mode=0o700)
    archive_info = archive_parent.stat()
    if archive_info.st_uid != os.getuid() or archive_info.st_mode & 0o022:
        raise ValueError("Archive directory must be owned by this user and not writable by others")
    if any(path.stat().st_dev != archive_info.st_dev or os.path.ismount(path) for path in targets):
        raise ValueError("Artifacts must be unmounted directories on the archive filesystem")
    archive = Path(tempfile.mkdtemp(prefix="reset-", dir=archive_parent))
    manifest = archive / "manifest.jsonl"
    # Sync the journal before each move. On failure it describes the attempted
    # plan; source/destination existence determines what moved.
    try:
        with manifest.open("x", encoding="utf-8") as journal:
            for source in targets:
                relative = source.relative_to(root)
                destination = archive / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                # Normal tooling must be idle. This is not protection against
                # malicious same-user filesystem mutations.
                for parent in reversed(source.parents):
                    if parent == root or root in parent.parents:
                        require_directory(parent)
                require_directory(source)
                journal.write(json.dumps({"source": str(relative), "destination": str(relative)}) + "\n")
                journal.flush()
                os.fsync(journal.fileno())
                os.rename(source, destination)
                for directory in (source.parent, destination.parent):
                    fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
                    try:
                        os.fsync(fd)
                    finally:
                        os.close(fd)
    except Exception as error:
        raise RuntimeError(f"Reset incomplete; review retained artifacts and journal at {archive}") from error
    return archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chain-id", required=True)
    parser.add_argument("--no-start", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    try:
        with ExitStack() as stack:
            reserve_rpc_port(stack)
            archive = archive_artifacts(root, args.chain_id)
        if archive:
            print(f"Artifacts archived (not deleted): {archive}", flush=True)
        else:
            print("No matching local artifacts to archive.", flush=True)
        if not args.no_start:
            # A competing launch may win after reservations are released. The
            # launcher then fails without stopping that competing node.
            os.execv("/bin/bash", ["bash", str(root / "scripts/start-local-anvil.sh")])
        print("Reset complete. Skipping restart.")
        return 0
    except Exception as error:
        print(f"Reset refused: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
