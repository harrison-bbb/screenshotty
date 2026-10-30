import CoreGraphics

/// Finds the visual blocks of a screen (sidebars, headers, card rows, cards, sections) the way a person
/// sees them: by the empty gutters between them. Recursive XY-cut: a region's background is the colour
/// of most of its empty lines; a gutter is a band of that background at least `minGap` thick, right
/// across the region. The region splits at its gutters (widest direction first), each piece is trimmed of
/// background (so a card keeps its own fill), and each piece is split again with its own background.
/// Works in any app, whatever it tells Accessibility.
public enum LayoutSegmenter {
    /// - Parameters:
    ///   - image: The area to analyse, ideally downscaled (≈1000 px wide) for speed.
    ///   - minGap: Narrowest gutter between two blocks, in the image's pixels. Gaps between the lines of a
    ///     paragraph should be narrower.
    ///   - minSize: Smallest block kept, in pixels, in both directions.
    /// - Returns: Blocks in the image's pixels (top-left origin), each parent before its children.
    public static func sections(in image: CGImage, minGap: Int, minSize: Int, maxDepth: Int = 9) -> [CGRect] {
        guard let pixels = RGBABuffer(image: image), pixels.width > minSize * 2, pixels.height > minSize * 2 else { return [] }
        var result: [CGRect] = []
        let all = Box(x0: 0, y0: 0, x1: pixels.width, y1: pixels.height)
        split(all, parentBackground: nil, depth: 0, rowsFirst: true, pixels: pixels, minGap: max(minGap, 1),
              minSize: minSize, maxDepth: maxDepth, into: &result)
        return result
    }

    struct Box: Equatable {
        var x0: Int, y0: Int, x1: Int, y1: Int
        var width: Int { x1 - x0 }
        var height: Int { y1 - y0 }
        var rect: CGRect { CGRect(x: x0, y: y0, width: width, height: height) }
    }

    /// The colour of a row (or column) across the box if it is one flat colour, allowing a stray pixel
    /// or two of anti-aliasing; nil if it has content.
    static func flatColor(_ index: Int, rows: Bool, in box: Box, pixels: RGBABuffer) -> RGBAPixel? {
        let length = rows ? box.width : box.height
        let step = max(1, length / 300)
        let first = rows ? pixels[box.x0, index] : pixels[index, box.y0]
        let allowed = max(1, length / step / 150)
        var misses = 0
        var i = step
        while i < length {
            let p = rows ? pixels[box.x0 + i, index] : pixels[index, box.y0 + i]
            if !p.isClose(to: first, tolerance: 10) {
                misses += 1
                if misses > allowed { return nil }
            }
            i += step
        }
        return first
    }

    /// What a region's content sits on: the colour of most of its flat (empty) rows and columns. A card's
    /// fill or a sidebar's colour covers less, so they stay part of their blocks.
    static func background(of box: Box, pixels: RGBABuffer) -> RGBAPixel? {
        var counts: [(color: RGBAPixel, count: Int)] = []
        func add(_ color: RGBAPixel) {
            if let i = counts.firstIndex(where: { $0.color.isClose(to: color, tolerance: 10) }) { counts[i].count += 1 }
            else { counts.append((color, 1)) }
        }
        for y in stride(from: box.y0, to: box.y1, by: max(1, box.height / 200)) {
            if let c = flatColor(y, rows: true, in: box, pixels: pixels) { add(c) }
        }
        for x in stride(from: box.x0, to: box.x1, by: max(1, box.width / 200)) {
            if let c = flatColor(x, rows: false, in: box, pixels: pixels) { add(c) }
        }
        return counts.max { $0.count < $1.count }?.color
    }

    /// Pixels around the edge of a box (`inset` px in), sampled.
    static func ring(of box: Box, inset: Int, pixels: RGBABuffer) -> [RGBAPixel] {
        let b = Box(x0: box.x0 + inset, y0: box.y0 + inset, x1: box.x1 - inset, y1: box.y1 - inset)
        guard b.width > 1, b.height > 1 else { return [] }
        var samples: [RGBAPixel] = []
        for x in stride(from: b.x0, to: b.x1, by: max(1, b.width / 150)) {
            samples.append(pixels[x, b.y0])
            samples.append(pixels[x, b.y1 - 1])
        }
        for y in stride(from: b.y0, to: b.y1, by: max(1, b.height / 150)) {
            samples.append(pixels[b.x0, y])
            samples.append(pixels[b.x1 - 1, y])
        }
        return samples
    }

    /// The middle 70% of each edge (corners left out, so a rounded card's corners don't look like gaps).
    static func edgeMiddles(of box: Box, pixels: RGBABuffer) -> [RGBAPixel] {
        var samples: [RGBAPixel] = []
        let mx = box.width * 15 / 100
        let my = box.height * 15 / 100
        for x in stride(from: box.x0 + mx, to: box.x1 - mx, by: max(1, box.width / 150)) {
            samples.append(pixels[x, box.y0])
            samples.append(pixels[x, box.y1 - 1])
        }
        for y in stride(from: box.y0 + my, to: box.y1 - my, by: max(1, box.height / 150)) {
            samples.append(pixels[box.x0, y])
            samples.append(pixels[box.x1 - 1, y])
        }
        return samples
    }

    /// A block keeps its parent's background while that background shows around its edge (the gaps in a
    /// row of cards). A block fully enclosed by another fill (a card, a sidebar) uses that fill, read a few
    /// pixels in so a 1 px border doesn't count.
    static func background(of box: Box, parent: RGBAPixel?, pixels: RGBABuffer) -> RGBAPixel? {
        if let parent {
            let edge = edgeMiddles(of: box, pixels: pixels)
            let share = Double(edge.filter { $0.isClose(to: parent, tolerance: 10) }.count) / Double(max(edge.count, 1))
            if share >= 0.02 { return parent }
            return ImageTrimmer.dominantColor(ring(of: box, inset: min(3, box.width / 4, box.height / 4), pixels: pixels)) ?? parent
        }
        return background(of: box, pixels: pixels)
    }

    private static func split(_ box: Box, parentBackground: RGBAPixel?, depth: Int, rowsFirst: Bool, pixels: RGBABuffer,
                              minGap: Int, minSize: Int, maxDepth: Int, into result: inout [CGRect]) {
        guard depth < maxDepth, box.width >= minSize, box.height >= minSize,
              let background = background(of: box, parent: parentBackground, pixels: pixels) else { return }
        // Split along the widest gutter first: columns of text separate before their paragraphs do.
        let across = pieces(of: box, rows: true, background: background, pixels: pixels, minGap: minGap)
        let down = pieces(of: box, rows: false, background: background, pixels: pixels, minGap: minGap)
        let options = [(true, across), (false, down)]
            .filter { $0.1.widest > 0 }
            .sorted { $0.1.widest != $1.1.widest ? $0.1.widest > $1.1.widest : $0.0 == rowsFirst }
        guard let (rows, found) = options.first else { return }
        let kept = found.parts
            .compactMap { trimmed($0, background: background, pixels: pixels) }
            .filter { $0.width >= minSize && $0.height >= minSize }
        for part in kept {
            if part != box { result.append(part.rect) }
            split(part, parentBackground: background, depth: depth + 1, rowsFirst: !rows, pixels: pixels,
                  minGap: minGap, minSize: minSize, maxDepth: maxDepth, into: &result)
        }
    }

    /// True when a row (or column) of the box is all background.
    private static func isGutterLine(_ index: Int, rows: Bool, in box: Box, background: RGBAPixel, pixels: RGBABuffer) -> Bool {
        guard let c = flatColor(index, rows: rows, in: box, pixels: pixels) else { return false }
        return c.isClose(to: background, tolerance: 10)
    }

    /// Splits the box across rows (or columns) at its widest background bands: every band at least half as
    /// thick as the widest (and at least `minGap`). Narrower bands, like the space between lines of text,
    /// are left for the next level down. Returns the pieces and the widest band (0 if nothing split).
    private static func pieces(of box: Box, rows: Bool, background: RGBAPixel, pixels: RGBABuffer, minGap: Int)
        -> (parts: [Box], widest: Int) {
        let start = rows ? box.y0 : box.x0
        let end = rows ? box.y1 : box.x1
        // Runs of background lines that sit between content (not the margins at either end).
        var gutters: [(from: Int, to: Int)] = []
        var runStart: Int? = nil
        var seenContent = false
        for i in start..<end {
            if isGutterLine(i, rows: rows, in: box, background: background, pixels: pixels) {
                if runStart == nil { runStart = i }
            } else {
                if let r = runStart, seenContent { gutters.append((r, i)) }
                runStart = nil
                seenContent = true
            }
        }
        let widest = gutters.map { $0.to - $0.from }.max() ?? 0
        guard widest >= minGap else { return ([box], 0) }
        let threshold = max(minGap, widest / 2)
        func make(_ a: Int, _ b: Int) -> Box {
            rows ? Box(x0: box.x0, y0: a, x1: box.x1, y1: b) : Box(x0: a, y0: box.y0, x1: b, y1: box.y1)
        }
        var parts: [Box] = []
        var pieceStart = start
        for gutter in gutters where gutter.to - gutter.from >= threshold {
            parts.append(make(pieceStart, gutter.from))
            pieceStart = gutter.to
        }
        parts.append(make(pieceStart, end))
        return parts.count > 1 ? (parts, widest) : ([box], 0)
    }

    /// The box shrunk by edge lines of background. Lines in another flat colour (a card's fill or border)
    /// are kept, so blocks keep their own shape.
    private static func trimmed(_ box: Box, background: RGBAPixel, pixels: RGBABuffer) -> Box? {
        var b = box
        while b.y0 < b.y1 - 1, isGutterLine(b.y0, rows: true, in: b, background: background, pixels: pixels) { b.y0 += 1 }
        while b.y1 > b.y0 + 1, isGutterLine(b.y1 - 1, rows: true, in: b, background: background, pixels: pixels) { b.y1 -= 1 }
        while b.x0 < b.x1 - 1, isGutterLine(b.x0, rows: false, in: b, background: background, pixels: pixels) { b.x0 += 1 }
        while b.x1 > b.x0 + 1, isGutterLine(b.x1 - 1, rows: false, in: b, background: background, pixels: pixels) { b.x1 -= 1 }
        return b
    }
}
