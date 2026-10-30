import AppKit
import ScreenshottyCore

/// Renders the editor window to a PNG and quits, for the website and README pictures.
///
///     SCREENSHOTTY_SNAPSHOT=out.png SCREENSHOTTY_SNAPSHOT_INPUT=shot.png \
///     [SCREENSHOTTY_SNAPSHOT_STYLE=builtin.laptop] [SCREENSHOTTY_SNAPSHOT_DARK=1] [SCREENSHOTTY_SNAPSHOT_DEMO=1] \
///     Screenshotty -AppleAccentColor 5      (purple controls, whatever the Mac's accent colour)
///
/// Draws the window's own views, so it needs no Screen Recording permission.
@MainActor
enum Snapshot {
    private static let env = ProcessInfo.processInfo.environment
    static var isRequested: Bool { env["SCREENSHOTTY_SNAPSHOT"] != nil }

    static func run() {
        guard let out = env["SCREENSHOTTY_SNAPSHOT"], let input = env["SCREENSHOTTY_SNAPSHOT_INPUT"],
              let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: input) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            Log.write("snapshot: missing SCREENSHOTTY_SNAPSHOT_INPUT")
            exit(1)
        }
        NSApp.appearance = NSAppearance(named: env["SCREENSHOTTY_SNAPSHOT_DARK"] == "1" ? .darkAqua : .aqua)
        let controller = EditorWindowController(image: image)
        if let id = env["SCREENSHOTTY_SNAPSHOT_STYLE"], let style = Style.builtIn.first(where: { $0.id == id }) {
            controller.model.apply(style)
        }
        if env["SCREENSHOTTY_SNAPSHOT_DEMO"] == "1" {
            // Marks for the made-up dashboard from scripts/site/samples.swift (2x pixels).
            controller.model.preload([
                Annotation(kind: .box, start: CGPoint(x: 516, y: 180), end: CGPoint(x: 1012, y: 428)),
                Annotation(kind: .arrow, start: CGPoint(x: 1240, y: 760), end: CGPoint(x: 1500, y: 600)),
                Annotation(kind: .text, start: CGPoint(x: 900, y: 790), end: CGPoint(x: 900, y: 790), text: "Best month yet", size: 34),
            ])
        }
        guard let window = controller.window else { exit(1) }
        window.setContentSize(NSSize(width: 1180, height: 760))
        window.alphaValue = 0      // laid out and drawn, but never visible on screen
        window.orderFrontRegardless()

        // Give the preview and the style thumbnails time to render.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let view = window.contentView!.superview ?? window.contentView!   // include the title bar
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
            exit(0)
        }
    }
}
