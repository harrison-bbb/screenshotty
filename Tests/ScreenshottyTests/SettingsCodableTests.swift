import Testing
@testable import ScreenshottyCore

@Suite struct SettingsCodableTests {
    @Test func roundTripsEveryBackgroundKind() throws {
        let backgrounds: [BackgroundStyle] = [
            .transparent,
            .solid(RGBAColor(hex: "#12345680")!),
            Presets.gradients[3].style,
            Presets.wallpapers[2].style,
            .image(ImageBackgroundSpec(path: "/tmp/bg.png", blur: 20)),
        ]
        for background in backgrounds {
            var settings = CompositionSettings(background: background)
            settings.aspectRatio = .social
            settings.windowChrome = .dark
            settings.frame = .glass
            #expect(try JSON.roundTrip(settings) == settings)
        }
    }

    @Test func jsonUsesReadableDiscriminators() throws {
        let settings = CompositionSettings(background: .solid(RGBAColor(hex: "#FF0000")!))
        let json = try JSON.string(settings)
        #expect(json.contains("\"type\":\"solid\""))
        #expect(json.contains("#FF0000"))
    }

    @Test func missingKeysFallBackToDefaults() throws {
        let decoded = try JSON.decode(#"{"padding": 42}"#)
        #expect(decoded.padding == 42)
        #expect(decoded.aspectRatio == CompositionSettings.default.aspectRatio)
        #expect(decoded.background == CompositionSettings.default.background)
    }

    @Test func hexParsing() {
        #expect(RGBAColor(hex: "#fff") == .white)
        #expect(RGBAColor(hex: "000000") == .black)
        #expect(RGBAColor(hex: "#00000080")!.alpha > 0.5)
        #expect(RGBAColor(hex: "nope") == nil)
        #expect(RGBAColor(hex: "#1A2B3C")!.hex == "#1A2B3C")
    }
}
