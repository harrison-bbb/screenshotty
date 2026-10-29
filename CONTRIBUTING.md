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

Builds are ad-hoc signed with a designated requirement pinned to the bundle identifier
(`com.screenshotty.app`), so Screen Recording permission survives rebuilds and updates. Do not remove
that requirement from `scripts/build-app.sh`: without it every build looks like a new app to macOS and
captures silently come back empty. Capture diagnostics go to `~/Library/Logs/Screenshotty.log`.

## How the code is organised

| Folder | What lives there |
| --- | --- |
| `Sources/ScreenshottyCore` | Everything that decides how the image looks, with no AppKit: the settings model and styles, presets and smart backgrounds, edge repair and auto-trim, layout, devices and window chrome, annotations, watermarks, sensitive-info scanning, the style and project file formats, and the Core Graphics compositor. A future Windows version can port this folder as a reference. |
| `Sources/Screenshotty/App` | App entry point, menu bar item, main menu, batch export, windows and the CLI. |
| `Sources/Screenshotty/Capture` | Capture via `/usr/sbin/screencapture`, the global hotkey, and the floating preview card. |
| `Sources/Screenshotty/Editor` | The editor window: canvas, annotation tools, crop, inspector, style cards, background picker and export. |
| `Sources/Screenshotty/Settings` | Preferences and the settings window. |
| `Tests/ScreenshottyTests` | Swift Testing tests for the core. Test files import only `Testing` and `CoreGraphics`; Foundation helpers live in `TestImages.swift` so the tests build with the Command Line Tools alone. |

A few rules keep things predictable:

- **One renderer.** The editor preview, the floating preview, exports and the CLI all go through
  `ShotPreparer.prepareShot` and `Compositor.render`, so what you see is what you get.
- **Units, not pixels.** Layout lengths use units of 1/1000 of the screenshot's longest side, so a style
  looks the same on any display. See [docs/composition-format.md](docs/composition-format.md).
- **Annotations live in capture pixels.** They stay attached to the content through crops, trims and style
  changes. The prepared shot's `offset` maps them into place.
- **Everything is drawn in code.** Devices, window chrome and wallpapers need no image assets.

## Adding a background preset

Add an entry to `Sources/ScreenshottyCore/Presets.swift` and document it if it needs explanation.
Keep preset IDs stable because the CLI and saved settings refer to them.

## Adding a built-in style

Add a `Style` to `Style.builtIn` in `Sources/ScreenshottyCore/Style.swift` with an id starting `builtin.`,
then add a row to the styles table in `docs/composition-format.md`. The CLI picks it up as `--style <id>`.

## Pull requests

- Keep changes focused and run `scripts/test.sh` before opening a PR.
- Add tests for changes to `ScreenshottyCore`.
- Include a before and after image for visual changes.

## Releasing

Push a tag like `v0.4.0`. GitHub Actions builds a universal app, packages a DMG and ZIP, and publishes a release.
The Homebrew cask and install script always point at the latest release.
