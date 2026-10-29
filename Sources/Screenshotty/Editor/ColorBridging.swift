import AppKit
import ScreenshottyCore
import SwiftUI

extension RGBAColor {
    var swiftUIColor: Color { Color(cgColor: cgColor) }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(red: Double(ns.redComponent), green: Double(ns.greenComponent),
                  blue: Double(ns.blueComponent), alpha: Double(ns.alphaComponent))
    }
}

/// Renders preset swatches once and reuses them.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private var cache: [String: CGImage] = [:]

    func image(for style: BackgroundStyle, key: String, size: CGSize = CGSize(width: 160, height: 110)) -> CGImage? {
        if let cached = cache[key] { return cached }
        let image = BackgroundRenderer.thumbnail(style, size: size)
        cache[key] = image
        return image
    }
}
