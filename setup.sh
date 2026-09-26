#!/usr/bin/env bash
set -euo pipefail

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

# Provision only missing commands on Debian/Ubuntu, as root or with passwordless sudo.
apt_updated=false
privilege=()
select_privilege() {
	privilege=()
	if ((EUID != 0)); then
		command -v sudo >/dev/null 2>&1 || fail "$1 requires root or passwordless sudo"
		sudo -n true || fail "$1 requires passwordless sudo"
		privilege=(sudo -n --preserve-env=DEBIAN_FRONTEND)
	fi
}

ensure_command() {
	local tool="$1" package="$2"
	command -v "$tool" >/dev/null 2>&1 && return 0
	command -v apt-get >/dev/null 2>&1 || fail "missing command $tool; install $package before running setup.sh (apt-get unavailable)"
	select_privilege "missing command $tool"
	if [[ $apt_updated == false ]]; then
		"${privilege[@]}" apt-get update
		apt_updated=true
	fi
	DEBIAN_FRONTEND=noninteractive "${privilege[@]}" apt-get install -y --no-install-recommends "$package"
	command -v "$tool" >/dev/null 2>&1 || fail "missing command $tool after installing $package"
}

ensure_command uname coreutils
[[ $(uname -s) == Linux ]] || fail "setup.sh requires Linux"
ensure_command dirname coreutils
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_dir"
ensure_command tr coreutils
expected_version="$(tr -d '[:space:]' <.godot-version)"
ensure_command python3 python3
python3 --version
# Resource import asks Linux for fallback fonts even in headless mode.
ensure_command fc-match fontconfig
fc-match --version

godot_bin="${GODOT_BIN:-godot}"
if ! command -v "$godot_bin" >/dev/null 2>&1; then
	[[ $godot_bin == godot || $godot_bin == /usr/local/bin/godot ]] || fail "GODOT_BIN command is missing: $GODOT_BIN"
	[[ $(uname -m) == x86_64 ]] || fail "automatic Godot installation requires Linux x86_64; provide GODOT_BIN for this architecture"
	# This checksum is the existing CI pin for the Standard Linux x86_64 archive.
	# Updating .godot-version also requires reviewing this pin.
	[[ $expected_version == 4.7.2.stable.official.ed1daf0bf ]] || fail "no reviewed Linux archive checksum for $expected_version"
	godot_sha256=cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4
	for tool in mkdir mktemp rm install; do
		ensure_command "$tool" coreutils
	done
	ensure_command curl curl
	if [[ ! -s /etc/ssl/certs/ca-certificates.crt ]]; then
		ensure_command update-ca-certificates ca-certificates
		select_privilege "repairing the certificate bundle"
		"${privilege[@]}" update-ca-certificates
	fi
	ensure_command sha256sum coreutils
	ensure_command unzip unzip

	temp_dir="$(mktemp -d)"
	trap 'rm -rf "$temp_dir"' EXIT
	release="${expected_version%%.stable.*}-stable"
	archive="Godot_v${release}_linux.x86_64.zip"
	curl --fail --location --retry 2 \
		"https://github.com/godotengine/godot-builds/releases/download/$release/$archive" \
		--output "$temp_dir/$archive"
	printf '%s  %s\n' "$godot_sha256" "$temp_dir/$archive" | sha256sum --check
	unzip -q "$temp_dir/$archive" -d "$temp_dir/godot"
	downloaded_bin="$temp_dir/godot/${archive%.zip}"
	command -v "$downloaded_bin" >/dev/null 2>&1 || fail "downloaded Godot executable is missing"
	[[ $("$downloaded_bin" --headless --version) == "$expected_version" ]] || fail "downloaded Godot version does not match $expected_version"
	if [[ ! -w /usr/local/bin ]]; then
		select_privilege "installing godot in /usr/local/bin"
		"${privilege[@]}" mkdir -p /usr/local/bin
	fi
	"${privilege[@]}" install -m 0755 "$downloaded_bin" /usr/local/bin/godot
	command -v "$godot_bin" >/dev/null 2>&1 || fail "missing command godot after installation; add /usr/local/bin to the environment PATH"
fi
actual_version="$("$godot_bin" --headless --version)"
[[ $actual_version == "$expected_version" ]] || fail "Godot version must be $expected_version (found $actual_version)"

# These commands are read by the existing shell checks, not only this setup session.
ensure_command bash bash
ensure_command mkdir coreutils
ensure_command tee coreutils
ensure_command grep grep
printf 'PASS: hosted container setup (Godot %s)\n' "$actual_version"
