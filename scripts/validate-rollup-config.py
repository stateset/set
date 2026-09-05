#!/usr/bin/env python3
"""Validate generated OP Stack artifacts offline before node initialization."""
import argparse
import json
from pathlib import Path
import re
import sys


def validate(genesis, rollup, l1_chain_id, l2_chain_id):
    errors = []

    def require(condition, message):
        if not condition:
            errors.append(message)

    def integer(value):
        if isinstance(value, bool):
            return None
        if isinstance(value, int):
            return value
        if isinstance(value, str):
            try:
                return int(value, 16) if value.startswith("0x") else int(value, 10)
            except ValueError:
                return None
        return None

    def hex_value(value, size):
        return (isinstance(value, str)
                and re.fullmatch(r"0x[0-9a-fA-F]{%d}" % (size * 2), value)
                and int(value, 16) != 0)

    config = genesis.get("config", {})
    origin = rollup.get("genesis", {})
    system = origin.get("system_config", {})
    require(l1_chain_id > 0 and l2_chain_id > 0 and l1_chain_id != l2_chain_id,
            "Expected chain IDs must be positive and distinct")
    require(integer(config.get("chainId")) == l2_chain_id, "Genesis L2 chain ID mismatch")
    require(integer(rollup.get("l1_chain_id")) == l1_chain_id, "Rollup L1 chain ID mismatch")
    require(integer(rollup.get("l2_chain_id")) == l2_chain_id, "Rollup L2 chain ID mismatch")
    require(integer(genesis.get("timestamp")) == integer(origin.get("l2_time"))
            and integer(origin.get("l2_time")) is not None, "Genesis timestamp mismatch")
    gas = integer(genesis.get("gasLimit"))
    require(gas is not None and gas > 0 and gas == integer(system.get("gasLimit")),
            "Genesis gas limit mismatch")
    for key in ("block_time", "max_sequencer_drift", "seq_window_size", "channel_timeout"):
        value = integer(rollup.get(key))
        require(value is not None and value > 0, f"Invalid rollup {key}")
    for key in ("batch_inbox_address", "deposit_contract_address", "l1_system_config_address"):
        require(hex_value(rollup.get(key), 20), f"Invalid or zero {key}")
    require(hex_value(system.get("batcherAddr"), 20), "Invalid or zero batcher address")
    for layer in ("l1", "l2"):
        block = origin.get(layer, {})
        require(hex_value(block.get("hash"), 32), f"Invalid {layer} genesis hash")
        number = integer(block.get("number"))
        require(number is not None and number >= 0, f"Invalid {layer} genesis block number")
    require(isinstance(genesis.get("alloc"), dict) and bool(genesis.get("alloc")),
            "Genesis allocations are missing")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--genesis", type=Path, required=True)
    parser.add_argument("--rollup", type=Path, required=True)
    parser.add_argument("--l1-chain-id", type=int, required=True)
    parser.add_argument("--l2-chain-id", type=int, required=True)
    args = parser.parse_args()
    try:
        errors = validate(json.loads(args.genesis.read_text()), json.loads(args.rollup.read_text()),
                          args.l1_chain_id, args.l2_chain_id)
    except (OSError, ValueError, AttributeError, TypeError) as error:
        print(f"Invalid or missing generated configuration: {type(error).__name__}", file=sys.stderr)
        return 1
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        return 1
    print("Generated chain IDs, origins, gas and addresses are consistent. Runtime settlement is not certified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
