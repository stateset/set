"""RPC startup checks with simulated responses and real subprocess deadlines."""
import copy
import importlib.util
import json
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("local_ready", ROOT / "scripts/check-local-rpc-ready.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class LocalRpcReadinessTests(unittest.TestCase):
    def setUp(self):
        self.hash = "0x" + "ab" * 32
        self.config = {"l1_chain_id": 1337, "l2_chain_id": 901,
                       "genesis": {"l2": {"number": 0, "hash": self.hash}}}
        self.execution_block = {"number": "0x0", "hash": self.hash}
        self.status = {"unsafe_l2": {"number": 0, "hash": self.hash}}
        self.responses = ["0x385", self.execution_block, self.execution_block,
                          self.config, self.status, self.execution_block]

    def inspect(self):
        MODULE.inspect("http://127.0.0.1:8547", "http://127.0.0.1:9545", self.config)

    def test_matching_execution_and_rollup(self):
        with patch.object(MODULE.TRANSPORT, "rpc", side_effect=self.responses) as rpc:
            self.inspect()
        self.assertEqual([call.args[1] for call in rpc.call_args_list], [
            "eth_chainId", "eth_getBlockByNumber", "eth_getBlockByNumber",
            "optimism_rollupConfig", "optimism_syncStatus", "eth_getBlockByNumber"])

    def test_execution_only_probe_does_not_require_consensus_node(self):
        with patch.object(MODULE.TRANSPORT, "rpc", side_effect=self.responses[:3]) as rpc:
            MODULE.inspect("http://127.0.0.1:8547", None, self.config)
        self.assertEqual(rpc.call_count, 3)

    def test_wrong_chain_or_genesis_rejected(self):
        for index, value in ((0, "0x1"), (1, {"number": "0x0", "hash": "0x" + "cd" * 32}),
                             (1, None), (2, {"number": "0x00", "hash": self.hash})):
            responses = list(self.responses)
            responses[index] = value
            with self.subTest(index=index), patch.object(MODULE.TRANSPORT, "rpc", side_effect=responses):
                with self.assertRaises(ValueError):
                    self.inspect()

    def test_wrong_running_rollup_config_rejected(self):
        for change in ({"l1_chain_id": 1}, {"l2_chain_id": "901"}, {"genesis": {}}):
            responses = list(self.responses)
            responses[3] = {**self.config, **change}
            with self.subTest(change=change), patch.object(MODULE.TRANSPORT, "rpc", side_effect=responses):
                with self.assertRaises(ValueError):
                    self.inspect()

    def test_rollup_head_must_be_canonical_on_execution(self):
        responses = list(self.responses)
        responses[-1] = {"number": "0x0", "hash": "0x" + "cd" * 32}
        with patch.object(MODULE.TRANSPORT, "rpc", side_effect=responses):
            with self.assertRaises(ValueError):
                self.inspect()

    def test_missing_or_malformed_sync_status_rejected(self):
        for value in (None, {}, {"unsafe_l2": {"number": True, "hash": self.hash}},
                      {"unsafe_l2": {"number": 0, "hash": "0x" + "00" * 32}}):
            responses = list(self.responses)
            responses[4] = value
            with self.subTest(value=value), patch.object(MODULE.TRANSPORT, "rpc", side_effect=responses):
                with self.assertRaises(ValueError):
                    self.inspect()

    def test_remote_endpoint_rejected_before_network(self):
        with patch.object(MODULE.TRANSPORT, "rpc") as rpc:
            with self.assertRaises(ValueError):
                MODULE.inspect("http://127.0.0.1:8547", "https://public.invalid", self.config)
            rpc.assert_not_called()

    def test_config_comparison_allows_extra_defaults_but_not_type_coercion(self):
        self.assertTrue(MODULE.matches(self.config, {**self.config, "extra_default": None}))
        config = copy.deepcopy(self.config)
        config["genesis"]["l2"]["number"] = False
        self.assertFalse(MODULE.matches(self.config, config))

    def test_deadline_interrupts_blocked_transport(self):
        self.assertNotIsInstance(MODULE.StartupDeadline(), OSError)
        with tempfile.TemporaryDirectory(prefix="set-rpc-deadline-") as directory:
            root = Path(directory)
            shutil.copyfile(ROOT / "scripts/check-local-rpc-ready.py", root / "check.py")
            (root / "validate-local-l1.py").write_text('''import time
def local_url(value): return value
def quantity(value): return int(value, 16)
def rpc(*args): time.sleep(60)
''')
            (root / "rollup.json").write_text(json.dumps(self.config))
            result = subprocess.run([sys.executable, str(root / "check.py"),
                "--execution", "http://127.0.0.1:8547", "--config", str(root / "rollup.json"),
                "--timeout", "1"], capture_output=True, text=True, timeout=5)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("StartupDeadline", result.stderr)
            self.assertNotIn("RPCs reachable", result.stdout)

    def test_transient_transport_failure_retries_and_cleans_timer(self):
        with tempfile.TemporaryDirectory(prefix="set-rpc-retry-") as directory:
            config = Path(directory) / "rollup.json"
            config.write_text(json.dumps(self.config))
            previous = signal.getsignal(signal.SIGALRM)
            with patch.object(sys, "argv", ["check", "--execution", "http://127.0.0.1:8547",
                              "--rollup-rpc", "http://127.0.0.1:9545", "--config", str(config)]), \
                 patch.object(MODULE.TRANSPORT, "rpc", side_effect=[OSError("transient")] + self.responses), \
                 patch.object(MODULE.time, "sleep") as pause:
                self.assertEqual(MODULE.main(), 0)
                pause.assert_called_once_with(0.25)
            self.assertEqual(signal.getsignal(signal.SIGALRM), previous)
            self.assertEqual(signal.getitimer(signal.ITIMER_REAL), (0.0, 0.0))


if __name__ == "__main__":
    unittest.main()
