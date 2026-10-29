import AppKit
import ScreenshottyCore
import SwiftUI

final class EditorWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let model: EditorModel
    var onClose: (() -> Void)?

    @MainActor
    init(image: CGImage, settings: CompositionSettings? = nil) {
        model = EditorModel(image: image, settings: settings ?? Preferences.shared.lastSettings)
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
            saveAs: { [weak self] in self?.saveImageAs(nil) },
            saveProject: { [weak self] in self?.saveProject(nil) })
        window.contentViewController = NSHostingController(rootView: EditorView(model: model, actions: actions))
        window.setContentSize(NSSize(width: 1180, height: 760))
        window.delegate = self
        window.setFrameAutosaveName("EditorWindow")
        if !window.setFrameUsingName("EditorWindow") { window.center() }

        // Esc steps back one level: out of a crop or a label being typed, then deselects, then closes.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self, let window = self.window, event.window === window else { return event }
            return MainActor.assumeIsolated { self.handleEscape() } ? nil : event
        }
    }

    private var escapeMonitor: Any?

    /// Returns true when Esc was used.
    @MainActor private func handleEscape() -> Bool {
        if model.tool == .crop { return false }          // the crop tool's own Cancel handles it
        if model.textEditing != nil { model.cancelText(); return true }
        if window?.firstResponder is NSText { window?.makeFirstResponder(nil); return true }
        if model.selectedID != nil { model.select(nil); return true }
        window?.performClose(nil)
        return true
    }

    /// Copies the finished image and closes the editor: the quickest way out (⌘↩).
    @MainActor @objc func copyAndClose(_ sender: Any?) {
        guard let image = render() else { return }
        Exporter.copyToPasteboard(image)
        Toast.show("Copied to clipboard")
        window?.performClose(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
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

    /// Saves a re-editable `.screenshotty` file: straight back to the file it came from, or via a panel.
    @MainActor @objc func saveProject(_ sender: Any?) {
        guard let document = ProjectDocument(image: model.source, settings: model.settings,
                                             annotations: model.annotations, crop: model.crop) else { return }
        let write: (URL) -> Void = { [weak self] url in
            do {
                try document.encoded().write(to: url, options: .atomic)
                self?.model.projectURL = url
                self?.window?.representedURL = url
                self?.window?.title = url.deletingPathExtension().lastPathComponent
                Toast.show("Saved \(url.lastPathComponent)")
            } catch {
                self?.presentError(error)
            }
        }
        if let url = model.projectURL {
            write(url)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.screenshottyProject]
        panel.nameFieldStringValue = Exporter.defaultFileName() + "." + ProjectDocument.fileExtension
        panel.directoryURL = Preferences.shared.saveFolder
        panel.message = "A project keeps the crop, annotations and style editable."
        guard let window else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { write(url) }
        }
    }

    @MainActor @objc func pasteImage(_ sender: Any?) {
        if let image = AppDelegate.clipboardImage() { model.replaceImage(image) }
    }

    @MainActor @objc func resetStyle(_ sender: Any?) {
        model.resetStyle()
    }

    @MainActor @objc func undoAnnotation(_ sender: Any?) { model.undo() }
    @MainActor @objc func redoAnnotation(_ sender: Any?) { model.redo() }
    @MainActor @objc func deleteAnnotation(_ sender: Any?) { model.deleteSelected() }
    @MainActor @objc func clearAnnotations(_ sender: Any?) { model.clearAnnotations() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        MainActor.assumeIsolated {
            // While typing (a text label, the browser address), Copy, Paste, Undo and Delete belong to the text.
            let typing = window?.firstResponder is NSText
            let textActions: [Selector] = [#selector(copyImage(_:)), #selector(pasteImage(_:)), #selector(undoAnnotation(_:)),
                                            #selector(redoAnnotation(_:)), #selector(deleteAnnotation(_:))]
            if typing, let action = menuItem.action, textActions.contains(action) { return false }
            switch menuItem.action {
            case #selector(pasteImage(_:)): return AppDelegate.clipboardImage() != nil
            case #selector(undoAnnotation(_:)): return model.canUndo
            case #selector(redoAnnotation(_:)): return model.canRedo
            case #selector(deleteAnnotation(_:)): return model.selectedID != nil
            case #selector(clearAnnotations(_:)): return !model.annotations.isEmpty
            default: return true
            }
        }
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
    var saveProject: () -> Void
}
