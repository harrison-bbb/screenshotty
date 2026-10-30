#!/usr/bin/env bash
# Packages build/Screenshotty.app into dist/Screenshotty.dmg (styled drag-to-Applications window)
# and dist/Screenshotty.zip (used by the installer script, Homebrew and auto-updates).
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Screenshotty.app
[[ -d "$APP" ]] || { echo "Run scripts/build-app.sh first" >&2; exit 1; }

rm -rf dist
mkdir -p dist
# Stage outside the project, without Finder info: synced folders (iCloud Desktop) tag app bundles
# with it, and codesign then rejects the copy users get.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto --noextattr --norsrc "$APP" "$STAGE/Screenshotty.app"

# Window background at 1x and 2x, combined so Retina screens get the sharp one.
swift scripts/make-dmg-background.swift "$STAGE/bg.png" 1
swift scripts/make-dmg-background.swift "$STAGE/bg@2x.png" 2
tiffutil -cathidpicheck "$STAGE/bg.png" "$STAGE/bg@2x.png" -out "$STAGE/background.tiff" >/dev/null

# dmgbuild lives in a private virtualenv so it never touches the system Python.
if [[ ! -x build/venv/bin/dmgbuild ]]; then
  python3 -m venv build/venv
  build/venv/bin/pip install --quiet "dmgbuild==1.6.5"
fi
build/venv/bin/dmgbuild -s scripts/dmg-settings.py \
  -D app="$STAGE/Screenshotty.app" -D background="$STAGE/background.tiff" \
  "Screenshotty" dist/Screenshotty.dmg >/dev/null

ditto -c -k --norsrc --noextattr --keepParent "$STAGE/Screenshotty.app" dist/Screenshotty.zip

(cd dist && shasum -a 256 Screenshotty.dmg Screenshotty.zip)
