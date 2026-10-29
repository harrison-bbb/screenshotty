import AppKit
import ScreenshottyCore

enum CaptureMode {
    /// Area selection; press Space to switch to window selection (the system ⌘⇧4 picker).
    case interactive
    /// The whole main display.
    case fullScreen
}

/// Captures via macOS's own `screencapture` tool, so selection works exactly like the built-in shortcuts.
enum CaptureService {
    static func capture(_ mode: CaptureMode) async -> CGImage? {
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
        guard launched else { return nil }
        // If the user pressed Escape there is no file.
        return ImageLoader.load(url)
    }

    static var hasScreenRecordingPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func requestScreenRecordingPermission() {
        CGRequestScreenCaptureAccess()
    }

    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
