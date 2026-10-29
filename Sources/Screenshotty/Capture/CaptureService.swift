import AppKit
import ScreenshottyCore

enum CaptureMode {
    /// Area selection; press Space to switch to window selection (the system ⌘⇧4 picker).
    case interactive
    /// The whole main display.
    case fullScreen
}

enum CaptureResult {
    case image(CGImage)
    /// The user pressed Escape.
    case cancelled
    /// macOS returned an empty image: Screen Recording is blocked for this copy of the app.
    case blocked
}

/// Captures via macOS's own `screencapture` tool, so selection works exactly like the built-in shortcuts.
enum CaptureService {
    static func capture(_ mode: CaptureMode) async -> CaptureResult {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("screenshotty-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        var arguments = ["-x"] // no shutter sound
        switch mode {
        case .interactive: arguments += ["-i", "-o"] // -o: no system window shadow, we draw our own
        case .fullScreen: arguments += ["-m"]
        }
        arguments.append(url.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments

        let launched: Bool = await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume(returning: true) }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
        // If the user pressed Escape there is no file.
        guard launched, let image = ImageLoader.load(url) else {
            Log.write("capture \(mode): no image (cancelled or failed, launched=\(launched), status=\(process.terminationStatus))")
            return .cancelled
        }
        let blank = ImageInspector.isFullyTransparent(image)
        Log.write("capture \(mode): \(image.width)x\(image.height) blank=\(blank) permission=\(hasScreenRecordingPermission)")
        return blank ? .blocked : .image(image)
    }

    static var hasScreenRecordingPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func requestScreenRecordingPermission() {
        CGRequestScreenCaptureAccess()
    }

    /// Clears the stored Screen Recording decision for this app so macOS asks again.
    /// Fixes captures that come back empty because the permission belongs to an older build.
    @discardableResult
    static func resetScreenRecordingPermission() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ScreenCapture", Bundle.main.bundleIdentifier ?? "com.screenshotty.app"]
        do {
            try process.run()
            process.waitUntilExit()
            Log.write("tccutil reset ScreenCapture: status \(process.terminationStatus)")
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
