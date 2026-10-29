import Combine
import Foundation
import ScreenshottyCore

enum AfterCaptureAction: String, CaseIterable, Identifiable {
    case quickPreview, openEditor, copy, save
    var id: String { rawValue }
    var title: String {
        switch self {
        case .quickPreview: "Show a quick preview"
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

    /// Enlarge small results pixel-for-pixel on export so they stay sharp once posted.
    @Published var upscaleSmallShots: Bool {
        didSet { defaults.set(upscaleSmallShots, forKey: "upscaleSmallShots") }
    }

    var exportMinimumLongSide: CGFloat? { upscaleSmallShots ? ExportScale.defaultMinimumLongSide : nil }

    /// Hide emails, API keys and similar automatically on every capture. Sticks once turned on.
    @Published var autoHideSensitive: Bool {
        didSet { defaults.set(autoHideSensitive, forKey: "autoHideSensitive") }
    }

    /// How sensitive info is hidden: a solid bar (`.redact`) or pixelation (`.blur`).
    @Published var sensitiveHideKind: Annotation.Kind {
        didSet { defaults.set(sensitiveHideKind.rawValue, forKey: "sensitiveHideKind") }
    }

    /// Styles the user saved, newest last.
    @Published var savedStyles: [Style] {
        didSet { saveJSON(savedStyles, key: "savedStyles") }
    }

    var allStyles: [Style] { Style.builtIn + savedStyles }

    /// Background images used before (paths inside Application Support), most recent first.
    @Published private(set) var recentBackgroundImages: [String] {
        didSet { defaults.set(recentBackgroundImages, forKey: "recentBackgroundImages") }
    }

    static let maxRecentImages = 12

    func rememberBackgroundImage(_ path: String) {
        guard recentBackgroundImages.first != path else { return }
        var list = recentBackgroundImages.filter { $0 != path }
        list.insert(path, at: 0)
        recentBackgroundImages = Array(list.prefix(Self.maxRecentImages))
    }

    func forgetBackgroundImage(_ path: String) {
        // The file is kept: a saved style may still use it.
        recentBackgroundImages.removeAll { $0 == path }
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
        afterCapture = defaults.string(forKey: "afterCapture").flatMap(AfterCaptureAction.init(rawValue:)) ?? .quickPreview
        upscaleSmallShots = defaults.object(forKey: "upscaleSmallShots") as? Bool ?? true
        autoHideSensitive = defaults.bool(forKey: "autoHideSensitive")
        sensitiveHideKind = defaults.string(forKey: "sensitiveHideKind").flatMap(Annotation.Kind.init(rawValue:))
            .flatMap { $0 == .blur ? .blur : .redact } ?? .redact
        savedStyles = Self.loadJSON([Style].self, key: "savedStyles", defaults: defaults) ?? []
        recentBackgroundImages = (defaults.stringArray(forKey: "recentBackgroundImages") ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
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
