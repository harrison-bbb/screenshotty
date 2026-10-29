import Foundation

public struct BackgroundPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let style: BackgroundStyle

    public init(id: String, name: String, style: BackgroundStyle) {
        self.id = id
        self.name = name
        self.style = style
    }
}

/// Curated backgrounds. Defined in code (no asset files) so they are easy to port to other platforms.
/// The same data is documented in docs/composition-format.md.
public enum Presets {
    private static func c(_ hex: String) -> RGBAColor { RGBAColor(hex: hex)! }

    private static func linear(_ id: String, _ name: String, _ angle: Double, _ hexes: [String]) -> BackgroundPreset {
        let stops = hexes.enumerated().map { i, hex in
            GradientStop(c(hex), hexes.count == 1 ? 0 : Double(i) / Double(hexes.count - 1))
        }
        return BackgroundPreset(id: id, name: name, style: .linearGradient(LinearGradientSpec(stops: stops, angle: angle)))
    }

    private static func mesh(_ id: String, _ name: String, _ base: String, _ blobs: [(Double, Double, Double, String)]) -> BackgroundPreset {
        BackgroundPreset(id: id, name: name, style: .mesh(MeshSpec(
            base: c(base),
            blobs: blobs.map { MeshBlob(x: $0.0, y: $0.1, radius: $0.2, color: c($0.3)) })))
    }

    public static let gradients: [BackgroundPreset] = [
        linear("sunset", "Sunset", 135, ["#FF9A8B", "#FF6A88", "#FF99AC"]),
        linear("peach", "Peach", 135, ["#FFECD2", "#FCB69F"]),
        linear("citrus", "Citrus", 135, ["#F6D365", "#FDA085"]),
        linear("flamingo", "Flamingo", 135, ["#F093FB", "#F5576C"]),
        linear("lavender", "Lavender", 135, ["#A18CD1", "#FBC2EB"]),
        linear("indigo", "Indigo", 135, ["#667EEA", "#764BA2"]),
        linear("ocean", "Ocean", 135, ["#2E3192", "#1BFFFF"]),
        linear("sky", "Sky", 135, ["#89F7FE", "#66A6FF"]),
        linear("mint", "Mint", 135, ["#D4FC79", "#96E6A1"]),
        linear("emerald", "Emerald", 135, ["#0BA360", "#3CBA92"]),
        linear("midnight", "Midnight", 135, ["#0F2027", "#203A43", "#2C5364"]),
        linear("graphite", "Graphite", 135, ["#434343", "#000000"]),
        linear("cloud", "Cloud", 180, ["#FDFBFB", "#EBEDEE"]),
        linear("aurora", "Aurora", 135, ["#00C9FF", "#92FE9D"]),
        linear("berry", "Berry", 135, ["#8E2DE2", "#4A00E0"]),
        linear("ember", "Ember", 135, ["#F12711", "#F5AF19"]),
    ]

    public static let wallpapers: [BackgroundPreset] = [
        mesh("sonoma", "Hills", "#F8B26A", [
            (0.15, 0.10, 0.70, "#FF7A59"), (0.90, 0.20, 0.65, "#FFC46B"),
            (0.30, 0.95, 0.70, "#E0457B"), (0.85, 0.90, 0.60, "#8E5BD9"),
        ]),
        mesh("tahoe", "Lake", "#3A7BD5", [
            (0.10, 0.15, 0.70, "#6DD5FA"), (0.85, 0.10, 0.60, "#2980B9"),
            (0.50, 0.95, 0.75, "#1E3C72"), (0.95, 0.80, 0.50, "#7F7FD5"),
        ]),
        mesh("bloom", "Bloom", "#FBD3E9", [
            (0.10, 0.20, 0.60, "#FFAFBD"), (0.90, 0.15, 0.60, "#C9A7FF"),
            (0.20, 0.90, 0.60, "#FFC3A0"), (0.85, 0.85, 0.60, "#A0E7E5"),
        ]),
        mesh("nebula", "Nebula", "#0B0B1F", [
            (0.15, 0.20, 0.60, "#6A00F4"), (0.85, 0.25, 0.55, "#DB00B6"),
            (0.50, 0.95, 0.70, "#0496FF"), (0.90, 0.90, 0.40, "#3A0CA3"),
        ]),
        mesh("forest", "Forest", "#0F3D2E", [
            (0.10, 0.10, 0.65, "#1D976C"), (0.90, 0.30, 0.55, "#93F9B9"),
            (0.40, 0.95, 0.70, "#134E5E"), (0.95, 0.95, 0.40, "#71B280"),
        ]),
        mesh("dune", "Dune", "#E6CBA8", [
            (0.20, 0.10, 0.65, "#F3E2C7"), (0.85, 0.20, 0.55, "#D9A066"),
            (0.30, 0.90, 0.70, "#B9773E"), (0.90, 0.95, 0.50, "#F1C27D"),
        ]),
        mesh("noir", "Noir", "#111214", [
            (0.15, 0.10, 0.60, "#2B2F36"), (0.90, 0.90, 0.70, "#1A1C20"),
            (0.80, 0.15, 0.45, "#3A3F47"),
        ]),
        mesh("pastel", "Pastel", "#E8EEFF", [
            (0.05, 0.05, 0.60, "#FDE2FF"), (0.95, 0.10, 0.60, "#D7F9F1"),
            (0.10, 0.95, 0.60, "#FFF1C9"), (0.90, 0.90, 0.60, "#CDE7FF"),
        ]),
    ]

    public static let solids: [RGBAColor] = [
        "#FFFFFF", "#F5F5F7", "#E5E7EB", "#1D1D1F", "#000000",
        "#FDE68A", "#FCA5A5", "#A7F3D0", "#BFDBFE", "#C4B5FD",
    ].map { c($0) }

    public static var all: [BackgroundPreset] { gradients + wallpapers }

    public static func preset(id: String) -> BackgroundPreset? {
        all.first { $0.id == id }
    }

    public static let defaultBackground: BackgroundStyle = gradients[5].style
}
