#!/usr/bin/env bash
# Writes dist/appcast.xml, the update feed Sparkle checks (see SUFeedURL in Packaging/Info.plist).
# Usage: scripts/make-appcast.sh <version> <notes.md> [download-url]
#   SPARKLE_KEY_FILE  file holding the private EdDSA key (default: read it from the login keychain)
#   SPARKLE_BIN       folder with Sparkle's sign_update tool (default: download it)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1#v}"
NOTES="$2"
URL="${3:-https://github.com/harrison-bbb/screenshotty/releases/download/v${VERSION}/Screenshotty.zip}"
ZIP=dist/Screenshotty.zip
[[ -f "$ZIP" ]] || { echo "Run scripts/make-dmg.sh first" >&2; exit 1; }

if [[ -z "${SPARKLE_BIN:-}" ]]; then
  SPARKLE_BIN="build/sparkle-tools/bin"
  if [[ ! -x "$SPARKLE_BIN/sign_update" ]]; then
    mkdir -p build/sparkle-tools
    curl -fsSL https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz | tar -xJ -C build/sparkle-tools
  fi
fi

KEY_ARGS=(--account screenshotty)
[[ -n "${SPARKLE_KEY_FILE:-}" ]] && KEY_ARGS=(--ed-key-file "$SPARKLE_KEY_FILE")
SIGNATURE="$("$SPARKLE_BIN/sign_update" "${KEY_ARGS[@]}" "$ZIP")"   # sparkle:edSignature="…" length="…"

BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' build/Screenshotty.app/Contents/Info.plist)"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' build/Screenshotty.app/Contents/Info.plist)"
NOTES_MD="$(cat "$NOTES")"

cat > dist/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Screenshotty</title>
    <item>
      <title>Screenshotty ${VERSION}</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MIN_OS}</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown"><![CDATA[
${NOTES_MD}
]]></description>
      <enclosure url="${URL}" type="application/octet-stream" ${SIGNATURE} />
    </item>
  </channel>
</rss>
XML
echo "==> dist/appcast.xml (${VERSION}, build ${BUILD})"
