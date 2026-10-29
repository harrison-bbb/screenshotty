import Combine
import Foundation
import ScreenshottyCore

enum AfterCaptureAction: String, CaseIterable, Identifiable {
    case openEditor, quickPreview, copy, save
    var id: String { rawValue }
    var title: String {
        switch self {
        case .quickPreview: "Show a floating preview (copy or drag without opening the editor)"
        case .openEditor: "Open the editor"
        case .copy: "Copy to clipboard instantly"
        case .save: "Save to folder instantly"
        }
    }
}

enum CaptureStyle: String, CaseIterable, Identifiable {
    /// Screenshotty's picker: locks onto elements, text blocks and windows.
    case smart
    /// macOS's own ⌘⇧4 picker.
    case system
    var id: String { rawValue }
    var title: String {
        switch self {
        case .smart: "Smart selection (locks onto elements)"
        case .system: "macOS picker"
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

    @Published var captureStyle: CaptureStyle {
        didSet { defaults.set(captureStyle.rawValue, forKey: "captureStyle") }
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

    var allStyles: [Style] { Style.builtIn + teamStyles + savedStyles }

    // MARK: Team styles

    /// A shared folder (Google Drive, iCloud, Dropbox, a git checkout…) of `.screenshotty-style` files.
    /// Everyone pointing at the same folder sees the same styles.
    @Published var teamStylesFolder: URL? {
        didSet {
            defaults.set(teamStylesFolder?.path, forKey: "teamStylesFolder")
            reloadTeamStyles()
            watchTeamFolder()
        }
    }

    /// Styles read from the team folder. Read-only here; duplicate one to change it.
    @Published private(set) var teamStyles: [Style] = []
    private var folderWatcher: DispatchSourceFileSystemObject?

    func reloadTeamStyles() {
        guard let folder = teamStylesFolder,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            teamStyles = []
            return
        }
        teamStyles = files
            .filter { $0.pathExtension == StyleDocument.fileExtension }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url), let document = try? StyleDocument.decode(data) else { return nil }
                var style = document.style(unpackingInto: Self.importedFolder)
                style.id = "team." + url.deletingPathExtension().lastPathComponent
                return style
            }
    }

    private func watchTeamFolder() {
        folderWatcher?.cancel()
        folderWatcher = nil
        guard let folder = teamStylesFolder else { return }
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reloadTeamStyles() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        folderWatcher = source
    }

    /// The style file name for a style: its name, made safe for a file system.
    static func fileName(for style: Style) -> String {
        let cleaned = style.name.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined(separator: "-")
        return (cleaned.isEmpty ? "Style" : cleaned) + "." + StyleDocument.fileExtension
    }

    /// Writes a style into the team folder so teammates get it.
    func shareWithTeam(_ style: Style) throws {
        guard let folder = teamStylesFolder else { return }
        try StyleDocument(style: style).encoded().write(to: folder.appendingPathComponent(Self.fileName(for: style)))
        reloadTeamStyles()
    }

    /// Adds a style from a `.screenshotty-style` file to My Styles. Returns it.
    @discardableResult
    func importStyle(from url: URL) throws -> Style {
        let document = try StyleDocument.decode(Data(contentsOf: url))
        var style = document.style(unpackingInto: Self.importedFolder)
        style.id = UUID().uuidString
        if let index = savedStyles.firstIndex(where: { $0.name == style.name }) {
            savedStyles[index].settings = style.settings
            return savedStyles[index]
        }
        savedStyles.append(style)
        return style
    }

    /// Where images from imported styles and projects are kept.
    nonisolated static var importedFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Screenshotty/Imported", isDirectory: true)
    }

    /// The team's logo, name and colours: the source for watermarks and brand swatches.
    @Published var brandKit: BrandKit {
        didSet { saveJSON(brandKit, key: "brandKit") }
    }

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
        afterCapture = defaults.string(forKey: "afterCapture").flatMap(AfterCaptureAction.init(rawValue:)) ?? .openEditor
        upscaleSmallShots = defaults.object(forKey: "upscaleSmallShots") as? Bool ?? true
        captureStyle = defaults.string(forKey: "captureStyle").flatMap(CaptureStyle.init(rawValue:)) ?? .smart
        autoHideSensitive = defaults.bool(forKey: "autoHideSensitive")
        sensitiveHideKind = defaults.string(forKey: "sensitiveHideKind").flatMap(Annotation.Kind.init(rawValue:))
            .flatMap { $0 == .blur ? .blur : .redact } ?? .redact
        savedStyles = Self.loadJSON([Style].self, key: "savedStyles", defaults: defaults) ?? []
        brandKit = Self.loadJSON(BrandKit.self, key: "brandKit", defaults: defaults) ?? BrandKit()
        teamStylesFolder = defaults.string(forKey: "teamStylesFolder").map { URL(fileURLWithPath: $0, isDirectory: true) }
        recentBackgroundImages = (defaults.stringArray(forKey: "recentBackgroundImages") ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
        if let path = defaults.string(forKey: "saveFolder") {
            saveFolder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            saveFolder = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory())
        }
        // didSet doesn't run during init, so load the team folder here.
        reloadTeamStyles()
        watchTeamFolder()
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

/// Logo, name and colours used for watermarks, brand backgrounds and annotation colours.
struct BrandKit: Codable, Equatable {
    var logoPath: String?
    var name: String = ""
    var colors: [RGBAColor] = []

    var isEmpty: Bool { logoPath == nil && name.trimmingCharacters(in: .whitespaces).isEmpty && colors.isEmpty }

    /// A watermark made from the kit: logo and name when both are set.
    var watermark: Watermark { Watermark(logoPath: logoPath, text: name) }

    /// Folder for the logo copy, so the kit keeps working if the original file moves.
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("Screenshotty/Brand", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
