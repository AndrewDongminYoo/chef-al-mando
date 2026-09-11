#!/usr/bin/env python3
import plistlib
from pathlib import Path
import re
import sys


UNUSED_KEYS = (
    "NSCameraUsageDescription",
    "NSMicrophoneUsageDescription",
    "NSPhotoLibraryUsageDescription",
)


def strip_permissions(info_path: Path, localized_path: Path) -> None:
    if not info_path.is_file() or not localized_path.is_file():
        raise FileNotFoundError("exported iOS privacy files are missing")
    with info_path.open("rb") as source:
        info = plistlib.load(source)
    for key in UNUSED_KEYS:
        info.pop(key, None)
    with info_path.open("wb") as target:
        plistlib.dump(info, target, sort_keys=False)

    localized = localized_path.read_text(encoding="utf-8")
    for key in UNUSED_KEYS:
        localized = re.sub(rf"^{re.escape(key)}\s*=.*?;\s*$\n?", "", localized, flags=re.MULTILINE)
    localized_path.write_text(localized, encoding="utf-8")

    with info_path.open("rb") as source:
        verified = plistlib.load(source)
    remaining = [key for key in UNUSED_KEYS if key in verified or key in localized]
    if remaining:
        raise ValueError("unused iOS privacy keys remain: " + ", ".join(remaining))


def main() -> int:
    if len(sys.argv) != 3:
        print("FAIL: usage is strip-ios-unused-permissions.py <Info.plist> <InfoPlist.strings>", file=sys.stderr)
        return 1
    try:
        strip_permissions(Path(sys.argv[1]), Path(sys.argv[2]))
    except (FileNotFoundError, OSError, plistlib.InvalidFileException, ValueError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
