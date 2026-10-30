import CoreGraphics
import Testing
@testable import ScreenshottyCore

/// Regressions found in the 1.0 bug hunt.
@Suite struct ReleaseFixTests {
    @Test func sharedFilesCantAskForHugeOrBrokenNumbers() throws {
        let settings = try JSON.decode(#"{"padding":20000,"cornerRadius":-5,"innerPadding":99999,"exportWidth":30000}"#)
        #expect(settings.padding == CompositionSettings.paddingRange.upperBound)
        #expect(settings.cornerRadius == 0)
        #expect(settings.innerPadding == CompositionSettings.innerPaddingRange.upperBound)
        #expect(settings.exportWidth == CompositionSettings.exportWidthRange.upperBound)
        #expect(CompositionSettings.clamp(.nan, to: 0...10, default: 4) == 4)
        #expect(CompositionSettings.clamp(.infinity, to: 0...10, default: 4) == 4)
    }

    @Test func aNearlyBlankCaptureIsNotShrunkToItsOneMark() {
        let white = RGBAColor(hex: "#FFFFFF")!
        let image = TestImages.make(width: 1200, height: 800, background: white,
                                    fills: [(CGRect(x: 600, y: 400, width: 3, height: 3), RGBAColor(hex: "#000000")!)])
        let shot = ShotPreparer.prepareShot(image, settings: .default)
        #expect(shot.image.width == 1200 && shot.image.height == 800)
        #expect(shot.offset == .zero)
    }

    @Test func aCropOutsideTheImageIsIgnored() {
        let image = TestImages.make(width: 400, height: 300, background: RGBAColor(hex: "#3366FF")!)
        var settings = CompositionSettings.default
        settings.autoTrim = false
        let shot = ShotPreparer.prepareShot(image, crop: CGRect(x: 5000, y: 5000, width: 100, height: 100), settings: settings)
        #expect(shot.image.width == 400)
        #expect(shot.offset == .zero)
    }

    @Test func landscapeIPhoneKeepsContentClearOfTheIsland() throws {
        var settings = CompositionSettings.default
        settings.device = .iphone
        let layout = CompositionLayout(imageSize: CGSize(width: 1400, height: 700), settings: settings)
        let device = try #require(layout.device)
        #expect(device.landscape)
        let gap = layout.cardRect.minX - device.screenRect.minX
        #expect(gap >= device.screenRect.height * 0.14)
    }

    @Test func photosAreTurnedUprightFromTheirExifOrientation() throws {
        let landscape = TestImages.make(width: 80, height: 40, background: RGBAColor(hex: "#FF0000")!)
        let loaded = try #require(ImageLoader.load(TestImages.jpeg(landscape, orientation: 6)))
        #expect(loaded.width == 40 && loaded.height == 80)
    }

    @Test func outputKeepsTheCapturesWideColourSpace() throws {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let ctx = try #require(CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 0, space: p3,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(ctx.makeImage())
        let output = try Compositor.render(image, settings: .default)
        #expect(output.colorSpace?.name == CGColorSpace.displayP3)
    }
}
