import CoreGraphics
import Testing
@testable import ScreenshottyCore

@Suite struct SmartBackgroundTests {
    /// A mostly grey UI with a small accent area, like a real app screenshot.
    func uiShot(accent: String) -> CGImage {
        TestImages.make(width: 600, height: 400, background: RGBAColor(hex: "#F5F5F7")!, fills: [
            (CGRect(x: 0, y: 0, width: 120, height: 400), RGBAColor(hex: "#1C1C1E")!),
            (CGRect(x: 200, y: 60, width: 160, height: 40), RGBAColor(hex: accent)!),
        ])
    }

    func hueDegrees(_ hue: Double) -> Double { hue * 360 }

    @Test(arguments: [("#FF3B30", 4.0), ("#34C759", 135.0), ("#0A84FF", 211.0), ("#AF52DE", 280.0)])
    func findsTheAccentHue(accent: String, expected: Double) {
        let palette = SmartBackground.palette(of: uiShot(accent: accent))
        #expect(palette.isColorful)
        let distance = SmartBackground.hueDistance(palette.primaryHue, expected / 360) * 360
        #expect(distance < 15, "expected ~\(expected)°, got \(hueDegrees(palette.primaryHue))°")
    }

    @Test func greyscaleScreenshotIsNotColourful() {
        let image = TestImages.make(width: 300, height: 200, background: .white,
                                    fills: [(CGRect(x: 50, y: 50, width: 100, height: 50), RGBAColor(hex: "#333333")!)])
        #expect(!SmartBackground.palette(of: image).isColorful)
    }

    @Test func secondHueStaysCloseToAvoidMuddyGradients() {
        // Orange and indigo accents are far apart on the wheel.
        let image = TestImages.make(width: 600, height: 400, background: .white, fills: [
            (CGRect(x: 0, y: 0, width: 300, height: 100), RGBAColor(hex: "#F59E0B")!),
            (CGRect(x: 0, y: 200, width: 200, height: 100), RGBAColor(hex: "#6366F1")!),
        ])
        let palette = SmartBackground.palette(of: image)
        #expect(SmartBackground.hueDistance(palette.primaryHue, palette.secondaryHue) * 360 <= 60.5)
    }

    @Test func everyVariantProducesABackground() throws {
        let palette = SmartBackground.palette(of: uiShot(accent: "#0A84FF"))
        for variant in SmartBackground.Variant.allCases {
            let style = SmartBackground.style(for: palette, variant: variant)
            #expect(style != .transparent)
            let thumb = try #require(BackgroundRenderer.thumbnail(style, size: CGSize(width: 40, height: 30)))
            #expect(thumb.width == 40)
        }
    }

    @Test func hsbRoundTrip() {
        let c = SmartBackground.color(hue: 0.6, saturation: 0.7, brightness: 0.8)
        let (h, s, b) = SmartBackground.hsb(r: c.red, g: c.green, b: c.blue)
        #expect(abs(h - 0.6) < 0.001 && abs(s - 0.7) < 0.001 && abs(b - 0.8) < 0.001)
    }

    @Test func settingsResolveSmartBackgroundPerImage() {
        var settings = CompositionSettings()
        settings.smartBackground = .vibrant
        let red = settings.resolved(for: uiShot(accent: "#FF3B30")).background
        let blue = settings.resolved(for: uiShot(accent: "#0A84FF")).background
        #expect(red != blue)
        settings.smartBackground = nil
        #expect(settings.resolved(for: uiShot(accent: "#FF3B30")).background == settings.background)
    }

    @Test func smartChoiceSurvivesJSON() throws {
        var settings = CompositionSettings()
        settings.smartBackground = .dark
        #expect(try JSON.roundTrip(settings).smartBackground == .dark)
    }
}
