#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
if [[ $# -gt 1 || ($# -eq 1 && $1 != /*) ]]; then
	echo "FAIL: usage is export-ios.sh [absolute-xcode-project-path]" >&2
	exit 1
fi

godot_bin="${GODOT_BIN:-godot}"
expected_version="$(tr -d '[:space:]' <.godot-version)"
actual_version="$("$godot_bin" --headless --version)"
if [[ $actual_version != "$expected_version" ]]; then
	echo "FAIL: Godot version must be $expected_version (found $actual_version)" >&2
	exit 1
fi

project_path="${1:-$repo_dir/build/ios/chef_al_mando.xcodeproj}"
mkdir -p "$(dirname "$project_path")"
"$godot_bin" --headless --path "$repo_dir" --export-debug iOS "$project_path"

project_name="$(basename "$project_path" .xcodeproj)"
application_dir="$(dirname "$project_path")/$project_name"
info_plist="$application_dir/$project_name-Info.plist"
localized_plist="$application_dir/en.lproj/InfoPlist.strings"
python3 "$repo_dir/scripts/strip-ios-unused-permissions.py" "$info_plist" "$localized_plist"
