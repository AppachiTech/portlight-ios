#!/usr/bin/env bash
# Builds an unsigned Portlight.ipa (release configuration) into build/.
# iOS won't install it as is: sign it with your own Apple ID, e.g. with
# AltStore or SideStore, or build from Xcode instead. See docs/INSTALL.md.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d Portlight.xcodeproj ] || xcodegen generate
rm -rf build/Portlight.xcarchive build/Payload build/Portlight.ipa
mkdir -p build

archive() {
  xcodebuild archive \
    -project Portlight.xcodeproj \
    -scheme Portlight \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath build/Portlight.xcarchive \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
}
if command -v xcbeautify >/dev/null; then
  archive | xcbeautify
else
  archive
fi

app="build/Portlight.xcarchive/Products/Applications/Portlight.app"
[ -d "$app" ] || { echo "Archive failed: $app not found"; exit 1; }

mkdir -p build/Payload
cp -R "$app" build/Payload/
(cd build && zip -qry Portlight.ipa Payload)
rm -rf build/Payload
shasum -a 256 build/Portlight.ipa | tee build/Portlight.ipa.sha256
echo "Built build/Portlight.ipa (unsigned)"
