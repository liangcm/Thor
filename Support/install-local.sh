#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
installed='/Applications/Thor+.app'
bundle_id='com.liangcm.ThorPlus'
identity_name='Thor+ Local Code Signing'
replace_identity=false

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

signing_requirement() {
    codesign -d -r- "$1" 2>&1 | sed -n 's/^designated => //p'
}

if [[ ${1:-} == --replace-signing-identity && $# == 1 ]]; then
    replace_identity=true
elif (( $# != 0 )); then
    fail 'Usage: bash Support/install-local.sh [--replace-signing-identity]'
fi

if [[ -d "$installed" ]]; then
    codesign --verify --strict -R="identifier \"$bundle_id\"" "$installed"
    installed_requirement=$(signing_requirement "$installed")
else
    installed_requirement=''
fi
identities=$(security find-identity -p codesigning)
identities=$(awk -F '"' -v name="$identity_name" '$2 == name {split($1, fields, " "); print fields[2]}' <<< "$identities")
if [[ -n "$installed_requirement" && "$replace_identity" == false ]]; then
    installed_hash=$(sed -n 's/.*certificate leaf = H"\([0-9a-fA-F]*\)".*/\1/p' <<< "$installed_requirement")
    [[ -n "$installed_hash" ]] || fail 'Use --replace-signing-identity for the one-time switch to local signing.'
    identities=$(grep -ixF "$installed_hash" <<< "$identities" || true)
fi
identity="$identities"
[[ "$identity" =~ ^[0-9A-Fa-f]{40}$ ]] ||
    fail 'The matching Thor+ Local Code Signing certificate and private key are required in Keychain.'
identity_lower=$(tr '[:upper:]' '[:lower:]' <<< "$identity")
requirement="identifier \"$bundle_id\" and certificate leaf = H\"$identity_lower\""
if [[ -n "$installed_requirement" && "$replace_identity" == false ]]; then
    [[ "$installed_requirement" == "$requirement" ]] ||
        fail 'The local signing requirement differs from the installed version.'
fi

build_dir="$PWD/.build/LocalBuild"
xcodebuild -workspace Thor.xcworkspace -scheme Thor -configuration Release \
    -derivedDataPath "$build_dir" -clonedSourcePackagesDirPath "$PWD/.build/SourcePackages" \
    -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=12.0 build

stage=$(mktemp -d /Applications/.thorplus-install.XXXXXX)
cleanup() {
    if [[ -d "$stage/previous.app" ]]; then
        # Leave the backup in place if a failed replacement needs manual recovery.
        printf 'Previous Thor+ retained at %s\n' "$stage/previous.app" >&2
    else
        rm -rf "$stage"
    fi
}
trap cleanup EXIT
candidate="$stage/Thor+.app"
ditto "$build_dir/Build/Products/Release/Thor+.app" "$candidate"
xattr -cr "$candidate"

sign_component() {
    codesign --force --sign "$identity" --timestamp=none --preserve-metadata=identifier,entitlements "$1"
}

sparkle="$candidate/Contents/Frameworks/Sparkle.framework"
for component in "$sparkle/Versions/Current/"{Autoupdate,Updater.app,XPCServices/*.xpc}; do
    sign_component "$component"
done
sign_component "$sparkle"
sign_component "$candidate/Contents/Frameworks/MASShortcut.framework"
sign_component "$candidate/Contents/Library/LoginItems/LaunchAtLoginHelper.app"
codesign --force --sign "$identity" --timestamp=none --identifier "$bundle_id" \
    --requirements "=designated => $requirement" "$candidate"
codesign --verify --deep --strict "$candidate"
codesign --verify -R="$requirement" "$candidate"
[[ "$(signing_requirement "$candidate")" == "$requirement" ]] ||
    fail 'The new build has a different designated signing requirement.'

osascript -l JavaScript - "$bundle_id" <<'JXA'
ObjC.import('AppKit');
function run(argv) {
    const running = () => $.NSRunningApplication.runningApplicationsWithBundleIdentifier(argv[0]);
    const apps = running();
    for (let i = 0; i < apps.count; i++) apps.objectAtIndex(i).terminate;
    for (let attempt = 0; attempt < 40; attempt++) {
        const remaining = running();
        if (Number(remaining.count) === 0) return;
        if (attempt === 20) {
            for (let i = 0; i < remaining.count; i++) remaining.objectAtIndex(i).forceTerminate;
        }
        delay(0.25);
    }
    throw Error('Thor+ is still running. Quit it and retry the installation.');
}
JXA

if [[ -d "$installed" ]]; then
    mv "$installed" "$stage/previous.app"
fi
if ! mv "$candidate" "$installed"; then
    if [[ -d "$stage/previous.app" ]]; then
        mv "$stage/previous.app" "$installed"
        open "$installed"
    fi
    exit 1
fi
if ! open "$installed" || ! osascript -l JavaScript - "$bundle_id" "$installed" <<'JXA'
ObjC.import('AppKit');
function run(argv) {
    for (let attempt = 0; attempt < 40; attempt++) {
        const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(argv[0]);
        if (Number(apps.count) === 1) {
            const app = apps.objectAtIndex(0);
            if (ObjC.unwrap(app.bundleURL.path) === argv[1] && app.finishedLaunching) return;
        }
        delay(0.25);
    }
    throw Error('Could not verify a single running instance of installed Thor+.');
}
JXA
then
    fail 'Thor+ startup could not be verified.'
fi
rm -rf "$stage/previous.app"
printf 'Updated %s and verified a single running instance.\n' "$installed"
