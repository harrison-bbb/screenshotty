import CoreGraphics
import CoreImage
import Foundation
import ImageIO

public enum CompositorError: Error {
    case contextCreationFailed
}

/// Renders a screenshot onto a styled background. Used for both the live preview and the final export,
/// so what you see is exactly what you get.
public enum Compositor {
    /// Composes `source` (already trimmed if desired) using `settings`.
    /// - Parameter scale: Output scale relative to the source's pixel size (1 = full resolution).
    public static func render(_ source: CGImage, settings: CompositionSettings, scale: CGFloat = 1) throws -> CGImage {
        let layout = CompositionLayout(imageSize: CGSize(width: source.width, height: source.height), settings: settings)
        let pixelW = max(Int((layout.canvasSize.width * scale).rounded()), 1)
        let pixelH = max(Int((layout.canvasSize.height * scale).rounded()), 1)

        guard let ctx = CGContext(data: nil, width: pixelW, height: pixelH, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CompositorError.contextCreationFailed
        }
        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)

        // Work in top-left-origin layout coordinates.
        ctx.translateBy(x: 0, y: CGFloat(pixelH))
        ctx.scaleBy(x: scale, y: -scale)

        let canvas = CGRect(origin: .zero, size: layout.canvasSize)
        BackgroundRenderer.draw(settings.background, in: ctx, rect: canvas, unit: layout.unit * scale)
        drawFrame(settings.frame, layout: layout, in: ctx)
        drawCard(source, settings: settings, layout: layout, in: ctx)

        guard let image = ctx.makeImage() else { throw CompositorError.contextCreationFailed }
        return image
    }

    /// Prepares the shot (trim and even inner margin, if enabled), draws annotations and renders in one step.
    /// - Parameter minimumLongSide: When set, small results are upscaled by a whole factor so the
    ///   longest side reaches at least this many pixels (see `ExportScale`).
    public static func compose(_ source: CGImage, settings: CompositionSettings, annotations: [Annotation] = [],
                               scale: CGFloat = 1, minimumLongSide: CGFloat? = nil) throws -> CGImage {
        let settings = settings.resolved(for: source)
        let prepared = ShotPreparer.prepareShot(source, settings: settings)
        if scale == 1 {
            return try renderExport(prepared, annotations: annotations, settings: settings, minimumLongSide: minimumLongSide)
        }
        let shot = AnnotationRenderer.apply(annotations, to: prepared.image, offset: prepared.offset)
        return try render(shot, settings: settings, scale: scale)
    }

    /// Full-resolution output. Small shots are first enlarged by a whole factor with nearest-neighbour
    /// sampling, which keeps UI and text pixel-sharp, and annotations are drawn at the new size so
    /// they stay smooth. The background, shadow and corners render natively at the larger size.
    public static func renderExport(_ prepared: PreparedShot, annotations: [Annotation], settings: CompositionSettings,
                                    minimumLongSide: CGFloat?) throws -> CGImage {
        var shot = prepared
        var marks = annotations
        if let minimumLongSide {
            let layout = CompositionLayout(imageSize: CGSize(width: prepared.image.width, height: prepared.image.height),
                                           settings: settings)
            let factor = ExportScale.factor(for: layout.canvasSize, minimumLongSide: minimumLongSide)
            if factor > 1, let enlarged = ExportScale.enlarge(prepared.image, by: factor) {
                let f = CGFloat(factor)
                shot = PreparedShot(image: enlarged, offset: CGPoint(x: prepared.offset.x * f, y: prepared.offset.y * f))
                marks = annotations.map { $0.scaled(by: f) }
            }
        }
        let image = AnnotationRenderer.apply(marks, to: shot.image, offset: shot.offset)
        return try render(image, settings: settings)
    }

    // MARK: - Pieces

    private static func drawFrame(_ frame: FrameStyle, layout: CompositionLayout, in ctx: CGContext) {
        guard frame == .glass else { return }
        let rect = layout.cardRect.insetBy(dx: -layout.frameWidth, dy: -layout.frameWidth)
        let path = CGPath(roundedRect: rect,
                          cornerWidth: layout.cornerRadius + layout.frameWidth,
                          cornerHeight: layout.cornerRadius + layout.frameWidth, transform: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setFillColor(RGBAColor.white.withAlpha(0.22).cgColor)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(RGBAColor.white.withAlpha(0.45).cgColor)
        ctx.setLineWidth(max(layout.unit, 1))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawCard(_ source: CGImage, settings: CompositionSettings, layout: CompositionLayout, in ctx: CGContext) {
        let card = layout.cardRect
        let cardPath = CGPath(roundedRect: card, cornerWidth: layout.cornerRadius,
                              cornerHeight: layout.cornerRadius, transform: nil)

        ctx.saveGState()
        if let shadow = settings.shadow.parameters {
            // Layout space is flipped, and CG shadow offsets ignore the CTM, so y is negated in device space.
            let scale = ctx.ctm.a
            ctx.setShadow(offset: CGSize(width: 0, height: -shadow.offsetY * layout.unit * scale),
                          blur: shadow.blur * layout.unit * scale,
                          color: RGBAColor.black.withAlpha(shadow.opacity).cgColor)
        }
        // A transparency layer makes the shadow follow the card's real shape, including transparent pixels.
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(cardPath)
        ctx.clip()
        if settings.windowChrome != .none {
            WindowChrome.draw(settings.windowChrome, in: ctx, rect: CGRect(x: card.minX, y: card.minY,
                                                                         width: card.width, height: layout.titleBarHeight),
                              unit: layout.unit, cornerRadius: layout.cornerRadius)
        }
        drawImage(source, in: layout.imageRect, ctx: ctx)
        ctx.endTransparencyLayer()
        ctx.restoreGState()

        if settings.frame == .hairline {
            ctx.saveGState()
            let inset = max(layout.unit, 1) / 2
            ctx.addPath(CGPath(roundedRect: card.insetBy(dx: inset, dy: inset),
                               cornerWidth: max(layout.cornerRadius - inset, 0),
                               cornerHeight: max(layout.cornerRadius - inset, 0), transform: nil))
            ctx.setStrokeColor(RGBAColor.white.withAlpha(0.35).cgColor)
            ctx.setLineWidth(max(layout.unit, 1))
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    /// Draws an image into a top-left-origin rect inside the flipped layout context.
    static func drawImage(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }
}

// MARK: - Background

public enum BackgroundRenderer {
    /// Renders a background on its own, e.g. for preset thumbnails.
    public static func thumbnail(_ style: BackgroundStyle, size: CGSize) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        draw(style, in: ctx, rect: CGRect(origin: .zero, size: size), unit: max(size.width, size.height) / 1000)
        return ctx.makeImage()
    }

    static func draw(_ style: BackgroundStyle, in ctx: CGContext, rect: CGRect, unit: CGFloat) {
        switch style {
        case .transparent:
            break
        case .solid(let color):
            ctx.setFillColor(color.cgColor)
            ctx.fill(rect)
        case .linearGradient(let spec):
            drawLinear(spec, in: ctx, rect: rect)
        case .mesh(let spec):
            drawMesh(spec, in: ctx, rect: rect)
        case .image(let spec):
            if !drawImage(spec, in: ctx, rect: rect, unit: unit) {
                drawLinear(LinearGradientSpec(stops: [GradientStop(RGBAColor(hex: "#888")!, 0),
                                                      GradientStop(RGBAColor(hex: "#444")!, 1)], angle: 180),
                           in: ctx, rect: rect)
            }
        }
    }

    private static func makeGradient(_ stops: [GradientStop]) -> CGGradient? {
        let sorted = stops.sorted { $0.location < $1.location }
        guard !sorted.isEmpty else { return nil }
        return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: sorted.map(\.color.cgColor) as CFArray,
                          locations: sorted.map { CGFloat($0.location) })
    }

    private static func drawLinear(_ spec: LinearGradientSpec, in ctx: CGContext, rect: CGRect) {
        guard let gradient = makeGradient(spec.stops) else { return }
        // CSS-style angle in a top-left-origin space: 0deg points up, 90deg points right.
        let radians = spec.angle * .pi / 180
        let dx = sin(radians)
        let dy = -cos(radians)
        let length = abs(rect.width * dx) + abs(rect.height * dy)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let start = CGPoint(x: center.x - dx * length / 2, y: center.y - dy * length / 2)
        let end = CGPoint(x: center.x + dx * length / 2, y: center.y + dy * length / 2)
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(gradient, start: start, end: end,
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    private static func drawMesh(_ spec: MeshSpec, in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.setFillColor(spec.base.cgColor)
        ctx.fill(rect)
        let longest = max(rect.width, rect.height)
        for blob in spec.blobs {
            guard let gradient = makeGradient([GradientStop(blob.color, 0),
                                               GradientStop(blob.color.withAlpha(blob.color.alpha * 0.5), 0.45),
                                               GradientStop(blob.color.withAlpha(0), 1)]) else { continue }
            let center = CGPoint(x: rect.minX + blob.x * rect.width, y: rect.minY + blob.y * rect.height)
            ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: blob.radius * longest, options: [])
        }
        ctx.restoreGState()
    }

    private static func drawImage(_ spec: ImageBackgroundSpec, in ctx: CGContext, rect: CGRect, unit: CGFloat) -> Bool {
        guard var image = ImageLoader.load(URL(fileURLWithPath: spec.path)) else { return false }
        if spec.blur > 0, let blurred = blur(image, radius: spec.blur * unit * CGFloat(image.width) / max(rect.width, 1)) {
            image = blurred
        }
        // Aspect-fill.
        let imageSize = CGSize(width: image.width, height: image.height)
        let fill = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let size = CGSize(width: imageSize.width * fill, height: imageSize.height * fill)
        let target = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                            width: size.width, height: size.height)
        ctx.saveGState()
        ctx.clip(to: rect)
        Compositor.drawImage(image, in: target, ctx: ctx)
        ctx.restoreGState()
        return true
    }

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    private static func blur(_ image: CGImage, radius: CGFloat) -> CGImage? {
        guard radius > 0.5 else { return image }
        let input = CIImage(cgImage: image).clampedToExtent()
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        else { return nil }
        return ciContext.createCGImage(output, from: output.extent)
    }
}
