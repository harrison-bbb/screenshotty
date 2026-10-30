import AppKit
import ScreenshottyCore

extension AppDelegate {
    // MARK: Batch export

    /// Applies one style to many images and saves them into a new folder.
    @objc func batchExport() {
        let prefs = Preferences.shared
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Choose the screenshots to export with one style"
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls

        let alert = NSAlert()
        alert.messageText = "Export \(urls.count) image\(urls.count == 1 ? "" : "s")"
        alert.informativeText = prefs.autoHideSensitive
            ? "Each image gets the style below. Sensitive info is hidden automatically."
            : "Each image gets the style below."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 26), pullsDown: false)
        popup.addItem(withTitle: "Current look")
        for style in prefs.allStyles { popup.addItem(withTitle: style.name) }
        alert.accessoryView = popup
        alert.addButton(withTitle: "Export")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let settings = popup.indexOfSelectedItem == 0 ? prefs.lastSettings : prefs.allStyles[popup.indexOfSelectedItem - 1].settings

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let folder = prefs.saveFolder.appendingPathComponent("Screenshotty Batch \(formatter.string(from: Date()))", isDirectory: true)
        let autoHide = prefs.autoHideSensitive
        let hideKind = prefs.sensitiveHideKind
        let minimumLongSide = prefs.exportMinimumLongSide
        Toast.show("Exporting \(urls.count) images…", systemImage: "square.stack.3d.up.fill")

        Task {
            let exported = await Task.detached(priority: .userInitiated) { () -> Int in
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                var count = 0
                for url in urls {
                    guard let image = ImageLoader.load(url) else { continue }
                    let marks = autoHide ? SensitiveScanner.scan(image).map { $0.annotation(hideKind) } : []
                    guard let output = try? Compositor.compose(image, settings: settings, annotations: marks,
                                                               minimumLongSide: minimumLongSide) else { continue }
                    // shot.png and shot.jpg (or same-named files from two folders) each get their own file.
                    let name = url.deletingPathExtension().lastPathComponent
                    var target = folder.appendingPathComponent(name).appendingPathExtension("png")
                    var copy = 2
                    while FileManager.default.fileExists(atPath: target.path) {
                        target = folder.appendingPathComponent("\(name) \(copy)").appendingPathExtension("png")
                        copy += 1
                    }
                    if (try? PNGEncoder.write(output, to: target)) != nil {
                        count += 1
                    }
                }
                return count
            }.value
            Toast.show("Exported \(exported) of \(urls.count) images")
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
    }
}
