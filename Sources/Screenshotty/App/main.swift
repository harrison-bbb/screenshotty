import AppKit

// `Screenshotty render ...` runs headless from the terminal; anything else launches the menu bar app.
if CommandLine.arguments.count > 1, CommandLine.arguments[1] == "render" {
    exit(CLI.run(Array(CommandLine.arguments.dropFirst(2))))
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
