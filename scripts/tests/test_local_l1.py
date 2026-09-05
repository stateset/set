"""Offline local-launcher safety checks; no RPC connections or node startup."""
import copy
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("local_l1", ROOT / "scripts/validate-local-l1.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class LocalL1Tests(unittest.TestCase):
    def setUp(self):
        self.origin = {"number": 10, "hash": "0x" + "ab" * 32}
        self.rollup = {"l1_chain_id": 1337, "genesis": {"l1": self.origin}}

    def validate(self, rollup=None):
        MODULE.validate("http://127.0.0.1:8545", "http://[::1]:5052", 1337, rollup or self.rollup)

    def test_local_identity_and_origin(self):
        with patch.object(MODULE, "rpc", side_effect=["0x539", {**self.origin, "number": "0xa"}]) as rpc:
            self.validate()
        self.assertEqual(rpc.call_count, 2)
        self.assertEqual(rpc.call_args.args[1:3], ("eth_getBlockByNumber", ["0xa", False]))

    def test_endpoint_restrictions_before_network(self):
        for url in ["https://127.0.0.1:8545", "http://localhost:8545", "http://example.com:8545",
                    "http://127.0.0.1:8545/path", "http://user:secret@127.0.0.1:8545",
                    "http://127.0.0.1:8545?key=secret", "http://127.0.0.1:8545#fragment",
                    "http://127.0.0.1", "http://127.0.0.1:99999", "http://127.1:8545"]:
            for role in ("execution", "beacon"):
                with self.subTest(url=url, role=role), patch.object(MODULE, "rpc") as rpc:
                    args = dict(execution="http://127.0.0.1:8545", beacon="http://127.0.0.1:5052",
                                chain_id=1337, rollup=self.rollup)
                    args[role] = url
                    with self.assertRaises(ValueError):
                        MODULE.validate(**args)
                    rpc.assert_not_called()

    def test_public_chain_ids_rejected_before_network(self):
        for chain in (1, 11155111, 17000, 0):
            with self.subTest(chain=chain), patch.object(MODULE, "rpc") as rpc:
                with self.assertRaises(ValueError):
                    MODULE.validate("http://127.0.0.1:8545", "http://127.0.0.1:5052", chain, self.rollup)
                rpc.assert_not_called()

    def test_loopback_proxy_to_wrong_chain_rejected(self):
        for chain in ("0x1", "0xaa36a7", "0x0539", None, 1337):
            with self.subTest(chain=chain), patch.object(MODULE, "rpc", return_value=chain):
                with self.assertRaises(ValueError):
                    self.validate()

    def test_wrong_origin_rejected(self):
        for block in (None, {"number": "0xb", "hash": self.origin["hash"]},
                      {"number": "0xa", "hash": "0x" + "cd" * 32}):
            with self.subTest(block=block), patch.object(MODULE, "rpc", side_effect=["0x539", block]):
                with self.assertRaises(ValueError):
                    self.validate()

    def test_wrong_config_rejected_before_network(self):
        rollup = copy.deepcopy(self.rollup)
        rollup["l1_chain_id"] = 11155111
        with patch.object(MODULE, "rpc") as rpc:
            with self.assertRaises(ValueError):
                self.validate(rollup)
            rpc.assert_not_called()

    def test_rpc_envelope_and_size_validation(self):
        values = [b"not json", b"[]", b"x" * (1024 * 1024 + 1)]
        valid = {"jsonrpc": "2.0", "id": 1, "result": "0x539"}
        values += [json.dumps({**valid, **change}).encode() for change in
                   ({"id": True}, {"id": 2}, {"jsonrpc": "1.0"}, {"error": {"code": -1}})]
        for raw in values:
            with self.subTest(size=len(raw)), patch.object(MODULE, "build_opener") as opener:
                opener.return_value.open.return_value = io.BytesIO(raw)
                with self.assertRaises(ValueError):
                    MODULE.rpc("http://127.0.0.1:8545", "eth_chainId", [], 1)

    def test_transport_disables_proxies_redirects_and_bounds_wait(self):
        with patch.object(MODULE, "build_opener") as opener:
            opener.return_value.open.return_value = io.BytesIO(b'{"jsonrpc":"2.0","id":1,"result":"0x539"}')
            self.assertEqual(MODULE.rpc("http://127.0.0.1:8545", "eth_chainId", [], 1), "0x539")
            self.assertEqual(opener.call_args.args[0].proxies, {})
            self.assertIsInstance(opener.call_args.args[1], MODULE.NoRedirect)
            self.assertEqual(opener.return_value.open.call_args.kwargs["timeout"], 5)
        self.assertIsNone(MODULE.NoRedirect().redirect_request(None, None, 302, None, None, "http://remote"))

    def test_launcher_never_sources_sepolia_environment(self):
        with tempfile.TemporaryDirectory(prefix="set-local-guard-") as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            (root / "config").mkdir()
            shutil.copyfile(ROOT / "scripts/start-devnet.sh", root / "scripts/start-devnet.sh")
            shutil.copyfile(ROOT / "scripts/local-lifecycle.sh", root / "scripts/local-lifecycle.sh")
            (root / "config/sepolia.env").write_text('touch "$PROJECT_DIR/unexpected-sepolia-load"\n')
            result = subprocess.run(["bash", str(root / "scripts/start-devnet.sh")],
                                    capture_output=True, text=True, timeout=5)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("local-rollup.env", result.stdout)
            self.assertFalse((root / "unexpected-sepolia-load").exists())
            self.assertFalse((root / "logs").exists())
            self.assertFalse((root / ".pids").exists())

    def test_launcher_rpc_exposure_and_preflight_order(self):
        source = (ROOT / "scripts/start-devnet.sh").read_text()
        for flag in ("--http.addr 127.0.0.1", "--ws.addr 127.0.0.1", "--authrpc.addr 127.0.0.1",
                     "--rpc.addr 127.0.0.1", "--http.api eth,net,web3", "--ws.api eth,net,web3"):
            self.assertIn(flag, source)
        self.assertNotIn("0.0.0.0", source)
        self.assertNotIn('kill "$pid"', source)
        self.assertLess(source.index('python3 "$SCRIPT_DIR/validate-local-l1.py"'),
                        source.index('mkdir -p "$LOG_DIR"'))


if __name__ == "__main__":
    unittest.main()
