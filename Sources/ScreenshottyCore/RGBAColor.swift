import CoreGraphics
import Foundation

/// An sRGB colour with components in 0...1. Encoded as a hex string ("#RRGGBB" or "#RRGGBBAA")
/// so the settings JSON stays readable and portable to other platforms.
public struct RGBAColor: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Accepts "#RGB", "#RRGGBB" or "#RRGGBBAA" (leading # optional).
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        if s.count == 6 {
            self.init(red: Double((value >> 16) & 0xFF) / 255,
                      green: Double((value >> 8) & 0xFF) / 255,
                      blue: Double(value & 0xFF) / 255)
        } else {
            self.init(red: Double((value >> 24) & 0xFF) / 255,
                      green: Double((value >> 16) & 0xFF) / 255,
                      blue: Double((value >> 8) & 0xFF) / 255,
                      alpha: Double(value & 0xFF) / 255)
        }
    }

    public var hex: String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        if byte(alpha) == 255 {
            return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        }
        return String(format: "#%02X%02X%02X%02X", byte(red), byte(green), byte(blue), byte(alpha))
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public func withAlpha(_ a: Double) -> RGBAColor {
        RGBAColor(red: red, green: green, blue: blue, alpha: a)
    }

    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
}

extension RGBAColor: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let color = RGBAColor(hex: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid hex colour \(string)")
        }
        self = color
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}
