#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
suite="${1:-m0}"
if [[ $# -gt 1 || $suite != "m0" ]]; then
	echo "FAIL: supported suite is m0" >&2
	exit 1
fi

godot_bin="${GODOT_BIN:-godot}"
expected_version="4.7.2.stable.official.ed1daf0bf"
actual_version="$("$godot_bin" --version)"
if [[ $actual_version != "$expected_version" ]]; then
	echo "FAIL: Godot version must be $expected_version (found $actual_version)" >&2
	exit 1
fi

mkdir -p build/check
touch build/.gdignore
run_engine() {
	local log_file="$1"
	shift
	"$godot_bin" --headless --path "$repo_dir" "$@" 2>&1 | tee "$log_file"
	if grep -Eq '(^|[[:space:]])(SCRIPT ERROR:|ERROR:|FAIL:)' "$log_file"; then
		echo "FAIL: engine errors in $log_file" >&2
		return 1
	fi
}

run_engine build/check/import.log --import
run_engine build/check/m0.log --max-fps 120 --quit-after 600 \
	--script tests/run_tests.gd -- --suite "$suite"
if ! grep -Eq '^PASS: m0 checks=[1-9][0-9]* failures=0$' build/check/m0.log; then
	echo "FAIL: m0 completion marker is missing" >&2
	exit 1
fi
