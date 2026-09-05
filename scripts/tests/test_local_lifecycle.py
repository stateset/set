"""Real lock tests and isolated launcher control-flow tests; no OP Stack nodes."""
import fcntl
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LocalLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="set-lifecycle-test-")
        self.root = Path(self.temp.name)
        (self.root / ".pids").mkdir()

    def tearDown(self):
        self.temp.cleanup()

    def lock(self):
        return subprocess.run(["bash", "-c",
            'source "$LIFECYCLE_HELPER"; acquire_local_lifecycle_lock'],
            env={**os.environ, "PID_DIR": str(self.root / ".pids"),
                 "LIFECYCLE_HELPER": str(ROOT / "scripts/local-lifecycle.sh")},
            capture_output=True, text=True, timeout=5)

    def test_lock_contention_and_release(self):
        with (self.root / ".pids/lifecycle.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.lock()
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("another local start/stop", result.stderr)
            fcntl.flock(lock, fcntl.LOCK_UN)
            self.assertEqual(self.lock().returncode, 0)

    def test_symlink_and_fifo_locks_rejected(self):
        lock = self.root / ".pids/lifecycle.lock"
        lock.symlink_to(self.root / "unrelated")
        self.assertNotEqual(self.lock().returncode, 0)
        self.assertFalse((self.root / "unrelated").exists())
        lock.unlink()
        os.mkfifo(lock)
        self.assertNotEqual(self.lock().returncode, 0)

    def prepare_launcher(self):
        for directory in ("scripts", "config", "bin", "op-stack/sequencer/op-geth", "op-stack/sequencer/op-node"):
            (self.root / directory).mkdir(parents=True, exist_ok=True)
        for name in ("start-devnet.sh", "stop-devnet.sh", "local-lifecycle.sh"):
            shutil.copyfile(ROOT / "scripts" / name, self.root / "scripts" / name)
        # This fixture tests shell orchestration, not RPC or process identity validation.
        for name in ("validate-rollup-config.py", "validate-local-l1.py"):
            (self.root / "scripts" / name).write_text("pass\n")
        (self.root / "scripts/check-local-rpc-ready.py").write_text('''import os, sys
if os.environ.get("FAIL_RPC") and "--rollup-rpc" in sys.argv:
    sys.exit(1)
''')
        (self.root / "scripts/local-process.py").write_text('''import os, sys
from pathlib import Path
root = Path(__file__).resolve().parents[1]
action = sys.argv[1]
component = sys.argv[2] if len(sys.argv) > 2 else "runtime"
with (root / "events").open("a") as log:
    log.write(action + " " + component + "\\n")
if action == "status" and component == os.environ.get("FAIL_COMPONENT"):
    sys.exit(1)
if action == "stop" and component == os.environ.get("FAIL_STOP"):
    sys.exit(1)
''')
        (self.root / "config/local-rollup.env").write_text(
            "L1_RPC_URL=http://127.0.0.1:8545\nL1_BEACON_URL=http://127.0.0.1:5052\n"
            "L1_CHAIN_ID=1337\nL2_CHAIN_ID=901\n")
        for name in ("op-geth/genesis.json", "op-geth/jwt.txt", "op-node/rollup.json"):
            (self.root / "op-stack/sequencer" / name).write_text("{}")
        # Immediate-exit stand-ins; the mocked status helper controls the reported state.
        for name in ("op-geth", "op-node", "sleep"):
            path = self.root / "bin" / name
            path.write_text("#!/bin/sh\nexit 0\n")
            path.chmod(0o700)

    def launch(self, **env):
        return subprocess.run(["bash", str(self.root / "scripts/start-devnet.sh")],
            env={**os.environ, "LOCAL_ROLLUP_PYTHON": sys.executable,
                 "PATH": f"{self.root / 'bin'}:{os.environ['PATH']}", **env},
            capture_output=True, text=True, timeout=10)

    def test_failed_second_node_rolls_back_in_reverse_order(self):
        self.prepare_launcher()
        result = self.launch(FAIL_COMPONENT="op-node")
        self.assertNotEqual(result.returncode, 0)
        events = (self.root / "events").read_text().splitlines()
        self.assertEqual(events[-2:], ["stop op-node", "stop op-geth"])
        self.assertNotIn("Legacy local launcher finished", result.stdout)
        self.assertIn("Startup failed", result.stderr)

    def test_rollback_refusal_is_visible_and_does_not_hide_failure(self):
        self.prepare_launcher()
        result = self.launch(FAIL_COMPONENT="op-node", FAIL_STOP="op-node")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Ownership record retained for review: op-node", result.stderr)
        self.assertEqual((self.root / "events").read_text().splitlines()[-1], "stop op-geth")

    def test_failed_rpc_probe_rolls_back_before_batcher_starts(self):
        self.prepare_launcher()
        result = self.launch(FAIL_RPC="1")
        self.assertNotEqual(result.returncode, 0)
        events = (self.root / "events").read_text().splitlines()
        self.assertEqual(events[-2:], ["stop op-node", "stop op-geth"])
        self.assertNotIn("record op-batcher", events)
        self.assertNotIn("Legacy local launcher finished", result.stdout)

    def test_success_does_not_invoke_rollback(self):
        self.prepare_launcher()
        result = self.launch()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("stop ", (self.root / "events").read_text())

    def test_contending_start_never_records_or_stops_components(self):
        self.prepare_launcher()
        with (self.root / ".pids/lifecycle.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.launch()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.root / "events").read_text(), "check runtime\n")

    def test_contending_stop_never_calls_process_helper(self):
        self.prepare_launcher()
        with (self.root / ".pids/lifecycle.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = subprocess.run(["bash", str(self.root / "scripts/stop-devnet.sh")],
                                    capture_output=True, text=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "events").exists())

    def test_long_lived_children_close_lifecycle_lock_descriptor(self):
        source = (ROOT / "scripts/start-devnet.sh").read_text()
        for component in ("op-geth", "op-node", "op-batcher", "op-proposer"):
            self.assertIn(f'9>&- > "$LOG_DIR/{component}.log" 2>&1 &', source)


if __name__ == "__main__":
    unittest.main()
