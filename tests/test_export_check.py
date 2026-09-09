import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


FAKE_ENGINE = """import os
from pathlib import Path
import sys

args = sys.argv[1:]
if "--version" in args:
    print(os.environ["TEST_ENGINE_VERSION"])
    Path(os.environ["TEST_VERSION_LOG"]).write_text(" ".join(args))
elif "--export-pack" in args:
    case = os.environ["TEST_EXPORT_CASE"]
    if case == "exit_failure":
        sys.exit(2)
    if case != "missing":
        Path(args[-1]).write_bytes(b"fresh pack")
    if case in ["ERROR:", "SCRIPT ERROR:"]:
        print(case + " injected export failure")
else:
    pack = Path(args[args.index("--main-pack") + 1])
    print("RUNTIME_PACK=" + str(pack))
    if pack.read_bytes() == b"invalid pack":
        print("ERROR: injected runtime failure")
    else:
        print("PASS: exported M1 content and first order")
        print("PASS: exported M2 preparation and first order")
        print("PASS: exported M2 extra menu prepared and served")
        if os.environ["TEST_EXPORT_CASE"] != "missing_m3":
            print("PASS: exported M3 campaign and first served order")
        if os.environ["TEST_EXPORT_CASE"] != "missing_m4_core":
            print("PASS: exported M4 storage core")
        if os.environ["TEST_EXPORT_CASE"] != "missing_m4":
            print("PASS: exported M4 resume and localization")
"""


class ExportCheckTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="chef-export-test-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        repo = Path(__file__).resolve().parents[1]
        (self.root / "scripts").mkdir()
        (self.root / "build/check").mkdir(parents=True)
        self.script = self.root / "scripts/check-export.sh"
        shutil.copy2(repo / "scripts/check-export.sh", self.script)
        shutil.copy2(repo / ".godot-version", self.root / ".godot-version")
        self.engine = self.root / "godot"
        self.engine.write_text(f"#!{sys.executable}\n{FAKE_ENGINE}")
        self.engine.chmod(0o700)
        self.stale = self.root / "build/check/m1.pck"
        self.version_log = self.root / "version-args.txt"

    def run_check(self, case="success", pack=None):
        return subprocess.run(
            ["bash", str(self.script), *([str(pack)] if pack else [])],
            env=dict(
                os.environ,
                GODOT_BIN=str(self.engine),
                TEST_ENGINE_VERSION=(self.root / ".godot-version").read_text().strip(),
                TEST_EXPORT_CASE=case,
                TEST_VERSION_LOG=str(self.version_log),
            ),
            capture_output=True,
            text=True,
            timeout=10,
        )

    def test_export_errors_stop_before_runtime_even_with_output(self):
        self.stale.write_bytes(b"old valid pack")
        for case in ["ERROR:", "SCRIPT ERROR:"]:
            with self.subTest(case=case):
                result = self.run_check(case)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("FAIL: pack export failed", result.stderr)
                self.assertNotIn("RUNTIME_PACK=", result.stdout)

    def test_missing_output_cannot_reuse_an_old_pack(self):
        for has_stale in [False, True]:
            with self.subTest(has_stale=has_stale):
                if has_stale:
                    self.stale.write_bytes(b"old valid pack")
                result = self.run_check("missing")
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("FAIL: exported pack is missing", result.stderr)
                self.assertNotIn("RUNTIME_PACK=", result.stdout)

    def test_missing_m3_completion_marker_fails(self):
        result = self.run_check("missing_m3")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("completion marker is missing", result.stderr)

    def test_missing_m4_core_completion_marker_fails(self):
        result = self.run_check("missing_m4_core")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("completion marker is missing", result.stderr)

    def test_missing_m4_completion_marker_fails(self):
        result = self.run_check("missing_m4")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("completion marker is missing", result.stderr)

    def test_version_probe_is_headless(self):
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.version_log.read_text(), "--headless --version")

    def test_nonzero_export_exit_stops_before_runtime(self):
        self.stale.write_bytes(b"old valid pack")
        result = self.run_check("exit_failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("RUNTIME_PACK=", result.stdout)

    def test_success_checks_a_fresh_pack_and_removes_it(self):
        self.stale.write_bytes(b"old valid pack")
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        runtime = next(line for line in result.stdout.splitlines() if line.startswith("RUNTIME_PACK="))
        checked_pack = Path(runtime.removeprefix("RUNTIME_PACK="))
        self.assertNotEqual(checked_pack, self.stale)
        self.assertFalse(checked_pack.exists())
        self.assertEqual(self.stale.read_bytes(), b"old valid pack")

    def test_explicit_pack_is_checked_without_export_or_removal(self):
        supplied = self.root / "external.pck"
        supplied.write_bytes(b"valid supplied pack")
        result = self.run_check("exit_failure", supplied)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("RUNTIME_PACK=" + str(supplied), result.stdout)
        self.assertEqual(supplied.read_bytes(), b"valid supplied pack")
        supplied.write_bytes(b"invalid pack")
        result = self.run_check("exit_failure", supplied)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAIL: exported runtime check failed", result.stderr)


if __name__ == "__main__":
    unittest.main()
