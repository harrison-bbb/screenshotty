#!/usr/bin/env bash
# Generates build/AppIcon.icns from scripts/make-icon.swift (uses only tools in the Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
swift scripts/make-icon.swift build/AppIcon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d build/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o build/AppIcon.icns
cp build/AppIcon-1024.png Packaging/AppIcon.png
echo "build/AppIcon.icns"
