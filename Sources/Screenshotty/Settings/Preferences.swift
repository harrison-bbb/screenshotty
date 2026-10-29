import Combine
import Foundation
import ScreenshottyCore

enum AfterCaptureAction: String, CaseIterable, Identifiable {
    case openEditor, copy, save
    var id: String { rawValue }
    var title: String {
        switch self {
        case .openEditor: "Open the editor"
        case .copy: "Copy to clipboard instantly"
        case .save: "Save to folder instantly"
        }
    }
}

/// User preferences, persisted in UserDefaults.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    /// The look used for the next capture (the last one the user picked).
    @Published var lastSettings: CompositionSettings {
        didSet { saveJSON(lastSettings, key: "lastSettings") }
    }

    @Published var hotKey: HotKey? {
        didSet {
            if let hotKey { saveJSON(hotKey, key: "hotKey") } else { defaults.set("none", forKey: "hotKey") }
        }
    }

    @Published var afterCapture: AfterCaptureAction {
        didSet { defaults.set(afterCapture.rawValue, forKey: "afterCapture") }
    }

    @Published var saveFolder: URL {
        didSet { defaults.set(saveFolder.path, forKey: "saveFolder") }
    }

    var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: "hasLaunchedBefore") }
        set { defaults.set(newValue, forKey: "hasLaunchedBefore") }
    }

    private init() {
        lastSettings = Self.loadJSON(CompositionSettings.self, key: "lastSettings", defaults: defaults) ?? .default
        if defaults.string(forKey: "hotKey") == "none" {
            hotKey = nil
        } else {
            hotKey = Self.loadJSON(HotKey.self, key: "hotKey", defaults: defaults) ?? .default
        }
        afterCapture = defaults.string(forKey: "afterCapture").flatMap(AfterCaptureAction.init(rawValue:)) ?? .openEditor
        if let path = defaults.string(forKey: "saveFolder") {
            saveFolder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            saveFolder = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory())
        }
    }

    private func saveJSON<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func loadJSON<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Where custom background images are copied so they keep working if the original moves.
    static var backgroundsFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("Screenshotty/Backgrounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
