import AppKit
import ScreenCaptureKit

/// A frozen picture of one display, taken when the capture starts so the selection is made on a still image.
struct FrozenScreen {
    let screen: NSScreen
    let image: CGImage
    /// The display's frame in global top-left coordinates (points), like Accessibility and window lists use.
    let globalFrame: CGRect
    var scale: CGFloat { screen.backingScaleFactor }

    /// The pixels inside `rect` (global top-left points).
    func crop(_ rect: CGRect) -> CGImage? {
        let local = rect.offsetBy(dx: -globalFrame.minX, dy: -globalFrame.minY)
        let pixels = CGRect(x: local.minX * scale, y: local.minY * scale, width: local.width * scale, height: local.height * scale)
            .integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !pixels.isEmpty else { return nil }
        return image.cropping(to: pixels)
    }
}

/// A window that can be picked whole, front to back.
struct PickableWindow {
    let id: CGWindowID
    let frame: CGRect          // global top-left points
    let pid: pid_t
    let title: String
    let appName: String
}

enum ScreenFreezer {
    /// The height of the main display, for converting AppKit's bottom-left coordinates.
    static var mainHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func globalFrame(of screen: NSScreen) -> CGRect {
        CGRect(x: screen.frame.minX, y: mainHeight - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
    }

    /// Snapshots every display, leaving out Screenshotty's own windows.
    static func freeze() async throws -> [FrozenScreen] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
        var result: [FrozenScreen] = []
        for display in content.displays {
            guard let screen = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
            }) else { continue }
            let config = SCStreamConfiguration()
            config.width = Int(CGFloat(display.width) * screen.backingScaleFactor)
            config.height = Int(CGFloat(display.height) * screen.backingScaleFactor)
            config.showsCursor = false
            config.captureResolution = .best
            let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            result.append(FrozenScreen(screen: screen, image: image, globalFrame: globalFrame(of: screen)))
        }
        return result
    }

    /// Normal app windows on screen, frontmost first.
    static func windows() -> [PickableWindow] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        let all: [PickableWindow] = list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= 40, bounds.height >= 40,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.05 else { return nil }
            return PickableWindow(id: id, frame: bounds, pid: pid,
                                  title: info[kCGWindowName as String] as? String ?? "",
                                  appName: info[kCGWindowOwnerName as String] as? String ?? "")
        }
        // Apps like browsers float invisible, untitled helper windows over their real window (toasts,
        // overlays). Skip untitled windows that sit inside a titled window of the same app.
        return all.filter { window in
            guard window.title.isEmpty else { return true }
            return !all.contains { other in
                other.id != window.id && other.pid == window.pid && !other.title.isEmpty &&
                    other.frame.insetBy(dx: -2, dy: -2).contains(window.frame)
            }
        }
    }

    /// One window on its own: no shadow, transparent rounded corners, and nothing covering it.
    static func capture(window id: CGWindowID, scale: CGFloat) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let window = content.windows.first(where: { $0.windowID == id }) else { return nil }
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.captureResolution = .best
        config.backgroundColor = .clear
        return try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                         configuration: config)
    }
}
