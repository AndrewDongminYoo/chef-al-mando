#!/usr/bin/env bash
set -euo pipefail

# Builds and uploads the Google Play internal test build of the "Android Play Store" preset.
#   release-android.sh build   local only: installs the Gradle build template, exports a signed AAB and checks it
#   release-android.sh upload  uploads the checked AAB to the Play internal test track
# build reads the upload keystore from GODOT_ANDROID_KEYSTORE_RELEASE_PATH, _USER and _PASSWORD; upload reads the
# Play service account key from SUPPLY_JSON_KEY. No key material is stored in the repository.
# docs/notes/store-distribution.md owns the procedure.

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
if [[ $# -ne 1 || ($1 != build && $1 != upload) ]]; then
	echo "FAIL: usage is release-android.sh build|upload" >&2
	exit 1
fi
# A separate assignment lets set -e stop the script when git itself fails.
changes="$(git status --porcelain)"
if [[ -n $changes ]]; then
	echo "FAIL: the release build needs a checkout without changes" >&2
	exit 1
fi

package="kr.donminzzi.chefalmando"
target_sdk=36
# The upload key the operator named on 2026-10-03 (release-android.jks, alias donminzzi). Play binds the first
# upload to this certificate, so a build signed by any other key fails here.
upload_cert_sha256="84:10:5B:BF:5B:C0:3D:7C:1A:E8:16:2D:76:8D:1F:44:C1:09:4C:21:53:63:57:0C:F9:0D:AF:6E:38:C3:97:E5"
release_dir="$repo_dir/build/android-release"
aab_path="$release_dir/chef-al-mando.aab"
# build records the commit it checked and the AAB hash; upload refuses any other commit or a changed AAB.
built_record="$release_dir/built-record"

if [[ $1 == build ]]; then
	for name in GODOT_ANDROID_KEYSTORE_RELEASE_PATH GODOT_ANDROID_KEYSTORE_RELEASE_USER GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD; do
		if [[ -z ${!name:-} ]]; then
			echo "FAIL: $name is required for build" >&2
			exit 1
		fi
	done
	godot_bin="${GODOT_BIN:-godot}"
	expected_version="$(tr -d '[:space:]' <.godot-version)"
	actual_version="$("$godot_bin" --headless --version)"
	if [[ $actual_version != "$expected_version" ]]; then
		echo "FAIL: Godot version must be $expected_version (found $actual_version)" >&2
		exit 1
	fi
	rm -rf "$release_dir"
	mkdir -p "$release_dir"
	"$godot_bin" --headless --path "$repo_dir" --install-android-build-template \
		--export-release "Android Play Store" "$aab_path" 2>&1 | tee "$release_dir/export.log"
	if [[ ! -f $aab_path ]] || grep -Eq '(^|[[:space:]])(SCRIPT ERROR:|ERROR:)' "$release_dir/export.log"; then
		echo "FAIL: the AAB export failed; see $release_dir/export.log" >&2
		exit 1
	fi
	sdk_dir="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
	aapt2="$(find "$sdk_dir/build-tools" -name aapt2 -type f | sort | tail -n 1)"
	# aapt2 cannot open an AAB, but it reads a proto-format APK: the base module's manifest at the root
	# next to its resources.pb.
	proto_dir="$release_dir/manifest-check"
	mkdir -p "$proto_dir"
	unzip -q -j -o "$aab_path" base/manifest/AndroidManifest.xml base/resources.pb -d "$proto_dir"
	(cd "$proto_dir" && zip -q -X proto.apk AndroidManifest.xml resources.pb)
	manifest="$("$aapt2" dump xmltree --file AndroidManifest.xml "$proto_dir/proto.apk")"
	problems=()
	grep -q "package=\"$package\"" <<<"$manifest" || problems+=("package is not $package")
	grep -Eq "targetSdkVersion\\(0x[0-9a-f]+\\)=$target_sdk " <<<"$manifest" || problems+=("targetSdkVersion is not $target_sdk")
	if grep -q 'android.permission.INTERNET' <<<"$manifest"; then
		problems+=("INTERNET permission is declared")
	fi
	if ((${#problems[@]} > 0)); then
		echo "FAIL: AAB manifest: ${problems[*]}" >&2
		exit 1
	fi
	jarsigner="$(/usr/libexec/java_home -v 17)/bin/jarsigner"
	signature="$("$jarsigner" -verify "$aab_path")"
	if ! grep -q 'jar verified' <<<"$signature"; then
		echo "FAIL: the AAB signature does not verify" >&2
		exit 1
	fi
	# jarsigner -verify accepts any valid signer, so compare the signer certificate with the pinned upload key.
	certificate="$("$(/usr/libexec/java_home -v 17)/bin/keytool" -printcert -jarfile "$aab_path")"
	if ! grep -Eq "SHA256: $upload_cert_sha256\$" <<<"$certificate"; then
		echo "FAIL: the AAB is not signed with the upload key ($upload_cert_sha256)" >&2
		exit 1
	fi
	grep -E 'versionCode|versionName' <<<"$manifest" | head -n 2
	echo "commit $(git rev-parse HEAD)"
	aab_hash="$(shasum -a 256 "$aab_path" | cut -d " " -f 1)"
	echo "AAB SHA-256 $aab_hash"
	printf "%s %s\n" "$(git rev-parse HEAD)" "$aab_hash" >"$built_record"
	echo "PASS: built $package; run release-android.sh upload to send it to the Play internal track"
	exit 0
fi

if [[ -z ${SUPPLY_JSON_KEY:-} || ! -f $SUPPLY_JSON_KEY ]]; then
	echo "FAIL: SUPPLY_JSON_KEY must name the Play service account key file" >&2
	exit 1
fi
if [[ ! -f $aab_path || ! -f $built_record ]]; then
	echo "FAIL: the checked AAB from release-android.sh build is missing" >&2
	exit 1
fi
read -r built_commit built_hash <"$built_record"
head_commit="$(git rev-parse HEAD)"
current_hash="$(shasum -a 256 "$aab_path" | cut -d " " -f 1)"
if [[ $built_commit != "$head_commit" || $built_hash != "$current_hash" ]]; then
	echo "FAIL: the AAB does not match the one release-android.sh build checked at HEAD; run release-android.sh build again" >&2
	exit 1
fi
fastlane supply --aab "$aab_path" --track internal --package_name "$package" --json_key "$SUPPLY_JSON_KEY" \
	--skip_upload_metadata true --skip_upload_changelogs true --skip_upload_images true --skip_upload_screenshots true
echo "PASS: uploaded $package from commit $head_commit to the Play internal track"
