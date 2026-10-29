import CoreGraphics
import Foundation

// MARK: - Embedded files

/// Image files a look depends on (a background image, a watermark logo), packed into a document so it
/// works on someone else's Mac. In packed settings, those paths read "asset:<name>".
public enum EmbeddedAssets {
    static let prefix = "asset:"

    /// Settings with file paths swapped for asset names, plus the files' contents.
    public static func pack(_ settings: CompositionSettings) -> (settings: CompositionSettings, files: [String: Data]) {
        var packed = settings
        var files: [String: Data] = [:]
        func embed(_ path: String) -> String {
            guard !path.hasPrefix(prefix), let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return path }
            let name = "\(contentHash(data)).\(URL(fileURLWithPath: path).pathExtension.isEmpty ? "png" : URL(fileURLWithPath: path).pathExtension)"
            files[name] = data
            return prefix + name
        }
        if case .image(var spec) = packed.background {
            spec.path = embed(spec.path)
            packed.background = .image(spec)
        }
        if let logo = packed.watermark?.logoPath {
            packed.watermark?.logoPath = embed(logo)
        }
        return (packed, files)
    }

    /// Writes the files into `folder` (named by content, so repeats are stored once) and points the
    /// settings at them.
    public static func unpack(_ settings: CompositionSettings, files: [String: Data], into folder: URL) -> CompositionSettings {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var unpacked = settings
        func restore(_ path: String) -> String? {
            guard path.hasPrefix(prefix) else { return path }
            let name = String(path.dropFirst(prefix.count))
            guard let data = files[name], !name.contains("/") else { return nil }
            let url = folder.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) { try? data.write(to: url) }
            return url.path
        }
        if case .image(var spec) = unpacked.background {
            if let path = restore(spec.path) {
                spec.path = path
                unpacked.background = .image(spec)
            } else {
                unpacked.background = Presets.defaultBackground
            }
        }
        if let logo = unpacked.watermark?.logoPath {
            unpacked.watermark?.logoPath = restore(logo)
        }
        return unpacked
    }

    /// A short, stable name for a file's contents (64-bit FNV-1a).
    static func contentHash(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

// MARK: - Style files

/// A style shared as a file (`.screenshotty-style`): the look, plus any images it uses.
public struct StyleDocument: Codable, Sendable {
    public static let fileExtension = "screenshotty-style"
    public var format = "screenshotty-style"
    public var version = 1
    public var style: Style
    public var assets: [String: Data]

    public init(style: Style) {
        let packed = EmbeddedAssets.pack(style.settings)
        var portable = style
        portable.settings = packed.settings
        self.style = portable
        self.assets = packed.files
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> StyleDocument {
        let document = try JSONDecoder().decode(StyleDocument.self, from: data)
        guard document.format == "screenshotty-style" else { throw CocoaError(.fileReadCorruptFile) }
        return document
    }

    /// The style, with its images written into `folder`.
    public func style(unpackingInto folder: URL) -> Style {
        var style = self.style
        style.settings = EmbeddedAssets.unpack(style.settings, files: assets, into: folder)
        return style
    }
}

// MARK: - Projects

/// A screenshot you can keep editing (`.screenshotty`): the original capture, crop, annotations and
/// look. Plain JSON with the images base64-encoded, so other tools (and a future Windows app) can read it.
public struct ProjectDocument: Codable, Sendable {
    public static let fileExtension = "screenshotty"
    public var format = "screenshotty-project"
    public var version = 1
    /// The original capture as PNG.
    public var image: Data
    public var settings: CompositionSettings
    public var annotations: [Annotation]
    public var crop: CGRect?
    public var assets: [String: Data]

    public init?(image: CGImage, settings: CompositionSettings, annotations: [Annotation], crop: CGRect?) {
        guard let png = PNGEncoder.data(for: image) else { return nil }
        let packed = EmbeddedAssets.pack(settings)
        self.image = png
        self.settings = packed.settings
        self.annotations = annotations
        self.crop = crop
        self.assets = packed.files
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> ProjectDocument {
        let document = try JSONDecoder().decode(ProjectDocument.self, from: data)
        guard document.format == "screenshotty-project" else { throw CocoaError(.fileReadCorruptFile) }
        return document
    }

    /// The decoded capture.
    public var capture: CGImage? { ImageLoader.load(image) }

    public func settings(unpackingInto folder: URL) -> CompositionSettings {
        EmbeddedAssets.unpack(settings, files: assets, into: folder)
    }
}
