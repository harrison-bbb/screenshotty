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

    func openEditor(with image: CGImage) {
        let controller = EditorWindowController(image: image)
        controller.onClose = { [weak self, weak controller] in
            self?.editors.removeAll { $0 === controller }
        }
        editors.append(controller)
        present(controller.window!)
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

    private func present(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
