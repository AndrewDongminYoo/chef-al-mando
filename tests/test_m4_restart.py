import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest


REPO = Path(__file__).resolve().parents[1]
GODOT_BIN = Path(os.environ.get("GODOT_BIN", "/Applications/Godot.app/Contents/MacOS/Godot"))
FIXTURE = REPO / "tests/check_m4_restart.gd"


def require_fixture(path: Path) -> Path:
    if not path.is_file():
        raise RuntimeError(f"required Godot fixture is missing: {path}")
    return path


def wait_for_marker(process: subprocess.Popen[str], marker: Path, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if marker.is_file():
            return
        if process.poll() is not None:
            output = process.communicate()[0]
            raise RuntimeError(f"writer exited before completion marker: {output}")
        time.sleep(0.02)
    raise TimeoutError(f"writer did not create completion marker: {marker}")


def terminate_owned(process: subprocess.Popen[str]) -> str:
    if process.poll() is None:
        process.terminate()
        try:
            return process.communicate(timeout=5)[0]
        except subprocess.TimeoutExpired:
            process.kill()
    return process.communicate(timeout=5)[0]


def kill_owned(process: subprocess.Popen[str]) -> str:
    if process.poll() is None:
        process.kill()
    return process.communicate(timeout=5)[0]


class RestartCheckTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="chef-m4-restart-")
        self.addCleanup(self.scratch.cleanup)
        self.directory = Path(self.scratch.name)
        self.save_path = self.directory / "campaign_records.json"
        self.settings_path = self.directory / "settings.json"
        self.status_path = self.directory / "status.json"
        self.marker_path = self.directory / "writer-ready.json"

    def command(self, mode: str, *, fixture: Path = FIXTURE) -> list[str]:
        script = require_fixture(fixture)
        return [
            str(GODOT_BIN),
            "--headless",
            "--path",
            str(REPO),
            "--script",
            str(script),
            "--",
            f"--mode={mode}",
            f"--save={self.save_path}",
            f"--settings={self.settings_path}",
            f"--status={self.status_path}",
            f"--marker={self.marker_path}",
        ]

    def run_reader(self, mode: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            self.command(mode),
            cwd=REPO,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=30,
            check=False,
        )

    def start_writer(self, mode: str) -> subprocess.Popen[str]:
        return subprocess.Popen(
            self.command(mode),
            cwd=REPO,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )

    def test_missing_fixture_is_rejected_before_any_engine_process(self):
        with self.assertRaisesRegex(RuntimeError, "required Godot fixture is missing"):
            self.command("writer", fixture=self.directory / "missing.gd")

    def test_missing_marker_is_not_a_success(self):
        process = subprocess.Popen(
            [sys.executable, "-c", "pass"], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
        )
        with self.assertRaisesRegex(RuntimeError, "completion marker"):
            wait_for_marker(process, self.marker_path, timeout=1)

    def test_marker_timeout_is_not_a_success(self):
        process = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(30)"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        try:
            with self.assertRaisesRegex(TimeoutError, "did not create completion marker"):
                wait_for_marker(process, self.marker_path, timeout=0.05)
        finally:
            terminate_owned(process)

    def test_fresh_process_restores_partial_session_and_preferences(self):
        writer = self.start_writer("writer")
        try:
            wait_for_marker(writer, self.marker_path, timeout=30)
        finally:
            writer_output = kill_owned(writer)
        self.assertTrue(self.marker_path.is_file(), writer_output)
        self.assertNotEqual(writer.returncode, 0, writer_output)
        checkpoint = json.loads(self.marker_path.read_text())
        self.assertEqual(checkpoint["kind"], "writer_ready")
        self.assertTrue(checkpoint["partial_movement"])
        self.assertTrue(checkpoint["active_work"])
        self.assertGreater(checkpoint["partial_tick"], 0)
        self.assertLess(checkpoint["partial_tick"], 300)
        self.assertGreater(checkpoint["working_tick"], 0)
        self.assertLess(checkpoint["working_tick"], 300)
        self.assertEqual(checkpoint["saved_partial_hash"], checkpoint["partial_hash"])
        self.assertEqual(checkpoint["saved_working_hash"], checkpoint["working_hash"])
        reader = self.run_reader("reader")
        self.assertEqual(reader.returncode, 0, reader.stdout)
        self.assertIn("PASS: fresh M4 reader preserves checkpoint and final hash", reader.stdout)

    def test_fresh_reader_rejects_a_wrong_saved_working_hash(self):
        writer = self.start_writer("writer")
        try:
            wait_for_marker(writer, self.marker_path, timeout=30)
        finally:
            writer_output = kill_owned(writer)
        self.assertTrue(self.marker_path.is_file(), writer_output)
        status = json.loads(self.status_path.read_text())
        status["working_hash"] = "wrong saved working fixture hash"
        self.status_path.write_text(json.dumps(status))
        reader = self.run_reader("reader")
        self.assertNotEqual(reader.returncode, 0, reader.stdout)
        self.assertIn("FAIL: fresh reader hash differs immediately after restoration", reader.stdout)

    def test_interrupt_before_primary_replacement_preserves_valid_recovery(self):
        writer = self.start_writer("interrupt_writer")
        try:
            wait_for_marker(writer, self.marker_path, timeout=30)
        finally:
            writer_output = kill_owned(writer)
        self.assertTrue(self.marker_path.is_file(), writer_output)
        self.assertNotEqual(writer.returncode, 0, writer_output)
        checkpoint = json.loads(self.marker_path.read_text())
        self.assertEqual(checkpoint["kind"], "replace_boundary")
        reader = self.run_reader("interrupt_reader")
        self.assertEqual(reader.returncode, 0, reader.stdout)
        self.assertIn("PASS: interrupted save keeps only valid primary or backup recovery", reader.stdout)


if __name__ == "__main__":
    unittest.main()
