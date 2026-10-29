import SwiftUI

struct WelcomeView: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var hasPermission = CaptureService.hasScreenRecordingPermission

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
            VStack(spacing: 6) {
                Text("Screenshotty lives in your menu bar")
                    .font(.title2.weight(.semibold))
                Text("Capture anything and get a polished, perfectly centred image ready to post.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                step("1", "Press \(prefs.hotKey?.displayString ?? "the menu bar icon") to capture an area. Press Space to pick a window.")
                step("2", "It opens already styled and tidied up. Pick a style, mockup or background; your look is remembered.")
                step("3", "Copy with ⌘C, save with ⌘S, or drag the preview straight into any app.")
            }
            .padding(16)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

            if !hasPermission {
                Text("macOS will ask for Screen Recording permission the first time you capture.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Button("Settings…") { WindowManager.shared.showSettings() }
                Spacer()
                Button("Capture Now") {
                    WindowManager.shared.closeWelcome()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        (NSApp.delegate as? AppDelegate)?.startCapture(.interactive)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(width: 460)
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number)
                .font(.callout.weight(.bold))
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.2), in: Circle())
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
