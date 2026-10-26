#!/usr/bin/env bash
# Installs a pinned XcodeGen release, checked against its SHA-256, under the
# directory given (default build/tools), and prints its bin directory. CI
# uses this instead of `brew install xcodegen`, which installs whatever is
# newest. To update: change VERSION, download the release's xcodegen.zip
# and put its `shasum -a 256` here.
set -euo pipefail

VERSION=2.46.0
SHA256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806

dest="${1:-build/tools}"
mkdir -p "$dest"
zip="$dest/xcodegen-$VERSION.zip"
curl -fsSL -o "$zip" "https://github.com/yonaskolb/XcodeGen/releases/download/$VERSION/xcodegen.zip"
echo "$SHA256  $zip" | shasum -a 256 -c - >&2
rm -rf "$dest/xcodegen"
unzip -q "$zip" -d "$dest"
cd "$dest/xcodegen/bin" && pwd
