"""Exercise actual launch scripts with fake executables, never real containers."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class AnvilLaunchTests(unittest.TestCase):
    def launch(self, docker=False, failure=False, fallback=False):
        with tempfile.TemporaryDirectory(prefix="set-launch-test-") as directory:
            temp = Path(directory)
            calls = temp / "calls"
            binary_dir = temp / "foundry" if fallback else temp
            binary_dir.mkdir(exist_ok=True)
            for name in ("anvil", "docker"):
                executable = (binary_dir if name == "anvil" else temp) / name
                executable.write_text("#!/usr/bin/env python3\n"
                    "import json, os, sys\n"
                    "from pathlib import Path\n"
                    "if sys.argv[1:] == ['--version']:\n"
                    " print('anvil Version: 1.8.1'); sys.exit(0)\n"
                    "with open(os.environ['TEST_CALLS'], 'a') as log:\n"
                    " log.write(json.dumps([Path(sys.argv[0]).name, *sys.argv[1:]]) + '\\n')\n"
                    "sys.exit(int(os.environ['TEST_EXIT']))\n")
                executable.chmod(0o755)
            # A broken PATH anvil forces discovery of the configured binary.
            if fallback:
                bad = temp / "anvil"
                bad.write_text("#!/bin/sh\nexit 1\n")
                bad.chmod(0o755)
            result = subprocess.run(["bash", str(ROOT / "scripts/start-local-anvil.sh")],
                env={**os.environ, "PATH": f"{temp}:{os.environ['PATH']}",
                     "FOUNDRY_USE_DOCKER": "1" if docker else "0",
                     "FOUNDRY_BIN_DIR": str(binary_dir), "TEST_CALLS": str(calls),
                     "TEST_EXIT": "19" if failure else "0"},
                capture_output=True, text=True, timeout=15)
            return result, [json.loads(line) for line in calls.read_text().splitlines()]

    def test_host_binds_only_loopback(self):
        result, calls = self.launch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][0], "anvil")
        self.assertEqual(calls[0][calls[0].index("--host") + 1], "127.0.0.1")

    def test_resolved_host_binary_is_executed(self):
        result, calls = self.launch(fallback=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[0][0], "anvil")

    def test_docker_publishes_only_loopback_without_stopping_existing_nodes(self):
        result, calls = self.launch(docker=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 1)  # No docker ps/down/rm before run.
        self.assertEqual(calls[0][:2], ["docker", "run"])
        self.assertEqual(calls[0][calls[0].index("-p") + 1], "127.0.0.1:8545:8545")

    def test_name_or_port_conflict_is_not_retried_or_cleaned_up(self):
        for docker in (False, True):
            with self.subTest(docker=docker):
                result, calls = self.launch(docker=docker, failure=True)
                self.assertEqual(result.returncode, 19)
                self.assertEqual(len(calls), 1)


@unittest.skipUnless(shutil.which("docker"), "Docker Compose required")
class LocalComposeTests(unittest.TestCase):
    def config(self, project=None):
        command = ["docker", "compose", "-f", str(ROOT / "docker/docker-compose.local.yml")]
        if project:
            command += ["-p", project]
        result = subprocess.run(command + ["config", "--no-interpolate", "--format", "json"],
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_private_rpc_and_engine(self):
        config = self.config()
        geth = config["services"]["op-geth"]
        self.assertEqual({port["target"] for port in geth["ports"]}, {8547, 8548})
        self.assertTrue(all(port["host_ip"] == "127.0.0.1" for port in geth["ports"]))
        for flag in geth["command"]:
            if flag.startswith(("--http.api=", "--ws.api=")):
                self.assertEqual(set(flag.split("=", 1)[1].split(",")), {"eth", "net", "web3"})
            if flag.startswith(("--http.corsdomain=", "--http.vhosts=", "--ws.origins=", "--authrpc.vhosts=")):
                self.assertNotIn("*", flag)

    def test_resources_are_project_scoped(self):
        for project in (None, "set-isolation-test"):
            with self.subTest(project=project):
                config = self.config(project)
                expected = project or "set-local-execution"
                self.assertEqual(config["name"], expected)
                self.assertTrue(all("container_name" not in service for service in config["services"].values()))
                for resource in ("volumes", "networks"):
                    self.assertTrue(all(value["name"].startswith(expected + "_")
                                        for value in config[resource].values()))

    def test_genesis_initialization_failure_propagates(self):
        command = self.config()["services"]["op-geth-init"]["command"][0]
        # Redirect the existence check to a test-owned nonexistent path.
        with tempfile.TemporaryDirectory(prefix="set-init-test-") as directory:
            temp = Path(directory)
            geth = temp / "geth"
            geth.write_text("#!/bin/sh\nexit 23\n")
            geth.chmod(0o755)
            command = command.replace("/data/geth/chaindata/CURRENT", str(temp / "missing"))
            result = subprocess.run(["sh", "-c", command], capture_output=True, text=True,
                                    env={**os.environ, "PATH": f"{temp}:{os.environ['PATH']}"}, timeout=10)
            self.assertEqual(result.returncode, 23)
            self.assertNotIn("Initialization complete", result.stdout)


if __name__ == "__main__":
    unittest.main()
