import CoreGraphics
import Testing
@testable import ScreenshottyCore

@Suite struct ShotPreparerTests {
    let dark = RGBAColor(hex: "#1C1C1E")!
    let text = RGBAColor(hex: "#E5E5EA")!

    /// Mimics a tight crop of text: lines run off the right edge and sit against the bottom.
    func tightTextShot() -> CGImage {
        TestImages.make(width: 900, height: 600, background: dark, fills: [
            (CGRect(x: 0, y: 40, width: 700, height: 18), text),
            (CGRect(x: 0, y: 120, width: 900, height: 18), text),   // touches left and right edges
            (CGRect(x: 30, y: 300, width: 500, height: 18), text),
            (CGRect(x: 0, y: 582, width: 600, height: 18), text),   // touches the bottom edge
        ])
    }

    @Test func detectsPlainBackgroundEvenWhenTextTouchesEdges() {
        let analysis = ImageTrimmer.analyze(tightTextShot())
        #expect(analysis.backgroundColor?.hex == "#1C1C1E")
        #expect(analysis.contentRect == CGRect(x: 0, y: 40, width: 900, height: 560))
    }

    @Test func addsEvenMarginInBackgroundColour() throws {
        var settings = CompositionSettings()
        settings.innerPadding = 50
        settings.cornerRadius = 0
        let shot = ShotPreparer.prepare(tightTextShot(), settings: settings)
        // Content is 900x560, unit 0.9 => 45px margin on every side.
        #expect(shot.width == 990 && shot.height == 650)
        let pixels = try #require(RGBABuffer(image: shot))
        // Margin pixels are the screenshot's background, content starts exactly 45px in.
        #expect(pixels[0, 0].isClose(to: pixels[44, 100], tolerance: 0))
        #expect(pixels[45, 120 - 40 + 45].r == 0xE5)
        #expect(pixels[shot.width - 46, 120 - 40 + 45].r == 0xE5)
        #expect(pixels[shot.width - 45, 120 - 40 + 45].r == 0x1C)
    }

    @Test func marginIsAtLeastHalfTheCornerRadius() {
        var settings = CompositionSettings()
        settings.innerPadding = 0
        settings.cornerRadius = 40
        let shot = ShotPreparer.prepare(tightTextShot(), settings: settings)
        // 20 units * 0.9 = 18px on each side.
        #expect(shot.width == 900 + 36)
    }

    @Test func busyEdgesAreLeftAlone() {
        // UI that runs to the edges: every column alternates colour, so no plain background.
        var fills: [(CGRect, RGBAColor)] = []
        for i in stride(from: 0, to: 400, by: 20) {
            fills.append((CGRect(x: i, y: 0, width: 10, height: 300), RGBAColor(hex: "#3366FF")!))
        }
        let image = TestImages.make(width: 400, height: 300, background: .white, fills: fills)
        let analysis = ImageTrimmer.analyze(image)
        #expect(analysis.backgroundColor == nil)
        #expect(ShotPreparer.prepare(image, settings: CompositionSettings()).width == 400)
    }

    @Test func colouredNavBarIsNotTreatedAsBackground() {
        let image = TestImages.make(width: 400, height: 300, background: .white,
                                    fills: [(CGRect(x: 0, y: 0, width: 400, height: 60), RGBAColor(hex: "#2563EB")!),
                                            (CGRect(x: 100, y: 120, width: 200, height: 40), .black)])
        let analysis = ImageTrimmer.analyze(image)
        #expect(analysis.backgroundColor == nil)
        #expect(analysis.contentRect == CGRect(x: 0, y: 0, width: 400, height: 300))
    }

    @Test func transparentWindowCaptureIsTrimmedButNotPadded() {
        let image = TestImages.make(width: 300, height: 200, background: nil,
                                    fills: [(CGRect(x: 20, y: 10, width: 200, height: 150), .white)])
        let shot = ShotPreparer.prepare(image, settings: CompositionSettings())
        #expect(shot.width == 200 && shot.height == 150)
    }

    @Test func autoTrimOffKeepsCaptureUntouched() {
        var settings = CompositionSettings()
        settings.autoTrim = false
        let shot = ShotPreparer.prepare(tightTextShot(), settings: settings)
        #expect(shot.width == 900 && shot.height == 600)
    }
}
