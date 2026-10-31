import CoreGraphics
import Testing
@testable import ScreenshottyCore

@Suite(.timeLimit(.minutes(1))) struct ScrollStitcherTests {
    static let width = 240
    static let view = 300          // visible height of the scrolling area
    static let header = 30
    static let footer = 20

    /// A long "page" of coloured bars that differ from row to row, like text and pictures.
    static func page(height: Int) -> CGImage {
        var seed: UInt32 = 7
        func next(_ n: Int) -> Int {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Int(seed >> 8) % n
        }
        var fills: [(CGRect, RGBAColor)] = []
        var y = 0
        while y < height {
            let h = 4 + next(14)
            let x = next(width / 2)
            let color = RGBAColor(red: Double(next(255)) / 255, green: Double(next(255)) / 255, blue: Double(next(255)) / 255)
            fills.append((CGRect(x: x, y: y, width: 20 + next(width - x), height: h), color))
            y += h + next(6)
        }
        return TestImages.make(width: width, height: height, background: RGBAColor(hex: "#FFFFFF")!, fills: fills)
    }

    /// What the area shows when the page is scrolled down by `offset`: a fixed header and footer around it.
    static func frame(of page: CGImage, at offset: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: view, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Page row `offset` lands just under the header (CG's origin is bottom-left).
        ctx.draw(page, in: CGRect(x: 0, y: view - header - (page.height - offset), width: width, height: page.height))
        ctx.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.6, alpha: 1))
        ctx.fill(CGRect(x: 0, y: view - header, width: width, height: header))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 10, y: view - 20, width: 60, height: 8))
        ctx.setFillColor(CGColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: footer))
        ctx.setFillColor(CGColor(red: 0.9, green: 0.5, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 100, y: 6, width: 40, height: 8))
        return ctx.makeImage()!
    }

    static func pixels(_ image: CGImage) -> [UInt8] {
        ScrollStitcher.Frame(image, space: CGColorSpace(name: CGColorSpace.sRGB)!, ignoredRightColumns: 0)!.pixels
    }

    @Test func stitchesAScrolledPageWithAStickyHeaderAndFooter() throws {
        let page = Self.page(height: 1200)
        let offsets = [0, 37, 120, 121, 260, 300, 455, 610]
        let stitcher = try #require(ScrollStitcher(first: Self.frame(of: page, at: 0)))
        for offset in offsets.dropFirst() {
            #expect(stitcher.add(Self.frame(of: page, at: offset)) != .noMatch, "offset \(offset)")
        }
        let moving = Self.view - Self.header - Self.footer
        let result = try #require(stitcher.image())
        #expect(result.height == Self.header + offsets.last! + moving + Self.footer)

        // The header once, then the page from the top, then the footer once.
        let first = Self.pixels(Self.frame(of: page, at: 0))
        let last = Self.pixels(Self.frame(of: page, at: offsets.last!))
        let pageRows = Self.pixels(page)
        let row = Self.width * 4
        var expected = Array(first[0 ..< Self.header * row])
        expected += pageRows[0 ..< (offsets.last! + moving) * row]
        expected += last[(Self.view - Self.footer) * row ..< Self.view * row]
        let actual = Self.pixels(result)
        #expect(actual.count == expected.count)
        // Compared by hand: a failing == on arrays this big makes the test runner diff them for minutes.
        let firstDifference = zip(actual, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset
        #expect(firstDifference == nil, "first different row: \((firstDifference ?? 0) / row)")
    }

    @Test func aFrameThatDidntMoveAddsNothing() throws {
        let page = Self.page(height: 800)
        let stitcher = try #require(ScrollStitcher(first: Self.frame(of: page, at: 0)))
        #expect(stitcher.add(Self.frame(of: page, at: 0)) == .unchanged)
        #expect(stitcher.height == Self.view)
        #expect(!stitcher.hasScrolled)
    }

    @Test func scrollingBackUpIsIgnoredUntilNewContentAppears() throws {
        let page = Self.page(height: 1000)
        let stitcher = try #require(ScrollStitcher(first: Self.frame(of: page, at: 0)))
        #expect(stitcher.add(Self.frame(of: page, at: 200)) == .added(200))
        #expect(stitcher.add(Self.frame(of: page, at: 90)) == .noMatch)
        #expect(stitcher.add(Self.frame(of: page, at: 260)) == .added(60))
        #expect(stitcher.height == Self.view + 260)
    }

    @Test func aJumpBiggerThanTheAreaCantBeMatched() throws {
        let page = Self.page(height: 1500)
        let stitcher = try #require(ScrollStitcher(first: Self.frame(of: page, at: 0)))
        #expect(stitcher.add(Self.frame(of: page, at: 700)) == .noMatch)
    }

    @Test func stopsAtTheHeightLimit() throws {
        let page = Self.page(height: 1500)
        let stitcher = try #require(ScrollStitcher(first: Self.frame(of: page, at: 0), maxHeight: 500))
        _ = stitcher.add(Self.frame(of: page, at: 150))
        _ = stitcher.add(Self.frame(of: page, at: 300))
        #expect(stitcher.add(Self.frame(of: page, at: 400)) == .full)
        #expect(stitcher.height == 500)
    }
}

extension ScrollStitcherTests {
    /// A frame with a grey overlay scroll bar at the right edge, positioned for `offset`.
    static func frameWithScrollBar(of page: CGImage, at offset: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: view, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(frame(of: page, at: offset), in: CGRect(x: 0, y: 0, width: width, height: view))
        ctx.setFillColor(CGColor(gray: 0.45, alpha: 1))
        ctx.fill(CGRect(x: width - 8, y: view - 60 - offset / 4, width: 6, height: 50))
        return ctx.makeImage()!
    }

    @Test func aScrollBarAtTheEdgeIsCutOff() throws {
        let page = Self.page(height: 1200)
        let stitcher = try #require(ScrollStitcher(first: Self.frameWithScrollBar(of: page, at: 0), ignoredRightColumns: 12))
        for offset in [80, 160, 240, 320] {
            #expect(stitcher.add(Self.frameWithScrollBar(of: page, at: offset)) == .added(80), "\(stitcher.diagnosis)")
        }
        #expect(stitcher.sawScrollBar)
        #expect(stitcher.image()?.width == Self.width - 12)
    }

    @Test func aStillEdgeIsKept() throws {
        let page = Self.page(height: 1200)
        let stitcher = try #require(ScrollStitcher(first: Self.frame(of: page, at: 0), ignoredRightColumns: 12))
        _ = stitcher.add(Self.frame(of: page, at: 100))
        #expect(!stitcher.sawScrollBar)
        #expect(stitcher.image()?.width == Self.width)
    }
}

extension ScrollStitcherTests {
    @Test func somethingChangingOnAStillPageIsNotAScroll() throws {
        let page = Self.page(height: 1200)
        let first = Self.frame(of: page, at: 200)
        let stitcher = try #require(ScrollStitcher(first: first))
        // The same view with a small box that changes, like a counter or a cursor.
        let ctx = CGContext(data: nil, width: Self.width, height: Self.view, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(first, in: CGRect(x: 0, y: 0, width: Self.width, height: Self.view))
        ctx.setFillColor(CGColor(gray: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 40, y: 60, width: 160, height: 30))
        let outcome = stitcher.add(ctx.makeImage()!)
        #expect(outcome == .unchanged || outcome == .noMatch)
        #expect(stitcher.height == Self.view)
    }
}

extension ScrollStitcherTests {
    /// A frame with a still sidebar of text on the left, and the page scrolled by `offset` beside it.
    static func frameWithSidebar(of page: CGImage, at offset: Int, sidebar: Int = 80) -> CGImage {
        let full = width + sidebar
        let ctx = CGContext(data: nil, width: full, height: view, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.85, green: 0.8, blue: 0.95, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: sidebar, height: view))
        ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
        for line in stride(from: 10, to: view - 10, by: 16) {
            ctx.fill(CGRect(x: 8, y: line, width: 30 + (line * 7) % 40, height: 6))
        }
        ctx.draw(frame(of: page, at: offset), in: CGRect(x: sidebar, y: 0, width: width, height: view))
        return ctx.makeImage()!
    }

    @Test func aStillSidebarIsKeptOnceAndFilledBelow() throws {
        let page = Self.page(height: 1200)
        let stitcher = try #require(ScrollStitcher(first: Self.frameWithSidebar(of: page, at: 0)))
        for offset in [40, 120, 200, 330] {
            #expect(stitcher.add(Self.frameWithSidebar(of: page, at: offset)) != .noMatch, "offset \(offset)")
        }
        let result = try #require(stitcher.image())
        #expect(result.height == Self.view + 330)
        #expect(result.width == Self.width + 80)
        // Below the first screen, the sidebar's lines of text don't repeat: its strip is one colour.
        let pixels = Self.pixels(result)
        let row = result.width * 4
        var colours = Set<[UInt8]>()
        for y in Self.view + 20 ..< result.height - 20 {
            let i = y * row + 20 * 4
            colours.insert(Array(pixels[i ..< i + 4]))
        }
        #expect(colours.count == 1)
    }

    @Test func aBoxThatKeepsChangingOnAStillPageIsNotLost() throws {
        let page = Self.page(height: 1200)
        let first = Self.frame(of: page, at: 100)
        let stitcher = try #require(ScrollStitcher(first: first))
        for step in 0 ..< 5 {
            // Like a playing video in one corner: a box whose picture keeps changing.
            let ctx = CGContext(data: nil, width: Self.width, height: Self.view, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(first, in: CGRect(x: 0, y: 0, width: Self.width, height: Self.view))
            for stripe in 0 ..< 10 {
                ctx.setFillColor(CGColor(gray: CGFloat((stripe + step) % 3) / 3, alpha: 1))
                ctx.fill(CGRect(x: 20, y: 60 + stripe * 14, width: 70, height: 14))
            }
            #expect(stitcher.add(ctx.makeImage()!) == .unchanged, "step \(step)")
        }
        #expect(stitcher.height == Self.view)
    }
}

extension ScrollStitcherTests {
    @Test func aBoxFloatingAtTheBottomDoesNotStreakThePage() throws {
        let page = Self.page(height: 1200)
        func floating(_ offset: Int) -> CGImage {
            let ctx = CGContext(data: nil, width: Self.width, height: Self.view, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(Self.frame(of: page, at: offset), in: CGRect(x: 0, y: 0, width: Self.width, height: Self.view))
            // A bubble just above the footer, in a colour the page never uses.
            ctx.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 180, y: Self.footer + 4, width: 40, height: 30))
            return ctx.makeImage()!
        }
        let stitcher = try #require(ScrollStitcher(first: floating(0)))
        for offset in stride(from: 40, through: 480, by: 40) { _ = stitcher.add(floating(offset)) }
        let pixels = Self.pixels(try #require(stitcher.image()))
        let row = Self.width * 4
        let rows = pixels.count / row
        // Only the last screenful (still on screen at the end) may show the bubble.
        var streaks = 0
        for y in 0 ..< rows - Self.view {
            let i = y * row + 200 * 4
            if pixels[i] == 255, pixels[i + 1] == 0, pixels[i + 2] == 255 { streaks += 1 }
        }
        #expect(streaks == 0)
    }
}
