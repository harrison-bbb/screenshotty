import CoreGraphics
import Testing
@testable import ScreenshottyCore

@Suite struct CompositorTests {
    @Test func outputSizeMatchesLayout() throws {
        let shot = TestImages.make(width: 800, height: 600, background: RGBAColor(hex: "#3366FF")!)
        for background in [Presets.gradients[0].style, Presets.wallpapers[0].style, .solid(.white), .transparent] {
            var settings = CompositionSettings(background: background)
            settings.aspectRatio = .widescreen
            settings.windowChrome = .light
            settings.frame = .glass
            let output = try Compositor.render(shot, settings: settings)
            let layout = CompositionLayout(imageSize: CGSize(width: 800, height: 600), settings: settings)
            #expect(CGFloat(output.width) == layout.canvasSize.width)
            #expect(CGFloat(output.height) == layout.canvasSize.height)
        }
    }

    @Test func screenshotPixelsLandInTheCentre() throws {
        let blue = RGBAColor(hex: "#0000FF")!
        let shot = TestImages.make(width: 400, height: 200, background: blue)
        var settings = CompositionSettings(background: .solid(.white), padding: 100, cornerRadius: 0, shadow: .none)
        settings.autoTrim = false
        let output = try Compositor.render(shot, settings: settings)
        let buffer = RGBABuffer(image: output)!
        // Centre pixel is the screenshot, corner pixel is the background.
        let centre = buffer[output.width / 2, output.height / 2]
        #expect(centre.b == 255 && centre.r == 0)
        let corner = buffer[2, 2]
        #expect(corner.r == 255 && corner.g == 255 && corner.b == 255)
        // Screenshot edge sits exactly at the padding (1 unit = 0.4px, padding 100 => 40px).
        #expect(buffer[40, output.height / 2].b == 255 && buffer[40, output.height / 2].r == 0)
        #expect(buffer[39, output.height / 2].r == 255)
    }

    @Test func composeTrimsWhenEnabled() throws {
        let shot = TestImages.make(width: 300, height: 300, background: .white,
                                   fills: [(CGRect(x: 100, y: 100, width: 100, height: 50), .black)])
        var settings = CompositionSettings(background: .solid(.white), padding: 0, cornerRadius: 0, shadow: .none)
        settings.autoTrim = true
        settings.innerPadding = 0
        let output = try Compositor.compose(shot, settings: settings)
        #expect(output.width == 100 && output.height == 50)
    }

    @Test func pngRoundTrip() throws {
        let shot = TestImages.make(width: 10, height: 10, background: .white)
        #expect(PNG.roundTripWidth(shot) == 10)
    }
}
