#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
if [[ $# -gt 1 ]]; then
	echo "FAIL: usage is check.sh [suite]" >&2
	exit 1
fi
suite="${1:-m0}"

godot_bin="${GODOT_BIN:-godot}"
expected_version="$(tr -d '[:space:]' <.godot-version)"
actual_version="$("$godot_bin" --version)"
if [[ $actual_version != "$expected_version" ]]; then
	echo "FAIL: Godot version must be $expected_version (found $actual_version)" >&2
	exit 1
fi

mkdir -p build/check build/android build/ios
run_engine() {
	local log_file="$1"
	shift
	local status=0
	"$godot_bin" --headless --path "$repo_dir" "$@" 2>&1 | tee "$log_file" || status=$?
	if ((status != 0)) || grep -Eq '(^|[[:space:]])(SCRIPT ERROR:|ERROR:|FAIL:)' "$log_file"; then
		echo "FAIL: engine run failed with exit $status; see $log_file" >&2
		return 1
	fi
}

run_engine build/check/import.log --import
run_engine "build/check/$suite.log" --max-fps 120 --quit-after 600 \
	--script tests/run_tests.gd -- --suite "$suite"
if ! grep -Eq "^PASS: $suite checks=[1-9][0-9]* failures=0\$" "build/check/$suite.log"; then
	echo "FAIL: $suite completion marker is missing" >&2
	exit 1
fi
