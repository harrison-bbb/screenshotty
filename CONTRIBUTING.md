# Contributing to Screenshotty

Thanks for helping. Bug reports, presets, features and docs are all welcome.

## Setup

You need macOS 14+ and either the Xcode Command Line Tools or Xcode.

```bash
scripts/test.sh            # run the tests
scripts/build-app.sh       # build build/Screenshotty.app
open build/Screenshotty.app
```

You can also open `Package.swift` in Xcode.

Each local build is ad-hoc signed with a new signature, so macOS may ask for Screen Recording
permission again after rebuilding. If capture shows only your wallpaper, remove Screenshotty from
**Privacy & Security → Screen & System Audio Recording**, add it again, and relaunch.

## How the code is organised

| Folder | What lives there |
| --- | --- |
| `Sources/ScreenshottyCore` | Platform-neutral rendering: settings model, presets, auto-trim, layout and the Core Graphics compositor. No AppKit. |
| `Sources/Screenshotty/App` | App entry point, menu bar item, main menu, windows, CLI. |
| `Sources/Screenshotty/Capture` | Capture via `/usr/sbin/screencapture`, and the global hotkey. |
| `Sources/Screenshotty/Editor` | The editor window: live preview, inspector, background picker, export. |
| `Sources/Screenshotty/Settings` | Preferences and the settings window. |
| `Tests/ScreenshottyTests` | Swift Testing tests for the core. |

The preview and the export use the same `Compositor.render` call, so what you see is what you get.
Layout lengths use "units" of 1/1000 of the screenshot's longest side, so styles look the same on any display.

## Adding a background preset

Add an entry to `Sources/ScreenshottyCore/Presets.swift` and document it if it needs explanation.
Keep preset IDs stable because the CLI and saved settings refer to them.

## Pull requests

- Keep changes focused and run `scripts/test.sh` before opening a PR.
- Add tests for changes to `ScreenshottyCore`.
- Include a before and after image for visual changes.

## Releasing

Push a tag like `v0.2.0`. GitHub Actions builds a universal app, packages a DMG and ZIP, and publishes a release.
The Homebrew cask and install script always point at the latest release.
