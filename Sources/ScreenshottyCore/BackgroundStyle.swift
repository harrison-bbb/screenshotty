import Foundation

public struct GradientStop: Codable, Hashable, Sendable {
    public var color: RGBAColor
    /// 0...1 along the gradient line.
    public var location: Double

    public init(_ color: RGBAColor, _ location: Double) {
        self.color = color
        self.location = location
    }
}

public struct LinearGradientSpec: Codable, Hashable, Sendable {
    public var stops: [GradientStop]
    /// CSS convention: 0 = towards the top, 90 = towards the right, 180 = towards the bottom.
    public var angle: Double

    public init(stops: [GradientStop], angle: Double) {
        self.stops = stops
        self.angle = angle
    }
}

/// A soft colour blob used to build "mesh" style wallpapers.
public struct MeshBlob: Codable, Hashable, Sendable {
    /// Centre, as a fraction of canvas width / height (0,0 = top-left).
    public var x: Double
    public var y: Double
    /// Radius as a fraction of the canvas' longest side.
    public var radius: Double
    public var color: RGBAColor

    public init(x: Double, y: Double, radius: Double, color: RGBAColor) {
        self.x = x
        self.y = y
        self.radius = radius
        self.color = color
    }
}

public struct MeshSpec: Codable, Hashable, Sendable {
    public var base: RGBAColor
    public var blobs: [MeshBlob]

    public init(base: RGBAColor, blobs: [MeshBlob]) {
        self.base = base
        self.blobs = blobs
    }
}

public struct ImageBackgroundSpec: Codable, Hashable, Sendable {
    /// Absolute path to an image file on disk.
    public var path: String
    /// Gaussian blur radius in layout units (see `CompositionSettings`).
    public var blur: Double

    public init(path: String, blur: Double = 0) {
        self.path = path
        self.blur = blur
    }
}

/// What gets painted behind the screenshot.
///
/// JSON form uses a `type` discriminator, e.g.
/// `{"type":"linearGradient","stops":[...],"angle":135}`.
public enum BackgroundStyle: Hashable, Sendable {
    case transparent
    case solid(RGBAColor)
    case linearGradient(LinearGradientSpec)
    case mesh(MeshSpec)
    case image(ImageBackgroundSpec)

    public var kind: Kind {
        switch self {
        case .transparent: .transparent
        case .solid: .solid
        case .linearGradient: .linearGradient
        case .mesh: .mesh
        case .image: .image
        }
    }

    public enum Kind: String, Codable, CaseIterable, Sendable {
        case transparent, solid, linearGradient, mesh, image
    }
}

extension BackgroundStyle: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, color, stops, angle, base, blobs, path, blur
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .transparent:
            self = .transparent
        case .solid:
            self = .solid(try c.decode(RGBAColor.self, forKey: .color))
        case .linearGradient:
            self = .linearGradient(LinearGradientSpec(
                stops: try c.decode([GradientStop].self, forKey: .stops),
                angle: try c.decodeIfPresent(Double.self, forKey: .angle) ?? 135))
        case .mesh:
            self = .mesh(MeshSpec(
                base: try c.decode(RGBAColor.self, forKey: .base),
                blobs: try c.decode([MeshBlob].self, forKey: .blobs)))
        case .image:
            self = .image(ImageBackgroundSpec(
                path: try c.decode(String.self, forKey: .path),
                blur: try c.decodeIfPresent(Double.self, forKey: .blur) ?? 0))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .type)
        switch self {
        case .transparent:
            break
        case .solid(let color):
            try c.encode(color, forKey: .color)
        case .linearGradient(let spec):
            try c.encode(spec.stops, forKey: .stops)
            try c.encode(spec.angle, forKey: .angle)
        case .mesh(let spec):
            try c.encode(spec.base, forKey: .base)
            try c.encode(spec.blobs, forKey: .blobs)
        case .image(let spec):
            try c.encode(spec.path, forKey: .path)
            try c.encode(spec.blur, forKey: .blur)
        }
    }
}
