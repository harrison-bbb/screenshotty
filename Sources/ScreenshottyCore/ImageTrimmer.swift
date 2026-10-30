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
    /// True when thin slivers of something else (desktop, a neighbouring window) were cut off the edges.
    public var cleanedEdges: Bool
    /// True when content that was cut off by the capture edge (half letters, clipped icons) was removed.
    public var removedClippedContent: Bool

    public init(contentRect: CGRect, backgroundColor: RGBAColor?, transparentMargins: Bool, cleanedEdges: Bool = false,
                removedClippedContent: Bool = false) {
        self.contentRect = contentRect
        self.backgroundColor = backgroundColor
        self.transparentMargins = transparentMargins
        self.cleanedEdges = cleanedEdges
        self.removedClippedContent = removedClippedContent
    }
}

/// Pixel bounds with exclusive upper ends.
struct PixelBounds: Equatable {
    var x0: Int, y0: Int, x1: Int, y1: Int
    var width: Int { x1 - x0 }
    var height: Int { y1 - y0 }
    var rect: CGRect { CGRect(x: x0, y: y0, width: width, height: height) }
}

/// Finds plain margins around a screenshot so the content can be trimmed, re-padded evenly and centred.
/// Also repairs sloppy selections by cutting thin slivers of unrelated pixels off the edges.
public enum ImageTrimmer {
    /// Share of all edge pixels that must be the background colour.
    static let edgeCoverageThreshold = 0.7
    /// Share of each single edge that must be the background colour. A coloured nav bar fills the
    /// whole top edge, so it fails this and is never mistaken for margin. Text touching an edge
    /// only covers a small share of it.
    static let perEdgeCoverageThreshold = 0.3

    /// - Parameter tolerance: Max per-channel difference (0...255) still treated as "the same colour".
    ///   Kept tight because screenshots are lossless and light UI greys (e.g. #F7F7FA) sit very close to white.
    /// - Parameter repairEdges: Cut slivers and clipped content off the edges. Off when the user has
    ///   cropped by hand, since they chose the edges themselves.
    public static func analyze(_ image: CGImage, tolerance: Int = 2, repairEdges: Bool = true) -> ShotAnalysis {
        let width = image.width
        let height = image.height
        let full = PixelBounds(x0: 0, y0: 0, x1: width, y1: height)
        guard width > 2, height > 2, let pixels = RGBABuffer(image: image) else {
            return ShotAnalysis(contentRect: full.rect, backgroundColor: nil, transparentMargins: false)
        }
        guard repairEdges else { return analyzeMargins(pixels, in: full, tolerance: tolerance) }
        let bounds = sliverFreeBounds(pixels)
        let unclipped = clippedContentFreeBounds(pixels, in: bounds)
        var result = analyzeMargins(pixels, in: unclipped, tolerance: tolerance)
        result.cleanedEdges = bounds != full
        result.removedClippedContent = unclipped != bounds
        return result
    }

    static func analyzeMargins(_ pixels: RGBABuffer, in b: PixelBounds, tolerance: Int) -> ShotAnalysis {
        let none = ShotAnalysis(contentRect: b.rect, backgroundColor: nil, transparentMargins: false)
        guard b.width > 2, b.height > 2 else { return none }

        // Edge pixels, one array per side.
        let edges: [[RGBAPixel]] = [
            (b.x0..<b.x1).map { pixels[$0, b.y0] },
            (b.x0..<b.x1).map { pixels[$0, b.y1 - 1] },
            (b.y0..<b.y1).map { pixels[b.x0, $0] },
            (b.y0..<b.y1).map { pixels[b.x1 - 1, $0] },
        ]

        // The candidate background is the most common edge colour.
        guard let dominant = dominantColor(edges.flatMap { $0 }) else { return none }
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

        func rowIsMargin(_ y: Int) -> Bool { (b.x0..<b.x1).allSatisfy { matches($0, y) } }
        func columnIsMargin(_ x: Int, _ yRange: Range<Int>) -> Bool { yRange.allSatisfy { matches(x, $0) } }

        var top = b.y0
        while top < b.y1, rowIsMargin(top) { top += 1 }
        guard top < b.y1 else { return none } // the whole image is one colour
        var bottom = b.y1 - 1
        while bottom > top, rowIsMargin(bottom) { bottom -= 1 }

        let rows = top..<(bottom + 1)
        var left = b.x0
        while left < b.x1, columnIsMargin(left, rows) { left += 1 }
        var right = b.x1 - 1
        while right > left, columnIsMargin(right, rows) { right -= 1 }

        let background = reference.map {
            RGBAColor(red: Double($0.r) / 255, green: Double($0.g) / 255, blue: Double($0.b) / 255,
                      alpha: Double($0.a) / 255)
        }
        return ShotAnalysis(contentRect: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1),
                            backgroundColor: background, transparentMargins: transparent)
    }

    // MARK: Sloppy edges

    /// Deepest sliver that gets cut, as a share of the image size, and in pixels.
    static let maxSliverShare = 0.02
    static let maxSliverPixels = 16

    enum Side: CaseIterable { case top, bottom, left, right }

    /// One line of pixels `depth` in from a side of `b`, sampled to at most ~1500 pixels.
    static func line(_ pixels: RGBABuffer, _ side: Side, _ depth: Int, in b: PixelBounds) -> [RGBAPixel] {
        let step: (Int) -> Int = { length in max(1, length / 1500) }
        switch side {
        case .top: return stride(from: b.x0, to: b.x1, by: step(b.width)).map { pixels[$0, b.y0 + depth] }
        case .bottom: return stride(from: b.x0, to: b.x1, by: step(b.width)).map { pixels[$0, b.y1 - 1 - depth] }
        case .left: return stride(from: b.y0, to: b.y1, by: step(b.height)).map { pixels[b.x0 + depth, $0] }
        case .right: return stride(from: b.y0, to: b.y1, by: step(b.height)).map { pixels[b.x1 - 1 - depth, $0] }
        }
    }

    static func cut(_ b: inout PixelBounds, _ side: Side, by depth: Int) {
        switch side {
        case .top: b.y0 += depth
        case .bottom: b.y1 -= depth
        case .left: b.x0 += depth
        case .right: b.x1 -= depth
        }
    }

    // MARK: Clipped content

    /// Largest strip removed, as a share of the image size.
    static let maxClippedShare = 0.25
    /// The empty gap that must separate a clipped strip from the main content: at least this share
    /// of the image size, and at least `minGapPixels`. Word spaces are far narrower, so a tight crop
    /// of a sentence is never mistaken for clipped content.
    static let minGapShare = 0.03
    static let minGapPixels = 16

    /// Bounds with content that the capture edge cut through removed, e.g. half a sidebar of labels
    /// at the left of a sloppy selection ("rts", "ptions"). A strip is removed only when:
    /// - the edge line is mostly background but has content running into it (it was cut),
    /// - a clean, wide gap of background separates it from the rest, within the outer 25%,
    /// - the strip itself is mostly background (text or icons, not a solid panel like a sidebar),
    /// - and the content beyond the gap is at least twice as large as the strip.
    static func clippedContentFreeBounds(_ pixels: RGBABuffer, in start: PixelBounds) -> PixelBounds {
        var b = start
        guard b.width >= 80, b.height >= 80 else { return b }
        let outer = Side.allCases.map { line(pixels, $0, 0, in: b) }
        guard let background = dominantColor(outer.flatMap { $0 }), background.a > 8 else { return b }
        func isEmpty(_ l: [RGBAPixel]) -> Bool { coverage(l, of: background) >= 0.998 }

        for side in Side.allCases {
            let edge = line(pixels, side, 0, in: b)
            let edgeCoverage = coverage(edge, of: background)
            guard edgeCoverage >= 0.5, edgeCoverage < 0.995 else { continue }   // nothing cut, or a solid panel
            let size = (side == .top || side == .bottom) ? b.height : b.width
            let maxStrip = Int(Double(size) * maxClippedShare)
            let minGap = max(minGapPixels, Int(Double(size) * minGapShare))
            guard maxStrip + minGap < size / 2 else { continue }

            // Find the first wide empty gap.
            var gapStart: Int?
            var run = 0
            var depth = 1
            while depth <= maxStrip + minGap {
                if isEmpty(line(pixels, side, depth, in: b)) {
                    if run == 0 { gapStart = depth }
                    run += 1
                    if run >= minGap { break }
                } else {
                    run = 0
                    gapStart = nil
                }
                depth += 1
            }
            guard run >= minGap, let strip = gapStart, strip <= maxStrip else { continue }

            // The strip is clipped text or icons on the background, not a filled panel.
            let stripCoverage = (0..<strip).map { coverage(line(pixels, side, $0, in: b), of: background) }.reduce(0, +) / Double(strip)
            guard stripCoverage >= 0.6 else { continue }

            // Real content continues past the gap, and it's much bigger than the strip.
            var first = strip + run
            while first < size, isEmpty(line(pixels, side, first, in: b)) { first += 1 }
            var far = 0
            while far < size - first, isEmpty(line(pixels, side, size - 1 - far, in: b)) { far += 1 }
            let contentSpan = size - far - first
            guard first < size, contentSpan >= strip * 2 else { continue }

            cut(&b, side, by: strip)
        }
        return b
    }

    /// Bounds with thin foreign strips removed: e.g. 4 px of desktop caught by a sloppy drag next to a window.
    ///
    /// A strip is cut only when all of this holds, so real content is left alone:
    /// - its outermost line does not match the colour that frames the rest of the image,
    /// - within a few pixels it gives way to a clean, uniform line (the real background starts there),
    /// - none of the lines being cut already has that background colour.
    static func sliverFreeBounds(_ pixels: RGBABuffer) -> PixelBounds {
        var b = PixelBounds(x0: 0, y0: 0, x1: pixels.width, y1: pixels.height)
        guard pixels.width >= 40, pixels.height >= 40 else { return b }

        func line(_ side: Side, _ depth: Int, in b: PixelBounds) -> [RGBAPixel] { Self.line(pixels, side, depth, in: b) }

        let outer = Side.allCases.map { line($0, 0, in: b) }
        guard let frame = dominantColor(outer.flatMap { $0 }) else { return b }

        for (index, side) in Side.allCases.enumerated() {
            guard coverage(outer[index], of: frame) < 0.5 else { continue } // looks like the rest of the frame
            let size = (side == .top || side == .bottom) ? b.height : b.width
            let maxDepth = min(maxSliverPixels, max(6, Int(Double(size) * maxSliverShare)))
            guard size > maxDepth * 4 else { continue }
            for depth in 1...maxDepth {
                let candidate = line(side, depth, in: b)
                guard let color = dominantColor(candidate), coverage(candidate, of: color) >= 0.92,
                      coverage(line(side, depth + 1, in: b), of: color) >= 0.9 else { continue }
                // Still inside the sliver itself: keep looking deeper.
                guard coverage(outer[index], of: color) < 0.6 else { continue }
                // If a line before this one already has the background colour there is no sliver.
                guard (1..<depth).allSatisfy({ coverage(line(side, $0, in: b), of: color) < 0.6 }) else { break }
                cut(&b, side, by: depth)
                break
            }
        }
        return b
    }

    static func dominantColor(_ pixels: [RGBAPixel]) -> RGBAPixel? {
        var counts: [UInt32: Int] = [:]
        for p in pixels { counts[p.key, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value }).map { RGBAPixel(key: $0.key) }
    }

    static func coverage(_ pixels: [RGBAPixel], of color: RGBAPixel, tolerance: Int = 6) -> Double {
        guard !pixels.isEmpty else { return 0 }
        return Double(pixels.filter { $0.isClose(to: color, tolerance: tolerance) }.count) / Double(pixels.count)
    }

    static func crop(_ image: CGImage, to rect: CGRect) -> CGImage {
        if rect.width == CGFloat(image.width), rect.height == CGFloat(image.height) { return image }
        return image.cropping(to: rect) ?? image
    }
}

/// Turns a raw capture into the "shot" that goes on the card:
/// trims plain margins, then adds an even inner margin in the screenshot's own background colour,
/// so text never touches the edge or gets clipped by rounded corners.
public struct PreparedShot {
    public var image: CGImage
    /// Where the original capture's (0, 0) sits inside `image`. Used to place annotations.
    public var offset: CGPoint

    public init(image: CGImage, offset: CGPoint) {
        self.image = image
        self.offset = offset
    }
}

public enum ShotPreparer {
    /// The one entry point: optional hand crop, then (with auto-trim) edge repair, trimming and an even
    /// inner margin. The offset maps original capture pixels, where annotations live, into the result.
    /// - Parameter analysis: Reuse an earlier analysis of the (cropped) image; the editor caches it so
    ///   sliders stay fast. Computed when nil.
    public static func prepareShot(_ source: CGImage, crop: CGRect? = nil, analysis: ShotAnalysis? = nil,
                                   settings: CompositionSettings) -> PreparedShot {
        // A crop that misses the image entirely (a stale or edited project file) is ignored, not half-applied.
        let cropRect = crop
            .map { $0.integral.intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height)) }
            .flatMap { $0.isNull || $0.width < 1 || $0.height < 1 ? nil : $0 }
        let working = cropRect.flatMap { source.cropping(to: $0) } ?? source
        var shot = PreparedShot(image: working, offset: .zero)
        if settings.autoTrim {
            // A hand-made crop is the user's call, so edge repair is skipped then.
            shot = trimmed(working, analysis: analysis ?? ImageTrimmer.analyze(working, repairEdges: crop == nil),
                           settings: settings)
        }
        if let cropRect {
            shot.offset = CGPoint(x: shot.offset.x - cropRect.minX, y: shot.offset.y - cropRect.minY)
        }
        return shot
    }

    /// Crops to the analysed content and adds the inner margin in the screenshot's background colour.
    static func trimmed(_ source: CGImage, analysis: ShotAnalysis, settings: CompositionSettings) -> PreparedShot {
        // A nearly blank capture (a white page with one small mark) isn't "margins around content":
        // trimming would shrink it to the mark. Keep it whole.
        let longSide = CGFloat(max(source.width, source.height))
        if max(analysis.contentRect.width, analysis.contentRect.height) < longSide * minimumContentShare {
            return PreparedShot(image: source, offset: .zero)
        }
        let content = ImageTrimmer.crop(source, to: analysis.contentRect)
        let cropOffset = CGPoint(x: -analysis.contentRect.minX, y: -analysis.contentRect.minY)
        guard let background = analysis.backgroundColor else { return PreparedShot(image: content, offset: cropOffset) }

        let unit = CGFloat(max(content.width, content.height)) / 1000
        // Always leave enough room that rounded corners can't clip the content.
        let minimumForCorners = CGFloat(settings.effectiveCornerRadius) * 0.5
        let margin = (max(CGFloat(settings.innerPadding), minimumForCorners) * unit).rounded()
        guard margin >= 1, let padded = pad(content, by: Int(margin), color: background) else {
            return PreparedShot(image: content, offset: cropOffset)
        }
        return PreparedShot(image: padded, offset: CGPoint(x: cropOffset.x + margin, y: cropOffset.y + margin))
    }

    /// Content smaller than this share of the capture's long side is left untrimmed.
    static let minimumContentShare: CGFloat = 0.1

    static func pad(_ image: CGImage, by margin: Int, color: RGBAColor) -> CGImage? {
        let width = image.width + margin * 2
        let height = image.height + margin * 2
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace.working(for: image),
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
