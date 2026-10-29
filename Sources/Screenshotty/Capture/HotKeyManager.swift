import Carbon.HIToolbox
import Foundation

/// Registers one global hotkey using Carbon's RegisterEventHotKey.
/// Unlike event taps, this needs no Accessibility permission.
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onTrigger: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    /// Returns false if the shortcut is already taken by another app.
    @discardableResult
    func register(_ hotKey: HotKey?) -> Bool {
        unregister()
        installHandlerIfNeeded()
        guard let hotKey else { return true }
        let id = EventHotKeyID(signature: OSType(0x5353_4854), id: 1) // "SSHT"
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKeyManager.shared.onTrigger?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}
