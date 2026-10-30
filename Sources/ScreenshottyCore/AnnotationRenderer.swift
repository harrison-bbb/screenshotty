import CoreGraphics
import CoreImage

/// Draws annotations onto a prepared shot.
public enum AnnotationRenderer {
    /// - Parameters:
    ///   - shot: The prepared (trimmed and padded) screenshot.
    ///   - offset: Where the original capture's (0, 0) sits inside `shot`.
    public static func apply(_ annotations: [Annotation], to shot: CGImage, offset: CGPoint) -> CGImage {
        guard !annotations.isEmpty else { return shot }
        let width = shot.width
        let height = shot.height
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace.working(for: shot),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return shot }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        Compositor.drawImage(shot, in: bounds, ctx: ctx)

        let unit = CGFloat(max(width, height)) / 1000
        let placed = annotations.map { $0.translated(by: CGVector(dx: offset.x, dy: offset.y)) }

        // Hiding comes first so arrows and boxes stay crisp on top of blurred areas.
        for annotation in placed where annotation.kind == .blur || annotation.kind == .redact {
            let rect = annotation.rect.intersection(bounds).integral
            guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { continue }
            if annotation.kind == .redact {
                drawRedaction(in: rect, ctx: ctx, unit: unit)
            } else if let pixelated = pixelate(shot, rect: rect, unit: unit) {
                Compositor.drawImage(pixelated, in: rect, ctx: ctx)
            } else {
                drawRedaction(in: rect, ctx: ctx, unit: unit)
            }
        }
        var stepNumber = 0
        for annotation in placed {
            switch annotation.kind {
            case .arrow: drawArrow(annotation, ctx: ctx, unit: unit)
            case .box: drawBox(annotation, ctx: ctx, unit: unit)
            case .text: drawText(annotation, ctx: ctx, unit: unit)
            case .step:
                stepNumber += 1
                drawStep(annotation, number: stepNumber, ctx: ctx, unit: unit)
            case .blur, .redact: break
            }
        }
        return ctx.makeImage() ?? shot
    }

    /// Stroke width for arrows and boxes, in shot pixels.
    public static func strokeWidth(unit: CGFloat) -> CGFloat { max(5 * unit, 2.5) }

    // MARK: - Drawing

    private static func setShadow(_ ctx: CGContext, unit: CGFloat) {
        // Shadow offsets ignore the flipped CTM, so y is negative to fall downwards.
        ctx.setShadow(offset: CGSize(width: 0, height: -1.5 * unit), blur: 6 * unit,
                      color: RGBAColor.black.withAlpha(0.3).cgColor)
    }

    private static func drawBox(_ annotation: Annotation, ctx: CGContext, unit: CGFloat) {
        let lineWidth = strokeWidth(unit: unit)
        let rect = annotation.rect
        guard rect.width > lineWidth, rect.height > lineWidth else { return }
        let radius = min(8 * unit, min(rect.width, rect.height) / 4)
        ctx.saveGState()
        setShadow(ctx, unit: unit)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setStrokeColor(annotation.color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawArrow(_ annotation: Annotation, ctx: CGContext, unit: CGFloat) {
        let length = annotation.length
        guard length > 1 else { return }
        let lineWidth = strokeWidth(unit: unit) * 1.15
        let dir = CGVector(dx: (annotation.end.x - annotation.start.x) / length,
                           dy: (annotation.end.y - annotation.start.y) / length)
        let normal = CGVector(dx: -dir.dy, dy: dir.dx)
        let headLength = min(lineWidth * 4.2, length * 0.5)
        let headHalfWidth = headLength * 0.62
        let tip = annotation.end
        let base = CGPoint(x: tip.x - dir.dx * headLength, y: tip.y - dir.dy * headLength)

        ctx.saveGState()
        setShadow(ctx, unit: unit)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil) // one shadow for shaft + head
        ctx.setStrokeColor(annotation.color.cgColor)
        ctx.setFillColor(annotation.color.cgColor)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Shaft stops inside the head so the joint is clean.
        ctx.setLineWidth(lineWidth)
        ctx.move(to: annotation.start)
        ctx.addLine(to: CGPoint(x: base.x + dir.dx * headLength * 0.3, y: base.y + dir.dy * headLength * 0.3))
        ctx.strokePath()

        // Head: a triangle with softened corners.
        ctx.setLineWidth(lineWidth * 0.5)
        ctx.move(to: tip)
        ctx.addLine(to: CGPoint(x: base.x + normal.dx * headHalfWidth, y: base.y + normal.dy * headHalfWidth))
        ctx.addLine(to: CGPoint(x: base.x - normal.dx * headHalfWidth, y: base.y - normal.dy * headHalfWidth))
        ctx.closePath()
        ctx.drawPath(using: .fillStroke)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// White text on the colour (black on light colours), on a rounded pill so it reads anywhere.
    private static func drawText(_ annotation: Annotation, ctx: CGContext, unit: CGFloat) {
        guard !annotation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let frame = annotation.frame(unit: unit)
        let font = annotation.fontSize(unit: unit)
        let ink = annotation.color.isLight ? RGBAColor(hex: "#111111")! : .white
        ctx.saveGState()
        setShadow(ctx, unit: unit)
        let radius = min(font * 0.45, frame.height / 2)
        ctx.addPath(CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(annotation.color.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        let lineHeight = font * 1.25
        let top = frame.minY + font * 0.32
        for (i, text) in Annotation.lines(of: annotation.text).enumerated() {
            TextLine(text, size: font, color: ink, weight: 0.3)
                .draw(in: ctx, x: frame.minX + font * 0.5, centerY: top + lineHeight * (CGFloat(i) + 0.5), maxWidth: .greatestFiniteMagnitude)
        }
    }

    /// A filled circle with a white ring and the step number.
    private static func drawStep(_ annotation: Annotation, number: Int, ctx: CGContext, unit: CGFloat) {
        let frame = annotation.frame(unit: unit)
        let ring = max(frame.width * 0.07, 1)
        ctx.saveGState()
        setShadow(ctx, unit: unit)
        ctx.setFillColor(RGBAColor.white.cgColor)
        ctx.fillEllipse(in: frame)
        ctx.restoreGState()
        ctx.setFillColor(annotation.color.cgColor)
        ctx.fillEllipse(in: frame.insetBy(dx: ring, dy: ring))
        let ink = annotation.color.isLight ? RGBAColor(hex: "#111111")! : .white
        let digits = "\(number)"
        let line = TextLine(digits, size: annotation.fontSize(unit: unit) * (digits.count > 1 ? 0.8 : 0.95), color: ink, weight: 0.5)
        line.draw(in: ctx, x: frame.midX - line.width / 2, centerY: frame.midY, maxWidth: frame.width)
    }

    private static func drawRedaction(in rect: CGRect, ctx: CGContext, unit: CGFloat) {
        let radius = min(3 * unit, min(rect.width, rect.height) / 4)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(RGBAColor(hex: "#111113")!.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Big square cells plus a light blur: unreadable, but still looks intentional.
    static func pixelate(_ image: CGImage, rect: CGRect, unit: CGFloat) -> CGImage? {
        guard let crop = image.cropping(to: rect) else { return nil }
        let cell = max(min(rect.width, rect.height) / 5, 14 * unit, 6)
        let input = CIImage(cgImage: crop).clampedToExtent()
        guard let pixellate = CIFilter(name: "CIPixellate"), let blur = CIFilter(name: "CIGaussianBlur") else { return nil }
        pixellate.setValue(input, forKey: kCIInputImageKey)
        pixellate.setValue(cell, forKey: kCIInputScaleKey)
        pixellate.setValue(CIVector(x: 0, y: 0), forKey: kCIInputCenterKey)
        blur.setValue(pixellate.outputImage, forKey: kCIInputImageKey)
        blur.setValue(cell * 0.25, forKey: kCIInputRadiusKey)
        guard let output = blur.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: crop.width, height: crop.height)) else {
            return nil
        }
        return ciContext.createCGImage(output, from: output.extent)
    }
}
