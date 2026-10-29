import CoreGraphics
import Foundation

/// Target shape of the exported canvas.
public enum AspectRatio: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case square = "1:1"
    case portrait = "4:5"
    case standard = "4:3"
    case classic = "3:2"
    case widescreen = "16:9"
    case social = "1.91:1"
    case story = "9:16"

    public var id: String { rawValue }

    /// Canvas shapes Auto stays within (width / height): from a 4:5 feed post to 2:1.
    public static let autoRange: ClosedRange<Double> = 0.8...2.0

    /// width / height, or nil for "fit the screenshot".
    public var ratio: Double? {
        switch self {
        case .auto: nil
        case .square: 1
        case .portrait: 4.0 / 5.0
        case .standard: 4.0 / 3.0
        case .classic: 3.0 / 2.0
        case .widescreen: 16.0 / 9.0
        case .social: 1.91
        case .story: 9.0 / 16.0
        }
    }

    public var title: String {
        switch self {
        case .auto: "Auto"
        case .square: "1:1"
        case .portrait: "4:5"
        case .standard: "4:3"
        case .classic: "3:2"
        case .widescreen: "16:9"
        case .social: "1.91:1"
        case .story: "9:16"
        }
    }

    public var subtitle: String {
        switch self {
        case .auto: "Fits the shot, never a thin strip"
        case .square: "Instagram"
        case .portrait: "Feed post"
        case .standard: "Slides"
        case .classic: "Photo"
        case .widescreen: "YouTube, X"
        case .social: "LinkedIn, OG"
        case .story: "Stories"
        }
    }
}

public enum ShadowStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, soft, medium, strong
    public var id: String { rawValue }

    /// (blur, y-offset, opacity) in layout units.
    public var parameters: (blur: Double, offsetY: Double, opacity: Double)? {
        switch self {
        case .none: nil
        case .soft: (blur: 30, offsetY: 8, opacity: 0.22)
        case .medium: (blur: 50, offsetY: 18, opacity: 0.35)
        case .strong: (blur: 70, offsetY: 28, opacity: 0.5)
        }
    }

    public var title: String { rawValue.capitalized }
}

public enum WindowChromeStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, light, dark
    /// A browser window: traffic lights, back and forward buttons and an address bar.
    case browserLight = "browser-light"
    case browserDark = "browser-dark"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: "None"
        case .light: "Light"
        case .dark: "Dark"
        case .browserLight: "Browser"
        case .browserDark: "Browser Dark"
        }
    }

    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case none, macOS, browser
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .none: "None"
            case .macOS: "macOS"
            case .browser: "Browser"
            }
        }
    }

    public var kind: Kind {
        switch self {
        case .none: .none
        case .light, .dark: .macOS
        case .browserLight, .browserDark: .browser
        }
    }

    public var isDark: Bool { self == .dark || self == .browserDark }

    public init(kind: Kind, dark: Bool) {
        switch kind {
        case .none: self = .none
        case .macOS: self = dark ? .dark : .light
        case .browser: self = dark ? .browserDark : .browserLight
        }
    }
}

/// A device drawn around the screenshot.
public enum DeviceStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, macbook, iphone
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .none: "None"
        case .macbook: "MacBook"
        case .iphone: "iPhone"
        }
    }
}

public enum FrameStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Nothing around the screenshot.
    case none
    /// A thin translucent outline.
    case hairline
    /// A frosted, translucent border around the screenshot.
    case glass
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

/// Everything that controls how a screenshot is composed.
///
/// Lengths are in **layout units**: 1 unit = 1/1000 of the (trimmed) screenshot's longest side.
/// That keeps the look identical whether the capture came from a Retina or non-Retina display.
public struct CompositionSettings: Codable, Hashable, Sendable {
    public var background: BackgroundStyle
    public var aspectRatio: AspectRatio
    public var padding: Double
    public var cornerRadius: Double
    public var shadow: ShadowStyle
    public var windowChrome: WindowChromeStyle
    public var frame: FrameStyle
    public var autoTrim: Bool
    /// Even margin added inside the card, in the screenshot's own background colour, when the
    /// screenshot is content on a plain background (e.g. text). Units of the trimmed content.
    public var innerPadding: Double
    /// When set, the background is generated from each screenshot's own colours with this look.
    public var smartBackground: SmartBackground.Variant?
    /// Text shown in the address bar of the browser window chrome (e.g. "screenshotty.app").
    public var browserURL: String
    /// A MacBook or iPhone drawn around the screenshot.
    public var device: DeviceStyle
    /// Exact width of the exported image in pixels. Nil exports at the screenshot's own resolution.
    public var exportWidth: Int?
    /// A logo and/or text in a corner of the canvas.
    public var watermark: Watermark?

    public init(background: BackgroundStyle = Presets.defaultBackground,
                aspectRatio: AspectRatio = .auto,
                padding: Double = 90,
                cornerRadius: Double = 12,
                shadow: ShadowStyle = .medium,
                windowChrome: WindowChromeStyle = .none,
                frame: FrameStyle = .none,
                autoTrim: Bool = true,
                innerPadding: Double = 40,
                smartBackground: SmartBackground.Variant? = .vibrant,
                browserURL: String = "",
                device: DeviceStyle = .none,
                exportWidth: Int? = nil,
                watermark: Watermark? = nil) {
        self.background = background
        self.aspectRatio = aspectRatio
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.windowChrome = windowChrome
        self.frame = frame
        self.autoTrim = autoTrim
        self.innerPadding = innerPadding
        self.smartBackground = smartBackground
        self.browserURL = browserURL
        self.device = device
        self.exportWidth = exportWidth
        self.watermark = watermark
    }

    /// These settings with the background resolved for `image` when a smart background is chosen.
    public func resolved(for image: CGImage) -> CompositionSettings {
        guard let variant = smartBackground else { return self }
        var copy = self
        copy.background = SmartBackground.style(for: image, variant: variant)
        return copy
    }

    public static let `default` = CompositionSettings()

    public static let paddingRange: ClosedRange<Double> = 0...300
    public static let cornerRadiusRange: ClosedRange<Double> = 0...60
    /// Largest radius used with a macOS title bar. Real macOS windows sit around this value, and
    /// rounder corners would cut into the title bar and its traffic lights.
    public static let maxChromeCornerRadius: Double = 24

    /// The radius actually drawn: capped while window chrome is on. The stored value is kept, so
    /// turning chrome off restores the user's rounder corners.
    public var effectiveCornerRadius: Double {
        windowChrome == .none ? cornerRadius : min(cornerRadius, Self.maxChromeCornerRadius)
    }
    public static let innerPaddingRange: ClosedRange<Double> = 0...150
    /// Export widths offered in the editor, in pixels (nil = the screenshot's own resolution).
    public static let exportWidthOptions: [Int?] = [nil, 1080, 1200, 1600, 1920, 2400]

    /// True when the two settings produce the same look. A smart background counts as equal whatever
    /// colours it was resolved to, because those depend on the screenshot.
    public func looksLike(_ other: CompositionSettings) -> Bool {
        var a = self
        var b = other
        if a.smartBackground != nil, a.smartBackground == b.smartBackground {
            a.background = .transparent
            b.background = .transparent
        }
        return a == b
    }

    // Tolerant decoding: missing keys fall back to defaults so old saved settings keep working.
    private enum CodingKeys: String, CodingKey {
        case background, aspectRatio, padding, cornerRadius, shadow, windowChrome, frame, autoTrim, innerPadding
        case smartBackground, browserURL, device, exportWidth, watermark
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CompositionSettings.default
        background = (try? c.decode(BackgroundStyle.self, forKey: .background)) ?? d.background
        aspectRatio = (try? c.decode(AspectRatio.self, forKey: .aspectRatio)) ?? d.aspectRatio
        padding = (try? c.decode(Double.self, forKey: .padding)) ?? d.padding
        cornerRadius = (try? c.decode(Double.self, forKey: .cornerRadius)) ?? d.cornerRadius
        shadow = (try? c.decode(ShadowStyle.self, forKey: .shadow)) ?? d.shadow
        windowChrome = (try? c.decode(WindowChromeStyle.self, forKey: .windowChrome)) ?? d.windowChrome
        frame = (try? c.decode(FrameStyle.self, forKey: .frame)) ?? d.frame
        autoTrim = (try? c.decode(Bool.self, forKey: .autoTrim)) ?? d.autoTrim
        innerPadding = (try? c.decode(Double.self, forKey: .innerPadding)) ?? d.innerPadding
        smartBackground = try? c.decode(SmartBackground.Variant.self, forKey: .smartBackground)
        browserURL = (try? c.decode(String.self, forKey: .browserURL)) ?? d.browserURL
        device = (try? c.decode(DeviceStyle.self, forKey: .device)) ?? d.device
        exportWidth = try? c.decode(Int.self, forKey: .exportWidth)
        watermark = try? c.decode(Watermark.self, forKey: .watermark)
    }
}
