import CoreGraphics
import Testing
@testable import ScreenshottyCore

@Suite struct TextAndStepTests {
    let blue = RGBAColor(hex: "#0A84FF")!

    func pixel(_ image: CGImage, _ x: CGFloat, _ y: CGFloat) -> RGBAPixel {
        RGBABuffer(image: image)![Int(x), Int(y)]
    }

    @Test func textLabelDrawsAPillInItsColour() {
        let shot = TestImages.make(width: 1000, height: 600, background: .white)
        let label = Annotation(kind: .text, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 100, y: 100),
                               color: blue, text: "Click here")
        let frame = label.frame(unit: 1)
        #expect(frame.width > 100 && frame.height > 20)
        let out = AnnotationRenderer.apply([label], to: shot, offset: .zero)
        let p = pixel(out, frame.minX + 4, frame.midY)
        #expect(p.b > 200 && p.r < 60)
    }

    @Test func emptyTextDrawsNothing() {
        let shot = TestImages.make(width: 400, height: 300, background: .white)
        let label = Annotation(kind: .text, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 50, y: 50), color: blue, text: "  ")
        let out = AnnotationRenderer.apply([label], to: shot, offset: .zero)
        #expect(pixel(out, 60, 60).r == 255)
    }

    @Test func stepsAreCirclesCentredOnTheClick() {
        let shot = TestImages.make(width: 1000, height: 600, background: .white)
        let step = Annotation(kind: .step, start: CGPoint(x: 300, y: 300), end: CGPoint(x: 300, y: 300), color: blue)
        let frame = step.frame(unit: 1)
        #expect(abs(frame.midX - 300) < 0.01 && abs(frame.midY - 300) < 0.01)
        let out = AnnotationRenderer.apply([step], to: shot, offset: .zero)
        // Just inside the white ring, the step colour.
        let p = pixel(out, frame.minX + frame.width * 0.2, frame.midY)
        #expect(p.b > 200 && p.r < 60)
    }

    @Test func biggerSizeMeansBiggerLabel() {
        var small = Annotation(kind: .text, start: .zero, end: .zero, text: "Hi")
        small.size = Annotation.textSizes[0]
        var large = small
        large.size = Annotation.textSizes[2]
        #expect(large.frame(unit: 1).height > small.frame(unit: 1).height)
    }

    @Test func textAndStepsAreHitByTheirArea() {
        let label = Annotation(kind: .text, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 100, y: 100), text: "Settings")
        let frame = label.frame(unit: 1)
        #expect(label.hitTest(CGPoint(x: frame.midX, y: frame.midY), tolerance: 2))
        #expect(!label.hitTest(CGPoint(x: frame.maxX + 40, y: frame.midY), tolerance: 2))
    }

    @Test func oldAnnotationsDecodeWithDefaults() throws {
        let json = ##"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"arrow","start":[1,2],"end":[3,4],"color":"#FF3B30"}"##
        let annotation = try Docs.decodeAnnotation(json)
        #expect(annotation.text == "")
        #expect(annotation.size == Annotation.defaultTextSize)
    }
}

@Suite struct WatermarkTests {
    @Test func watermarkDrawsInTheChosenCorner() throws {
        let shot = TestImages.make(width: 1200, height: 800, background: RGBAColor(hex: "#222222")!)
        var settings = CompositionSettings.default
        settings.smartBackground = nil
        settings.background = .solid(RGBAColor(hex: "#101010")!)
        let plain = try Compositor.compose(shot, settings: settings)
        settings.watermark = Watermark(text: "acme.com", position: .bottomRight, size: 40, opacity: 1)
        let marked = try Compositor.compose(shot, settings: settings)
        #expect(plain.width == marked.width)
        // Something light appears bottom-right, nothing changes top-left.
        let a = RGBABuffer(image: plain)!, b = RGBABuffer(image: marked)!
        var changedBottomRight = 0
        for y in (b.height * 9 / 10)..<b.height { for x in (b.width * 3 / 4)..<b.width where b[x, y].r > a[x, y].r + 60 { changedBottomRight += 1 } }
        #expect(changedBottomRight > 20)
        #expect(a[10, 10].r == b[10, 10].r)
    }

    @Test func emptyWatermarkIsIgnored() {
        #expect(Watermark().isEmpty)
        #expect(!Watermark(text: "@acme").isEmpty)
    }

    @Test func settingsKeepTheWatermark() throws {
        var settings = CompositionSettings.default
        settings.watermark = Watermark(logoPath: "/tmp/logo.png", text: "@acme", position: .topLeft, size: 50, opacity: 0.5)
        #expect(try JSON.roundTrip(settings) == settings)
    }
}

@Suite struct DocumentTests {
    @Test func styleFilesCarryTheirLogo() throws {
        let folder = Docs.tempFolder()
        let logoURL = try #require(TempFile.writePNG(TestImages.make(width: 64, height: 64, background: RGBAColor(hex: "#FF0000")!)))
        var settings = CompositionSettings.default
        settings.watermark = Watermark(logoPath: logoURL.path, text: "acme")
        let style = Style(name: "Acme launch", settings: settings)
        let restored = try Docs.styleRoundTrip(style, unpackInto: folder)
        #expect(restored.name == "Acme launch")
        let path = try #require(restored.settings.watermark?.logoPath)
        #expect(path != logoURL.path)
        #expect(path.hasPrefix(folder.path))
        #expect(Docs.sameContents(path, logoURL.path))
        #expect(try Docs.styleFileIsJSON(style))
    }

    @Test func missingImagesFallBackSafely() throws {
        var settings = CompositionSettings.default
        settings.background = .image(ImageBackgroundSpec(path: "asset:missing.png"))
        let unpacked = EmbeddedAssets.unpack(settings, files: [:], into: Docs.tempFolder())
        #expect(unpacked.background == Presets.defaultBackground)
    }

    @Test func projectsReopenWithEverythingEditable() throws {
        let capture = TestImages.make(width: 500, height: 300, background: RGBAColor(hex: "#3366FF")!)
        var settings = CompositionSettings.default
        settings.device = .macbook
        let marks = [Annotation(kind: .step, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 40, y: 40)),
                     Annotation(kind: .text, start: CGPoint(x: 80, y: 40), end: CGPoint(x: 80, y: 40), text: "Here")]
        let crop = CGRect(x: 10, y: 20, width: 400, height: 250)
        let project = try #require(ProjectDocument(image: capture, settings: settings, annotations: marks, crop: crop))
        let reopened = try Docs.projectRoundTrip(project)
        #expect(reopened.capture?.width == 500)
        #expect(reopened.annotations == marks)
        #expect(reopened.crop == crop)
        #expect(reopened.settings.device == .macbook)
    }

    @Test func projectsRenderLikeTheEditor() throws {
        let capture = TestImages.make(width: 500, height: 300, background: RGBAColor(hex: "#3366FF")!)
        let crop = CGRect(x: 0, y: 0, width: 250, height: 300)
        var settings = CompositionSettings.default
        settings.autoTrim = false
        let full = try Compositor.compose(capture, settings: settings)
        let cropped = try Compositor.compose(capture, settings: settings, crop: crop)
        #expect(cropped.width < full.width)
    }
}
