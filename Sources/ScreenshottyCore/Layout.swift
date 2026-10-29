import CoreGraphics

/// Pure geometry for a composition. All rects use a top-left origin, in output pixels at scale 1.
public struct CompositionLayout: Equatable, Sendable {
    /// Size of the full exported image.
    public let canvasSize: CGSize
    /// The screenshot card (title bar + screenshot), centred on the canvas.
    public let cardRect: CGRect
    /// Where the screenshot pixels go (inside the card, below any title bar).
    public let imageRect: CGRect
    /// Height of the fake window title bar (0 when chrome is off).
    public let titleBarHeight: CGFloat
    public let cornerRadius: CGFloat
    /// Thickness of the glass frame (0 when off).
    public let frameWidth: CGFloat
    /// Pixels per layout unit.
    public let unit: CGFloat

    public init(imageSize: CGSize, settings: CompositionSettings) {
        let w = max(imageSize.width.rounded(), 1)
        let h = max(imageSize.height.rounded(), 1)
        let unit = max(w, h) / 1000
        self.unit = unit

        let titleBar: CGFloat = settings.windowChrome == .none ? 0 : (28 * unit).rounded()
        let frame: CGFloat = settings.frame == .glass ? (14 * unit).rounded() : 0
        let cardW = w
        let cardH = h + titleBar
        let padding = (CGFloat(settings.padding) * unit).rounded()

        // Smallest canvas that fits the card plus padding (frame sits inside the padding area).
        var canvasW = cardW + 2 * (padding + frame)
        var canvasH = cardH + 2 * (padding + frame)

        if let ratio = settings.aspectRatio.ratio {
            if canvasW / canvasH < CGFloat(ratio) {
                canvasW = canvasH * CGFloat(ratio)
            } else {
                canvasH = canvasW / CGFloat(ratio)
            }
        }

        // Round up so the leftover space on each side is a whole pixel: the card is centred exactly.
        canvasW = Self.roundUp(canvasW, sameParityAs: cardW)
        canvasH = Self.roundUp(canvasH, sameParityAs: cardH)

        canvasSize = CGSize(width: canvasW, height: canvasH)
        let card = CGRect(x: (canvasW - cardW) / 2, y: (canvasH - cardH) / 2, width: cardW, height: cardH)
        cardRect = card
        imageRect = CGRect(x: card.minX, y: card.minY + titleBar, width: w, height: h)
        titleBarHeight = titleBar
        cornerRadius = min(CGFloat(settings.cornerRadius) * unit, min(cardW, cardH) / 2)
        frameWidth = frame
    }

    private static func roundUp(_ value: CGFloat, sameParityAs reference: CGFloat) -> CGFloat {
        var v = value.rounded(.up)
        if Int(v) % 2 != Int(reference) % 2 { v += 1 }
        return v
    }
}
