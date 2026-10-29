import CoreGraphics
import Foundation

/// A mark drawn on top of the screenshot.
///
/// Points are in the **original capture's pixels** (top-left origin), so annotations stay attached to
/// the same content when trimming, margins, aspect ratio or background change.
public struct Annotation: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case arrow
        /// Rounded outline that draws attention to an area.
        case box
        /// Pixelates the area. Good for hiding busy detail; use `redact` for anything truly secret.
        case blur
        /// Covers the area with a solid bar. Nothing underneath survives in the export.
        case redact

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .arrow: "Arrow"
            case .box: "Box"
            case .blur: "Blur"
            case .redact: "Redact"
            }
        }

        /// True for kinds that use the annotation colour.
        public var usesColor: Bool { self == .arrow || self == .box }
    }

    public var id: UUID
    public var kind: Kind
    public var start: CGPoint
    public var end: CGPoint
    public var color: RGBAColor

    public init(id: UUID = UUID(), kind: Kind, start: CGPoint, end: CGPoint, color: RGBAColor = Annotation.defaultColor) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.color = color
    }

    /// The area covered by box, blur and redact (start and end are opposite corners).
    public var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    public var length: CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    public func scaled(by factor: CGFloat) -> Annotation {
        var copy = self
        copy.start = CGPoint(x: start.x * factor, y: start.y * factor)
        copy.end = CGPoint(x: end.x * factor, y: end.y * factor)
        return copy
    }

    public func translated(by delta: CGVector) -> Annotation {
        var copy = self
        copy.start = CGPoint(x: start.x + delta.dx, y: start.y + delta.dy)
        copy.end = CGPoint(x: end.x + delta.dx, y: end.y + delta.dy)
        return copy
    }

    /// Whether `point` (same coordinate space) touches this annotation, within `tolerance`.
    public func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        switch kind {
        case .arrow:
            return Self.distance(from: point, toSegment: start, end) <= tolerance
        case .box:
            // The outline, or anywhere inside, so small boxes are easy to grab.
            return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .blur, .redact:
            return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    public static let defaultColor = RGBAColor(hex: "#FF3B30")!

    /// Colours offered in the editor. Bright enough to read on light and dark UIs.
    public static let palette: [RGBAColor] = [
        "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#0A84FF", "#AF52DE", "#FFFFFF", "#1C1C1E",
    ].map { RGBAColor(hex: $0)! }
}
