import AppKit

// MARK: - Main menu (visible while an editor or settings window is open)

@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Screenshotty", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(AppDelegate.checkForUpdates), keyEquivalent: "")
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
        file.addItem(withTitle: "Capture Scrolling Area", action: #selector(AppDelegate.captureScrolling), keyEquivalent: "")
        file.addItem(withTitle: "Capture Text", action: #selector(AppDelegate.captureText), keyEquivalent: "")
        file.addItem(withTitle: "Open…", action: #selector(AppDelegate.openImage), keyEquivalent: "o")
        file.addItem(withTitle: "Batch Export…", action: #selector(AppDelegate.batchExport), keyEquivalent: "")
        file.addItem(withTitle: "Import Style…", action: #selector(AppDelegate.importStyle), keyEquivalent: "")
        file.addItem(.separator())
        file.addItem(withTitle: "Save", action: #selector(EditorWindowController.saveImage(_:)), keyEquivalent: "s")
        let saveAs = file.addItem(withTitle: "Save As…", action: #selector(EditorWindowController.saveImageAs(_:)), keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        let saveProject = file.addItem(withTitle: "Save Project…", action: #selector(EditorWindowController.saveProject(_:)), keyEquivalent: "s")
        saveProject.keyEquivalentModifierMask = [.command, .option]
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu: file, title: "File")

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: #selector(EditorWindowController.undoAnnotation(_:)), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: #selector(EditorWindowController.redoAnnotation(_:)), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Copy Image", action: #selector(EditorWindowController.copyImage(_:)), keyEquivalent: "c")
        let copyText = edit.addItem(withTitle: "Copy Text", action: #selector(EditorWindowController.copyText(_:)), keyEquivalent: "c")
        copyText.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(withTitle: "Pin to Screen", action: #selector(EditorWindowController.pinToScreen(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Copy and Close", action: #selector(EditorWindowController.copyAndClose(_:)), keyEquivalent: "\r")
        edit.addItem(withTitle: "Paste Image", action: #selector(EditorWindowController.pasteImage(_:)), keyEquivalent: "v")
        let delete = edit.addItem(withTitle: "Delete Annotation", action: #selector(EditorWindowController.deleteAnnotation(_:)),
                                  keyEquivalent: String(UnicodeScalar(NSBackspaceCharacter)!))
        delete.keyEquivalentModifierMask = []
        edit.addItem(withTitle: "Clear All Annotations", action: #selector(EditorWindowController.clearAnnotations(_:)), keyEquivalent: "")
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
