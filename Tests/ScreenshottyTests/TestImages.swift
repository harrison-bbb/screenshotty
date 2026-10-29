import CoreGraphics
import Foundation
@testable import ScreenshottyCore

/// Builds test bitmaps. Rects are top-left origin.
enum TestImages {
    static func make(width: Int, height: Int, background: RGBAColor?, fills: [(CGRect, RGBAColor)] = []) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        if let background {
            ctx.setFillColor(background.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        for (rect, color) in fills {
            ctx.setFillColor(color.cgColor)
            ctx.fill(rect)
        }
        return ctx.makeImage()!
    }
}

/// Foundation helpers live here so test files only import Testing (keeps CLT-only builds working).
enum JSON {
    static func roundTrip(_ settings: CompositionSettings) throws -> CompositionSettings {
        try JSONDecoder().decode(CompositionSettings.self, from: JSONEncoder().encode(settings))
    }
    static func string(_ settings: CompositionSettings) throws -> String {
        String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
    }
    static func decode(_ json: String) throws -> CompositionSettings {
        try JSONDecoder().decode(CompositionSettings.self, from: Data(json.utf8))
    }
}

enum PNG {
    static func roundTripWidth(_ image: CGImage) -> Int? {
        guard let data = PNGEncoder.data(for: image) else { return nil }
        return ImageLoader.load(data)?.width
    }
}

extension JSON {
    static func roundTrip(_ annotation: Annotation) throws -> Annotation {
        try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(annotation))
    }
}

import CoreText

extension TestImages {
    /// Black text lines on white, for text recognition tests.
    static func text(_ lines: [String], width: Int = 1400, lineHeight: CGFloat = 70, size: CGFloat = 40) -> CGImage {
        let height = Int(lineHeight) * (lines.count + 1)
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Menlo" as CFString, size, nil)
        for (i, line) in lines.enumerated() {
            let attributed = NSAttributedString(string: line, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
            ])
            ctx.textPosition = CGPoint(x: 40, y: CGFloat(height) - lineHeight * CGFloat(i + 1))
            CTLineDraw(CTLineCreateWithAttributedString(attributed), ctx)
        }
        return ctx.makeImage()!
    }
}

enum Text {
    static func kinds(_ text: String) -> [SensitiveFinding.Kind] {
        SensitiveScanner.matches(in: text).map(\.kind)
    }
}
