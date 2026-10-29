import CoreGraphics

/// Groups recognised text lines into blocks (paragraphs, lists, headings), for the capture picker.
public enum TextBlocks {
    /// Joins lines that sit close below each other, have a similar height and overlap horizontally.
    /// Each block is padded a little so it doesn't touch the letters. Rects are top-left origin.
    public static func group(_ lines: [CGRect]) -> [CGRect] {
        var blocks: [(rect: CGRect, lineHeight: CGFloat)] = []
        for line in lines.sorted(by: { $0.minY < $1.minY }) {
            let height = line.height
            if let index = blocks.firstIndex(where: { block in
                let gap = line.minY - block.rect.maxY
                let similar = abs(block.lineHeight - height) < max(block.lineHeight, height) * 0.45
                return similar && gap > -height * 0.5 && gap < height * 1.1 &&
                    line.minX < block.rect.maxX + height && line.maxX > block.rect.minX - height
            }) {
                blocks[index].rect = blocks[index].rect.union(line)
            } else {
                blocks.append((line, height))
            }
        }
        return blocks.map { $0.rect.insetBy(dx: -$0.lineHeight * 0.5, dy: -$0.lineHeight * 0.4) }
    }
}
