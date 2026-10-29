import CoreGraphics
import Testing
@testable import ScreenshottyCore

@Suite struct EdgeCleanupTests {
    let text = RGBAColor(hex: "#1F2937")!
    let desktop = RGBAColor(hex: "#3B6EA5")!
    let border = RGBAColor(hex: "#C8C8CC")!

    /// A page of "text" on white with something else caught along the right edge.
    func page(rightSliver: [(Int, RGBAColor)]) -> CGImage {
        var fills: [(CGRect, RGBAColor)] = [(CGRect(x: 60, y: 60, width: 300, height: 40), text)]
        var x = 500
        for (width, color) in rightSliver.reversed() {
            x -= width
            fills.append((CGRect(x: x, y: 0, width: width, height: 400), color))
        }
        return TestImages.make(width: 500, height: 400, background: .white, fills: fills)
    }

    @Test func cutsDesktopSliverAndBalancesMargins() {
        let analysis = ImageTrimmer.analyze(page(rightSliver: [(5, desktop)]))
        #expect(analysis.cleanedEdges)
        #expect(analysis.backgroundColor == .white)
        #expect(analysis.contentRect == CGRect(x: 60, y: 60, width: 300, height: 40))
    }

    @Test func cutsWindowBorderPlusDesktop() {
        let analysis = ImageTrimmer.analyze(page(rightSliver: [(1, border), (4, desktop)]))
        #expect(analysis.cleanedEdges)
        #expect(analysis.contentRect == CGRect(x: 60, y: 60, width: 300, height: 40))
    }

    @Test func busySliverNextToBusyContentIsCut() {
        // Dark app UI running to the edges, with 3 px of desktop at the bottom.
        let ui = RGBAColor(hex: "#111827")!
        let image = TestImages.make(width: 400, height: 300, background: ui,
                                    fills: [(CGRect(x: 0, y: 297, width: 400, height: 3), desktop),
                                            (CGRect(x: 0, y: 0, width: 10, height: 297), border)])
        let analysis = ImageTrimmer.analyze(image)
        #expect(analysis.cleanedEdges)
        #expect(analysis.contentRect.maxY == 297)
    }

    @Test func keepsNavBarThatFillsTheTop() {
        let nav = RGBAColor(hex: "#4F46E5")!
        let image = TestImages.make(width: 500, height: 400, background: .white,
                                    fills: [(CGRect(x: 0, y: 0, width: 500, height: 12), nav),
                                            (CGRect(x: 60, y: 100, width: 300, height: 40), text)])
        let analysis = ImageTrimmer.analyze(image)
        #expect(!analysis.cleanedEdges)
        #expect(analysis.contentRect.minY == 0)
    }

    @Test func keepsWhiteMarginAboveAHeader() {
        // White margin, then a full-width header: the white is real background, not a sliver.
        let header = RGBAColor(hex: "#E5E7EB")!
        let image = TestImages.make(width: 500, height: 400, background: .white,
                                    fills: [(CGRect(x: 0, y: 4, width: 500, height: 30), header),
                                            (CGRect(x: 60, y: 100, width: 300, height: 40), text)])
        #expect(!ImageTrimmer.analyze(image).cleanedEdges)
    }

    @Test func cleanImageIsUntouched() {
        #expect(!ImageTrimmer.analyze(page(rightSliver: [])).cleanedEdges)
    }

    @Test func preparedShotKeepsAnnotationOffsetsInOriginalPixels() {
        var settings = CompositionSettings.default
        settings.innerPadding = 0
        settings.cornerRadius = 0
        let prepared = ShotPreparer.prepareShot(page(rightSliver: [(5, desktop)]), settings: settings)
        #expect(prepared.offset == CGPoint(x: -60, y: -60))
        #expect(prepared.image.width == 300)
    }
}

@Suite struct ExportScaleTests {
    @Test func smallShotsAreDoubled() {
        #expect(ExportScale.factor(for: CGSize(width: 900, height: 500), minimumLongSide: 1600) == 2)
        #expect(ExportScale.factor(for: CGSize(width: 300, height: 200), minimumLongSide: 1600) == 4)
    }

    @Test func largeShotsAreLeftAlone() {
        #expect(ExportScale.factor(for: CGSize(width: 2400, height: 1500), minimumLongSide: 1600) == 1)
    }

    @Test func enlargeKeepsPixelsSharp() {
        let red = RGBAColor(hex: "#FF0000")!
        let image = TestImages.make(width: 10, height: 10, background: .white,
                                    fills: [(CGRect(x: 0, y: 0, width: 5, height: 10), red)])
        let big = ExportScale.enlarge(image, by: 3)!
        let pixels = RGBABuffer(image: big)!
        #expect(big.width == 30)
        #expect(pixels[14, 5].r == 255 && pixels[14, 5].g == 0)   // last red column
        #expect(pixels[15, 5].g == 255)                              // first white column, no blending
    }

    @Test func exportOfSmallShotIsEnlargedAndCentred() throws {
        let image = TestImages.make(width: 400, height: 300, background: RGBAColor(hex: "#111827")!)
        var settings = CompositionSettings.default
        settings.smartBackground = nil
        let normal = try Compositor.compose(image, settings: settings)
        let sharp = try Compositor.compose(image, settings: settings, minimumLongSide: 1600)
        #expect(sharp.width == normal.width * 4)
        #expect(sharp.height == normal.height * 4)
    }
}

@Suite struct BalancedCanvasTests {
    @Test func wideShotIsNotAStrip() {
        let layout = CompositionLayout(imageSize: CGSize(width: 3000, height: 400), settings: .default)
        let ratio = layout.canvasSize.width / layout.canvasSize.height
        #expect(ratio <= 2.0 + 0.01)
        #expect(abs(layout.cardRect.midY - layout.canvasSize.height / 2) < 0.01)
    }

    @Test func tallShotIsNotAStrip() {
        let layout = CompositionLayout(imageSize: CGSize(width: 400, height: 2400), settings: .default)
        #expect(layout.canvasSize.width / layout.canvasSize.height >= 0.8 - 0.01)
    }
}

@Suite struct SmartWeightingTests {
    @Test func accentCoveringMostAreaWins() {
        // Lots of medium-saturation indigo, one small loud amber button.
        let indigo = RGBAColor(hex: "#6366F1")!
        let amber = RGBAColor(hex: "#F59E0B")!
        let image = TestImages.make(width: 400, height: 300, background: .white,
                                    fills: [(CGRect(x: 20, y: 20, width: 200, height: 40), indigo),
                                            (CGRect(x: 20, y: 80, width: 200, height: 40), indigo),
                                            (CGRect(x: 250, y: 20, width: 110, height: 40), amber)])
        let palette = SmartBackground.palette(of: image)
        #expect(SmartBackground.hueDistance(palette.primaryHue, 0.66) < 0.05)
    }
}

@Suite struct ClippedContentTests {
    let dark = RGBAColor(hex: "#101010")!
    let white = RGBAColor.white

    /// Dark page: label fragments touching the left edge, a wide gap, then a card and a text block.
    func page(stripWidth: Int = 60, gapTo: Int = 260) -> CGImage {
        var fills: [(CGRect, RGBAColor)] = []
        for i in 0..<4 { fills.append((CGRect(x: 0, y: 100 + i * 200, width: stripWidth - i * 8, height: 30), white)) }
        fills.append((CGRect(x: gapTo, y: 80, width: 1000, height: 600), white))
        fills.append((CGRect(x: gapTo + 60, y: 760, width: 700, height: 40), white))
        return TestImages.make(width: 1400, height: 1000, background: dark, fills: fills)
    }

    @Test func removesContentCutByTheEdge() {
        let analysis = ImageTrimmer.analyze(page())
        #expect(analysis.removedClippedContent)
        #expect(analysis.contentRect.minX == 260)
        #expect(analysis.backgroundColor == dark)
    }

    @Test func keepsATightCropOfASentence() {
        // "Hi there, …" cropped tightly: words touch the edge and are separated by narrow spaces.
        var fills: [(CGRect, RGBAColor)] = []
        var x = 0
        for word in [40, 110, 70, 160, 90, 130] {
            fills.append((CGRect(x: x, y: 20, width: word, height: 40), white))
            x += word + 14
        }
        let image = TestImages.make(width: x - 14, height: 80, background: dark, fills: fills)
        #expect(!ImageTrimmer.analyze(image).removedClippedContent)
    }

    @Test func keepsASolidSidebar() {
        let sidebar = RGBAColor(hex: "#1E293B")!
        let image = TestImages.make(width: 1400, height: 1000, background: dark,
                                    fills: [(CGRect(x: 0, y: 0, width: 250, height: 1000), sidebar),
                                            (CGRect(x: 400, y: 100, width: 800, height: 600), white)])
        #expect(!ImageTrimmer.analyze(image).removedClippedContent)
    }

    @Test func keepsContentWhenNothingElseIsThere() {
        // Only the strip has content: removing it would leave nothing.
        let image = TestImages.make(width: 1400, height: 1000, background: dark,
                                    fills: [(CGRect(x: 0, y: 300, width: 200, height: 40), white),
                                            (CGRect(x: 600, y: 500, width: 40, height: 40), white)])
        #expect(!ImageTrimmer.analyze(image).removedClippedContent)
    }

    @Test func manualCropTurnsRepairOff() {
        #expect(!ImageTrimmer.analyze(page(), repairEdges: false).removedClippedContent)
    }

    @Test func cropKeepsAnnotationOffsetsInOriginalPixels() {
        var settings = CompositionSettings.default
        settings.autoTrim = false
        let shot = ShotPreparer.prepareShot(page(), crop: CGRect(x: 100, y: 50, width: 800, height: 600),
                                            analysis: nil, settings: settings)
        #expect(shot.image.width == 800)
        #expect(shot.offset == CGPoint(x: -100, y: -50))
    }
}
