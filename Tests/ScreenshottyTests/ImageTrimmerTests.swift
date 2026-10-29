import CoreGraphics
import Testing
@testable import ScreenshottyCore

@Suite struct ImageTrimmerTests {
    let red = RGBAColor(hex: "#FF0000")!

    @Test func trimsWhiteMargins() {
        let image = TestImages.make(width: 200, height: 100, background: .white,
                                    fills: [(CGRect(x: 30, y: 10, width: 100, height: 50), red)])
        #expect(ImageTrimmer.analyze(image).contentRect == CGRect(x: 30, y: 10, width: 100, height: 50))
    }

    @Test func trimsTransparentMargins() {
        let image = TestImages.make(width: 120, height: 80, background: nil,
                                    fills: [(CGRect(x: 5, y: 7, width: 40, height: 20), red)])
        #expect(ImageTrimmer.analyze(image).contentRect == CGRect(x: 5, y: 7, width: 40, height: 20))
    }

    @Test func leavesImageAloneWhenCornersDiffer() {
        // Coloured "nav bar" across the top: corners don't match, so nothing must be trimmed.
        let image = TestImages.make(width: 100, height: 100, background: .white,
                                    fills: [(CGRect(x: 0, y: 0, width: 100, height: 20), red),
                                            (CGRect(x: 40, y: 50, width: 20, height: 20), .black)])
        #expect(ImageTrimmer.analyze(image).contentRect == CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    @Test func toleratesNoiseWithinTolerance() {
        let offWhite = RGBAColor(hex: "#FEFEFE")!
        let image = TestImages.make(width: 100, height: 100, background: .white,
                                    fills: [(CGRect(x: 0, y: 0, width: 100, height: 3), offWhite),
                                            (CGRect(x: 20, y: 20, width: 60, height: 60), red)])
        #expect(ImageTrimmer.analyze(image).contentRect == CGRect(x: 20, y: 20, width: 60, height: 60))
    }

    @Test func doesNotTrimIntoLightGreyAppBackground() {
        // A light-grey app surface on a white margin must be kept whole.
        let grey = RGBAColor(hex: "#F7F7FA")!
        let image = TestImages.make(width: 300, height: 200, background: .white,
                                    fills: [(CGRect(x: 50, y: 20, width: 200, height: 150), grey),
                                            (CGRect(x: 120, y: 80, width: 40, height: 40), red)])
        #expect(ImageTrimmer.analyze(image).contentRect == CGRect(x: 50, y: 20, width: 200, height: 150))
    }

    @Test func uniformImageIsReturnedWhole() {
        let image = TestImages.make(width: 50, height: 40, background: .white)
        #expect(ImageTrimmer.analyze(image).contentRect == CGRect(x: 0, y: 0, width: 50, height: 40))
        #expect(ImageTrimmer.crop(image, to: ImageTrimmer.analyze(image).contentRect).width == 50)
    }

    @Test func trimProducesCroppedImage() {
        let image = TestImages.make(width: 200, height: 100, background: .white,
                                    fills: [(CGRect(x: 30, y: 10, width: 100, height: 50), red)])
        let trimmed = ImageTrimmer.crop(image, to: ImageTrimmer.analyze(image).contentRect)
        #expect(trimmed.width == 100)
        #expect(trimmed.height == 50)
    }
}
