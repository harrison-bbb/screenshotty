import CoreGraphics
import Testing
@testable import ScreenshottyCore

@Suite struct ImageInspectorTests {
    @Test func detectsFullyTransparentCapture() {
        let blank = TestImages.make(width: 400, height: 300, background: nil)
        #expect(ImageInspector.isFullyTransparent(blank))
    }

    @Test func opaqueImageIsNotBlank() {
        #expect(!ImageInspector.isFullyTransparent(TestImages.make(width: 400, height: 300, background: .white)))
        #expect(!ImageInspector.isFullyTransparent(TestImages.make(width: 400, height: 300, background: .black)))
    }

    @Test func smallContentOnTransparentIsNotBlank() {
        let image = TestImages.make(width: 1000, height: 1000, background: nil,
                                    fills: [(CGRect(x: 495, y: 495, width: 10, height: 10), .black)])
        #expect(!ImageInspector.isFullyTransparent(image))
    }
}
