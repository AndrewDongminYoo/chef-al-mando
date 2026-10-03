#!/usr/bin/env bash
set -euo pipefail

# Builds and uploads the App Store Connect (TestFlight) build of the "iOS App Store" preset.
#   release-ios.sh build   local only: release export, archive, and checks of the archived app
#   release-ios.sh upload  writes to the Apple developer portal (App ID profile) and uploads the archive
# upload reads the App Store Connect API key from ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH; no key
# material is stored in the repository. docs/notes/store-distribution.md owns the procedure.

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
if [[ $# -ne 1 || ($1 != build && $1 != upload) ]]; then
	echo "FAIL: usage is release-ios.sh build|upload" >&2
	exit 1
fi
# A separate assignment lets set -e stop the script when git itself fails.
changes="$(git status --porcelain)"
if [[ -n $changes ]]; then
	echo "FAIL: the release build needs a checkout without changes" >&2
	exit 1
fi

bundle_id="kr.donminzzi.chefalmando"
team_id="393JTTV68D"
release_dir="$repo_dir/build/ios-release"
project_path="$release_dir/chef_al_mando.xcodeproj"
archive_path="$release_dir/chef_al_mando.xcarchive"
app_path="$archive_path/Products/Applications/chef_al_mando.app"
# build records the commit it checked and a hash of every archive file; upload refuses any other commit or
# an archive that changed after the checks.
built_record="$release_dir/built-record"

archive_hash() {
	(cd "$archive_path" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 | shasum -a 256 | cut -d " " -f 1)
}

if [[ $1 == build ]]; then
	rm -rf "$release_dir"
	IOS_EXPORT_PRESET="iOS App Store" IOS_EXPORT_MODE=release bash "$repo_dir/scripts/export-ios.sh" "$project_path"
	# Archives are signed for development under automatic signing; the upload step re-signs them for
	# distribution, so the archive needs no portal access.
	xcodebuild -project "$project_path" -scheme chef_al_mando -configuration Release \
		-destination 'generic/platform=iOS' -archivePath "$archive_path" \
		-derivedDataPath "$repo_dir/build/ios-release-derived" \
		CODE_SIGN_IDENTITY="Apple Development" archive
	python3 - "$app_path/Info.plist" "$bundle_id" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as source:
    info = plistlib.load(source)
problems = []
if info.get("CFBundleIdentifier") != sys.argv[2]:
    problems.append(f"bundle ID is {info.get('CFBundleIdentifier')}")
if info.get("ITSAppUsesNonExemptEncryption") is not False:
    problems.append("ITSAppUsesNonExemptEncryption is not false")
for key in ("NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSPhotoLibraryUsageDescription"):
    if key in info:
        problems.append(f"{key} is present")
if problems:
    sys.exit("FAIL: archived app: " + "; ".join(problems))
print(f"version {info['CFBundleShortVersionString']} build {info['CFBundleVersion']}")
PY
	codesign --verify --deep --strict "$app_path"
	echo "commit $(git rev-parse HEAD)"
	shasum -a 256 "$app_path/chef_al_mando.pck"
	checked_hash="$(archive_hash)"
	printf "%s %s\n" "$(git rev-parse HEAD)" "$checked_hash" >"$built_record"
	echo "PASS: archived $bundle_id; run release-ios.sh upload to send it to App Store Connect"
	exit 0
fi

for name in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH; do
	if [[ -z ${!name:-} ]]; then
		echo "FAIL: $name is required for upload" >&2
		exit 1
	fi
done
if [[ ! -f $ASC_KEY_PATH || ! -d $archive_path || ! -f $built_record ]]; then
	echo "FAIL: the API key file or the checked archive from release-ios.sh build is missing" >&2
	exit 1
fi
read -r built_commit built_hash <"$built_record"
head_commit="$(git rev-parse HEAD)"
current_hash="$(archive_hash)"
if [[ $built_commit != "$head_commit" || $built_hash != "$current_hash" ]]; then
	echo "FAIL: the archive does not match the one release-ios.sh build checked at HEAD; run release-ios.sh build again" >&2
	exit 1
fi
export_options="$release_dir/ExportOptions.plist"
cat >"$export_options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>upload</string>
	<key>teamID</key>
	<string>$team_id</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$archive_path" -exportOptionsPlist "$export_options" \
	-exportPath "$release_dir/upload" -allowProvisioningUpdates \
	-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" \
	-authenticationKeyIssuerID "$ASC_ISSUER_ID"
echo "PASS: uploaded $bundle_id from commit $(git rev-parse HEAD) to App Store Connect"
