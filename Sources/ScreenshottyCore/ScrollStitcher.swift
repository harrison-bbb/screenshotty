import CoreGraphics
import Foundation

/// Joins screenshots of one area, taken while its content scrolls, into one tall image.
///
/// Each new frame is matched against the last frame that was used: the stitcher looks for how far the
/// content moved up by comparing rows of pixels, then adds only the rows that came into view. Rows that
/// stay put at the top and bottom of the area (a sticky header or footer) are found on the first scroll
/// and appear once, at the top and bottom of the result.
public final class ScrollStitcher {
    public enum Outcome: Equatable {
        /// New rows were added (how many).
        case added(Int)
        /// The content didn't move.
        case unchanged
        /// The frame couldn't be matched: it scrolled up, jumped too far, or the content changed.
        case noMatch
        /// The image reached `maxHeight`; later frames are ignored.
        case full
    }

    public let width: Int
    public let frameHeight: Int
    public let maxHeight: Int
    /// Columns at the right edge left out of matching, where overlay scroll bars appear while scrolling.
    private let ignoredRightColumns: Int
    private let space: CGColorSpace

    /// The result so far, without the footer: RGBA rows.
    private var rows: [UInt8]
    /// The fixed rows at the bottom of the area, from the latest frame.
    private var footer: [UInt8] = []
    private var last: Frame
    private var bands: (top: Int, bottom: Int)?
    private var lastShift: Int?
    /// Where the latest frame's first row sits in the result.
    private var frameTop = 0
    private var isFull = false
    /// Set when the right edge changed while the content beside it didn't: a scroll bar. It's cut off the result.
    public private(set) var sawScrollBar = false

    /// The height of the image so far, in pixels.
    public var height: Int { (rows.count + footer.count) / bytesPerRow }
    /// Whether any frame has been added after the first.
    public private(set) var hasScrolled = false

    private var bytesPerRow: Int { width * 4 }

    public init?(first: CGImage, ignoredRightColumns: Int = 0, maxHeight: Int = 30_000) {
        guard first.width > 0, first.height > 1 else { return nil }
        width = first.width
        frameHeight = first.height
        self.maxHeight = maxHeight
        self.ignoredRightColumns = min(max(ignoredRightColumns, 0), first.width / 4)
        space = CGColorSpace.working(for: first)
        guard let frame = Frame(first, space: space, ignoredRightColumns: self.ignoredRightColumns) else { return nil }
        last = frame
        rows = frame.pixels
    }

    @discardableResult
    public func add(_ image: CGImage) -> Outcome {
        guard !isFull else { return .full }
        guard image.width == width, image.height == frameHeight,
              let frame = Frame(image, space: space, ignoredRightColumns: ignoredRightColumns) else { return .noMatch }
        let all = Matcher(last, frame, buckets: Array(0 ..< Frame.buckets))
        if all.score(shift: 0, top: 0, moving: frameHeight, threshold: 0.97) != nil { return .unchanged }

        // Only the columns that changed can show how far the content moved. A sidebar or panel that stays
        // put beside the scrolling part is left out (and trimmed off the result).
        let columns = Self.columns(last, frame)
        guard !columns.moving.isEmpty else { return .unchanged }
        let matcher = Matcher(last, frame, buckets: columns.moving)
        let bands = self.bands ?? matcher.fixedBands()
        let top = bands.top, bottom = bands.bottom
        let moving = frameHeight - top - bottom
        // A scroll has to line up clearly better than staying put: otherwise a patch that keeps changing on
        // a still page could pass for a tiny scroll.
        let still = matcher.score(shift: 0, top: top, moving: moving, threshold: 0) ?? 0
        let found = moving >= 8 ? bestShift(matcher, top: top, moving: moving, still: still) : nil
        guard let shift = found?.shift, shift > 0 else {
            // A scroll changes the whole height of the moving columns; a video or an animation changes a patch.
            let changedRows = all.changedRowShare()
            diagnosis = "no clear shift (best \(found.map { String(format: "%.2f", $0.score) } ?? "-"), still \(String(format: "%.2f", still))); "
                + "\(Int(changedRows * 100))% of rows changed; \(rivalNote)"
            return changedRows < 0.6 ? .unchanged : .noMatch
        }

        if ignoredRightColumns > 0, !sawScrollBar {
            sawScrollBar = matcher.edgeChanged(shift: shift, top: top, moving: moving)
        }
        if self.bands == nil {
            // The first scroll tells us which rows are fixed; the first frame's footer moves to the end.
            self.bands = bands
            rows.removeLast(bottom * bytesPerRow)
        }
        // Columns that didn't move along with the scroll (a sidebar that sticks, or one that shifted on its
        // own) are left as they were and filled below, rather than copied in at the wrong place.
        let agreement = all.agreement(shift: shift, top: top, moving: moving)
        var offbeat = (0 ..< Frame.buckets).map { columns.still[$0] || (agreement[$0].map { $0 < 0.5 } ?? false) }
        // Plain strips beside them (card edges, margins) can't be judged on their own; they belong to the
        // same column, up to the first strip that clearly moves with the page.
        for k in 0 ..< Frame.buckets where offbeat[k] {
            var left = k - 1
            while left >= 0, !offbeat[left], agreement[left] == nil { offbeat[left] = true; left -= 1 }
        }
        for k in (0 ..< Frame.buckets).reversed() where offbeat[k] {
            var right = k + 1
            while right < Frame.buckets, !offbeat[right], agreement[right] == nil { offbeat[right] = true; right += 1 }
        }
        let stillSpans = stillPixelSpans(offbeat, in: frame)
        let previousCount = rows.count / bytesPerRow
        var added = shift
        if rows.count / bytesPerRow + added + bottom > maxHeight {
            added = max(maxHeight - bottom - rows.count / bytesPerRow, 0)
            isFull = true
        }
        let start = (frameHeight - bottom - shift) * bytesPerRow
        rows.append(contentsOf: frame.pixels[start ..< start + added * bytesPerRow])
        frameTop += shift
        // Redraw the rows this frame shows below its top quarter. A row's final pixels then come from when it
        // had moved up away from the bottom edge, so things floating there (a chat bubble, a cookie banner, a
        // video) don't leave streaks, while see-through headers at the top are still avoided.
        let redrawFrom = top + moving / 4
        let redrawTo = min(frameHeight - bottom, rows.count / bytesPerRow - frameTop)
        if redrawTo > redrawFrom {
            copyRows(from: frame, rows: redrawFrom ..< redrawTo, skipping: stillSpans)
        }
        // A column that stays put while the page scrolls (a sidebar that sticks partway down) ends where it
        // stopped; below that it's filled with the page's background, instead of repeating its bottom edge.
        fill(stillSpans, rows: previousCount ..< rows.count / bytesPerRow)
        footer = Array(frame.pixels[(frameHeight - bottom) * bytesPerRow ..< frameHeight * bytesPerRow])
        last = frame
        lastShift = shift
        hasScrolled = true
        return isFull && added == 0 ? .full : .added(added)
    }

    private var rivalNote = ""

    /// Why the last frame didn't match, for the log.
    public private(set) var diagnosis = ""

    /// The stitched image.
    public func image() -> CGImage? {
        let data = rows + footer
        let height = data.count / bytesPerRow
        guard height > 0, let provider = CGDataProvider(data: Data(data) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                                  space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        guard sawScrollBar else { return image }
        return image.cropping(to: CGRect(x: 0, y: 0, width: width - ignoredRightColumns, height: height)) ?? image
    }

    // MARK: Still columns

    /// Fill colours already chosen, by the first strip of their run, so a column's fill doesn't change.
    private var fillColors: [Int: (UInt8, UInt8, UInt8, UInt8)] = [:]

    /// Pixel spans of runs of still column strips, each with the colour to fill below them: the most common
    /// colour just outside the run, which is the page background around a column.
    private func stillPixelSpans(_ still: [Bool], in frame: Frame) -> [(x: Range<Int>, color: (UInt8, UInt8, UInt8, UInt8))] {
        let matchedWidth = width - ignoredRightColumns
        func x(_ bucket: Int) -> Int { bucket * matchedWidth / Frame.buckets }
        var spans: [(x: Range<Int>, color: (UInt8, UInt8, UInt8, UInt8))] = []
        var k = 0
        while k < Frame.buckets {
            guard still[k] else { k += 1; continue }
            let start = k
            while k < Frame.buckets, still[k] { k += 1 }
            let range = x(start) ..< x(k)
            // The same column can start a strip earlier or later from frame to frame; keep its colour.
            let key = fillColors.keys.first { abs($0 - start) <= 3 } ?? start
            if fillColors[key] == nil {
                var counts: [UInt32: Int] = [:]
                // Just outside the run: the gap beside a column, or the page margin.
                let outside = [range.lowerBound - 2, range.lowerBound - 10, range.upperBound + 1, range.upperBound + 9]
                    .filter { (0 ..< width).contains($0) }
                for edge in outside.isEmpty ? [range.lowerBound] : outside {
                    for y in stride(from: 0, to: frameHeight, by: 2) {
                        let i = y * bytesPerRow + edge * 4
                        let colour = UInt32(frame.pixels[i]) << 24 | UInt32(frame.pixels[i + 1]) << 16
                            | UInt32(frame.pixels[i + 2]) << 8 | UInt32(frame.pixels[i + 3])
                        counts[colour, default: 0] += 1
                    }
                }
                let common = counts.max { $0.value < $1.value }?.key ?? 0
                fillColors[key] = (UInt8(common >> 24), UInt8(common >> 16 & 0xFF), UInt8(common >> 8 & 0xFF), UInt8(common & 0xFF))
            }
            spans.append((range, fillColors[key]!))
        }
        return spans
    }

    /// Copies frame rows into the result at their place, leaving the still spans alone.
    private func copyRows(from frame: Frame, rows range: Range<Int>, skipping spans: [(x: Range<Int>, color: (UInt8, UInt8, UInt8, UInt8))]) {
        guard !spans.isEmpty else {
            rows.replaceSubrange((frameTop + range.lowerBound) * bytesPerRow ..< (frameTop + range.upperBound) * bytesPerRow,
                                 with: frame.pixels[range.lowerBound * bytesPerRow ..< range.upperBound * bytesPerRow])
            return
        }
        var segments: [Range<Int>] = []
        var x = 0
        for span in spans.sorted(by: { $0.x.lowerBound < $1.x.lowerBound }) {
            if span.x.lowerBound > x { segments.append(x ..< span.x.lowerBound) }
            x = max(x, span.x.upperBound)
        }
        if x < width { segments.append(x ..< width) }
        let bytesPerRow = bytesPerRow, frameTop = frameTop
        rows.withUnsafeMutableBytes { target in
            frame.pixels.withUnsafeBytes { source in
                for y in range {
                    for segment in segments {
                        let from = y * bytesPerRow + segment.lowerBound * 4
                        let to = (frameTop + y) * bytesPerRow + segment.lowerBound * 4
                        (target.baseAddress! + to).copyMemory(from: source.baseAddress! + from, byteCount: segment.count * 4)
                    }
                }
            }
        }
    }

    private func fill(_ spans: [(x: Range<Int>, color: (UInt8, UInt8, UInt8, UInt8))], rows range: Range<Int>) {
        guard !spans.isEmpty, !range.isEmpty else { return }
        let bytesPerRow = bytesPerRow
        rows.withUnsafeMutableBufferPointer { p in
            for y in range {
                for span in spans {
                    for x in span.x {
                        let i = y * bytesPerRow + x * 4
                        p[i] = span.color.0; p[i + 1] = span.color.1; p[i + 2] = span.color.2; p[i + 3] = span.color.3
                    }
                }
            }
        }
    }

    // MARK: Matching

    /// How close two rows must be to count as the same: the average brightness difference, out of 255.
    /// Loose enough for faint noise and see-through backgrounds, tight enough to tell lines of text apart.
    static let rowTolerance: Float = 4
    /// The share of detailed cells that must line up for a shift to be accepted…
    static let requiredMatch = 0.45
    /// …and by how much it must beat staying put and every other shift.
    static let margin = 0.12
    /// Shifts scoring below this on the quick first pass aren't considered.
    static let roughFloor = 0.3

    /// Sorts the 64 column strips by what they did between two frames: changed (`moving`), stayed the same
    /// while showing something (`still`, like a sidebar), or show nothing at all (plain, in neither).
    static func columns(_ a: Frame, _ b: Frame) -> (moving: [Int], still: [Bool], stillShare: Double) {
        var moving: [Int] = []
        var still: [Bool] = Array(repeating: false, count: Frame.buckets)
        let h = a.height
        for k in 0 ..< Frame.buckets {
            var detailed = 0, same = 0
            for y in 1 ..< h where abs(a.value(y, k) - a.value(y - 1, k)) > 3 {
                detailed += 1
                if abs(a.value(y, k) - b.value(y, k)) < rowTolerance { same += 1 }
            }
            guard detailed >= max(3, h / 200) else { continue }   // plain: no use for matching
            if Double(same) >= Double(detailed) * 0.97 { still[k] = true } else { moving.append(k) }
        }
        let stillCount = still.filter { $0 }.count
        let stillShare = Double(stillCount) / Double(max(stillCount + moving.count, 1))
        return (moving, still, stillShare)
    }

    /// How many rows the content moved up between two frames, or nil if no shift stands out.
    ///
    /// Something playing in the page (a video) spoils its cells at every shift, so instead of a fixed pass
    /// mark the right shift has to stand out: clearly better than staying put and than any other shift.
    /// Every shift is first scored on a quarter of the rows; the most promising are then scored in full.
    private func bestShift(_ matcher: Matcher, top: Int, moving: Int, still: Double) -> (shift: Int, score: Double)? {
        let minimumOverlap = max(moving / 6, 6)
        guard moving - minimumOverlap >= 1 else { return nil }
        var rough: [(shift: Int, score: Double)] = []
        for shift in 1 ... moving - minimumOverlap {
            if let score = matcher.score(shift: shift, top: top, moving: moving, threshold: Self.roughFloor, rowStep: 4) {
                rough.append((shift, score))
            }
        }
        rough.sort { $0.score > $1.score }
        var refined: [(shift: Int, score: Double)] = []
        for candidate in rough.prefix(8) {
            if let score = matcher.score(shift: candidate.shift, top: top, moving: moving, threshold: 0) {
                refined.append((candidate.shift, score))
            }
        }
        guard let best = refined.max(by: { $0.score < $1.score }) else { return nil }
        // The runner-up: the best shift that isn't just a row or two away from the winner. A shift that leaves
        // much less overlap is judged on fewer rows and scores high by chance more easily, so it doesn't count.
        let overlap = moving - best.shift
        let rival = (refined + rough)
            .filter { abs($0.shift - best.shift) > 4 && Double(moving - $0.shift) >= Double(overlap) * 0.6 }
            .max { $0.score < $1.score }
        let runnerUp = rival?.score ?? 0
        rivalNote = rival.map { "rival \($0.shift) at \(String(format: "%.2f", $0.score)), best \(best.shift)" } ?? ""
        guard best.score >= Self.requiredMatch, best.score >= still + Self.margin, best.score >= runnerUp + Self.margin
        else { return (0, best.score) }
        return best
    }

    /// Compares two frames using some of their column strips.
    struct Matcher {
        let a: Frame
        let b: Frame
        let buckets: [Int]
        /// Cells (a row of one column strip) of `a` that show an edge, which is what matching looks at:
        /// plain areas match anywhere. Running count per row, and the cells' strips per row.
        private let detailPrefix: [Int]
        private let detailCells: [[Int]]

        /// How close one cell must be to count as the same, out of 255. Screen captures carry a little noise.
        static let cellTolerance: Float = 6

        init(_ a: Frame, _ b: Frame, buckets: [Int]) {
            self.a = a
            self.b = b
            self.buckets = buckets
            var prefix = [Int](repeating: 0, count: a.height + 1)
            var cells = [[Int]](repeating: [], count: a.height)
            for y in 0 ..< a.height {
                for k in buckets {
                    let v = a.value(y, k)
                    let up = y > 0 ? abs(v - a.value(y - 1, k)) : 0
                    let down = y + 1 < a.height ? abs(v - a.value(y + 1, k)) : 0
                    if max(up, down) > 3 { cells[y].append(k) }
                }
                prefix[y + 1] = prefix[y] + cells[y].count
            }
            detailPrefix = prefix
            detailCells = cells
        }

        /// Average brightness difference between row `rowA` of `a` and row `rowB` of `b`.
        func distance(_ rowA: Int, _ rowB: Int) -> Float {
            var total: Float = 0
            for k in buckets { total += abs(a.value(rowA, k) - b.value(rowB, k)) }
            return total / Float(max(buckets.count, 1))
        }

        /// The share of detailed cells that line up when `b` is `a` moved up by `shift` rows, or nil when it's
        /// below `threshold` (it stops counting as soon as it can't reach it). Counting cells rather than whole
        /// rows means something changing in one spot (a video, a flashing badge) spoils only its own cells.
        func score(shift: Int, top: Int, moving: Int, threshold: Double, rowStep: Int = 1) -> Double? {
            let overlap = moving - shift
            guard overlap > 0 else { return nil }
            var informative = detailPrefix[top + shift + overlap] - detailPrefix[top + shift]
            guard informative >= max(8, overlap / 10) else { return nil }
            informative = max(informative / rowStep, 1)
            let allowedMisses = Int(Double(informative) * (1 - threshold))
            var misses = 0
            for i in stride(from: 0, to: overlap, by: rowStep) {
                let rowA = top + shift + i, rowB = top + i
                for k in detailCells[rowA] where abs(a.value(rowA, k) - b.value(rowB, k)) >= Self.cellTolerance {
                    misses += 1
                    if misses > allowedMisses { return nil }
                }
            }
            return max(1 - Double(misses) / Double(informative), 0)
        }

        /// For each column strip, the share of its detailed cells that line up at `shift`, or nil when it has
        /// too few to tell.
        func agreement(shift: Int, top: Int, moving: Int) -> [Double?] {
            var detailed = [Int](repeating: 0, count: Frame.buckets), matched = [Int](repeating: 0, count: Frame.buckets)
            for i in 0 ..< moving - shift {
                let rowA = top + shift + i, rowB = top + i
                for k in detailCells[rowA] {
                    detailed[k] += 1
                    if abs(a.value(rowA, k) - b.value(rowB, k)) < Self.cellTolerance { matched[k] += 1 }
                }
            }
            return (0 ..< Frame.buckets).map { detailed[$0] >= 10 ? Double(matched[$0]) / Double(detailed[$0]) : nil }
        }

        /// The share of detailed rows with any cell that changed in place.
        func changedRowShare() -> Double {
            var detailed = 0, changed = 0
            for y in 0 ..< a.height where !detailCells[y].isEmpty {
                detailed += 1
                if detailCells[y].contains(where: { abs(a.value(y, $0) - b.value(y, $0)) >= Self.cellTolerance }) { changed += 1 }
            }
            return detailed == 0 ? 0 : Double(changed) / Double(detailed)
        }

        /// Rows that look the same, in the same place, at the top and bottom of both frames (a sticky header
        /// or footer). A blank margin that happens to match is harmless: rows in a band are still added in
        /// order, only matching skips them. At least a third of the area is kept for matching.
        func fixedBands() -> (top: Int, bottom: Int) {
            let h = a.height
            var top = 0
            while top < h, distance(top, top) < rowTolerance { top += 1 }
            var bottom = 0
            while bottom < h - top, distance(h - 1 - bottom, h - 1 - bottom) < rowTolerance { bottom += 1 }
            let spare = top + bottom - h * 2 / 3
            if spare > 0 {
                // Give rows back to the middle, from the bigger band first.
                let fromTop = min(top, spare * top / max(top + bottom, 1))
                top -= fromTop
                bottom -= spare - fromTop
            }
            return (top, max(bottom, 0))
        }

        /// Whether the right edge differs, in a few rows where the content beside it lines up: a scroll bar.
        func edgeChanged(shift: Int, top: Int, moving: Int) -> Bool {
            var changed = 0
            for i in 0 ..< moving - shift {
                let rowA = top + shift + i, rowB = top + i
                if a.edgeDistance(row: rowA, to: b, row: rowB) >= rowTolerance * 3, distance(rowA, rowB) < rowTolerance {
                    changed += 1
                    if changed > 3 { return true }
                }
            }
            return false
        }
    }

    // MARK: Frames

    struct Frame {
        /// Brightness is averaged over this many columns per row for matching.
        static let buckets = 64

        let pixels: [UInt8]
        let height: Int
        /// `buckets` brightness values per row.
        private let profile: [Float]
        /// Average brightness per row of the right edge left out of matching.
        private let edge: [Float]

        init?(_ image: CGImage, space: CGColorSpace, ignoredRightColumns: Int) {
            let width = image.width, height = image.height, bytesPerRow = width * 4
            var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
            let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            let matchedWidth = max(width - ignoredRightColumns, 1)
            let buckets = min(Self.buckets, matchedWidth)
            var profile = [Float](repeating: 0, count: height * Self.buckets)
            var edge = [Float](repeating: 0, count: height)
            pixels.withUnsafeBufferPointer { p in
                for y in 0 ..< height {
                    let row = y * bytesPerRow
                    if ignoredRightColumns > 0 {
                        var sum = 0
                        for x in matchedWidth ..< width {
                            let i = row + x * 4
                            sum += Int(p[i]) * 3 + Int(p[i + 1]) * 6 + Int(p[i + 2])
                        }
                        edge[y] = Float(sum) / Float(ignoredRightColumns * 10)
                    }
                    for bucket in 0 ..< buckets {
                        let x0 = bucket * matchedWidth / buckets, x1 = max((bucket + 1) * matchedWidth / buckets, x0 + 1)
                        var sum = 0
                        for x in x0 ..< x1 {
                            let i = row + x * 4
                            sum += Int(p[i]) * 3 + Int(p[i + 1]) * 6 + Int(p[i + 2])
                        }
                        let value = Float(sum) / Float((x1 - x0) * 10)
                        profile[y * Self.buckets + bucket] = value
                    }
                }
            }
            self.pixels = pixels
            self.height = height
            self.profile = profile
            self.edge = edge
        }

        /// The brightness of column strip `bucket` in `row`.
        @inline(__always) func value(_ row: Int, _ bucket: Int) -> Float { profile[row * Self.buckets + bucket] }

        func edgeDistance(row: Int, to other: Frame, row otherRow: Int) -> Float { abs(edge[row] - other.edge[otherRow]) }

    }
}
