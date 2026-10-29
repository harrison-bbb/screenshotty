import AppKit
import ScreenshottyCore
import SwiftUI

/// Owns the editor, settings and welcome windows.
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private var editors: [EditorWindowController] = []
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?

    func openEditor(with image: CGImage, annotations: [Annotation] = []) {
        let controller = EditorWindowController(image: image)
        controller.model.preload(annotations)
        controller.onClose = { [weak self, weak controller] in
            self?.editors.removeAll { $0 === controller }
        }
        editors.append(controller)
        present(controller.window!)
    }

    /// Opens a `.screenshotty` project with its crop, annotations and look restored.
    func openProject(_ url: URL) throws {
        let document = try ProjectDocument.decode(Data(contentsOf: url))
        guard let image = document.capture else { throw CocoaError(.fileReadCorruptFile) }
        let controller = EditorWindowController(image: image, settings: document.settings(unpackingInto: Preferences.importedFolder))
        controller.model.loadProject(annotations: document.annotations, crop: document.crop)
        controller.model.projectURL = url
        controller.window?.representedURL = url
        controller.window?.title = url.deletingPathExtension().lastPathComponent
        controller.onClose = { [weak self, weak controller] in
            self?.editors.removeAll { $0 === controller }
        }
        editors.append(controller)
        present(controller.window!)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Screenshotty Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
            window.center()
        }
        present(settingsWindow!)
    }

    func showWelcome() {
        if welcomeWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: WelcomeView()))
            window.title = "Welcome to Screenshotty"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            welcomeWindow = window
            window.center()
        }
        present(welcomeWindow!)
    }

    func closeWelcome() {
        welcomeWindow?.close()
    }

    /// Screenshotty's windows open on the desktop you're on, including a full-screen app's own desktop
    /// (macOS keeps ordinary windows off those and would otherwise switch you to another desktop).
    static let stayOnCurrentDesktop: NSWindow.CollectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

    /// Shows a window on the desktop you're on. Every Screenshotty window moves to the active desktop, so
    /// activating the app never jumps you to another desktop where an older window happens to be.
    private func present(_ window: NSWindow) {
        window.collectionBehavior.formUnion(Self.stayOnCurrentDesktop)
        for other in NSApp.windows where other.styleMask.contains(.titled) {
            other.collectionBehavior.formUnion(Self.stayOnCurrentDesktop)
        }
        // Screenshotty stays a menu bar app: switching to a Dock app while active (as it is right after the
        // picker) makes macOS jump to another desktop. The Dock icon is an opt-in setting.
        if Preferences.shared.showInDock { NSApp.setActivationPolicy(.regular) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Diagnostics for "the capture jumped me somewhere else": what's in front once things settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak window] in
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
            Log.write("window shown: front=\(front) key=\(window?.isKeyWindow ?? false) activeSpace=\(window?.isOnActiveSpace ?? false)")
        }
    }
}
