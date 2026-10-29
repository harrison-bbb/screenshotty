#!/usr/bin/env bash
# One-line installer:
#   curl -fsSL https://raw.githubusercontent.com/harrison-bbb/screenshotty/main/scripts/install.sh | bash
#
# Downloads the latest release into /Applications and clears the download quarantine flag,
# so macOS opens it without the "unidentified developer" prompt.
set -euo pipefail

URL="https://github.com/harrison-bbb/screenshotty/releases/latest/download/Screenshotty.zip"
DEST="/Applications"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Screenshotty…"
curl -fsSL "$URL" -o "$TMP/Screenshotty.zip"
ditto -x -k "$TMP/Screenshotty.zip" "$TMP"

if [[ -d "$DEST/Screenshotty.app" ]]; then
  osascript -e 'quit app "Screenshotty"' >/dev/null 2>&1 || true
  rm -rf "$DEST/Screenshotty.app"
fi

if [[ -w "$DEST" ]]; then
  mv "$TMP/Screenshotty.app" "$DEST/"
else
  echo "Administrator password needed to install into $DEST"
  sudo mv "$TMP/Screenshotty.app" "$DEST/"
fi
xattr -dr com.apple.quarantine "$DEST/Screenshotty.app" 2>/dev/null || true

echo "Installed to $DEST/Screenshotty.app"
open "$DEST/Screenshotty.app"
