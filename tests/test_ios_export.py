import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest


FAKE_ENGINE = r'''import os
from pathlib import Path
import plistlib
import sys

args = sys.argv[1:]
if "--version" in args:
    print(os.environ["TEST_ENGINE_VERSION"])
elif "--export-debug" in args:
    project = Path(args[-1])
    name = project.stem
    application = project.parent / name
    localized = application / "en.lproj"
    localized.mkdir(parents=True)
    with (application / f"{name}-Info.plist").open("wb") as target:
        plistlib.dump({
            "CFBundleDisplayName": "Chef al Mando",
            "NSCameraUsageDescription": "",
            "NSMicrophoneUsageDescription": "",
            "NSPhotoLibraryUsageDescription": "",
        }, target)
    (localized / "InfoPlist.strings").write_text(
        'CFBundleDisplayName = "Chef al Mando";\n'
        'NSCameraUsageDescription = "";\n'
        'NSMicrophoneUsageDescription = "";\n'
        'NSPhotoLibraryUsageDescription = "";\n'
    )
    Path(os.environ["TEST_EXPORT_LOG"]).write_text(" ".join(args))
'''


class IOSExportTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="chef-ios-export-test-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        repo = Path(__file__).resolve().parents[1]
        (self.root / "scripts").mkdir()
        shutil.copy2(repo / "scripts/export-ios.sh", self.root / "scripts/export-ios.sh")
        shutil.copy2(
            repo / "scripts/strip-ios-unused-permissions.py",
            self.root / "scripts/strip-ios-unused-permissions.py",
        )
        shutil.copy2(repo / ".godot-version", self.root / ".godot-version")
        self.engine = self.root / "godot"
        self.engine.write_text(f"#!{sys.executable}\n{FAKE_ENGINE}")
        self.engine.chmod(0o700)
        self.export_log = self.root / "export-args.txt"

    def test_export_removes_unused_privacy_keys(self):
        project = self.root / "build/ios/chef_al_mando.xcodeproj"
        result = subprocess.run(
            ["bash", str(self.root / "scripts/export-ios.sh"), str(project)],
            env=dict(
                os.environ,
                GODOT_BIN=str(self.engine),
                TEST_ENGINE_VERSION=(self.root / ".godot-version").read_text().strip(),
                TEST_EXPORT_LOG=str(self.export_log),
            ),
            capture_output=True,
            text=True,
            timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        info_path = self.root / "build/ios/chef_al_mando/chef_al_mando-Info.plist"
        with info_path.open("rb") as source:
            info = plistlib.load(source)
        localized = (info_path.parent / "en.lproj/InfoPlist.strings").read_text()
        for key in (
            "NSCameraUsageDescription",
            "NSMicrophoneUsageDescription",
            "NSPhotoLibraryUsageDescription",
        ):
            self.assertNotIn(key, info)
            self.assertNotIn(key, localized)
        self.assertIn("--export-debug iOS " + str(project), self.export_log.read_text())

    def test_missing_output_fails(self):
        result = subprocess.run(
            [
                sys.executable,
                str(self.root / "scripts/strip-ios-unused-permissions.py"),
                str(self.root / "missing.plist"),
                str(self.root / "missing.strings"),
            ],
            capture_output=True,
            text=True,
            timeout=10,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("privacy files are missing", result.stderr)


if __name__ == "__main__":
    unittest.main()
