import CoreGraphics
import CoreText
import Foundation

/// One line of system-font text, drawn into the flipped (top-left origin) layout context.
struct TextLine {
    private let line: CTLine
    let width: CGFloat
    private let ascent: CGFloat
    private let descent: CGFloat
    private let attributed: NSAttributedString

    init(_ text: String, size: CGFloat, color: RGBAColor, weight: CGFloat = 0) {
        let base = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let traits = [kCTFontWeightTrait: weight] as CFDictionary
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(base),
                                                                  [kCTFontTraitsAttribute: traits] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ])
        line = CTLineCreateWithAttributedString(attributed)
        var a: CGFloat = 0
        var d: CGFloat = 0
        width = CGFloat(CTLineGetTypographicBounds(line, &a, &d, nil))
        ascent = a
        descent = d
    }

    /// Draws the line vertically centred on `centerY`, truncated with an ellipsis past `maxWidth`.
    func draw(in ctx: CGContext, x: CGFloat, centerY: CGFloat, maxWidth: CGFloat) {
        var drawn = line
        if width > maxWidth {
            let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes:
                attributed.attributes(at: 0, effectiveRange: nil)))
            drawn = CTLineCreateTruncatedLine(line, Double(maxWidth), .end, ellipsis) ?? line
        }
        ctx.saveGState()
        // The layout space is flipped; flip the text matrix so glyphs stay upright.
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: x, y: centerY + (ascent - descent) / 2)
        CTLineDraw(drawn, ctx)
        ctx.restoreGState()
    }
}
