#!/usr/bin/env bash
# Runs the test suite. Works with full Xcode or with only the Command Line Tools installed.
set -euo pipefail
cd "$(dirname "$0")/.."
CLT_FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools* && -d "$CLT_FRAMEWORKS/Testing.framework" ]]; then
  exec swift test -Xswiftc -F"$CLT_FRAMEWORKS" -Xlinker -F"$CLT_FRAMEWORKS" -Xlinker -rpath -Xlinker "$CLT_FRAMEWORKS" "$@"
fi
exec swift test "$@"
