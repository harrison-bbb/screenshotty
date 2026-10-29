import CoreGraphics
import Testing
@testable import ScreenshottyCore

@Suite struct TextBlockTests {
    @Test func paragraphLinesBecomeOneBlock() {
        let lines = (0..<4).map { CGRect(x: 100, y: 100 + CGFloat($0) * 24, width: 400 - CGFloat($0) * 30, height: 18) }
        let blocks = TextBlocks.group(lines)
        #expect(blocks.count == 1)
        #expect(blocks[0].contains(CGPoint(x: 300, y: 150)))
    }

    @Test func separateColumnsStaySeparate() {
        let left = (0..<3).map { CGRect(x: 100, y: 100 + CGFloat($0) * 24, width: 200, height: 18) }
        let right = (0..<3).map { CGRect(x: 700, y: 100 + CGFloat($0) * 24, width: 200, height: 18) }
        #expect(TextBlocks.group(left + right).count == 2)
    }

    @Test func headingAndBodyWithAGapStaySeparate() {
        let heading = CGRect(x: 100, y: 100, width: 300, height: 40)
        let body = (0..<3).map { CGRect(x: 100, y: 220 + CGFloat($0) * 24, width: 400, height: 18) }
        #expect(TextBlocks.group([heading] + body).count == 2)
    }
}
