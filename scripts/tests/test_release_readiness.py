"""Release checks must reject failed scanners and malformed dependency metadata."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(all(shutil.which(tool) for tool in ("git", "node", "rg")), "git, node and rg required")
class ReleaseReadinessTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="set-release-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for path in ("scripts", "sdk", "anchor", ".github/workflows", "contracts/lib/example"):
            (self.root / path).mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / "scripts/check-release-readiness.sh", self.root / "scripts/check-release-readiness.sh")
        (self.root / "sdk/package.json").write_text('{"version":"1.2.3"}')
        (self.root / "anchor/Cargo.toml").write_text('version = "0.2.5"\n')
        self.workflow = self.root / ".github/workflows/test.yml"
        self.workflow.write_text("jobs:\n  test:\n    runs-on: ubuntu-24.04\n    steps:\n"
                                 "      - uses: actions/checkout@" + "a" * 40 + "\n")
        dependency = self.root / "contracts/lib/example"
        self.git("init", "-q", cwd=dependency)
        (dependency / "example").write_text("fixture\n")
        self.git("add", "example", cwd=dependency)
        self.git("-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                 "commit", "-qm", "fixture", cwd=dependency)
        revision = self.git("rev-parse", "HEAD", cwd=dependency).stdout.strip()
        self.lock = self.root / "contracts/foundry.lock"
        self.lock.write_text(json.dumps({"lib/example": {"rev": revision}}))
        self.git("init", "-q")
        self.git("add", ".")

    def git(self, *args, cwd=None):
        return subprocess.run(["git", *args], cwd=cwd or self.root, check=True,
                              capture_output=True, text=True, timeout=10)

    def check(self, env=None):
        result = subprocess.run(["/bin/bash", str(self.root / "scripts/check-release-readiness.sh")],
                                env={**os.environ, "GITHUB_REF_NAME": "", **(env or {})},
                                capture_output=True, text=True, timeout=15)
        return result

    def reject(self, env=None):
        result = self.check(env)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("release metadata verified", result.stdout)
        return result

    def test_valid_fixture(self):
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("release metadata verified", result.stdout)

    def test_missing_scanner_fails(self):
        path = self.root / "tools"
        path.mkdir()
        for tool in ("dirname", "node", "sed", "head", "git"):
            (path / tool).symlink_to(shutil.which(tool))
        result = self.reject({"PATH": str(path)})
        self.assertIn("requires rg", result.stderr)

    def test_scanner_runtime_failure_fails(self):
        path = self.root / "tools"
        path.mkdir()
        scanner = path / "rg"
        scanner.write_text("#!/bin/sh\nexit 2\n")
        scanner.chmod(0o755)
        result = self.reject({"PATH": f"{path}:{os.environ['PATH']}"})
        self.assertIn("scanner failed", result.stderr)

    def test_malformed_or_empty_dependency_lock_fails(self):
        for value in ("not-json", "{}", "[]", "null", '{"lib/example":{"rev":"bad"}}',
                      '{"../outside":{"rev":"' + "a" * 40 + '"}}'):
            with self.subTest(value=value):
                self.lock.write_text(value)
                self.reject()

    def test_tracked_secret_fails(self):
        (self.root / ".env").write_text("TEST_ONLY=fixture\n")
        self.git("add", ".env")
        result = self.reject()
        self.assertIn("tracked runtime secret", result.stderr)

    def test_mutable_action_pin_fails(self):
        for ref in ("main", "v4", "v4.2.0", "release-candidate", "refs/tags/v4.2.0", "a" * 39):
            with self.subTest(ref=ref):
                self.workflow.write_text("uses: actions/checkout@" + ref + "\n")
                self.assertIn("immutable commit SHAs", self.reject().stderr)

    def test_quoted_sha_pin_is_accepted(self):
        for quote in ("'", '"'):
            with self.subTest(quote=quote):
                self.workflow.write_text("uses: " + quote + "actions/checkout@" + "a" * 40 + quote + " # pin\n")
                result = self.check()
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_floating_runner_fails(self):
        self.workflow.write_text("runs-on: ubuntu-latest\n")
        self.assertIn("pin the runner", self.reject().stderr)

    def test_missing_workflow_directory_fails(self):
        self.workflow.rename(self.root / "workflow-backup")
        self.workflow.parent.rmdir()
        self.assertIn("scanner failed", self.reject().stderr)


if __name__ == "__main__":
    unittest.main()
