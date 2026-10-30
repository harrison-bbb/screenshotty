import AppKit
import ServiceManagement
import ScreenshottyCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var updater = Updater.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var hasPermission = CaptureService.hasScreenRecordingPermission
    @State private var axTrusted = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section("Capture") {
                LabeledContent("Global shortcut") {
                    HotKeyRecorder(hotKey: $prefs.hotKey)
                }
                Picker("Selecting an area", selection: $prefs.captureStyle) {
                    ForEach(CaptureStyle.allCases) { Text($0.title).tag($0) }
                }
                if prefs.captureStyle == .smart {
                    LabeledContent("Element detection") {
                        HStack {
                            Label(axTrusted ? "On" : "Text blocks and windows only",
                                  systemImage: axTrusted ? "checkmark.circle.fill" : "info.circle")
                                .foregroundStyle(axTrusted ? .green : .secondary)
                            if !axTrusted {
                                Button("Turn On") {
                                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                                    axTrusted = AXIsProcessTrustedWithOptions(options)
                                }
                                .help("Accessibility permission lets the picker find buttons, panels and paragraphs inside apps")
                            }
                        }
                    }
                }
                Picker("After capturing", selection: $prefs.afterCapture) {
                    ForEach(AfterCaptureAction.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Hide sensitive info automatically", isOn: $prefs.autoHideSensitive)
                    .help("Emails, API keys, tokens, card and phone numbers and IP addresses are found on this Mac and covered on every capture")
                Picker("Hide sensitive info with", selection: $prefs.sensitiveHideKind) {
                    Text("Solid bar").tag(Annotation.Kind.redact)
                    Text("Blur").tag(Annotation.Kind.blur)
                }
                Toggle("Sharpen small screenshots", isOn: $prefs.upscaleSmallShots)
                    .help("Small captures are enlarged pixel-for-pixel on export, so they stay crisp after X, LinkedIn or Slack resize them")
                LabeledContent("Save to") {
                    HStack {
                        Text(prefs.saveFolder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…", action: chooseFolder)
                    }
                }
            }

            Section {
                BrandKitEditor(kit: $prefs.brandKit)
            } header: {
                Text("Brand kit")
            } footer: {
                Text("Used for watermarks, and offered first as background and annotation colours.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Shared folder") {
                    HStack {
                        Text(prefs.teamStylesFolder.map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") } ?? "None")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        if prefs.teamStylesFolder != nil {
                            Button("Remove") { prefs.teamStylesFolder = nil }
                        }
                        Button("Choose…", action: chooseTeamFolder)
                    }
                }
                if prefs.teamStylesFolder != nil {
                    Text("\(prefs.teamStyles.count) team style\(prefs.teamStyles.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Team styles")
            } footer: {
                Text("Pick a folder your team shares (Google Drive, iCloud, Dropbox or a git repo). Styles in it appear for everyone; right-click a style and choose Share with Team to add one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("System") {
                Toggle("Show in Dock while a window is open", isOn: $prefs.showInDock)
                    .help("Adds a Dock icon and ⌘Tab entry for open editors. Can make macOS switch desktops right after a capture.")
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if updater.isAvailable {
                    LabeledContent {
                        Button("Check Now") { updater.checkForUpdates() }
                    } label: {
                        Toggle("Tell me when there's an update", isOn: $updater.automaticallyChecks)
                    }
                }
                LabeledContent("Screen Recording") {
                    HStack {
                        Label(hasPermission ? "Allowed" : "Not allowed",
                              systemImage: hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(hasPermission ? .green : .orange)
                        if !hasPermission {
                            Button("Open Settings") { CaptureService.openScreenRecordingSettings() }
                        }
                        Button("Reset") {
                            CaptureService.resetScreenRecordingPermission()
                            UserDefaults.standard.set(true, forKey: "requestPermissionOnLaunch")
                            CaptureService.relaunch()
                        }
                        .help("Fixes captures that come back empty after an update. Screenshotty restarts and macOS asks for permission again.")
                    }
                }
            }

            Section {
                HStack {
                    Text("Screenshotty \(Bundle.main.shortVersion) · Free and open source (MIT)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Link("GitHub", destination: AppDelegate.repositoryURL)
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasPermission = CaptureService.hasScreenRecordingPermission
            axTrusted = AXIsProcessTrusted()
            launchAtLogin = SMAppService.mainApp.status == .enabled   // may have changed in System Settings
        }
    }

    private func chooseTeamFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Choose the folder your team shares styles in"
        if panel.runModal() == .OK, let url = panel.url {
            prefs.teamStylesFolder = url
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = prefs.saveFolder
        if panel.runModal() == .OK, let url = panel.url {
            prefs.saveFolder = url
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        // Nothing to do when the toggle only caught up with the real state (refresh, or a failed change reverting).
        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            let alert = NSAlert(error: error)
            alert.informativeText = "Move Screenshotty to your Applications folder and try again."
            alert.runModal()
        }
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

/// Logo, name and colours for the team.
struct BrandKitEditor: View {
    @Binding var kit: BrandKit

    var body: some View {
        LabeledContent("Logo") {
            HStack(spacing: 8) {
                if let path = kit.logoPath, let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 26)
                    Button("Remove") { kit.logoPath = nil }
                }
                Button(kit.logoPath == nil ? "Choose…" : "Change…", action: chooseLogo)
            }
        }
        TextField("Name or handle", text: $kit.name, prompt: Text("e.g. acme.com or @acme"))
        LabeledContent("Colours") {
            HStack(spacing: 6) {
                ForEach(kit.colors.indices, id: \.self) { index in
                    ColorPicker("", selection: Binding(get: { kit.colors[index].swiftUIColor },
                                                       set: { kit.colors[index] = RGBAColor($0) }),
                                supportsOpacity: false)
                        .labelsHidden()
                        .contextMenu {
                            Button("Remove") { kit.colors.remove(at: index) }
                        }
                }
                if kit.colors.count < 8 {
                    Button {
                        kit.colors.append(kit.colors.last ?? RGBAColor(hex: "#4F46E5")!)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add a brand colour. Right-click a colour to remove it.")
                }
            }
        }
    }

    private func chooseLogo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .pdf]
        panel.message = "Choose your logo. A PNG with a transparent background looks best."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let destination = BrandKit.folder.appendingPathComponent("logo-\(UUID().uuidString.prefix(8))")
            .appendingPathExtension(url.pathExtension.isEmpty ? "png" : url.pathExtension)
        kit.logoPath = (try? FileManager.default.copyItem(at: url, to: destination)) != nil ? destination.path : url.path
    }
}
