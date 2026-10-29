import CoreGraphics
import Testing
@testable import ScreenshottyCore

@Suite struct LayoutTests {
    func isCentred(_ layout: CompositionLayout) -> Bool {
        let left = layout.cardRect.minX
        let right = layout.canvasSize.width - layout.cardRect.maxX
        let top = layout.cardRect.minY
        let bottom = layout.canvasSize.height - layout.cardRect.maxY
        return left == right && top == bottom && left == left.rounded() && top == top.rounded()
    }

    @Test(arguments: AspectRatio.allCases)
    func cardIsCentredToThePixel(aspect: AspectRatio) {
        for size in [CGSize(width: 1999, height: 1201), CGSize(width: 800, height: 1400), CGSize(width: 333, height: 333)] {
            for chrome in WindowChromeStyle.allCases {
                var settings = CompositionSettings()
                settings.aspectRatio = aspect
                settings.windowChrome = chrome
                let layout = CompositionLayout(imageSize: size, settings: settings)
                #expect(isCentred(layout), "\(aspect) \(size) \(chrome)")
            }
        }
    }

    @Test(arguments: AspectRatio.allCases.filter { $0 != .auto })
    func canvasMatchesAspectRatio(aspect: AspectRatio) {
        var settings = CompositionSettings()
        settings.aspectRatio = aspect
        let layout = CompositionLayout(imageSize: CGSize(width: 1600, height: 1000), settings: settings)
        let actual = layout.canvasSize.width / layout.canvasSize.height
        // Within one pixel of rounding.
        #expect(abs(actual - aspect.ratio!) < 2 / layout.canvasSize.height)
    }

    @Test func paddingNeverShrinksBelowMinimum() {
        var settings = CompositionSettings()
        settings.padding = 100
        for aspect in AspectRatio.allCases {
            settings.aspectRatio = aspect
            let layout = CompositionLayout(imageSize: CGSize(width: 2000, height: 1000), settings: settings)
            // 1 unit = 2px here, so padding is 200px on every side at least.
            #expect(layout.cardRect.minX >= 200)
            #expect(layout.cardRect.minY >= 200)
        }
    }

    @Test func autoAspectUsesEqualPadding() {
        var settings = CompositionSettings()
        settings.padding = 50
        let layout = CompositionLayout(imageSize: CGSize(width: 1000, height: 500), settings: settings)
        #expect(layout.canvasSize == CGSize(width: 1100, height: 600))
        #expect(layout.cardRect == CGRect(x: 50, y: 50, width: 1000, height: 500))
    }

    @Test func chromeAddsTitleBarAboveImage() {
        var settings = CompositionSettings()
        settings.windowChrome = .dark
        let layout = CompositionLayout(imageSize: CGSize(width: 1000, height: 500), settings: settings)
        #expect(layout.titleBarHeight == 28)
        #expect(layout.imageRect.minY == layout.cardRect.minY + 28)
        #expect(layout.imageRect.size == CGSize(width: 1000, height: 500))
    }

    @Test func cornerRadiusIsClamped() {
        var settings = CompositionSettings()
        settings.cornerRadius = 60
        let layout = CompositionLayout(imageSize: CGSize(width: 1000, height: 40), settings: settings)
        #expect(layout.cornerRadius <= 20)
    }
}
