#!/usr/bin/env python3
"""Linux-only process ownership records for the legacy local rollup launcher."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import select
import signal
import stat
import sys
import time

COMPONENTS = ("op-geth", "op-node", "op-batcher", "op-proposer")


def read_owned(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd) as stream:
        info = os.fstat(stream.fileno())
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                or info.st_mode & 0o022 or info.st_size > 16384):
            raise ValueError("Untrusted process record")
        return stream.read(16385)


def process_pid(path):
    raw = read_owned(path).strip()
    if not re.fullmatch(r"[1-9][0-9]{0,9}", raw) or int(raw) <= 1:
        raise ValueError("Invalid process ID")
    return int(raw)


def identity(pid, component, root):
    proc = Path(f"/proc/{pid}")
    executable = (proc / "exe").resolve(strict=True)
    if executable.name != component or (proc / "cwd").resolve(strict=True) != root.resolve():
        raise ValueError("Process does not belong to this local launcher")
    if proc.stat().st_uid != os.getuid():
        raise ValueError("Process belongs to another user")
    # comm may contain spaces or parentheses. Fields after its final ')' start at state.
    fields = (proc / "stat").read_text().rsplit(")", 1)[1].split()
    executable_info = (proc / "exe").stat()
    return {"pid": pid, "component": component, "root": str(root.resolve()),
            "boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
            "start_ticks": fields[19], "executable": str(executable),
            "device": executable_info.st_dev, "inode": executable_info.st_ino,
            # Arguments may contain signing keys: persist only a digest, never plaintext.
            "argv_sha256": hashlib.sha256((proc / "cmdline").read_bytes()).hexdigest()}


def record(root, component):
    path = root / ".pids" / f"{component}.pid"
    pid = process_pid(path)
    metadata = path.with_suffix(".identity.json")
    # Do not overwrite an existing ownership record, including a symlink.
    info = identity(pid, component, root)
    fd = os.open(metadata, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as stream:
        json.dump(info, stream, sort_keys=True)
        stream.flush()
        os.fsync(stream.fileno())


def running(root, component):
    path = root / ".pids" / f"{component}.pid"
    pid = process_pid(path)
    expected = json.loads(read_owned(path.with_suffix(".identity.json")))
    fd = os.pidfd_open(pid)
    try:
        if identity(pid, component, root) != expected:
            raise ValueError("Process identity changed")
        poller = select.poll()
        poller.register(fd, select.POLLIN)
        if poller.poll(0):
            raise ProcessLookupError("Process exited")
    finally:
        os.close(fd)
    return "identity-verified running (RPC readiness not checked)"


def stop(root, component, grace=5):
    path = root / ".pids" / f"{component}.pid"
    metadata = path.with_suffix(".identity.json")
    if not path.exists() and not path.is_symlink():
        if metadata.exists() or metadata.is_symlink():
            raise ValueError("Orphaned identity record requires operator review")
        return "not recorded"
    pid = process_pid(path)
    expected = json.loads(read_owned(metadata))
    # A pidfd refers to one process instance even if the numeric PID is later reused.
    # Unsupported kernels fail closed; there is intentionally no os.kill fallback.
    fd = os.pidfd_open(pid)
    try:
        if identity(pid, component, root) != expected:
            raise ValueError("Process identity changed; refusing to signal")
        poller = select.poll()
        poller.register(fd, select.POLLIN)
        signal.pidfd_send_signal(fd, signal.SIGTERM)
        if not poller.poll(grace * 1000):
            signal.pidfd_send_signal(fd, signal.SIGKILL)
            if not poller.poll(2000):
                raise TimeoutError("Process did not exit; records retained")
    finally:
        os.close(fd)
    # Remove only the same records we validated, never a replacement launch's files.
    if process_pid(path) != pid or json.loads(read_owned(metadata)) != expected:
        raise ValueError("Process records changed; retained for operator review")
    metadata.unlink()
    path.unlink()
    return "stopped; ownership records removed"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("check", "record", "status", "stop"))
    parser.add_argument("component", choices=COMPONENTS, nargs="?")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    try:
        if args.action == "check":
            if not hasattr(os, "pidfd_open") or not hasattr(signal, "pidfd_send_signal"):
                raise RuntimeError("Linux Python 3.9+ with pidfd support required")
            fd = os.pidfd_open(os.getpid())
            os.close(fd)
            return 0
        if args.component is None:
            parser.error("record, status and stop require a component")
        if args.action == "record":
            # Give the background child a bounded interval to exec its binary.
            for attempt in range(20):
                try:
                    record(root, args.component)
                    return 0
                except (FileNotFoundError, ProcessLookupError, ValueError):
                    if attempt == 19:
                        raise
                    time.sleep(0.05)
        elif args.action == "status":
            print(f"{args.component}: {running(root, args.component)}")
        else:
            print(f"{args.component}: {stop(root, args.component)}")
    except Exception as error:
        # Do not print /proc command lines or exceptions containing secret arguments.
        print(f"{args.component or 'runtime'}: {args.action} refused ({type(error).__name__}); "
              "requires Linux Python 3.9+ with pidfd support and valid local ownership records",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
