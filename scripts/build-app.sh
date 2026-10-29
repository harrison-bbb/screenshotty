#!/usr/bin/env bash
# Builds Screenshotty.app with Swift Package Manager only (no Xcode needed).
# Usage: scripts/build-app.sh [version]   -> build/Screenshotty.app
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-${VERSION:-0.0.0-dev}}"
VERSION="${VERSION#v}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
APP="build/Screenshotty.app"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "==> Building release binary (${VERSION})"
swift build -c release --product Screenshotty "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}"
BIN_DIR="$(swift build -c release --product Screenshotty "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}" --show-bin-path)"

echo "==> Assembling ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Screenshotty" "$APP/Contents/MacOS/Screenshotty"
sed -e "s/__VERSION__/${VERSION}/" -e "s/__BUILD__/${BUILD_NUMBER}/" Packaging/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ ! -f build/AppIcon.icns ]]; then
  scripts/make-icon.sh >/dev/null
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc signing"
# Ad-hoc signatures normally identify the app by a hash of this exact build, so macOS forgets the
# Screen Recording permission after every update. Pinning the designated requirement to the bundle
# identifier keeps the permission across builds and releases.
codesign --force --deep --sign - --options runtime --timestamp=none --identifier com.screenshotty.app \
  --requirements '=designated => identifier "com.screenshotty.app"' "$APP"

echo "==> Done: $APP"
