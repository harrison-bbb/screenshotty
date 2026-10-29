import CoreGraphics

/// What the edges of a screenshot look like.
public struct ShotAnalysis: Equatable, Sendable {
    /// The content inside any plain-colour (or transparent) margins, in pixels, top-left origin.
    public var contentRect: CGRect
    /// The plain colour behind the content, if the screenshot has one (e.g. a page of text).
    /// Nil for busy edges (UI that runs to the edge) and for transparent margins.
    public var backgroundColor: RGBAColor?
    /// True when the margins are transparent (e.g. a window capture).
    public var transparentMargins: Bool
}

/// Finds plain margins around a screenshot so the content can be trimmed, re-padded evenly and centred.
public enum ImageTrimmer {
    /// Share of all edge pixels that must be the background colour.
    static let edgeCoverageThreshold = 0.7
    /// Share of each single edge that must be the background colour. A coloured nav bar fills the
    /// whole top edge, so it fails this and is never mistaken for margin. Text touching an edge
    /// only covers a small share of it.
    static let perEdgeCoverageThreshold = 0.3

    /// - Parameter tolerance: Max per-channel difference (0...255) still treated as "the same colour".
    ///   Kept tight because screenshots are lossless and light UI greys (e.g. #F7F7FA) sit very close to white.
    public static func analyze(_ image: CGImage, tolerance: Int = 2) -> ShotAnalysis {
        let width = image.width
        let height = image.height
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        let none = ShotAnalysis(contentRect: full, backgroundColor: nil, transparentMargins: false)
        guard width > 2, height > 2, let pixels = RGBABuffer(image: image) else { return none }

        // Edge pixels, one array per side.
        let edges: [[RGBAPixel]] = [
            (0..<width).map { pixels[$0, 0] },
            (0..<width).map { pixels[$0, height - 1] },
            (0..<height).map { pixels[0, $0] },
            (0..<height).map { pixels[width - 1, $0] },
        ]

        // The candidate background is the most common edge colour.
        var counts: [UInt32: Int] = [:]
        for edge in edges {
            for p in edge { counts[p.key, default: 0] += 1 }
        }
        guard let dominantKey = counts.max(by: { $0.value < $1.value })?.key else { return none }
        let dominant = RGBAPixel(key: dominantKey)
        let transparent = dominant.a < 8

        func isBackground(_ p: RGBAPixel) -> Bool {
            transparent ? p.a < 8 : p.isClose(to: dominant, tolerance: tolerance)
        }
        func matches(_ x: Int, _ y: Int) -> Bool { isBackground(pixels[x, y]) }

        var total = 0
        var matched = 0
        for edge in edges {
            let hits = edge.filter(isBackground).count
            guard Double(hits) / Double(edge.count) >= perEdgeCoverageThreshold else { return none }
            total += edge.count
            matched += hits
        }
        guard Double(matched) / Double(total) >= edgeCoverageThreshold else { return none }
        let reference: RGBAPixel? = transparent ? nil : dominant

        func rowIsMargin(_ y: Int) -> Bool { (0..<width).allSatisfy { matches($0, y) } }
        func columnIsMargin(_ x: Int, _ yRange: Range<Int>) -> Bool { yRange.allSatisfy { matches(x, $0) } }

        var top = 0
        while top < height, rowIsMargin(top) { top += 1 }
        guard top < height else { return none } // the whole image is one colour
        var bottom = height - 1
        while bottom > top, rowIsMargin(bottom) { bottom -= 1 }

        let rows = top..<(bottom + 1)
        var left = 0
        while left < width, columnIsMargin(left, rows) { left += 1 }
        var right = width - 1
        while right > left, columnIsMargin(right, rows) { right -= 1 }

        let background = reference.map {
            RGBAColor(red: Double($0.r) / 255, green: Double($0.g) / 255, blue: Double($0.b) / 255,
                      alpha: Double($0.a) / 255)
        }
        return ShotAnalysis(contentRect: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1),
                            backgroundColor: background, transparentMargins: transparent)
    }

    /// The crop rect of the content inside plain margins (the full image if there are none).
    public static func contentRect(of image: CGImage, tolerance: Int = 2) -> CGRect {
        analyze(image, tolerance: tolerance).contentRect
    }

    /// Returns the image with plain margins removed (or the original if there are none).
    public static func trim(_ image: CGImage, tolerance: Int = 2) -> CGImage {
        crop(image, to: contentRect(of: image, tolerance: tolerance))
    }

    static func crop(_ image: CGImage, to rect: CGRect) -> CGImage {
        if rect.width == CGFloat(image.width), rect.height == CGFloat(image.height) { return image }
        return image.cropping(to: rect) ?? image
    }
}

/// Turns a raw capture into the "shot" that goes on the card:
/// trims plain margins, then adds an even inner margin in the screenshot's own background colour,
/// so text never touches the edge or gets clipped by rounded corners.
public enum ShotPreparer {
    public static func prepare(_ source: CGImage, settings: CompositionSettings) -> CGImage {
        guard settings.autoTrim else { return source }
        return prepare(source, analysis: ImageTrimmer.analyze(source), settings: settings)
    }

    /// Same as above, reusing an analysis (the editor caches it so sliders stay fast).
    public static func prepare(_ source: CGImage, analysis: ShotAnalysis, settings: CompositionSettings) -> CGImage {
        guard settings.autoTrim else { return source }
        let content = ImageTrimmer.crop(source, to: analysis.contentRect)
        guard let background = analysis.backgroundColor else { return content }

        let unit = CGFloat(max(content.width, content.height)) / 1000
        // Always leave enough room that rounded corners can't clip the content.
        let minimumForCorners = CGFloat(settings.effectiveCornerRadius) * 0.5
        let margin = (max(CGFloat(settings.innerPadding), minimumForCorners) * unit).rounded()
        guard margin >= 1 else { return content }
        return pad(content, by: Int(margin), color: background) ?? content
    }

    static func pad(_ image: CGImage, by margin: Int, color: RGBAColor) -> CGImage? {
        let width = image.width + margin * 2
        let height = image.height + margin * 2
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(image, in: CGRect(x: margin, y: margin, width: image.width, height: image.height))
        return ctx.makeImage()
    }
}

struct RGBAPixel {
    var r: UInt8, g: UInt8, b: UInt8, a: UInt8

    init(r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    init(key: UInt32) {
        self.init(r: UInt8(key >> 24 & 0xFF), g: UInt8(key >> 16 & 0xFF), b: UInt8(key >> 8 & 0xFF), a: UInt8(key & 0xFF))
    }

    var key: UInt32 { UInt32(r) << 24 | UInt32(g) << 16 | UInt32(b) << 8 | UInt32(a) }

    func isClose(to other: RGBAPixel, tolerance: Int) -> Bool {
        abs(Int(r) - Int(other.r)) <= tolerance &&
            abs(Int(g) - Int(other.g)) <= tolerance &&
            abs(Int(b) - Int(other.b)) <= tolerance &&
            abs(Int(a) - Int(other.a)) <= tolerance
    }
}

/// The image redrawn into a known 8-bit RGBA layout with a top-left origin.
struct RGBABuffer {
    let width: Int
    let height: Int
    private let data: [UInt8]

    init?(image: CGImage) {
        let width = image.width
        let height = image.height
        self.width = width
        self.height = height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        data = bytes
    }

    /// (x, y) with y measured from the top.
    subscript(x: Int, y: Int) -> RGBAPixel {
        // Bitmap memory starts at the top row, so no flip is needed.
        let i = (y * width + x) * 4
        return RGBAPixel(r: data[i], g: data[i + 1], b: data[i + 2], a: data[i + 3])
    }
}
