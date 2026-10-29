import CoreGraphics
import Foundation

/// A logo and/or text (a name, a handle, a URL) in a corner of the canvas, so every image is on-brand.
public struct Watermark: Codable, Hashable, Sendable {
    public enum Position: String, Codable, CaseIterable, Identifiable, Sendable {
        case topLeft, topRight, bottomLeft, bottomCenter, bottomRight
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .topLeft: "Top left"
            case .topRight: "Top right"
            case .bottomLeft: "Bottom left"
            case .bottomCenter: "Bottom centre"
            case .bottomRight: "Bottom right"
            }
        }
    }

    /// Path to a logo image (PNG or SVG-free formats ImageIO reads). Nil for text only.
    public var logoPath: String?
    /// Text shown after the logo. Empty for logo only.
    public var text: String
    public var position: Position
    /// Height of the watermark in layout units.
    public var size: Double
    public var opacity: Double

    public init(logoPath: String? = nil, text: String = "", position: Position = .bottomRight,
                size: Double = 30, opacity: Double = 0.9) {
        self.logoPath = logoPath
        self.text = text
        self.position = position
        self.size = size
        self.opacity = opacity
    }

    public static let sizeRange: ClosedRange<Double> = 14...80

    public var isEmpty: Bool { logoPath == nil && text.trimmingCharacters(in: .whitespaces).isEmpty }

    private enum CodingKeys: String, CodingKey { case logoPath, text, position, size, opacity }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Watermark()
        logoPath = try? c.decode(String.self, forKey: .logoPath)
        text = (try? c.decode(String.self, forKey: .text)) ?? d.text
        position = (try? c.decode(Position.self, forKey: .position)) ?? d.position
        size = (try? c.decode(Double.self, forKey: .size)) ?? d.size
        opacity = (try? c.decode(Double.self, forKey: .opacity)) ?? d.opacity
    }
}

enum WatermarkRenderer {
    /// Draws the watermark onto the finished canvas. Text is white on dark backgrounds and near-black
    /// on light ones, judged from the pixels already drawn under it.
    static func draw(_ watermark: Watermark, layout: CompositionLayout, in ctx: CGContext) {
        guard !watermark.isEmpty else { return }
        let unit = layout.unit
        let height = CGFloat(watermark.size) * unit
        let logo = watermark.logoPath.flatMap { ImageLoader.load(URL(fileURLWithPath: $0)) }
        let logoWidth = logo.map { height * CGFloat($0.width) / CGFloat(max($0.height, 1)) } ?? 0
        let text = watermark.text.trimmingCharacters(in: .whitespaces)
        let gap = logo != nil && !text.isEmpty ? height * 0.35 : 0
        let probe = TextLine(text, size: height * 0.62, color: .white, weight: 0.3)
        let textWidth = text.isEmpty ? 0 : probe.width
        let width = logoWidth + gap + textWidth
        guard width > 0 else { return }

        // Inset from the canvas edge: inside the padding where possible.
        let canvas = layout.canvasSize
        let inset = max(min(CGFloat(layout.cardRect.minY) * 0.5 - height / 2, 60 * unit), 16 * unit)
        let x: CGFloat
        let y: CGFloat
        switch watermark.position {
        case .topLeft: (x, y) = (inset, inset)
        case .topRight: (x, y) = (canvas.width - inset - width, inset)
        case .bottomLeft: (x, y) = (inset, canvas.height - inset - height)
        case .bottomCenter: (x, y) = ((canvas.width - width) / 2, canvas.height - inset - height)
        case .bottomRight: (x, y) = (canvas.width - inset - width, canvas.height - inset - height)
        }
        let area = CGRect(x: x, y: y, width: width, height: height)
        let dark = backgroundIsDark(under: area, in: ctx)
        let ink: RGBAColor = dark ? .white : RGBAColor(hex: "#111111")!

        ctx.saveGState()
        ctx.setAlpha(CGFloat(watermark.opacity))
        ctx.setShadow(offset: CGSize(width: 0, height: -unit * ctx.ctm.a), blur: 4 * unit * ctx.ctm.a,
                      color: RGBAColor.black.withAlpha(dark ? 0.25 : 0.08).cgColor)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        if let logo {
            Compositor.drawImage(logo, in: CGRect(x: x, y: y, width: logoWidth, height: height), ctx: ctx)
        }
        if !text.isEmpty {
            TextLine(text, size: height * 0.62, color: ink, weight: 0.3)
                .draw(in: ctx, x: x + logoWidth + gap, centerY: y + height / 2, maxWidth: textWidth + 1)
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// Average brightness of what's already drawn under `rect` (layout space, top-left origin).
    private static func backgroundIsDark(under rect: CGRect, in ctx: CGContext) -> Bool {
        let scale = ctx.ctm.a
        guard let snapshot = ctx.makeImage(),
              let region = snapshot.cropping(to: CGRect(x: rect.minX * scale, y: rect.minY * scale,
                                                        width: max(rect.width * scale, 1), height: max(rect.height * scale, 1))),
              let pixels = RGBABuffer(image: region) else { return true }
        var total = 0.0
        var count = 0.0
        for y in stride(from: 0, to: pixels.height, by: max(1, pixels.height / 12)) {
            for x in stride(from: 0, to: pixels.width, by: max(1, pixels.width / 24)) {
                let p = pixels[x, y]
                guard p.a > 20 else { continue }
                total += (0.2126 * Double(p.r) + 0.7152 * Double(p.g) + 0.0722 * Double(p.b)) / 255
                count += 1
            }
        }
        return count == 0 || total / count < 0.6
    }
}
