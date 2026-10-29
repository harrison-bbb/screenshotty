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
        /// A text label on a colour pill. Anchored at `start` (its top-left corner).
        case text
        /// A numbered circle (1, 2, 3…, in the order steps were added). Centred on `start`.
        case step

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .arrow: "Arrow"
            case .box: "Box"
            case .blur: "Blur"
            case .redact: "Redact"
            case .text: "Text"
            case .step: "Step"
            }
        }

        /// True for kinds that use the annotation colour.
        public var usesColor: Bool { self != .blur && self != .redact }

        /// Placed with a click rather than dragged out.
        public var isPlaced: Bool { self == .text || self == .step }
    }

    public var id: UUID
    public var kind: Kind
    public var start: CGPoint
    public var end: CGPoint
    public var color: RGBAColor
    /// The label of a text annotation.
    public var text: String
    /// Text size (and step size) in layout units of the shot.
    public var size: Double

    public static let defaultTextSize: Double = 24
    public static let textSizes: [Double] = [18, 24, 34]

    public init(id: UUID = UUID(), kind: Kind, start: CGPoint, end: CGPoint, color: RGBAColor = Annotation.defaultColor,
                text: String = "", size: Double = Annotation.defaultTextSize) {
        self.text = text
        self.size = size
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

    // MARK: Text and steps

    /// Font size of a text label or step number, in pixels of a shot with this `unit`.
    public func fontSize(unit: CGFloat) -> CGFloat { max(CGFloat(size) * unit, 9) }

    /// Radius of a step circle.
    public func stepRadius(unit: CGFloat) -> CGFloat { fontSize(unit: unit) * 0.85 }

    /// The area a text label or step covers (its pill or circle). Other kinds use `rect`.
    public func frame(unit: CGFloat) -> CGRect {
        switch kind {
        case .text:
            let font = fontSize(unit: unit)
            let lines = Self.lines(of: text)
            let width = lines.map { TextLine($0, size: font, color: .white, weight: 0.3).width }.max() ?? 0
            let padH = font * 0.5
            let padV = font * 0.32
            return CGRect(x: start.x, y: start.y, width: width + padH * 2,
                          height: font * 1.25 * CGFloat(lines.count) + padV * 2)
        case .step:
            let r = stepRadius(unit: unit)
            return CGRect(x: start.x - r, y: start.y - r, width: r * 2, height: r * 2)
        default:
            return rect
        }
    }

    static func lines(of text: String) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return lines.isEmpty ? [""] : lines
    }

    /// Whether `point` (same coordinate space) touches this annotation, within `tolerance`.
    /// `unit` sizes text labels and steps.
    public func hitTest(_ point: CGPoint, tolerance: CGFloat, unit: CGFloat = 1) -> Bool {
        switch kind {
        case .text, .step:
            return frame(unit: unit).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
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

    // Old files have no `text` or `size`; they decode with the defaults.
    private enum CodingKeys: String, CodingKey { case id, kind, start, end, color, text, size }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        start = try c.decode(CGPoint.self, forKey: .start)
        end = try c.decode(CGPoint.self, forKey: .end)
        color = try c.decode(RGBAColor.self, forKey: .color)
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        size = (try? c.decode(Double.self, forKey: .size)) ?? Self.defaultTextSize
    }

    public static let defaultColor = RGBAColor(hex: "#FF3B30")!

    /// Colours offered in the editor. Bright enough to read on light and dark UIs.
    public static let palette: [RGBAColor] = [
        "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#0A84FF", "#AF52DE", "#FFFFFF", "#1C1C1E",
    ].map { RGBAColor(hex: $0)! }
}
