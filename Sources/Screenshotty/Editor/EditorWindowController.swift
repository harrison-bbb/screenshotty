import AppKit
import ScreenshottyCore
import SwiftUI

final class EditorWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let model: EditorModel
    var onClose: (() -> Void)?

    @MainActor
    init(image: CGImage) {
        model = EditorModel(image: image, settings: Preferences.shared.lastSettings)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Screenshotty"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 860, height: 560)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)

        let actions = EditorActions(
            copy: { [weak self] in self?.copyImage(nil) },
            save: { [weak self] in self?.saveImage(nil) },
            saveAs: { [weak self] in self?.saveImageAs(nil) })
        window.contentViewController = NSHostingController(rootView: EditorView(model: model, actions: actions))
        window.setContentSize(NSSize(width: 1180, height: 760))
        window.delegate = self
        window.setFrameAutosaveName("EditorWindow")
        if !window.setFrameUsingName("EditorWindow") { window.center() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    // MARK: - Menu actions

    @MainActor @objc func copyImage(_ sender: Any?) {
        guard let image = render() else { return }
        Exporter.copyToPasteboard(image)
        Toast.show("Copied to clipboard")
    }

    @MainActor @objc func saveImage(_ sender: Any?) {
        guard let image = render() else { return }
        do {
            let url = try Exporter.save(image, in: Preferences.shared.saveFolder)
            Toast.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)")
        } catch {
            presentError(error)
        }
    }

    @MainActor @objc func saveImageAs(_ sender: Any?) {
        guard let image = render() else { return }
        Exporter.saveWithPanel(image, from: window, directory: Preferences.shared.saveFolder)
    }

    @MainActor @objc func pasteImage(_ sender: Any?) {
        if let image = AppDelegate.clipboardImage() { model.replaceImage(image) }
    }

    @MainActor @objc func resetStyle(_ sender: Any?) {
        model.resetStyle()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(pasteImage(_:)) {
            return MainActor.assumeIsolated { AppDelegate.clipboardImage() != nil }
        }
        return true
    }

    @MainActor private func render() -> CGImage? {
        do {
            return try model.renderFull()
        } catch {
            presentError(error)
            return nil
        }
    }
}

/// Callbacks from SwiftUI buttons into the window controller.
struct EditorActions {
    var copy: () -> Void
    var save: () -> Void
    var saveAs: () -> Void
}
