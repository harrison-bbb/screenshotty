import CoreGraphics

/// Pure geometry for a composition. All rects use a top-left origin, in output pixels at scale 1.
extension CompositionLayout.DeviceGeometry {
    func offsetBy(dx: CGFloat, dy: CGFloat) -> Self {
        Self(bodyRect: bodyRect.offsetBy(dx: dx, dy: dy), bodyCornerRadius: bodyCornerRadius,
             screenRect: screenRect.offsetBy(dx: dx, dy: dy), screenCornerRadius: screenCornerRadius,
             baseRect: baseRect?.offsetBy(dx: dx, dy: dy), mode: mode, landscape: landscape, statusBarHeight: statusBarHeight)
    }
}

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
        public enum Mode: Equatable, Sendable {
            /// The screenshot fills the screen (any small difference in shape is filled with its edge colour).
            case fullBleed
            /// The screenshot sits as a window on a desktop wallpaper (MacBook with a non-screen-shaped shot).
            case desktop
            /// A phone screen with a status bar above the screenshot and a home indicator below.
            case phoneApp
        }

        /// The laptop lid or the phone body.
        public let bodyRect: CGRect
        public let bodyCornerRadius: CGFloat
        /// The display, with the device's real proportions.
        public let screenRect: CGRect
        public let screenCornerRadius: CGFloat
        /// The laptop's keyboard base, below the lid.
        public let baseRect: CGRect?
        public let mode: Mode
        /// True for a phone turned on its side (wide screenshots).
        public let landscape: Bool
        /// Height of the phone status bar (0 unless `mode` is `.phoneApp`).
        public let statusBarHeight: CGFloat
    }

    /// Real screen shapes (width / height): a 14" MacBook Pro and an iPhone 15 Pro in portrait.
    public static let macBookScreenAspect: CGFloat = 3024.0 / 1964.0
    public static let iPhoneScreenAspect: CGFloat = 1179.0 / 2556.0

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
        var deviceParts: DeviceGeometry?

        switch settings.device {
        case .none:
            break
        case .macbook:
            frame = 0
            let device = Self.macBook(cardW: cardW, cardH: cardH)
            objectW = device.object.width
            objectH = device.object.height
            cardOffset = device.cardOffset
            radius = device.geometry.mode == .desktop ? max(radius, (10 * unit).rounded()) : 0
            deviceParts = device.geometry
        case .iphone:
            frame = 0
            let device = Self.iPhone(cardW: cardW, cardH: cardH)
            objectW = device.object.width
            objectH = device.object.height
            cardOffset = device.cardOffset
            radius = 0
            deviceParts = device.geometry
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
        device = deviceParts.map { $0.offsetBy(dx: origin.x, dy: origin.y) }
    }

    // MARK: Devices

    /// Smallest rect of `aspect` that contains `size`, grown so each side leaves an even number of
    /// pixels around it (the content is then centred on whole pixels).
    private static func containing(_ size: CGSize, aspect: CGFloat) -> CGSize {
        var w = max(size.width, (size.height * aspect).rounded(.up))
        var h = max(size.height, (w / aspect).rounded())
        if h > (w / aspect).rounded() { w = (h * aspect).rounded(.up) }
        if Int(w - size.width) % 2 != 0 { w += 1 }
        if Int(h - size.height) % 2 != 0 { h += 1 }
        return CGSize(width: w, height: h)
    }

    private typealias DeviceResult = (object: CGSize, cardOffset: CGPoint, geometry: DeviceGeometry)

    /// MacBook Pro: thin bezels, a camera notch, and a keyboard base wider than the lid.
    /// Screen-shaped shots fill the display; anything else sits as a window on a desktop wallpaper.
    private static func macBook(cardW: CGFloat, cardH: CGFloat) -> DeviceResult {
        let aspect = macBookScreenAspect
        let fits = abs((cardW / cardH) / aspect - 1) < 0.05
        let margin = (max(cardW, cardH) * 0.07).rounded()
        // A screen-shaped shot fills the display exactly (its shape is within 5% of the real one).
        let screen = fits ? CGSize(width: cardW, height: cardH)
                          : containing(CGSize(width: cardW + 2 * margin, height: cardH + 2 * margin), aspect: aspect)
        let side = max((screen.width * 0.022).rounded(), 2)
        let top = max((screen.width * 0.03).rounded(), 2)
        let chin = max((screen.width * 0.042).rounded(), 3)
        let lidW = screen.width + 2 * side
        let lidH = screen.height + top + chin
        var baseW = (lidW * 1.12).rounded()
        if Int(baseW - lidW) % 2 != 0 { baseW += 1 }
        let baseH = max((lidW * 0.03).rounded(), 4)
        let lidX = (baseW - lidW) / 2
        let screenRect = CGRect(x: lidX + side, y: top, width: screen.width, height: screen.height)
        let cardOffset = CGPoint(x: screenRect.minX + (screen.width - cardW) / 2,
                                 y: screenRect.minY + (screen.height - cardH) / 2)
        let geometry = DeviceGeometry(
            bodyRect: CGRect(x: lidX, y: 0, width: lidW, height: lidH),
            bodyCornerRadius: (lidW * 0.028).rounded(),
            screenRect: screenRect,
            screenCornerRadius: (screen.width * 0.012).rounded(),
            baseRect: CGRect(x: 0, y: lidH, width: baseW, height: baseH),
            mode: fits ? .fullBleed : .desktop, landscape: false, statusBarHeight: 0)
        return (CGSize(width: baseW, height: lidH + baseH), cardOffset, geometry)
    }

    /// iPhone 15 Pro: real screen shape, Dynamic Island, titanium edge. Wide shots turn the phone
    /// landscape. Portrait shots that aren't phone-shaped get a status bar, like an app.
    private static func iPhone(cardW: CGFloat, cardH: CGFloat) -> DeviceResult {
        let landscape = cardW > cardH
        let aspect = landscape ? 1 / iPhoneScreenAspect : iPhoneScreenAspect
        let fits = abs((cardW / cardH) / aspect - 1) < 0.06
        let appMode = !landscape && !fits
        var screen: CGSize
        var statusBar: CGFloat = 0
        var cardOffset: CGPoint
        if appMode {
            // Status bar (54 pt of 393) on top and room for the home indicator (34 pt) below.
            let barShare: CGFloat = 54.0 / 393.0
            let homeShare: CGFloat = 34.0 / 393.0
            var w = max(cardW, (cardH / (1 / aspect - barShare - homeShare)).rounded(.up))
            if Int(w - cardW) % 2 != 0 { w += 1 }
            screen = CGSize(width: w, height: (w / aspect).rounded())
            statusBar = (w * barShare).rounded()
            cardOffset = CGPoint(x: (w - cardW) / 2, y: statusBar)
        } else {
            screen = fits ? CGSize(width: cardW, height: cardH) : containing(CGSize(width: cardW, height: cardH), aspect: aspect)
            cardOffset = CGPoint(x: (screen.width - cardW) / 2, y: (screen.height - cardH) / 2)
        }
        let short = min(screen.width, screen.height)
        let bezel = max((short * 0.04).rounded(), 3)
        let screenRadius = (short * 0.14).rounded()
        let body = CGSize(width: screen.width + 2 * bezel, height: screen.height + 2 * bezel)
        let screenRect = CGRect(x: bezel, y: bezel, width: screen.width, height: screen.height)
        let geometry = DeviceGeometry(
            bodyRect: CGRect(origin: .zero, size: body),
            bodyCornerRadius: screenRadius + bezel,
            screenRect: screenRect,
            screenCornerRadius: screenRadius,
            baseRect: nil,
            mode: appMode ? .phoneApp : .fullBleed, landscape: landscape, statusBarHeight: statusBar)
        return (body, CGPoint(x: bezel + cardOffset.x, y: bezel + cardOffset.y), geometry)
    }

    private static func roundUp(_ value: CGFloat, sameParityAs reference: CGFloat) -> CGFloat {
        var v = value.rounded(.up)
        if Int(v) % 2 != Int(reference) % 2 { v += 1 }
        return v
    }
}
