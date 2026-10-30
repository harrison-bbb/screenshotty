import AppKit
import SwiftUI

/// Click, then press a key combination. Esc cancels, Delete clears.
struct HotKeyRecorder: View {
    @Binding var hotKey: HotKey?
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleRecording) {
                Text(isRecording ? "Type shortcut…" : (hotKey?.displayString ?? "None"))
                    .frame(minWidth: 110)
                    .foregroundStyle(isRecording ? Color.accentColor : .primary)
            }
            if hotKey != nil, !isRecording {
                Button {
                    hotKey = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove shortcut")
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        HotKeyManager.shared.unregister() // so pressing the current combo is captured here
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case 53: // Escape
                stopRecording()
            case 51, 117: // Delete, Forward Delete
                hotKey = nil
                stopRecording()
            default:
                guard let recorded = HotKey(event: event) else {
                    NSSound.beep()
                    return nil
                }
                // Keep listening (and the old shortcut) if macOS won't accept this one, e.g. Option-only combos.
                guard HotKeyManager.shared.register(recorded) else {
                    NSSound.beep()
                    Toast.show("\(recorded.displayString) can't be used. Try one with ⌘ or ⌃.",
                               systemImage: "exclamationmark.triangle.fill")
                    return nil
                }
                hotKey = recorded
                stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        HotKeyManager.shared.register(hotKey)
    }
}
