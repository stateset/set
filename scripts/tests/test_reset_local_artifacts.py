"""Reset tests only touch temporary fixtures, never repository build artifacts."""
from contextlib import ExitStack
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("reset_artifacts", ROOT / "scripts/reset-local-artifacts.py")
RESET = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RESET)
CHAIN = "84532001"


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="set-reset-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.paths = ("contracts/cache", "contracts/out", f"contracts/broadcast/Deploy.s.sol/{CHAIN}")
        for name in (*self.paths, "contracts/broadcast/Deploy.s.sol/11155111"):
            directory = self.root / name
            directory.mkdir(parents=True)
            (directory / "evidence.json").write_text(name)

    def assert_intact(self):
        for name in self.paths:
            self.assertEqual((self.root / name / "evidence.json").read_text(), name)

    def test_moves_only_build_outputs_and_configured_chain_with_journal(self):
        archive = RESET.archive_artifacts(self.root, CHAIN)
        for name in self.paths:
            self.assertFalse((self.root / name).exists())
            self.assertEqual((archive / name / "evidence.json").read_text(), name)
        self.assertTrue((self.root / "contracts/broadcast/Deploy.s.sol/11155111/evidence.json").exists())
        journal = [json.loads(line) for line in (archive / "manifest.jsonl").read_text().splitlines()]
        self.assertEqual({row["source"] for row in journal}, set(self.paths))
        # Restoring an archived directory requires only a rename, not reconstruction.
        original = self.root / self.paths[0]
        os.rename(archive / self.paths[0], original)
        self.assertTrue((original / "evidence.json").exists())

    def test_empty_second_reset_does_not_create_another_archive(self):
        archive = RESET.archive_artifacts(self.root, CHAIN)
        self.assertIsNone(RESET.archive_artifacts(self.root, CHAIN))
        self.assertEqual(list(archive.parent.iterdir()), [archive])

    def test_invalid_chain_ids_never_move_artifacts(self):
        for chain in ("", ".", "..", "../out", "/tmp", "01", "-1", "1\n", str(2**64)):
            with self.subTest(chain=chain):
                with self.assertRaises(ValueError):
                    RESET.archive_artifacts(self.root, chain)
                self.assert_intact()
        self.assertFalse((self.root / ".devnet-reset-archive").exists())

    def test_symlinked_paths_are_rejected_before_any_moves(self):
        for name in ("contracts", "contracts/out", "contracts/broadcast",
                     "contracts/broadcast/Deploy.s.sol", self.paths[2]):
            with self.subTest(name=name):
                source = self.root / name
                saved = self.root / "saved"
                source.rename(saved)
                source.symlink_to(saved, target_is_directory=True)
                try:
                    with self.assertRaises(ValueError):
                        RESET.archive_artifacts(self.root, CHAIN)
                finally:
                    source.unlink()
                    saved.rename(source)
                self.assert_intact()

    def test_archive_symlink_is_rejected(self):
        (self.root / ".devnet-reset-archive").symlink_to(self.root / "contracts")
        with self.assertRaises(ValueError):
            RESET.archive_artifacts(self.root, CHAIN)
        self.assert_intact()

    def test_writable_by_others_archive_is_rejected(self):
        archive = self.root / ".devnet-reset-archive"
        archive.mkdir()
        archive.chmod(0o777)
        with self.assertRaises(ValueError):
            RESET.archive_artifacts(self.root, CHAIN)
        self.assert_intact()

    def test_fifo_source_is_rejected_without_blocking(self):
        cache = self.root / self.paths[0]
        cache.rename(self.root / "saved")
        os.mkfifo(cache)
        with self.assertRaises(ValueError):
            RESET.archive_artifacts(self.root, CHAIN)
        self.assertTrue((self.root / self.paths[1] / "evidence.json").exists())

    def test_nested_symlink_is_moved_not_followed(self):
        outside = self.root / "outside"
        outside.write_text("untouched")
        (self.root / "contracts/out/link").symlink_to(outside)
        archive = RESET.archive_artifacts(self.root, CHAIN)
        self.assertTrue((archive / "contracts/out/link").is_symlink())
        self.assertEqual(outside.read_text(), "untouched")

    def test_partial_failure_retains_journal_and_all_data(self):
        rename = os.rename
        attempts = []
        def fail_second(source, destination):
            attempts.append(source)
            if len(attempts) == 2:
                raise OSError("simulated disk failure")
            rename(source, destination)
        with patch.object(RESET.os, "rename", side_effect=fail_second):
            with self.assertRaisesRegex(RuntimeError, "Reset incomplete"):
                RESET.archive_artifacts(self.root, CHAIN)
        archive = next((self.root / ".devnet-reset-archive").iterdir())
        self.assertEqual(len((archive / "manifest.jsonl").read_text().splitlines()), 2)
        for name in self.paths:
            copies = [path for path in (self.root / name, archive / name) if path.exists()]
            self.assertEqual(len(copies), 1)
            self.assertEqual((copies[0] / "evidence.json").read_text(), name)

    def test_mount_point_rejected_before_moves(self):
        with patch.object(RESET.os.path, "ismount", return_value=True):
            with self.assertRaises(ValueError):
                RESET.archive_artifacts(self.root, CHAIN)
        self.assert_intact()

    def test_main_does_not_restart_after_archive_failure(self):
        with patch.object(sys, "argv", ["reset", "--chain-id", CHAIN]), \
             patch.object(RESET, "reserve_rpc_port"), \
             patch.object(RESET, "archive_artifacts", side_effect=ValueError("unsafe path")), \
             patch.object(RESET.os, "execv") as start:
            self.assertEqual(RESET.main(), 1)
            start.assert_not_called()
        self.assert_intact()


class ResetPortTests(unittest.TestCase):
    def test_busy_port_refuses_reset_without_disrupting_listener(self):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            port = listener.getsockname()[1]
            with ExitStack() as stack:
                with self.assertRaisesRegex(RuntimeError, "stop the intended node"):
                    RESET.reserve_rpc_port(stack, port)
            with socket.create_connection(("127.0.0.1", port), timeout=1) as client:
                connection, _ = listener.accept()
                connection.close()

    def test_reservation_blocks_competing_start_until_released(self):
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        with ExitStack() as stack:
            RESET.reserve_rpc_port(stack, port)
            with socket.socket() as competitor:
                with self.assertRaises(OSError):
                    competitor.bind(("127.0.0.1", port))
        with socket.socket() as competitor:
            competitor.bind(("127.0.0.1", port))


class ResetShellTests(unittest.TestCase):
    def test_force_no_start_only_invokes_archive_helper(self):
        with tempfile.TemporaryDirectory(prefix="set-reset-shell-") as directory:
            root = Path(directory)
            for name in ("scripts", "config", "bin"):
                (root / name).mkdir()
            (root / "scripts/reset-devnet.sh").write_text((ROOT / "scripts/reset-devnet.sh").read_text())
            (root / "config/chain-config.toml").write_text("[chain]\nchain_id = 84532001\n")
            log = root / "calls"
            for tool in ("docker", "lsof", "pgrep", "kill", "rm", "find", "python3"):
                executable = root / "bin" / tool
                executable.write_text("#!/bin/sh\nprintf '%s\\n' \"$0 $*\" >> \"$TEST_CALLS\"\n")
                executable.chmod(0o755)
            result = subprocess.run(["bash", str(root / "scripts/reset-devnet.sh"), "--force", "--no-start"],
                env={**os.environ, "PATH": f"{root / 'bin'}:{os.environ['PATH']}",
                     "LOCAL_RESET_PYTHON": str(root / "bin/python3"), "TEST_CALLS": str(log)},
                capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = log.read_text().splitlines()
            self.assertEqual(len(calls), 1)
            self.assertIn("reset-local-artifacts.py --chain-id 84532001 --no-start", calls[0])


if __name__ == "__main__":
    unittest.main()
