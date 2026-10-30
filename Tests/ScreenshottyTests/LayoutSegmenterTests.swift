import CoreGraphics
import Testing
@testable import ScreenshottyCore

@Suite struct LayoutSegmenterTests {
    let page = RGBAColor(hex: "#10192A")!
    let sidebar = RGBAColor(hex: "#1B2433")!
    let card = RGBAColor(hex: "#E5E7EB")!
    let ink = RGBAColor(hex: "#F9FAFB")!

    /// A page: a sidebar, a row of three cards with photos, and two columns of text lines below.
    func layout() -> CGImage {
        var fills: [(CGRect, RGBAColor)] = [(CGRect(x: 0, y: 0, width: 140, height: 600), sidebar)]
        for i in 0..<4 { fills.append((CGRect(x: 20, y: 40 + i * 40, width: 100, height: 14), ink)) }   // sidebar items
        for i in 0..<3 {
            let x = 200 + i * 240
            fills.append((CGRect(x: x, y: 40, width: 210, height: 200), card))
            fills.append((CGRect(x: x + 20, y: 60, width: 170, height: 160), RGBAColor(hex: "#334155")!))
        }
        for column in 0..<2 {
            for line in 0..<5 {
                fills.append((CGRect(x: 200 + column * 360, y: 300 + line * 22, width: 300 - line * 12, height: 12), ink))
            }
        }
        return TestImages.make(width: 960, height: 600, background: page, fills: fills)
    }

    func contains(_ rects: [CGRect], _ expected: CGRect, tolerance: CGFloat = 3) -> Bool {
        rects.contains { abs($0.minX - expected.minX) <= tolerance && abs($0.minY - expected.minY) <= tolerance &&
            abs($0.maxX - expected.maxX) <= tolerance && abs($0.maxY - expected.maxY) <= tolerance }
    }

    @Test func findsEachCardWithItsFill() {
        let blocks = LayoutSegmenter.sections(in: layout(), minGap: 8, minSize: 20)
        for i in 0..<3 {
            #expect(contains(blocks, CGRect(x: 200 + i * 240, y: 40, width: 210, height: 200)), "card \(i)")
        }
    }

    @Test func findsTheSidebar() {
        let blocks = LayoutSegmenter.sections(in: layout(), minGap: 8, minSize: 20)
        #expect(blocks.contains { $0.minX <= 1 && $0.width >= 135 && $0.width <= 141 })
    }

    @Test func textColumnsSplitBeforeTheirLines() {
        let blocks = LayoutSegmenter.sections(in: layout(), minGap: 8, minSize: 20)
        // Each column of lines is one block (lines are 10 px apart, under the 8 px gap? no: 10 > 8, so
        // they may split further, but the column itself must exist first).
        #expect(contains(blocks, CGRect(x: 200, y: 300, width: 300, height: 100)))
        #expect(contains(blocks, CGRect(x: 560, y: 300, width: 300, height: 100)))
    }

    @Test func plainImageHasNoSections() {
        #expect(LayoutSegmenter.sections(in: TestImages.make(width: 400, height: 300, background: page), minGap: 8, minSize: 20).isEmpty)
    }
}
