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

@Suite struct ImageLoaderTests {
    /// Captures are loaded from a temp file that is deleted right away. The image must still draw.
    @Test func imageSurvivesDeletingItsFile() throws {
        let red = RGBAColor(hex: "#FF0000")!
        let original = TestImages.make(width: 300, height: 200, background: red)
        let url = try #require(TempFile.writePNG(original))
        let loaded = try #require(ImageLoader.load(url))
        TempFile.delete(url)
        let pixels = try #require(RGBABuffer(image: loaded))
        #expect(pixels[150, 100].r == 255 && pixels[150, 100].g == 0)
        #expect(PNG.roundTripWidth(loaded) == 300)
        let output = try Compositor.compose(loaded, settings: .default)
        let layout = CompositionLayout(imageSize: CGSize(width: 300, height: 200), settings: .default)
        let centre = try #require(RGBABuffer(image: output))[Int(layout.imageRect.midX), Int(layout.imageRect.midY)]
        #expect(centre.r == 255 && centre.g == 0 && centre.b == 0)
    }
}
