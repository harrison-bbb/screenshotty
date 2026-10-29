#!/usr/bin/env bash
# Packages build/Screenshotty.app into dist/Screenshotty.dmg and dist/Screenshotty.zip.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Screenshotty.app
[[ -d "$APP" ]] || { echo "Run scripts/build-app.sh first" >&2; exit 1; }

rm -rf dist build/dmg
mkdir -p dist build/dmg
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications

hdiutil create -volname "Screenshotty" -srcfolder build/dmg -ov -format UDZO dist/Screenshotty.dmg >/dev/null
ditto -c -k --keepParent "$APP" dist/Screenshotty.zip

(cd dist && shasum -a 256 Screenshotty.dmg Screenshotty.zip)
