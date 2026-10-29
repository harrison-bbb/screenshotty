import Foundation

/// A named, reusable look: background, layout, frame and export size together.
/// Built-in styles cover the common places people post; users can save their own.
public struct Style: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var settings: CompositionSettings

    public init(id: String = UUID().uuidString, name: String, settings: CompositionSettings) {
        self.id = id
        self.name = name
        self.settings = settings
    }

    public var isBuiltIn: Bool { id.hasPrefix("builtin.") }
    /// Loaded from the team's shared styles folder.
    public var isTeam: Bool { id.hasPrefix("team.") }

    public static let builtIn: [Style] = [
        Style(id: "builtin.x", name: "X post",
              settings: CompositionSettings(aspectRatio: .widescreen, padding: 90, cornerRadius: 14,
                                            smartBackground: .vibrant, exportWidth: 1600)),
        Style(id: "builtin.linkedin", name: "LinkedIn",
              settings: CompositionSettings(aspectRatio: .social, padding: 90, cornerRadius: 14,
                                            smartBackground: .mesh, exportWidth: 1200)),
        Style(id: "builtin.instagram", name: "Instagram",
              settings: CompositionSettings(aspectRatio: .portrait, padding: 100, cornerRadius: 16,
                                            smartBackground: .pastel, exportWidth: 1080)),
        Style(id: "builtin.launch", name: "Launch",
              settings: CompositionSettings(aspectRatio: .widescreen, padding: 80, cornerRadius: 12,
                                            shadow: .strong, windowChrome: .browserLight,
                                            smartBackground: .mesh, exportWidth: 1920)),
        Style(id: "builtin.mobile", name: "Mobile app",
              settings: CompositionSettings(aspectRatio: .portrait, padding: 110, shadow: .strong,
                                            smartBackground: .mesh, device: .iphone, exportWidth: 1080)),
        Style(id: "builtin.laptop", name: "MacBook",
              settings: CompositionSettings(aspectRatio: .widescreen, padding: 70, shadow: .strong,
                                            smartBackground: .dark, device: .macbook, exportWidth: 1920)),
        Style(id: "builtin.docs", name: "Docs",
              settings: CompositionSettings(background: .transparent, padding: 50, cornerRadius: 10,
                                            shadow: .soft, smartBackground: nil)),
    ]
}
