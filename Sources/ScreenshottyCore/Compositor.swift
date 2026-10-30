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
    /// - Parameter pixelSize: Exact output size. The canvas is stretched to fit, so pass a size with
    ///   (almost exactly) the canvas' shape. Overrides `scale`.
    public static func render(_ source: CGImage, settings: CompositionSettings, scale: CGFloat = 1,
                              pixelSize: CGSize? = nil) throws -> CGImage {
        let layout = CompositionLayout(imageSize: CGSize(width: source.width, height: source.height), settings: settings)
        let pixelW = max(Int((pixelSize?.width ?? layout.canvasSize.width * scale).rounded()), 1)
        let pixelH = max(Int((pixelSize?.height ?? layout.canvasSize.height * scale).rounded()), 1)
        let scaleX = CGFloat(pixelW) / layout.canvasSize.width
        let scaleY = CGFloat(pixelH) / layout.canvasSize.height

        guard let ctx = CGContext(data: nil, width: pixelW, height: pixelH, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace.working(for: source),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CompositorError.contextCreationFailed
        }
        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)

        // Work in top-left-origin layout coordinates.
        ctx.translateBy(x: 0, y: CGFloat(pixelH))
        ctx.scaleBy(x: scaleX, y: -scaleY)

        let canvas = CGRect(origin: .zero, size: layout.canvasSize)
        BackgroundRenderer.draw(settings.background, in: ctx, rect: canvas, unit: layout.unit * scaleX)
        if let device = layout.device {
            DeviceFrame.drawBody(settings.device, geometry: device, shadow: settings.shadow, unit: layout.unit, in: ctx)
            let colors = DeviceFrame.ScreenColors.sample(source)
            ctx.saveGState()
            let screenPath = CGPath(roundedRect: device.screenRect, cornerWidth: device.screenCornerRadius,
                                    cornerHeight: device.screenCornerRadius, transform: nil)
            ctx.addPath(screenPath)
            ctx.clip()
            switch device.mode {
            case .desktop:
                // A window on a Mac desktop.
                BackgroundRenderer.draw(Presets.macDesktop, in: ctx, rect: device.screenRect, unit: layout.unit)
                drawCard(source, settings: settings, layout: layout, in: ctx, shadow: .medium)
            case .fullBleed, .phoneApp:
                let screen = device.screenRect
                let card = layout.cardRect
                ctx.setFillColor(colors.fill.cgColor)
                ctx.fill(screen)
                // The side fills run 2 px under the screenshot, so no seam shows where the edges are blended.
                if card.minX > screen.minX {
                    ctx.setFillColor(colors.left.cgColor)
                    ctx.fill(CGRect(x: screen.minX, y: screen.minY, width: card.minX - screen.minX + 2, height: screen.height))
                }
                if card.maxX < screen.maxX {
                    ctx.setFillColor(colors.right.cgColor)
                    ctx.fill(CGRect(x: card.maxX - 2, y: screen.minY, width: screen.maxX - card.maxX + 2, height: screen.height))
                }
                if layout.titleBarHeight > 0 {
                    // Carry the window's title bar across the gaps so it doesn't look cut short.
                    ctx.setFillColor(WindowChrome.barColor(settings.windowChrome).cgColor)
                    ctx.fill(CGRect(x: screen.minX, y: card.minY, width: screen.width, height: layout.titleBarHeight))
                }
                if device.mode == .phoneApp {
                    ctx.setFillColor(colors.top.cgColor)
                    ctx.fill(CGRect(x: device.screenRect.minX, y: device.screenRect.minY,
                                    width: device.screenRect.width, height: device.statusBarHeight))
                }
                drawCard(source, settings: settings, layout: layout, in: ctx, shadow: nil)
            }
            ctx.restoreGState()
            DeviceFrame.drawOverlay(settings.device, geometry: device, colors: colors, in: ctx)
        } else {
            drawFrame(settings.frame, layout: layout, in: ctx)
            drawCard(source, settings: settings, layout: layout, in: ctx, shadow: settings.shadow)
        }
        if let watermark = settings.watermark {
            WatermarkRenderer.draw(watermark, layout: layout, in: ctx)
        }

        guard let image = ctx.makeImage() else { throw CompositorError.contextCreationFailed }
        return image
    }

    /// Prepares the shot (trim and even inner margin, if enabled), draws annotations and renders in one step.
    /// - Parameter minimumLongSide: When set, small results are upscaled by a whole factor so the
    ///   longest side reaches at least this many pixels (see `ExportScale`).
    public static func compose(_ source: CGImage, settings: CompositionSettings, annotations: [Annotation] = [],
                               crop: CGRect? = nil, scale: CGFloat = 1, minimumLongSide: CGFloat? = nil) throws -> CGImage {
        let settings = settings.resolved(for: source)
        let prepared = ShotPreparer.prepareShot(source, crop: crop, settings: settings)
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
        if let width = settings.exportWidth, width > 0 {
            // Exact output width. Big enlargements first double the shot pixel-for-pixel so text stays sharp.
            let canvas = CompositionLayout(imageSize: CGSize(width: prepared.image.width, height: prepared.image.height),
                                           settings: settings).canvasSize
            let factor = Int((CGFloat(width) / canvas.width).rounded(.down))
            if factor >= 2, let enlarged = ExportScale.enlarge(prepared.image, by: min(factor, ExportScale.maxFactor)) {
                let f = CGFloat(min(factor, ExportScale.maxFactor))
                shot = PreparedShot(image: enlarged, offset: CGPoint(x: prepared.offset.x * f, y: prepared.offset.y * f))
                marks = annotations.map { $0.scaled(by: f) }
            }
            let image = AnnotationRenderer.apply(marks, to: shot.image, offset: shot.offset)
            let finalCanvas = CompositionLayout(imageSize: CGSize(width: image.width, height: image.height),
                                                settings: settings).canvasSize
            return try render(image, settings: settings, pixelSize: ExportScale.size(forWidth: width, canvas: finalCanvas,
                                                                                    aspect: settings.aspectRatio))
        }
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

    /// Frosted glass: the background behind the border is blurred, brightened and given a soft top
    /// highlight, with a bright outer edge and a faint inner edge, like a pane of glass around the shot.
    private static func drawFrame(_ frame: FrameStyle, layout: CompositionLayout, in ctx: CGContext) {
        guard frame == .glass, layout.frameWidth > 0 else { return }
        let rect = layout.cardRect.insetBy(dx: -layout.frameWidth, dy: -layout.frameWidth)
        let radius = layout.cornerRadius + layout.frameWidth
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let scale = ctx.ctm.a
        let line = max(layout.unit * 0.75, 1 / scale)

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        // Blur what's behind the pane. The bitmap's first row is the top, matching layout space.
        if let snapshot = ctx.makeImage(),
           let behind = snapshot.cropping(to: CGRect(x: rect.minX * scale, y: rect.minY * scale,
                                                     width: rect.width * scale, height: rect.height * scale)),
           let blurred = BackgroundRenderer.blur(behind, radius: layout.frameWidth * 1.2 * scale) {
            drawImage(blurred, in: rect, ctx: ctx)
        }
        // Milky tint, brighter at the top.
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                     colors: [RGBAColor.white.withAlpha(0.34).cgColor,
                                              RGBAColor.white.withAlpha(0.14).cgColor] as CFArray,
                                     locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
        }
        ctx.restoreGState()

        ctx.saveGState()
        // Bright outer edge and a faint shadow line where the pane meets the screenshot.
        ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: line / 2, dy: line / 2), cornerWidth: radius - line / 2,
                           cornerHeight: radius - line / 2, transform: nil))
        ctx.setStrokeColor(RGBAColor.white.withAlpha(0.6).cgColor)
        ctx.setLineWidth(line)
        ctx.strokePath()
        let card = layout.cardRect.insetBy(dx: -line / 2, dy: -line / 2)
        ctx.addPath(CGPath(roundedRect: card, cornerWidth: layout.cornerRadius + line / 2,
                           cornerHeight: layout.cornerRadius + line / 2, transform: nil))
        ctx.setStrokeColor(RGBAColor.black.withAlpha(0.12).cgColor)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawCard(_ source: CGImage, settings: CompositionSettings, layout: CompositionLayout,
                                 in ctx: CGContext, shadow: ShadowStyle?) {
        let card = layout.cardRect
        let cardPath = CGPath(roundedRect: card, cornerWidth: layout.cornerRadius,
                              cornerHeight: layout.cornerRadius, transform: nil)

        ctx.saveGState()
        if let shadow = shadow?.parameters {
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
                              unit: layout.unit, cornerRadius: layout.cornerRadius, url: settings.browserURL)
        }
        drawImage(source, in: layout.imageRect, ctx: ctx)
        ctx.endTransparencyLayer()
        ctx.restoreGState()

        if settings.frame == .hairline, layout.device == nil {
            // Two hairlines, like a macOS window edge: a dark one just outside defines the edge on light
            // backgrounds, a light one just inside catches the light on dark ones.
            ctx.saveGState()
            let line = max(layout.unit * 0.6, 1 / ctx.ctm.a)
            func stroke(_ offset: CGFloat, _ color: RGBAColor) {
                let r = card.insetBy(dx: offset, dy: offset)
                let radius = max(layout.cornerRadius - offset, 0)
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
                ctx.setStrokeColor(color.cgColor)
                ctx.strokePath()
            }
            ctx.setLineWidth(line)
            stroke(-line / 2, RGBAColor.black.withAlpha(0.22))
            stroke(line / 2, RGBAColor.white.withAlpha(0.28))
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

    static func blur(_ image: CGImage, radius: CGFloat) -> CGImage? {
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
