import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var hasPermission = CaptureService.hasScreenRecordingPermission

    var body: some View {
        Form {
            Section("Capture") {
                LabeledContent("Global shortcut") {
                    HotKeyRecorder(hotKey: $prefs.hotKey)
                }
                Picker("After capturing", selection: $prefs.afterCapture) {
                    ForEach(AfterCaptureAction.allCases) { Text($0.title).tag($0) }
                }
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

            Section("System") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                LabeledContent("Screen Recording") {
                    HStack {
                        Label(hasPermission ? "Allowed" : "Not allowed",
                              systemImage: hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(hasPermission ? .green : .orange)
                        if !hasPermission {
                            Button("Open Settings") { CaptureService.openScreenRecordingSettings() }
                        }
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
