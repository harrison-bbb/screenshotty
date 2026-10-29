import CoreGraphics

/// Pure geometry for a composition. All rects use a top-left origin, in output pixels at scale 1.
public struct CompositionLayout: Equatable, Sendable {
    /// Size of the full exported image.
    public let canvasSize: CGSize
    /// The screenshot card (title bar + screenshot). Inside the device's screen when a device is drawn.
    public let cardRect: CGRect
    /// Where the screenshot pixels go (inside the card, below any title bar).
    public let imageRect: CGRect
    /// Height of the fake window title bar (0 when chrome is off).
    public let titleBarHeight: CGFloat
    /// Corner radius of the card (the device's screen corners when a device is drawn).
    public let cornerRadius: CGFloat
    /// Thickness of the glass frame (0 when off).
    public let frameWidth: CGFloat
    /// Pixels per layout unit.
    public let unit: CGFloat
    /// Everything that is centred on the canvas: the card, or the whole device including a laptop base.
    public let objectRect: CGRect
    /// Device geometry, when a device is drawn.
    public let device: DeviceGeometry?

    public struct DeviceGeometry: Equatable, Sendable {
        /// The laptop lid or the phone body.
        public let bodyRect: CGRect
        public let bodyCornerRadius: CGFloat
        /// Thickness of the black border around the screen.
        public let bezel: CGFloat
        /// The laptop's keyboard base, below the lid.
        public let baseRect: CGRect?
    }

    public init(imageSize: CGSize, settings: CompositionSettings) {
        let w = max(imageSize.width.rounded(), 1)
        let h = max(imageSize.height.rounded(), 1)
        let unit = max(w, h) / 1000
        self.unit = unit

        let chrome = settings.windowChrome
        let titleBar: CGFloat = switch chrome.kind {
        case .none: 0
        case .macOS: (28 * unit).rounded()
        case .browser: (46 * unit).rounded()
        }
        let cardW = w
        let cardH = h + titleBar
        let padding = (CGFloat(settings.padding) * unit).rounded()

        // The object that gets centred, and where the card sits inside it.
        var objectW = cardW
        var objectH = cardH
        var cardOffset = CGPoint.zero
        var frame: CGFloat = settings.frame == .glass ? (14 * unit).rounded() : 0
        var radius = min(CGFloat(settings.effectiveCornerRadius) * unit, min(cardW, cardH) / 2)
        var deviceParts: (body: CGRect, bodyRadius: CGFloat, bezel: CGFloat, base: CGRect?)?

        switch settings.device {
        case .none:
            break
        case .macbook:
            frame = 0
            let bezel = max((cardW * 0.032).rounded(), 3)
            let chin = (bezel * 1.5).rounded()
            let lidW = cardW + 2 * bezel
            let lidH = cardH + bezel + chin
            var baseW = (lidW * 1.16).rounded()
            if Int(baseW - lidW) % 2 != 0 { baseW += 1 }
            let baseH = max((lidW * 0.034).rounded(), 4)
            objectW = baseW
            objectH = lidH + baseH
            let lidX = (baseW - lidW) / 2
            cardOffset = CGPoint(x: lidX + bezel, y: bezel)
            radius = max((bezel * 0.35).rounded(), 1)
            deviceParts = (CGRect(x: lidX, y: 0, width: lidW, height: lidH), (bezel * 1.1).rounded(), bezel,
                           CGRect(x: 0, y: lidH, width: baseW, height: baseH))
        case .iphone:
            frame = 0
            let bezel = max((cardW * 0.045).rounded(), 3)
            let bodyW = cardW + 2 * bezel
            let bodyH = cardH + 2 * bezel
            let bodyRadius = (min(bodyW, bodyH) * 0.155).rounded()
            objectW = bodyW
            objectH = bodyH
            cardOffset = CGPoint(x: bezel, y: bezel)
            radius = max(bodyRadius - bezel, 1)
            deviceParts = (CGRect(x: 0, y: 0, width: bodyW, height: bodyH), bodyRadius, bezel, nil)
        }

        // Smallest canvas that fits the object plus padding (a glass frame sits inside the padding area).
        var canvasW = objectW + 2 * (padding + frame)
        var canvasH = objectH + 2 * (padding + frame)

        if let ratio = settings.aspectRatio.ratio {
            if canvasW / canvasH < CGFloat(ratio) {
                canvasW = canvasH * CGFloat(ratio)
            } else {
                canvasH = canvasW / CGFloat(ratio)
            }
        } else {
            // Auto: follow the shot, but never as a thin strip. Very wide or tall shots get extra
            // padding so the result still reads well in a feed.
            let range = AspectRatio.autoRange
            if canvasW / canvasH > CGFloat(range.upperBound) {
                canvasH = canvasW / CGFloat(range.upperBound)
            } else if canvasW / canvasH < CGFloat(range.lowerBound) {
                canvasW = canvasH * CGFloat(range.lowerBound)
            }
        }

        // Round up so the leftover space on each side is a whole pixel: the object is centred exactly.
        canvasW = Self.roundUp(canvasW, sameParityAs: objectW)
        canvasH = Self.roundUp(canvasH, sameParityAs: objectH)

        canvasSize = CGSize(width: canvasW, height: canvasH)
        let origin = CGPoint(x: (canvasW - objectW) / 2, y: (canvasH - objectH) / 2)
        objectRect = CGRect(x: origin.x, y: origin.y, width: objectW, height: objectH)
        let card = CGRect(x: origin.x + cardOffset.x, y: origin.y + cardOffset.y, width: cardW, height: cardH)
        cardRect = card
        imageRect = CGRect(x: card.minX, y: card.minY + titleBar, width: w, height: h)
        titleBarHeight = titleBar
        cornerRadius = radius
        frameWidth = frame
        device = deviceParts.map {
            DeviceGeometry(bodyRect: $0.body.offsetBy(dx: origin.x, dy: origin.y), bodyCornerRadius: $0.bodyRadius,
                           bezel: $0.bezel, baseRect: $0.base?.offsetBy(dx: origin.x, dy: origin.y))
        }
    }

    private static func roundUp(_ value: CGFloat, sameParityAs reference: CGFloat) -> CGFloat {
        var v = value.rounded(.up)
        if Int(v) % 2 != Int(reference) % 2 { v += 1 }
        return v
    }
}
