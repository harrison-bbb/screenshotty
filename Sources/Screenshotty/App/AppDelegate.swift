import AppKit
import Combine
import ScreenshottyCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let repositoryURL = URL(string: "https://github.com/harrison-bbb/screenshotty")!

    private var statusItem: NSStatusItem!
    private var captureMenuItem: NSMenuItem!
    private var cancellables = Set<AnyCancellable>()
    private var isCapturing = false
    private let prefs = Preferences.shared

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("launch \(Bundle.main.shortVersion) (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "?")) permission=\(CaptureService.hasScreenRecordingPermission)")
        NSApp.mainMenu = MainMenu.build()
        setUpStatusItem()

        HotKeyManager.shared.onTrigger = { [weak self] in self?.startCapture(.interactive) }
        prefs.$hotKey
            .sink { [weak self] hotKey in
                if !HotKeyManager.shared.register(hotKey), let hotKey {
                    Toast.show("\(hotKey.displayString) is used by another app", systemImage: "exclamationmark.triangle.fill")
                }
                self?.updateCaptureMenuShortcut(hotKey)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)
            .sink { [weak self] _ in
                // Run after the window is gone so it isn't counted.
                DispatchQueue.main.async { self?.updateActivationPolicy() }
            }
            .store(in: &cancellables)

        if UserDefaults.standard.bool(forKey: "requestPermissionOnLaunch") {
            UserDefaults.standard.removeObject(forKey: "requestPermissionOnLaunch")
            CaptureService.requestScreenRecordingPermission()
        }

        if !prefs.hasLaunchedBefore {
            prefs.hasLaunchedBefore = true
            WindowManager.shared.showWelcome()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Double-clicking the app again while it runs in the menu bar: show something useful.
        if !flag { WindowManager.shared.showWelcome() }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let image = ImageLoader.load(url) {
                WindowManager.shared.openEditor(with: image)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Show in the Dock and app switcher only while a window is open.
    func updateActivationPolicy() {
        let hasWindows = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
        let policy: NSApplication.ActivationPolicy = hasWindows ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Screenshotty")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        captureMenuItem = menu.addItem(withTitle: "Capture Area or Window", action: #selector(captureInteractive), keyEquivalent: "")
        menu.addItem(withTitle: "Capture Full Screen", action: #selector(captureFullScreen), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Image…", action: #selector(openImage), keyEquivalent: "")
        menu.addItem(withTitle: "Beautify Clipboard Image", action: #selector(beautifyClipboard), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Screenshotty on GitHub", action: #selector(openRepository), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Screenshotty", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        menu.delegate = self
        statusItem.menu = menu
    }

    private func updateCaptureMenuShortcut(_ hotKey: HotKey?) {
        guard let item = captureMenuItem else { return }
        if let (key, flags) = hotKey?.menuKeyEquivalent {
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = flags
        } else {
            item.keyEquivalent = ""
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if let item = menu.items.first(where: { $0.action == #selector(beautifyClipboard) }) {
            item.isEnabled = Self.clipboardImage() != nil
        }
    }

    // MARK: - Actions (also reached from the main menu via the responder chain)

    @objc func captureInteractive() { startCapture(.interactive) }
    @objc func captureFullScreen() { startCapture(.fullScreen) }

    @objc func openImage() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        application(NSApp, open: panel.urls)
    }

    @objc func beautifyClipboard() {
        guard let image = Self.clipboardImage() else {
            Toast.show("No image on the clipboard", systemImage: "exclamationmark.triangle.fill")
            return
        }
        WindowManager.shared.openEditor(with: image)
    }

    @objc func showSettings() { WindowManager.shared.showSettings() }
    @objc func openRepository() { NSWorkspace.shared.open(Self.repositoryURL) }

    static func clipboardImage() -> CGImage? {
        let pasteboard = NSPasteboard.general
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), let image = ImageLoader.load(data) { return image }
        }
        if let url = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?.first as? URL {
            return ImageLoader.load(url)
        }
        return nil
    }

    // MARK: - Capture flow

    func startCapture(_ mode: CaptureMode) {
        guard !isCapturing else { return }
        guard ensureScreenRecordingPermission() else { return }
        isCapturing = true
        Task { @MainActor in
            defer { isCapturing = false }
            switch await CaptureService.capture(mode) {
            case .image(let image): handleCaptured(image)
            case .cancelled: break
            case .blocked: showCaptureBlockedAlert()
            }
        }
    }

    private func handleCaptured(_ image: CGImage) {
        switch prefs.afterCapture {
        case .openEditor:
            WindowManager.shared.openEditor(with: image)
        case .copy:
            guard let output = try? Compositor.compose(image, settings: prefs.lastSettings) else { return }
            Exporter.copyToPasteboard(output)
            Toast.show("Copied to clipboard")
        case .save:
            guard let output = try? Compositor.compose(image, settings: prefs.lastSettings) else { return }
            do {
                let url = try Exporter.save(output, in: prefs.saveFolder)
                Toast.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)")
            } catch {
                NSApp.activate(ignoringOtherApps: true)
                NSAlert(error: error).runModal()
            }
        }
    }

    /// Shown when macOS hands back an empty image even though permission looks granted.
    /// This happens when the permission was given to a different build of the app.
    func showCaptureBlockedAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "macOS blocked the capture"
        alert.informativeText = """
        The screenshot came back empty. This happens when Screen Recording permission was given to \
        an older copy of Screenshotty, for example before an update.

        Click Reset Permission. Screenshotty will restart and macOS will ask again. Allow it, then \
        quit and reopen Screenshotty if macOS asks you to.
        """
        alert.addButton(withTitle: "Reset Permission")
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            CaptureService.resetScreenRecordingPermission()
            UserDefaults.standard.set(true, forKey: "requestPermissionOnLaunch")
            CaptureService.relaunch()
        case .alertSecondButtonReturn:
            CaptureService.openScreenRecordingSettings()
        default:
            break
        }
    }

    /// Returns true if capture should go ahead.
    private func ensureScreenRecordingPermission() -> Bool {
        if CaptureService.hasScreenRecordingPermission { return true }
        Log.write("capture requested without Screen Recording permission")
        CaptureService.requestScreenRecordingPermission()

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Allow Screen Recording"
        alert.informativeText = """
        macOS needs your permission before Screenshotty can capture the screen.

        Open System Settings → Privacy & Security → Screen & System Audio Recording, \
        turn on Screenshotty, then quit and reopen Screenshotty.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Try Anyway")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            CaptureService.openScreenRecordingSettings()
            return false
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }
}

// MARK: - Main menu (visible while an editor or settings window is open)

@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Screenshotty", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Screenshotty", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Screenshotty", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: appMenu, title: "Screenshotty")

        let file = NSMenu(title: "File")
        file.addItem(withTitle: "New Capture", action: #selector(AppDelegate.captureInteractive), keyEquivalent: "n")
        let full = file.addItem(withTitle: "Capture Full Screen", action: #selector(AppDelegate.captureFullScreen), keyEquivalent: "n")
        full.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(withTitle: "Open Image…", action: #selector(AppDelegate.openImage), keyEquivalent: "o")
        file.addItem(.separator())
        file.addItem(withTitle: "Save", action: #selector(EditorWindowController.saveImage(_:)), keyEquivalent: "s")
        let saveAs = file.addItem(withTitle: "Save As…", action: #selector(EditorWindowController.saveImageAs(_:)), keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu: file, title: "File")

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy Image", action: #selector(EditorWindowController.copyImage(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste Image", action: #selector(EditorWindowController.pasteImage(_:)), keyEquivalent: "v")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Reset Style", action: #selector(EditorWindowController.resetStyle(_:)), keyEquivalent: "")
        main.addItem(submenu: edit, title: "Edit")

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        main.addItem(submenu: window, title: "Window")
        NSApp.windowsMenu = window

        let help = NSMenu(title: "Help")
        help.addItem(withTitle: "Screenshotty on GitHub", action: #selector(AppDelegate.openRepository), keyEquivalent: "")
        main.addItem(submenu: help, title: "Help")
        NSApp.helpMenu = help

        return main
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        submenu.title = title
        item.submenu = submenu
        addItem(item)
    }
}
