"""Actual loopback HTTP transport and CLI tests with simulated chain responses."""
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("ready_http", ROOT / "scripts/check-local-rpc-ready.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


@contextmanager
def server(responder):
    calls = []
    released = threading.Event()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_POST(self):
            request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            calls.append(request)
            status, headers, body = responder(request)
            if status == "stall":
                released.wait(10)
                return
            if status == "disconnect":
                self.close_connection = True
                return
            self.send_response(status)
            for key, value in headers.items():
                self.send_header(key, value)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass

    instance = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=instance.serve_forever, kwargs={"poll_interval": 0.01})
    thread.start()
    try:
        yield f"http://127.0.0.1:{instance.server_port}", calls
    finally:
        released.set()
        instance.shutdown()
        instance.server_close()
        thread.join(timeout=5)


class LocalRpcHttpTests(unittest.TestCase):
    def setUp(self):
        self.hash = "0x" + "ab" * 32
        self.config = {"l1_chain_id": 1337, "l2_chain_id": 901,
                       "genesis": {"l2": {"number": 0, "hash": self.hash}}}

    def reply(self, request):
        method = request["method"]
        if method == "eth_chainId":
            result = "0x385"
        elif method == "eth_getBlockByNumber":
            result = {"hash": self.hash, "number": "0x0"}
        elif method == "optimism_rollupConfig":
            result = self.config
        elif method == "optimism_syncStatus":
            result = {"unsafe_l2": {"hash": self.hash, "number": 0}}
        else:
            raise AssertionError(f"Unexpected RPC: {method}")
        body = json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": result}).encode()
        return 200, {"Content-Type": "application/json"}, body

    def cli(self, execution, rollup=None, timeout=2):
        with tempfile.TemporaryDirectory(prefix="set-http-check-") as directory:
            config = Path(directory) / "rollup.json"
            config.write_text(json.dumps(self.config))
            command = [sys.executable, str(ROOT / "scripts/check-local-rpc-ready.py"),
                       "--execution", execution, "--config", str(config), "--timeout", str(timeout)]
            if rollup:
                command += ["--rollup-rpc", rollup]
            return subprocess.run(command, capture_output=True, text=True, timeout=8)

    def test_complete_probe_over_two_real_http_listeners(self):
        with server(self.reply) as (execution, execution_calls), server(self.reply) as (rollup, rollup_calls):
            result = self.cli(execution, rollup)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("settlement and sync completion are not certified", result.stdout)
        self.assertEqual(len(execution_calls), 4)
        self.assertEqual([call["method"] for call in rollup_calls], ["optimism_rollupConfig", "optimism_syncStatus"])

    def test_redirects_are_never_followed(self):
        with server(self.reply) as (destination, destination_calls):
            for code in (301, 302, 303, 307, 308):
                with self.subTest(code=code), server(lambda request: (code, {"Location": destination}, b"")) as (url, calls):
                    with self.assertRaises(HTTPError):
                        MODULE.TRANSPORT.rpc(url, "eth_chainId", [], 1)
                    self.assertEqual(len(calls), 1)
            self.assertEqual(destination_calls, [])

    def test_proxy_environment_cannot_intercept_local_rpc(self):
        with server(self.reply) as (destination, calls), server(self.reply) as (proxy, proxy_calls):
            with patch.dict(os.environ, {"HTTP_PROXY": proxy, "http_proxy": proxy,
                                         "ALL_PROXY": proxy, "all_proxy": proxy,
                                         "NO_PROXY": "", "no_proxy": ""}):
                self.assertEqual(MODULE.TRANSPORT.rpc(destination, "eth_chainId", [], 1), "0x385")
            self.assertEqual(len(calls), 1)
            self.assertEqual(proxy_calls, [])

    def test_malformed_and_oversized_http_bodies_fail_closed(self):
        bodies = [b"not-json", b"[]", b"x" * (1024 * 1024 + 1),
                  b'{"jsonrpc":"2.0","id":true,"result":"0x385"}',
                  b'{"jsonrpc":"2.0","id":2,"result":"0x385"}',
                  b'{"jsonrpc":"2.0","id":1,"error":{"code":-1},"result":"0x385"}']
        for body in bodies:
            with self.subTest(size=len(body)), server(lambda request: (200, {}, body)) as (url, calls):
                with self.assertRaises(ValueError):
                    MODULE.TRANSPORT.rpc(url, "eth_chainId", [], 1)

    def test_deadline_interrupts_server_that_never_sends_headers(self):
        with server(lambda request: ("stall", {}, b"")) as (url, calls):
            result = self.cli(url, timeout=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("StartupDeadline", result.stderr)
        self.assertNotIn("RPCs reachable", result.stdout)
        self.assertEqual(len(calls), 1)

    def test_ambiguous_json_fields_and_nonfinite_numbers_rejected(self):
        bodies = [
            b'{"jsonrpc":"2.0","id":2,"id":1,"result":"0x385"}',
            b'{"jsonrpc":"2.0","id":1,"result":"0x1","result":"0x385"}',
            b'{"jsonrpc":"2.0","id":1,"result":{"number":1,"number":0}}',
            b'{"jsonrpc":"2.0","id":1,"result":"0x385","extra":NaN}',
            b'{"jsonrpc":"2.0","id":1,"result":Infinity}',
            b'{"jsonrpc":"2.0","id":1,"result":-Infinity}',
            b'{"jsonrpc":"2.0","id":1,"result":1e9999}',
            b'{"jsonrpc":"2.0","id":1,"result":-1e9999}',
        ]
        for body in bodies:
            with self.subTest(body=body), server(lambda request: (200, {}, body)) as (url, calls):
                with self.assertRaises(ValueError):
                    MODULE.TRANSPORT.rpc(url, "eth_chainId", [], 1)

    def test_transport_itself_rejects_nonlocal_urls(self):
        with patch.object(MODULE.TRANSPORT, "build_opener") as opener:
            with self.assertRaises(ValueError):
                MODULE.TRANSPORT.rpc("https://public.invalid", "eth_chainId", [], 1)
            opener.assert_not_called()

    def test_transient_http_failure_recovers_within_deadline(self):
        attempt = 0
        def reply(request):
            nonlocal attempt
            attempt += 1
            if attempt == 1:
                return 503, {}, b"temporary failure"
            return self.reply(request)
        with server(reply) as (url, calls):
            result = self.cli(url)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(attempt, 4)


if __name__ == "__main__":
    unittest.main()
