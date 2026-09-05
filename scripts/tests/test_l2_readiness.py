"""Offline regression tests: no chain connections or deployment credentials."""
import json
import copy
import importlib.util
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("rollup_validator", ROOT / "scripts/validate-rollup-config.py")
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


class SettlementTests(unittest.TestCase):
    def check(self, scenario, expected=0, address=None):
        with tempfile.TemporaryDirectory(prefix="set-settlement-test-") as directory:
            temp = Path(directory)
            # Stub the transport, exercising the actual shell validator and jq.
            curl = temp / "curl"
            curl.write_text("""#!/usr/bin/env python3
import json, os, sys
request = json.loads(sys.argv[sys.argv.index('-d') + 1])
scenario = os.environ['RPC_SCENARIO']
if scenario == 'transport': sys.exit(7)
if scenario == 'malformed': print('not json'); sys.exit(0)
if request['method'] == 'eth_chainId':
    result = '0x1' if scenario == 'wrong_chain' else '0x539'
else:
    result = {'empty':'0x', 'null':None, 'odd':'0x123',
              'nonhex':'0xzz', 'object':{}}.get(scenario, '0x60006000')
response = {'jsonrpc':'2.0', 'id':1, 'result':result}
if scenario == 'rpc_error': response = {'jsonrpc':'2.0','id':1,'error':{'code':-32000}}
if scenario == 'wrong_id': response['id'] = 2
print(json.dumps(response))
""")
            curl.chmod(0o755)
            env_file = temp / "test.env"
            contract = address or "0x1111111111111111111111111111111111111111"
            env_file.write_text("L1_RPC_URL=http://offline.invalid\nL1_CHAIN_ID=1337\n" +
                "\n".join(f"{key}={contract}" for key in (
                    "OPTIMISM_PORTAL_ADDRESS", "L2_OUTPUT_ORACLE_ADDRESS",
                    "SYSTEM_CONFIG_ADDRESS", "DISPUTE_GAME_FACTORY_ADDRESS")))
            result = subprocess.run([
                "bash", str(ROOT / "scripts/check-l1-settlement.sh"),
                "--env-file", str(env_file), "--require-addresses"],
                env={**os.environ, "PATH":f"{temp}:{os.environ['PATH']}",
                     "RPC_SCENARIO":scenario}, capture_output=True, text=True,
                timeout=10)
            if expected == 0:
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            else:
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_valid_bytecode_and_network(self):
        self.check("valid")

    def test_errors_fail_closed(self):
        for scenario in ("transport", "malformed", "wrong_chain", "empty",
                         "null", "odd", "nonhex", "object", "rpc_error", "wrong_id"):
            with self.subTest(scenario=scenario):
                self.check(scenario, expected=1)

    def test_invalid_address(self):
        self.check("valid", expected=1, address="not-an-address")


class RollupConfigTests(unittest.TestCase):
    def setUp(self):
        address = "0x" + "11" * 20
        self.genesis = {"config": {"chainId": 84532001}, "timestamp": "0x64",
                        "gasLimit": "0x1c9c380", "alloc": {address: {"balance": "0x1"}}}
        self.rollup = {"l1_chain_id": 1337, "l2_chain_id": 84532001,
                       "block_time": 2, "max_sequencer_drift": 600,
                       "seq_window_size": 3600, "channel_timeout": 300,
                       "batch_inbox_address": address, "deposit_contract_address": address,
                       "l1_system_config_address": address,
                       "genesis": {"l2_time": 100,
                           "l1": {"hash": "0x" + "22" * 32, "number": 0},
                           "l2": {"hash": "0x" + "33" * 32, "number": 0},
                           "system_config": {"batcherAddr": address, "gasLimit": 30000000}}}

    def test_consistent_artifacts(self):
        self.assertEqual(VALIDATOR.validate(self.genesis, self.rollup, 1337, 84532001), [])

    def test_wrong_network_and_missing_fields(self):
        for key, value in (("l1_chain_id", 1), ("l2_chain_id", 10),
                           ("deposit_contract_address", "0x" + "00" * 20),
                           ("block_time", 0), ("channel_timeout", True),
                           ("genesis", {})):
            with self.subTest(key=key):
                rollup = copy.deepcopy(self.rollup)
                rollup[key] = value
                self.assertTrue(VALIDATOR.validate(self.genesis, rollup, 1337, 84532001))

    def test_genesis_drift(self):
        for key, value in (("timestamp", "0x65"), ("gasLimit", "0x1"),
                           ("alloc", {}), ("config", {"chainId": 10})):
            with self.subTest(key=key):
                genesis = copy.deepcopy(self.genesis)
                genesis[key] = value
                self.assertTrue(VALIDATOR.validate(genesis, self.rollup, 1337, 84532001))


class OperationalConfigTests(unittest.TestCase):
    def run_config(self, updates, mode="testnet"):
        address = "0x" + "11" * 20
        values = {key: address for key in (
            "ADMIN_ADDRESS", "DEPLOYER_ADDRESS", "SEQUENCER_ADDRESS", "BATCHER_ADDRESS",
            "PROPOSER_ADDRESS", "CHALLENGER_ADDRESS", "DISPUTE_GAME_FACTORY_ADDRESS",
            "UPGRADE_MULTISIG_ADDRESS", "UPGRADE_TIMELOCK_ADDRESS", "PAUSE_GUARDIAN_ADDRESS")}
        values.update({key: "0x" + "22" * 32 for key in (
            "DEPLOYER_PRIVATE_KEY", "SEQUENCER_PRIVATE_KEY", "BATCHER_PRIVATE_KEY",
            "PROPOSER_PRIVATE_KEY", "CHALLENGER_PRIVATE_KEY")})
        values.update({"L1_RPC_URL": "http://offline.invalid", "L1_BEACON_URL": "http://offline.invalid",
                       "L2_RPC_URL": "http://offline.invalid", "JWT_SECRET": "33" * 32,
                       "UPGRADE_TIMELOCK_DELAY_SECS": "86400"})
        values.update(updates)
        with tempfile.TemporaryDirectory(prefix="set-ops-test-") as directory:
            config = Path(directory) / "test.env"
            config.write_text("\n".join(f"{key}={value}" for key, value in values.items()))
            return subprocess.run(["bash", str(ROOT / "scripts/validate-ops-config.sh"),
                "--env-file", str(config), "--mode", mode, "--require-admin-policy"],
                capture_output=True, text=True, timeout=10)

    def test_valid_testnet_policy(self):
        result = self.run_config({})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_rejects_malformed_policy(self):
        for key, value in (("ADMIN_ADDRESS", "invalid"), ("JWT_SECRET", "short"),
                           ("BATCHER_PRIVATE_KEY", "invalid"),
                           ("UPGRADE_TIMELOCK_DELAY_SECS", "zero"),
                           ("UPGRADE_TIMELOCK_DELAY_SECS", "1"),
                           ("UPGRADE_TIMELOCK_DELAY_SECS", "9999999"),
                           ("ADMIN_ADDRESS", "0x" + "44" * 20)):
            with self.subTest(key=key, value=value):
                self.assertNotEqual(self.run_config({key: value}).returncode, 0)

    def test_production_requires_fault_proofs_without_optional_flag(self):
        result = self.run_config({"DISPUTE_GAME_FACTORY_ADDRESS": ""}, mode="production")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Dispute game factory", result.stdout)


class FaultProofWalkthroughTests(unittest.TestCase):
    def test_walkthrough_cannot_certify_a_dispute(self):
        with tempfile.TemporaryDirectory(prefix="set-fault-test-") as directory:
            cast = Path(directory) / "cast"
            cast.write_text("#!/bin/sh\nprintf '0\\n'\n")
            cast.chmod(0o755)
            env = {**os.environ, "PATH":f"{directory}:{os.environ['PATH']}",
                   "L1_RPC_URL":"http://offline.invalid", "L2_RPC_URL":"http://offline.invalid",
                   "DISPUTE_GAME_FACTORY":"0x" + "11" * 20, "CHALLENGER_KEY":"synthetic"}
            for command in ("exercise", "create"):
                with self.subTest(command=command):
                    result = subprocess.run(["bash", str(ROOT / "scripts/fault-proof-exercise.sh"), command],
                                            env=env, capture_output=True, text=True, timeout=10)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn("Exercise Complete", result.stdout)


@unittest.skipUnless(shutil.which("docker"), "Docker Compose required for configuration checks")
class ComposeTests(unittest.TestCase):
    def test_private_rpc_and_generated_artifact_mounts(self):
        result = subprocess.run(["docker", "compose", "-f",
            str(ROOT / "docker/docker-compose.sepolia.yml"), "config", "--no-interpolate",
            "--format", "json"], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        services = json.loads(result.stdout)["services"]
        geth = services["op-geth"]
        node = services["op-node"]
        for service in (geth, node):
            for port in service.get("ports", []):
                self.assertEqual(port["host_ip"], "127.0.0.1")
                self.assertNotEqual(port["target"], 8551)
        for flag in geth["command"]:
            if flag.startswith(("--http.api=", "--ws.api=")):
                self.assertFalse({"debug", "engine", "admin", "personal"} & set(flag.split("=")[1].split(",")))
        self.assertIn("--sequencer.l1-confs=4", node["command"])
        self.assertIn("--verifier.l1-confs=4", node["command"])
        rollup_path = next(flag.split("=", 1)[1] for flag in node["command"] if flag.startswith("--rollup.config="))
        mount = next(volume for volume in node["volumes"] if volume["target"] == str(Path(rollup_path).parent))
        self.assertEqual(Path(mount["source"]), ROOT / "op-stack/sequencer/op-node")
        data = next(volume for volume in geth["volumes"] if volume["target"] == "/data")
        self.assertEqual(Path(data["source"]), ROOT / "op-stack/sequencer/op-geth/data")


if __name__ == "__main__":
    unittest.main()
