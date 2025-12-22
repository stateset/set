#!/usr/bin/env python3
"""
Minimal mock stateset-sequencer API for local devnet testing.
"""

import argparse
import datetime as dt
import json
import os
import re
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer


def env_uuid(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if value:
        return value
    return str(uuid.uuid4())


def env_bytes32(name: str, default_zero: bool = False) -> str:
    value = os.environ.get(name, "").strip()
    if value:
        return value
    if default_zero:
        return "0x" + "0" * 64
    hex_part = (uuid.uuid4().hex + uuid.uuid4().hex)[:64]
    return "0x" + hex_part


def env_int(name: str, default: int) -> int:
    value = os.environ.get(name, "").strip()
    if value:
        try:
            return int(value)
        except ValueError:
            return default
    return default


def commitment_from_env() -> dict:
    committed_at = os.environ.get("MOCK_COMMITTED_AT", "").strip()
    if not committed_at:
        committed_at = dt.datetime.now(dt.timezone.utc).isoformat()

    sequence_start = env_int("MOCK_SEQUENCE_START", 1)
    sequence_end = env_int("MOCK_SEQUENCE_END", sequence_start)
    event_count = env_int("MOCK_EVENT_COUNT", 1)

    return {
        "batch_id": env_uuid("MOCK_BATCH_ID"),
        "tenant_id": env_uuid("MOCK_TENANT_ID"),
        "store_id": env_uuid("MOCK_STORE_ID"),
        "prev_state_root": env_bytes32("MOCK_PREV_STATE_ROOT", default_zero=True),
        "new_state_root": env_bytes32("MOCK_NEW_STATE_ROOT"),
        "events_root": env_bytes32("MOCK_EVENTS_ROOT"),
        "sequence_start": sequence_start,
        "sequence_end": sequence_end,
        "event_count": event_count,
        "committed_at": committed_at,
        "chain_tx_hash": None,
    }


class State:
    def __init__(self, commitment: dict):
        self.pending = [commitment]
        self.notifications = []


class Handler(BaseHTTPRequestHandler):
    state: State = None  # type: ignore[assignment]

    def _send_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length == 0:
            return None
        data = self.rfile.read(length)
        try:
            return json.loads(data.decode("utf-8"))
        except json.JSONDecodeError:
            return None

    def do_GET(self):  # noqa: N802
        if self.path == "/health":
            self._send_json(200, {"status": "ok"})
            return

        if self.path == "/v1/commitments/pending":
            payload = {
                "commitments": self.state.pending,
                "total": len(self.state.pending),
            }
            self._send_json(200, payload)
            return

        if self.path == "/__mock/stats":
            payload = {
                "pending": len(self.state.pending),
                "anchored_notifications": len(self.state.notifications),
                "last_notification": self.state.notifications[-1] if self.state.notifications else None,
            }
            self._send_json(200, payload)
            return

        self._send_json(404, {"error": "not_found"})

    def do_POST(self):  # noqa: N802
        match = re.match(r"^/v1/commitments/([0-9a-fA-F-]+)/anchored$", self.path)
        if match:
            batch_id = match.group(1)
            body = self._read_json() or {}
            self.state.notifications.append({"batch_id": batch_id, "notification": body})
            self.state.pending = [
                c for c in self.state.pending if c.get("batch_id") != batch_id
            ]
            self._send_json(200, {"status": "ok"})
            return

        self._send_json(404, {"error": "not_found"})

    def log_message(self, format, *args):  # noqa: A003
        return


def main() -> None:
    parser = argparse.ArgumentParser(description="Mock sequencer API")
    parser.add_argument("--port", type=int, default=3001)
    args = parser.parse_args()

    commitment = commitment_from_env()
    state = State(commitment)
    Handler.state = state

    server = HTTPServer(("0.0.0.0", args.port), Handler)
    print(f"Mock sequencer listening on :{args.port}")
    print(f"Initial batch_id: {commitment['batch_id']}")
    server.serve_forever()


if __name__ == "__main__":
    main()
