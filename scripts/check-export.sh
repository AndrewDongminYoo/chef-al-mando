#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
if [[ $# -gt 1 || ($# -eq 1 && $1 != /*) ]]; then
	echo "FAIL: usage is check-export.sh [absolute-pack-path]" >&2
	exit 1
fi
godot_bin="${GODOT_BIN:-godot}"
expected_version="$(tr -d '[:space:]' <.godot-version)"
if [[ $("$godot_bin" --version) != "$expected_version" ]]; then
	echo "FAIL: Godot version must be $expected_version" >&2
	exit 1
fi
mkdir -p build/check/export-runtime
pack_file="${1:-$repo_dir/build/check/m1.pck}"
if [[ $# -eq 0 ]]; then
	"$godot_bin" --headless --path "$repo_dir" --export-pack Android "$pack_file"
fi
if [[ ! -f $pack_file ]]; then
	echo "FAIL: exported pack is missing: $pack_file" >&2
	exit 1
fi
log_file="$repo_dir/build/check/export-runtime.log"
command_exit=0
"$godot_bin" --headless --path "$repo_dir/build/check/export-runtime" \
	--main-pack "$pack_file" --max-fps 120 --quit-after 600 \
	--script "$repo_dir/tests/check_export.gd" 2>&1 | tee "$log_file" || command_exit=$?
if ((command_exit != 0)) || grep -Eq '(^|[[:space:]])(SCRIPT ERROR:|ERROR:|FAIL:)' "$log_file"; then
	echo "FAIL: exported runtime check failed; see $log_file" >&2
	exit 1
fi
if ! grep -Fxq 'PASS: exported M1 content and first order' "$log_file"; then
	echo "FAIL: exported runtime completion marker is missing" >&2
	exit 1
fi
