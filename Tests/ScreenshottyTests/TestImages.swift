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
