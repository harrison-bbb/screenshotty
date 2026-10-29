import AppKit
import ScreenshottyCore
import UniformTypeIdentifiers

enum Exporter {
    static func copyToPasteboard(_ image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // PNG keeps transparency; TIFF is there for older apps that only read TIFF.
        if let png = PNGEncoder.data(for: image) {
            pasteboard.setData(png, forType: .png)
        }
        if let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    static func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshotty \(formatter.string(from: Date()))"
    }

    /// Saves into `folder` with a unique, timestamped name.
    static func save(_ image: CGImage, in folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = defaultFileName()
        var url = folder.appendingPathComponent(base).appendingPathExtension("png")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension("png")
            n += 1
        }
        try PNGEncoder.write(image, to: url)
        return url
    }

    @MainActor
    static func saveWithPanel(_ image: CGImage, from window: NSWindow?, directory: URL) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = defaultFileName() + ".png"
        panel.directoryURL = directory
        panel.canCreateDirectories = true
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try PNGEncoder.write(image, to: url)
                Toast.show("Saved \(url.lastPathComponent)")
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    /// Writes a temporary PNG, used for dragging the result into other apps.
    static func temporaryFile(_ image: CGImage) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Screenshotty-Drag", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(defaultFileName()).appendingPathExtension("png")
        do {
            try PNGEncoder.write(image, to: url)
            return url
        } catch {
            return nil
        }
    }
}
