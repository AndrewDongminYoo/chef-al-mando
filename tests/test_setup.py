import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="chef-setup-test-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        repo = Path(__file__).resolve().parents[1]
        self.script = repo / "setup.sh"
        self.version = (repo / ".godot-version").read_text().strip()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.bash = shutil.which("bash")
        for tool in ["dirname", "tr", "uname", "bash", "mkdir", "tee", "grep"]:
            (self.bin / tool).symlink_to(shutil.which(tool))
        self.fake(
            "uname",
            'if [[ $1 == -m ]]; then printf "%s\\n" "${TEST_ARCH:-x86_64}"; '
            'else printf "%s\\n" "${TEST_PLATFORM:-Linux}"; fi\n',
        )
        self.fake("python3", "printf 'Python 3.12.0\\n'\n")
        self.fake("fc-match", "printf 'fontconfig version 2.15.0\\n'\n")
        self.fake("godot", f"printf '%s\\n' '{self.version}'\n")

    def fake(self, name, body):
        target = self.bin / name
        if target.exists():
            target.unlink()
        target.write_text(f"#!{self.bash}\n{body}")
        target.chmod(0o700)

    def run_setup(self, **env):
        return subprocess.run(
            [self.bash, str(self.script)],
            env={**os.environ, "PATH": str(self.bin), "GODOT_BIN": "godot", **env},
            capture_output=True,
            text=True,
            timeout=10,
        )

    def test_present_tools_work_twice_without_an_installer(self):
        for _ in range(2):
            result = self.run_setup()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("PASS: hosted container setup", result.stdout)

    def test_wrong_engine_version_fails(self):
        self.fake("godot", "printf 'wrong-version\\n'\n")
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAIL: Godot version must be", result.stderr)

    def test_missing_python_names_the_command_without_a_package_manager(self):
        (self.bin / "python3").unlink()
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAIL: missing command python3", result.stderr)

    def test_installer_success_without_the_requested_command_still_fails(self):
        (self.bin / "python3").unlink()
        self.fake("apt-get", "exit 0\n")
        self.fake("sudo", "exit 0\n")
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAIL: missing command python3 after installing python3", result.stderr)

    def test_missing_downloader_names_curl(self):
        (self.bin / "godot").unlink()
        for tool in ["mktemp", "rm", "install"]:
            (self.bin / tool).symlink_to(shutil.which(tool))
        result = self.run_setup(GODOT_BIN="godot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAIL: missing command curl", result.stderr)

    def test_explicit_missing_engine_is_not_silently_replaced(self):
        result = self.run_setup(GODOT_BIN=str(self.root / "missing-engine"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAIL: GODOT_BIN command is missing", result.stderr)

    def test_non_linux_fails_before_installation(self):
        result = self.run_setup(TEST_PLATFORM="Darwin")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAIL: setup.sh requires Linux", result.stderr)

    def test_missing_engine_on_unsupported_architecture_fails_before_download(self):
        (self.bin / "godot").unlink()
        result = self.run_setup(GODOT_BIN="", TEST_ARCH="aarch64")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("automatic Godot installation requires Linux x86_64", result.stderr)

    @unittest.skipUnless(sys.platform.startswith("linux"), "requires Linux sha256sum --check")
    def test_bad_download_fails_checksum_before_unzip_or_install(self):
        (self.bin / "godot").unlink()
        for tool in ["mktemp", "rm", "install", "sha256sum"]:
            (self.bin / tool).symlink_to(shutil.which(tool))
        self.fake("update-ca-certificates", "exit 0\n")
        self.fake("curl", 'while [[ $1 != --output ]]; do shift; done\nprintf "corrupt archive" > "$2"\n')
        self.fake("unzip", 'echo "UNZIP_CALLED" >&2\nexit 99\n')
        result = self.run_setup(GODOT_BIN="")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAILED", result.stdout)
        self.assertNotIn("UNZIP_CALLED", result.stderr)


if __name__ == "__main__":
    unittest.main()
