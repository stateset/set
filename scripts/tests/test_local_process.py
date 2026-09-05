"""Ownership and pidfd regressions using only test-owned temporary processes."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("local_process", ROOT / "scripts/local-process.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
HAS_PIDFD = hasattr(os, "pidfd_open") and hasattr(signal, "pidfd_send_signal")


class LocalProcessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="set-process-test-")
        self.root = Path(self.temp.name)
        (self.root / ".pids").mkdir()
        self.pid_file = self.root / ".pids/op-geth.pid"
        self.pid_file.touch(mode=0o600)
        self.metadata = self.root / ".pids/op-geth.identity.json"
        self.children = []

    def tearDown(self):
        for child in self.children:
            if child.poll() is None:
                child.terminate()
            child.wait(timeout=5)
        self.temp.cleanup()

    def start_child(self):
        binary = self.root / "op-geth"
        shutil.copy2(shutil.which("sleep"), binary)
        child = subprocess.Popen([str(binary), "60"], cwd=self.root)
        self.children.append(child)
        self.pid_file.write_text(str(child.pid))
        MODULE.record(self.root, "op-geth")
        return child

    @unittest.skipUnless(HAS_PIDFD, "Linux Python 3.9+ required for real pidfd coverage")
    def test_matching_process_stopped_through_pidfd(self):
        child = self.start_child()
        with patch.object(MODULE.os, "kill", side_effect=AssertionError("Bare PID signaling forbidden")):
            result = MODULE.stop(self.root, "op-geth")
        self.assertIn("stopped", result)
        self.assertEqual(child.wait(timeout=5), -signal.SIGTERM)
        self.assertFalse(self.pid_file.exists())
        self.assertFalse(self.metadata.exists())

    def test_metadata_has_identity_without_plaintext_arguments(self):
        self.start_child()
        value = json.loads(self.metadata.read_text())
        self.assertIn("start_ticks", value)
        self.assertIn("boot_id", value)
        self.assertEqual(len(value["argv_sha256"]), 64)
        self.assertNotIn("cmdline", value)
        self.assertEqual(self.metadata.stat().st_mode & 0o777, 0o600)

    @unittest.skipUnless(HAS_PIDFD, "Linux Python 3.9+ required for real pidfd coverage")
    def test_running_status_checks_identity_without_signaling(self):
        self.start_child()
        with patch.object(MODULE.signal, "pidfd_send_signal") as send:
            self.assertIn("RPC readiness not checked", MODULE.running(self.root, "op-geth"))
            send.assert_not_called()
        info = json.loads(self.metadata.read_text())
        self.metadata.write_text(json.dumps({**info, "start_ticks": "wrong"}))
        with self.assertRaises(ValueError):
            MODULE.running(self.root, "op-geth")

    @unittest.skipUnless(HAS_PIDFD, "Linux Python 3.9+ required for real pidfd coverage")
    def test_exited_process_never_reports_running(self):
        child = self.start_child()
        child.terminate()
        child.wait(timeout=5)
        with self.assertRaises(ProcessLookupError):
            MODULE.running(self.root, "op-geth")

    @unittest.skipUnless(HAS_PIDFD, "Linux Python 3.9+ required for real pidfd coverage")
    def test_force_stop_uses_same_pidfd_after_grace_period(self):
        child = self.start_child()
        real_send = signal.pidfd_send_signal
        def simulate_ignored_term(fd, sig):
            if sig == signal.SIGKILL:
                real_send(fd, sig)
        with patch.object(MODULE.signal, "pidfd_send_signal", side_effect=simulate_ignored_term) as send:
            MODULE.stop(self.root, "op-geth", grace=0)
        self.assertEqual(child.wait(timeout=5), -signal.SIGKILL)
        self.assertEqual([call.args[1] for call in send.call_args_list], [signal.SIGTERM, signal.SIGKILL])
        self.assertEqual(send.call_args_list[0].args[0], send.call_args_list[1].args[0])

    @unittest.skipUnless(HAS_PIDFD, "Linux Python 3.9+ required for real pidfd coverage")
    def test_failed_signal_keeps_records_and_process(self):
        child = self.start_child()
        with patch.object(MODULE.signal, "pidfd_send_signal", side_effect=PermissionError("denied")):
            with self.assertRaises(PermissionError):
                MODULE.stop(self.root, "op-geth")
        self.assertIsNone(child.poll())
        self.assertTrue(self.pid_file.exists())
        self.assertTrue(self.metadata.exists())

    @unittest.skipUnless(HAS_PIDFD, "Linux Python 3.9+ required for real pidfd coverage")
    def test_changed_identity_never_signals(self):
        child = self.start_child()
        original = json.loads(self.metadata.read_text())
        for field in ("start_ticks", "boot_id", "inode", "argv_sha256", "root", "pid"):
            self.metadata.write_text(json.dumps({**original, field: "different"}))
            with self.subTest(field=field), patch.object(MODULE.signal, "pidfd_send_signal") as send:
                with self.assertRaises(ValueError):
                    MODULE.stop(self.root, "op-geth")
                send.assert_not_called()
            self.assertIsNone(child.poll())
            self.assertTrue(self.pid_file.exists())

    def test_legacy_pid_only_record_never_signals(self):
        child = self.start_child()
        self.metadata.unlink()
        with patch.object(MODULE.signal, "pidfd_send_signal", create=True) as send:
            with self.assertRaises(FileNotFoundError):
                MODULE.stop(self.root, "op-geth")
            send.assert_not_called()
        self.assertIsNone(child.poll())
        self.assertTrue(self.pid_file.exists())

    def test_unrelated_current_process_cannot_be_recorded(self):
        self.pid_file.write_text(str(os.getpid()))
        with self.assertRaises(ValueError):
            MODULE.record(self.root, "op-geth")
        self.assertFalse(self.metadata.exists())

    def test_invalid_pid_values(self):
        for value in ("0", "1", "-1", "-999", "01", "abc", "123\n456", "9" * 30):
            self.pid_file.write_text(value)
            with self.subTest(value=value), self.assertRaises(ValueError):
                MODULE.process_pid(self.pid_file)

    def test_symlink_and_writable_record_refused(self):
        target = self.root / "target"
        target.write_text("123")
        self.pid_file.unlink()
        self.pid_file.symlink_to(target)
        with self.assertRaises(OSError):
            MODULE.process_pid(self.pid_file)
        self.pid_file.unlink()
        self.pid_file.write_text("123")
        self.pid_file.chmod(0o666)
        with self.assertRaises(ValueError):
            MODULE.process_pid(self.pid_file)

    def test_existing_metadata_is_never_overwritten(self):
        self.start_child()
        original = self.metadata.read_text()
        with self.assertRaises(FileExistsError):
            MODULE.record(self.root, "op-geth")
        self.assertEqual(self.metadata.read_text(), original)

    def test_fifo_cannot_block_record_reads(self):
        self.pid_file.unlink()
        os.mkfifo(self.pid_file, mode=0o600)
        with self.assertRaises(ValueError):
            MODULE.process_pid(self.pid_file)

    def test_missing_pidfd_support_never_falls_back_to_kill(self):
        child = self.start_child()
        with patch.object(MODULE.os, "pidfd_open", side_effect=OSError("unsupported"), create=True), \
             patch.object(MODULE.os, "kill") as kill:
            with self.assertRaises(OSError):
                MODULE.stop(self.root, "op-geth")
            kill.assert_not_called()
        self.assertIsNone(child.poll())

    @unittest.skipUnless(HAS_PIDFD, "Linux Python 3.9+ required for real pidfd coverage")
    def test_exited_process_records_retained_for_review(self):
        child = self.start_child()
        child.terminate()
        child.wait(timeout=5)
        with self.assertRaises(ProcessLookupError):
            MODULE.stop(self.root, "op-geth")
        self.assertTrue(self.metadata.exists())
        self.assertTrue(self.pid_file.exists())

    def test_orphaned_metadata_not_silently_ignored(self):
        self.pid_file.unlink()
        self.metadata.write_text("{}")
        with self.assertRaises(ValueError):
            MODULE.stop(self.root, "op-geth")


if __name__ == "__main__":
    unittest.main()
