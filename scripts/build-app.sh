#!/usr/bin/env bash
# Builds Screenshotty.app with Swift Package Manager only (no Xcode needed).
# Usage: scripts/build-app.sh [version]   -> build/Screenshotty.app
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-${VERSION:-0.0.0-dev}}"
VERSION="${VERSION#v}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
OUT="build/Screenshotty.app"
# Assemble and sign outside the project: synced folders (iCloud Desktop & Documents) keep re-adding
# Finder info to the bundle, which codesign rejects.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Screenshotty.app"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "==> Building release binary (${VERSION})"
swift build -c release --product Screenshotty "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}"
BIN_DIR="$(swift build -c release --product Screenshotty "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}" --show-bin-path)"

echo "==> Assembling ${APP}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Screenshotty" "$APP/Contents/MacOS/Screenshotty"
# Sparkle (auto-updates) ships as a framework next to the binary; bundle it and point the loader at it.
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Screenshotty"
sed -e "s/__VERSION__/${VERSION}/" -e "s/__BUILD__/${BUILD_NUMBER}/" Packaging/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ ! -f build/AppIcon.icns ]]; then
  scripts/make-icon.sh >/dev/null
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc signing"
# Extended attributes (e.g. Finder info) make codesign refuse to sign.
# Ad-hoc signatures normally identify the app by a hash of this exact build, so macOS forgets the
# Screen Recording permission after every update. Pinning the designated requirement to the bundle
# identifier keeps the permission across builds and releases.
# Sparkle's helpers are signed inside-out first, keeping their own identifiers; then the app itself.
sign() {
  xattr -cr "$APP"
  local fw="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  for nested in "$fw"/XPCServices/*.xpc "$fw/Autoupdate" "$fw/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework"; do
    codesign --force --sign - --options runtime --timestamp=none "$nested"
  done
  codesign --force --sign - --options runtime --timestamp=none --identifier com.screenshotty.app \
    --entitlements Packaging/Screenshotty.entitlements \
    --requirements '=designated => identifier "com.screenshotty.app"' "$APP"
}
# macOS sometimes re-tags a fresh bundle with attributes mid-sign, so retry once, then insist it verifies.
sign || { sleep 1; sign; }
codesign --verify --deep --strict "$APP"

rm -rf "$OUT"
mkdir -p build
ditto "$APP" "$OUT"
# (Not --strict here: a synced folder may tag the copy with Finder info again, which only matters to codesign.)
codesign --verify --deep "$OUT"
echo "==> Done: $OUT"
