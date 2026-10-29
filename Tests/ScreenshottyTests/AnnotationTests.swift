import CoreGraphics
import Testing
@testable import ScreenshottyCore

@Suite struct AnnotationTests {
    let grey = RGBAColor(hex: "#808080")!

    @Test func rectIsNormalisedFromAnyDragDirection() {
        let a = Annotation(kind: .box, start: CGPoint(x: 50, y: 80), end: CGPoint(x: 10, y: 20))
        #expect(a.rect == CGRect(x: 10, y: 20, width: 40, height: 60))
    }

    @Test func arrowHitTestFollowsTheLine() {
        let arrow = Annotation(kind: .arrow, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0))
        #expect(arrow.hitTest(CGPoint(x: 50, y: 4), tolerance: 5))
        #expect(!arrow.hitTest(CGPoint(x: 50, y: 20), tolerance: 5))
        #expect(!arrow.hitTest(CGPoint(x: 120, y: 0), tolerance: 5))
    }

    @Test func translateMovesBothEnds() {
        let a = Annotation(kind: .arrow, start: .zero, end: CGPoint(x: 10, y: 10)).translated(by: CGVector(dx: 5, dy: -2))
        #expect(a.start == CGPoint(x: 5, y: -2) && a.end == CGPoint(x: 15, y: 8))
    }

    @Test func redactCoversPixelsCompletely() throws {
        let shot = TestImages.make(width: 200, height: 100, background: .white,
                                   fills: [(CGRect(x: 60, y: 30, width: 80, height: 40), RGBAColor(hex: "#FF0000")!)])
        let out = AnnotationRenderer.apply([Annotation(kind: .redact, start: CGPoint(x: 50, y: 20), end: CGPoint(x: 150, y: 80))],
                                           to: shot, offset: .zero)
        let px = try #require(RGBABuffer(image: out))
        for (x, y) in [(100, 50), (60, 30), (139, 69)] {
            #expect(px[x, y].r < 30, "pixel \(x),\(y) still visible")
        }
        #expect(px[10, 10].r == 255) // outside untouched
    }

    @Test func blurDestroysDetail() throws {
        // Fine 2px stripes: after pixelation neighbouring pixels must look alike.
        var fills: [(CGRect, RGBAColor)] = []
        for x in stride(from: 0, to: 200, by: 4) { fills.append((CGRect(x: x, y: 0, width: 2, height: 200), .black)) }
        let shot = TestImages.make(width: 200, height: 200, background: .white, fills: fills)
        let out = AnnotationRenderer.apply([Annotation(kind: .blur, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 160, y: 160))],
                                           to: shot, offset: .zero)
        let px = try #require(RGBABuffer(image: out))
        let a = Int(px[100, 100].r), b = Int(px[102, 100].r)
        #expect(abs(a - b) < 40)
        // Outside the blur the stripes are intact.
        #expect(px[0, 10].r == 0 && px[2, 10].r == 255)
    }

    @Test func arrowAndBoxUseTheirColour() throws {
        let shot = TestImages.make(width: 1000, height: 600, background: .white)
        let blue = RGBAColor(hex: "#0A84FF")!
        let out = AnnotationRenderer.apply([
            Annotation(kind: .arrow, start: CGPoint(x: 100, y: 300), end: CGPoint(x: 600, y: 300), color: blue),
            Annotation(kind: .box, start: CGPoint(x: 700, y: 100), end: CGPoint(x: 900, y: 500), color: blue),
        ], to: shot, offset: .zero)
        let px = try #require(RGBABuffer(image: out))
        let shaft = px[300, 300]
        #expect(shaft.b > 200 && shaft.r < 60)
        let edge = px[700, 300] // left side of the box outline
        #expect(edge.b > 200 && edge.r < 60)
        #expect(px[800, 300].r == 255) // box interior untouched
    }

    /// Annotations are stored in original-capture pixels and must land on the same content
    /// after the shot is trimmed and given an inner margin.
    @Test func annotationsStayOnContentThroughTrimAndPadding() throws {
        let red = RGBAColor(hex: "#FF0000")!
        let source = TestImages.make(width: 800, height: 600, background: .white,
                                     fills: [(CGRect(x: 300, y: 200, width: 200, height: 100), red)])
        var settings = CompositionSettings()
        settings.innerPadding = 100
        let prepared = ShotPreparer.prepareShot(source, settings: settings)
        #expect(prepared.offset != .zero)
        let out = AnnotationRenderer.apply([Annotation(kind: .redact, start: CGPoint(x: 300, y: 200), end: CGPoint(x: 500, y: 300))],
                                           to: prepared.image, offset: prepared.offset)
        let px = try #require(RGBABuffer(image: out))
        // The red block's centre in the prepared shot is now redacted.
        let centre = CGPoint(x: 400 + prepared.offset.x, y: 250 + prepared.offset.y)
        #expect(px[Int(centre.x), Int(centre.y)].r < 30)
    }

    @Test func composeWithAnnotationsMatchesManualPipeline() throws {
        let source = TestImages.make(width: 400, height: 300, background: grey)
        let annotations = [Annotation(kind: .box, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 200, y: 200))]
        let composed = try Compositor.compose(source, settings: CompositionSettings(), annotations: annotations)
        let prepared = ShotPreparer.prepareShot(source, settings: CompositionSettings())
        let manual = try Compositor.render(AnnotationRenderer.apply(annotations, to: prepared.image, offset: prepared.offset),
                                           settings: CompositionSettings())
        #expect(composed.width == manual.width && composed.height == manual.height)
    }

    @Test func emptyAnnotationsReturnTheSameImage() {
        let shot = TestImages.make(width: 10, height: 10, background: .white)
        #expect(AnnotationRenderer.apply([], to: shot, offset: .zero) === shot)
    }
}

@Suite struct AnnotationCodingTests {
    @Test func roundTrips() throws {
        let a = Annotation(kind: .blur, start: CGPoint(x: 1, y: 2), end: CGPoint(x: 3, y: 4), color: RGBAColor(hex: "#34C759")!)
        #expect(try JSON.roundTrip(a) == a)
    }
}
