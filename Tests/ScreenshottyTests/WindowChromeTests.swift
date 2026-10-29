import CoreGraphics
import Testing
@testable import ScreenshottyCore

@Suite struct WindowChromeTests {
    @Test func radiusIsCappedOnlyWithChrome() {
        var settings = CompositionSettings()
        settings.cornerRadius = 60
        #expect(settings.effectiveCornerRadius == 60)
        settings.windowChrome = .dark
        #expect(settings.effectiveCornerRadius == CompositionSettings.maxChromeCornerRadius)
        settings.cornerRadius = 10
        #expect(settings.effectiveCornerRadius == 10)
    }

    @Test func layoutUsesCappedRadius() {
        var settings = CompositionSettings()
        settings.cornerRadius = 60
        settings.windowChrome = .light
        let layout = CompositionLayout(imageSize: CGSize(width: 1000, height: 600), settings: settings)
        #expect(layout.cornerRadius == CGFloat(CompositionSettings.maxChromeCornerRadius))
    }

    /// Even if a caller passes a huge radius, every light stays inside the rounded card.
    @Test(arguments: [0.0, 12, 24, 40, 60, 100])
    func trafficLightsFitInsideTheCorner(radius: Double) {
        let unit: CGFloat = 2
        let titleBar = CGRect(x: 0, y: 0, width: 2000, height: 28 * unit)
        let r = CGFloat(radius) * unit
        let lightRadius = WindowChrome.lightRadius * unit
        let corner = CGPoint(x: r, y: r)
        for center in WindowChrome.trafficLightCenters(in: titleBar, unit: unit, cornerRadius: r) {
            #expect(center.x - lightRadius >= 0)
            if center.x < corner.x, center.y < corner.y {
                let distance = ((center.x - corner.x) * (center.x - corner.x) + (center.y - corner.y) * (center.y - corner.y)).squareRoot()
                #expect(distance + lightRadius <= r, "radius \(radius): light at \(center) pokes out of the corner")
            }
        }
    }

    @Test func lightsKeepMacOSPositionAtNormalRadius() {
        let centers = WindowChrome.trafficLightCenters(in: CGRect(x: 0, y: 0, width: 1000, height: 28), unit: 1, cornerRadius: 12)
        #expect(centers.map(\.x) == [20, 40, 60])
    }

    @Test func redLightIsDrawnAtMaxRadius() throws {
        let shot = TestImages.make(width: 1000, height: 600, background: .white)
        var settings = CompositionSettings(background: .solid(.black), padding: 0, cornerRadius: 60, shadow: .none)
        settings.windowChrome = .dark
        settings.autoTrim = false
        let output = try Compositor.render(shot, settings: settings)
        let pixels = try #require(RGBABuffer(image: output))
        let layout = CompositionLayout(imageSize: CGSize(width: 1000, height: 600), settings: settings)
        let titleBar = CGRect(x: layout.cardRect.minX, y: layout.cardRect.minY, width: layout.cardRect.width, height: layout.titleBarHeight)
        let red = WindowChrome.trafficLightCenters(in: titleBar, unit: layout.unit, cornerRadius: layout.cornerRadius)[0]
        let p = pixels[Int(red.x), Int(red.y)]
        #expect(p.r > 200 && p.g < 120 && p.b < 120)
    }
}
