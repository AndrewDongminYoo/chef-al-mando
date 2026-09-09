import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


REPO = Path(__file__).resolve().parents[1]
GODOT_BIN = Path(os.environ.get("GODOT_BIN", "/Applications/Godot.app/Contents/MacOS/Godot"))
FIXTURE = REPO / "tests/check_m4_restart.gd"


def pack_for_mode(mode: str) -> Path | None:
    writer = os.environ.get("M4_WRITER_PACK", "")
    reader = os.environ.get("M4_READER_PACK", "")
    if bool(writer) != bool(reader):
        raise RuntimeError("both M4_WRITER_PACK and M4_READER_PACK are required")
    for value in [writer, reader]:
        if value and (not Path(value).is_absolute() or not Path(value).is_file()):
            raise RuntimeError(f"required absolute PCK is missing: {value}")
    if writer and hashlib.sha256(Path(writer).read_bytes()).digest() == hashlib.sha256(Path(reader).read_bytes()).digest():
        raise RuntimeError("old and new PCK artifacts must have different SHA-256 hashes")
    return Path(writer if "writer" in mode else reader) if writer else None


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


class VersionProbeTests(unittest.TestCase):
    def test_mismatch_or_failed_probe_stops_before_cross_pack_processes(self):
        with tempfile.TemporaryDirectory(prefix="chef-version-probe-") as folder:
            directory = Path(folder)
            writer = directory / "old.pck"
            reader = directory / "new.pck"
            writer.write_bytes(b"old fixture")
            reader.write_bytes(b"new fixture")
            for version, probe_exit in [("wrong-engine-version", 0), ((REPO / ".godot-version").read_text().strip(), 2)]:
                with self.subTest(version=version, probe_exit=probe_exit):
                    calls = directory / "calls.jsonl"
                    calls.write_text("")
                    engine = directory / "godot"
                    engine.write_text(
                        f"#!{sys.executable}\nimport json, sys\nfrom pathlib import Path\n"
                        f"with Path({str(calls)!r}).open('a') as log: log.write(json.dumps(sys.argv[1:]) + '\\n')\n"
                        f"print({version!r})\nsys.exit({probe_exit})\n"
                    )
                    engine.chmod(0o700)
                    result = subprocess.run(
                        [sys.executable, str(Path(__file__).resolve()), "RestartCheckTests.test_fresh_process_restores_partial_session_and_preferences"],
                        env=dict(os.environ, GODOT_BIN=str(engine), M4_WRITER_PACK=str(writer), M4_READER_PACK=str(reader)),
                        capture_output=True,
                        text=True,
                        timeout=15,
                    )
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("Godot version must be", result.stdout + result.stderr)
                    self.assertEqual([json.loads(line) for line in calls.read_text().splitlines()], [["--headless", "--version"]])


class RestartCheckTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        expected = (REPO / ".godot-version").read_text().strip()
        probe = subprocess.run([str(GODOT_BIN), "--headless", "--version"], capture_output=True, text=True, timeout=10)
        if probe.returncode != 0 or probe.stdout.strip() != expected:
            raise RuntimeError(f"Godot version must be {expected} (found {probe.stdout.strip()!r}, exit {probe.returncode})")

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
        pack = pack_for_mode(mode)
        runtime = self.directory / "runtime"
        runtime.mkdir(exist_ok=True)
        return [
            str(GODOT_BIN),
            "--headless",
            "--path",
            str(runtime if pack else REPO),
            *(["--main-pack", str(pack)] if pack else []),
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

    def test_incomplete_or_missing_pack_pair_is_rejected(self):
        for writer, reader, message in [
            ("/old.pck", "", "both M4_WRITER_PACK"),
            ("", "/new.pck", "both M4_WRITER_PACK"),
            (str(self.directory / "absent.pck"), str(self.directory / "absent.pck"), "required absolute PCK is missing"),
        ]:
            with self.subTest(writer=writer, reader=reader):
                with patch.dict(os.environ, M4_WRITER_PACK=writer, M4_READER_PACK=reader):
                    with self.assertRaisesRegex(RuntimeError, message):
                        self.command("writer")

    def test_pack_pair_routes_each_process_without_source_fallback(self):
        writer = self.directory / "old.pck"
        reader = self.directory / "new.pck"
        writer.write_bytes(b"writer fixture")
        reader.write_bytes(b"reader fixture")
        with patch.dict(os.environ, M4_WRITER_PACK=str(writer), M4_READER_PACK=str(reader)):
            for mode, expected in [("writer", writer), ("reader", reader), ("interrupt_writer", writer), ("interrupt_reader", reader)]:
                command = self.command(mode)
                self.assertEqual(command[command.index("--main-pack") + 1], str(expected))
                self.assertEqual(command[command.index("--path") + 1], str(self.directory / "runtime"))
                self.assertIn("--headless", command)

    def test_identical_pack_artifacts_are_rejected(self):
        writer = self.directory / "old.pck"
        copy = self.directory / "copy.pck"
        writer.write_bytes(b"same artifact")
        copy.write_bytes(writer.read_bytes())
        for reader in [writer, copy]:
            with patch.dict(os.environ, M4_WRITER_PACK=str(writer), M4_READER_PACK=str(reader)):
                with self.assertRaisesRegex(RuntimeError, "must have different SHA-256 hashes"):
                    self.command("writer")

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
