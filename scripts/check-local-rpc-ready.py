#!/usr/bin/env python3
"""Read-only local RPC startup checks, not settlement or synchronization certification."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import signal
import sys
import time

SPEC = importlib.util.spec_from_file_location("local_l1_rpc", Path(__file__).with_name("validate-local-l1.py"))
TRANSPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TRANSPORT)


def block(value, rpc_number=True):
    if not isinstance(value, dict):
        raise ValueError("Block unavailable")
    number = TRANSPORT.quantity(value.get("number")) if rpc_number else value.get("number")
    block_hash = value.get("hash")
    if (type(number) is not int or number < 0 or not isinstance(block_hash, str)
            or not re.fullmatch(r"0x[0-9a-fA-F]{64}", block_hash) or int(block_hash, 16) == 0):
        raise ValueError("Invalid block reference")
    return number, block_hash.lower()


def matches(expected, actual):
    if type(expected) is not type(actual):
        return False
    if isinstance(expected, dict):
        return all(key in actual and matches(value, actual[key]) for key, value in expected.items())
    if isinstance(expected, str) and expected.startswith("0x"):
        return expected.lower() == actual.lower()
    return expected == actual


def inspect(execution, rollup_rpc, config):
    TRANSPORT.local_url(execution)
    if rollup_rpc is not None:
        TRANSPORT.local_url(rollup_rpc)
    if (config.get("l1_chain_id") not in (1337, 31337)
            or type(config.get("l2_chain_id")) is not int or config["l2_chain_id"] <= 0
            or config["l2_chain_id"] == config["l1_chain_id"]):
        raise ValueError("Local chain configuration required")
    origin = block(config["genesis"]["l2"], rpc_number=False)
    rpc = TRANSPORT.rpc
    if TRANSPORT.quantity(rpc(execution, "eth_chainId", [], 1)) != config["l2_chain_id"]:
        raise ValueError("Execution chain mismatch")
    if block(rpc(execution, "eth_getBlockByNumber", [hex(origin[0]), False], 2)) != origin:
        raise ValueError("Execution genesis mismatch")
    latest = block(rpc(execution, "eth_getBlockByNumber", ["latest", False], 3))
    if latest[0] < origin[0]:
        raise ValueError("Execution head predates genesis")
    if rollup_rpc is not None:
        actual = rpc(rollup_rpc, "optimism_rollupConfig", [], 4)
        if not matches(config, actual):
            raise ValueError("Running rollup configuration mismatch")
        status = rpc(rollup_rpc, "optimism_syncStatus", [], 5)
        if not isinstance(status, dict):
            raise ValueError("Rollup status unavailable")
        unsafe = block(status.get("unsafe_l2"), rpc_number=False)
        if unsafe[0] < origin[0]:
            raise ValueError("Rollup head predates genesis")
        canonical = block(rpc(execution, "eth_getBlockByNumber", [hex(unsafe[0]), False], 6))
        if canonical != unsafe:
            raise ValueError("Rollup head is not canonical on execution node")


class StartupDeadline(RuntimeError):
    # urllib can wrap OSError (including TimeoutError) as a retryable URLError
    # during connection setup. The whole-operation alarm must escape that path.
    pass


def expired(signum, frame):
    raise StartupDeadline("RPC startup deadline exceeded")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execution", required=True)
    parser.add_argument("--rollup-rpc")
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=30)
    args = parser.parse_args()
    if not 1 <= args.timeout <= 120:
        parser.error("timeout must be between 1 and 120 seconds")
    previous = signal.signal(signal.SIGALRM, expired)
    signal.setitimer(signal.ITIMER_REAL, args.timeout)
    last_error = "not observed"
    try:
        config = json.loads(args.config.read_text())
        TRANSPORT.local_url(args.execution)
        if args.rollup_rpc is not None:
            TRANSPORT.local_url(args.rollup_rpc)
        while True:
            try:
                inspect(args.execution, args.rollup_rpc, config)
                break
            except StartupDeadline:
                raise
            except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
                last_error = type(error).__name__
                time.sleep(0.25)
    except Exception as error:
        print(f"Local RPC startup check failed ({type(error).__name__}; last check: {last_error})", file=sys.stderr)
        return 1
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)
    print("Local RPCs reachable with matching chain/configuration; settlement and sync completion are not certified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
