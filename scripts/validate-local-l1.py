#!/usr/bin/env python3
"""Read-only guard for the legacy local launcher; never certifies rollup readiness."""
import argparse
import json
import math
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener


def local_url(value):
    url = urlsplit(value)
    if (url.scheme != "http" or url.hostname not in ("127.0.0.1", "::1")
            or url.username is not None or url.password is not None
            or url.path not in ("", "/") or url.query or url.fragment
            or url.port is None or not 1 <= url.port <= 65535):
        raise ValueError("Use credential-free numeric loopback HTTP endpoints with explicit ports")
    return value


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError("Duplicate JSON object key")
        value[key] = item
    return value


def invalid_constant(value):
    raise ValueError("Non-finite JSON number")


def finite_float(value):
    number = float(value)
    if not math.isfinite(number):
        raise ValueError("Non-finite JSON number")
    return number


def rpc(url, method, params, request_id):
    local_url(url)
    request = Request(url, data=json.dumps({"jsonrpc": "2.0", "id": request_id,
                      "method": method, "params": params}).encode(),
                      headers={"Content-Type": "application/json"})
    # Environment HTTP proxies and redirects must not bypass loopback restrictions.
    with build_opener(ProxyHandler({}), NoRedirect()).open(request, timeout=5) as response:
        raw = response.read(1024 * 1024 + 1)
    if len(raw) > 1024 * 1024:
        raise ValueError("Oversized RPC response")
    value = json.loads(raw, object_pairs_hook=unique_object,
                       parse_constant=invalid_constant, parse_float=finite_float)
    if (not isinstance(value, dict) or value.get("jsonrpc") != "2.0"
            or type(value.get("id")) is not int or value["id"] != request_id
            or "error" in value or "result" not in value):
        raise ValueError("Invalid JSON-RPC response")
    return value["result"]


def quantity(value):
    if not isinstance(value, str) or not re.fullmatch(r"0x(?:0|[1-9a-fA-F][0-9a-fA-F]*)", value):
        raise ValueError("Invalid RPC quantity")
    return int(value, 16)


def validate(execution, beacon, chain_id, rollup):
    local_url(execution)
    local_url(beacon)
    if chain_id not in (1337, 31337):
        raise ValueError("Local launcher only permits L1 chain IDs 1337 and 31337")
    if type(rollup.get("l1_chain_id")) is not int or rollup["l1_chain_id"] != chain_id:
        raise ValueError("Rollup configuration does not match the local L1")
    origin = rollup["genesis"]["l1"]
    if (type(origin["number"]) is not int or origin["number"] < 0
            or not isinstance(origin["hash"], str)
            or not re.fullmatch(r"0x[0-9a-fA-F]{64}", origin["hash"])
            or int(origin["hash"], 16) == 0):
        raise ValueError("Invalid rollup L1 origin")
    if quantity(rpc(execution, "eth_chainId", [], 1)) != chain_id:
        raise ValueError("RPC is not serving the expected local L1")
    block = rpc(execution, "eth_getBlockByNumber", [hex(origin["number"]), False], 2)
    if (not isinstance(block, dict) or quantity(block.get("number")) != origin["number"]
            or not isinstance(block.get("hash"), str)
            or block["hash"].lower() != origin["hash"].lower()):
        raise ValueError("Rollup L1 origin is not canonical on this local node")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execution", required=True)
    parser.add_argument("--beacon", required=True)
    parser.add_argument("--chain-id", type=int, required=True)
    parser.add_argument("--rollup", type=Path, required=True)
    args = parser.parse_args()
    try:
        validate(args.execution, args.beacon, args.chain_id, json.loads(args.rollup.read_text()))
    except Exception as error:
        # Never echo transport exceptions: they may contain endpoints or credentials.
        print(f"Local L1 preflight failed ({type(error).__name__}); no nodes started", file=sys.stderr)
        return 1
    print("Local L1 identity and rollup origin match. Settlement and fault proofs are not certified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
