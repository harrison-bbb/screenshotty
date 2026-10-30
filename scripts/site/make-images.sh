#!/usr/bin/env bash
# Regenerates the website pictures in site/images from made-up sample screens, using Screenshotty itself.
# Run after UI changes so the site shows the current editor. Usage: scripts/site/make-images.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
swift build -c release --product Screenshotty >/dev/null
APP="$(swift build -c release --show-bin-path)/Screenshotty"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swift scripts/site/samples.swift dashboard "$TMP/dashboard.png"
swift scripts/site/samples.swift phone "$TMP/phone.png"

render() { "$APP" render "$@" >/dev/null; }
render "$TMP/dashboard.png" -o "$TMP/after.png" --style x --smart vibrant --width 1800
render "$TMP/dashboard.png" -o "$TMP/before.png" --color FFFFFF --padding 0 --radius 0 --shadow none --aspect 16:9 --no-trim --width 1800
render "$TMP/dashboard.png" -o "$TMP/redacted.png" --redact --preset lavender --chrome light --aspect 16:9 --width 1800
render "$TMP/dashboard.png" -o "$TMP/macbook.png" --style laptop --preset sonoma --width 1800
render "$TMP/dashboard.png" -o "$TMP/browser.png" --chrome browser-light --url northwind.io/overview --preset ocean --aspect 16:9 --width 1800
render "$TMP/phone.png" -o "$TMP/iphone.png" --device iphone --preset bloom --aspect 4:5 --width 1200

# The editor window, drawn by the app itself (purple controls regardless of this Mac's accent colour).
for mode in light dark; do
  SCREENSHOTTY_SNAPSHOT="$TMP/editor-$mode.png" SCREENSHOTTY_SNAPSHOT_INPUT="$TMP/dashboard.png" \
  SCREENSHOTTY_SNAPSHOT_STYLE=builtin.x SCREENSHOTTY_SNAPSHOT_DEMO=1 \
  SCREENSHOTTY_SNAPSHOT_DARK=$([[ $mode == dark ]] && echo 1 || echo 0) "$APP" -AppleAccentColor 5
done

jpg() { sips -s format jpeg -s formatOptions 82 -Z "$3" "$TMP/$1.png" --out "site/images/$2.jpg" >/dev/null; }
jpg editor-light editor-light 2000; jpg editor-dark editor-dark 2000
jpg after after 1600; jpg before before 1600; jpg redacted redacted 1400
jpg macbook macbook 1400; jpg browser browser 1400; jpg iphone iphone 900
echo "site/images updated"
