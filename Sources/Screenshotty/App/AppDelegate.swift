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
        // Load the on-device text recognition model now, so the first sensitive-info check is quick.
        Task.detached(priority: .utility) {
            SensitiveScanner.warmUp()
            RegionDetector.warmUp()
        }
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
        // Opening the app again while it runs in the menu bar takes a screenshot, like the system
        // Screenshot app. The welcome window only shows on the very first launch.
        if !flag {
            if prefs.hasLaunchedBefore { startCapture(.interactive) } else { WindowManager.shared.showWelcome() }
        }
        return true
    }

    /// Images open in the editor, `.screenshotty` projects reopen editable, style files are added to My Styles.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch url.pathExtension.lowercased() {
            case ProjectDocument.fileExtension:
                do { try WindowManager.shared.openProject(url) } catch { showOpenError(error, url: url) }
            case StyleDocument.fileExtension:
                do {
                    let style = try prefs.importStyle(from: url)
                    Toast.show("Added the style \(style.name)")
                } catch {
                    showOpenError(error, url: url)
                }
            default:
                if let image = ImageLoader.load(url) {
                    WindowManager.shared.openEditor(with: image)
                }
            }
        }
    }

    private func showOpenError(_ error: Error, url: URL) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Couldn't open \(url.lastPathComponent)"
        alert.informativeText = "The file may be damaged or from a newer version of Screenshotty. (\(error.localizedDescription))"
        alert.runModal()
    }

    @objc func importStyle() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.screenshottyStyle]
        panel.allowsMultipleSelection = true
        panel.message = "Choose .screenshotty-style files to add to My Styles"
        guard panel.runModal() == .OK else { return }
        application(NSApp, open: panel.urls)
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
        menu.addItem(withTitle: "Open from Clipboard", action: #selector(openFromClipboard), keyEquivalent: "")
        menu.addItem(withTitle: "Batch Export…", action: #selector(batchExport), keyEquivalent: "")
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
        if let item = menu.items.first(where: { $0.action == #selector(openFromClipboard) }) {
            item.isEnabled = Self.clipboardImage() != nil
        }
    }

    // MARK: - Actions (also reached from the main menu via the responder chain)

    @objc func captureInteractive() { startCapture(.interactive) }
    @objc func captureFullScreen() { startCapture(.fullScreen) }

    @objc func openImage() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .screenshottyProject, .screenshottyStyle]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        application(NSApp, open: panel.urls)
    }

    @objc func openFromClipboard() {
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
            // Smart selection when chosen; the system picker if it's off or can't start.
            var result: CaptureResult?
            if mode == .interactive, prefs.captureStyle == .smart {
                result = await SmartCapture.run()
                if result == nil { Log.write("smart capture unavailable, using the system picker") }
            }
            switch await result.asyncOr({ await CaptureService.capture(mode) }) {
            case .image(let image): handleCaptured(image)
            case .cancelled: break
            case .blocked: showCaptureBlockedAlert()
            }
        }
    }

    private func handleCaptured(_ image: CGImage) {
        switch prefs.afterCapture {
        case .quickPreview:
            QuickPreviewManager.shared.show(image)
        case .openEditor:
            WindowManager.shared.openEditor(with: image)
        case .copy:
            guard let output = try? Compositor.compose(image, settings: prefs.lastSettings,
                                                       annotations: Self.autoHideAnnotations(for: image),
                                                       minimumLongSide: prefs.exportMinimumLongSide) else { return }
            Exporter.copyToPasteboard(output)
            Toast.show("Copied to clipboard")
        case .save:
            guard let output = try? Compositor.compose(image, settings: prefs.lastSettings,
                                                       annotations: Self.autoHideAnnotations(for: image),
                                                       minimumLongSide: prefs.exportMinimumLongSide) else { return }
            do {
                let url = try Exporter.save(output, in: prefs.saveFolder)
                Toast.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)")
            } catch {
                NSApp.activate(ignoringOtherApps: true)
                NSAlert(error: error).runModal()
            }
        }
    }

    /// Covers sensitive info when auto-hide is on (used by the paths that skip the editor).
    static func autoHideAnnotations(for image: CGImage) -> [Annotation] {
        let prefs = Preferences.shared
        guard prefs.autoHideSensitive else { return [] }
        return SensitiveScanner.scan(image).map { $0.annotation(prefs.sensitiveHideKind) }
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

private extension Optional {
    func asyncOr(_ fallback: () async -> Wrapped) async -> Wrapped {
        if let self { return self }
        return await fallback()
    }
}
