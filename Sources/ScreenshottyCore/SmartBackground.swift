import CoreGraphics
import Foundation

/// Backgrounds generated from the screenshot's own colours, so the result always matches the product.
public enum SmartBackground {
    public enum Variant: String, Codable, CaseIterable, Identifiable, Sendable {
        case vibrant, mesh, pastel, dark
        public var id: String { rawValue }
        public var title: String { rawValue.capitalized }
    }

    /// The colours a screenshot is "about".
    public struct Palette: Equatable, Sendable {
        /// Dominant accent hue, 0...1.
        public var primaryHue: Double
        /// A second hue that pairs with the first, 0...1.
        public var secondaryHue: Double
        /// False when the screenshot is basically greyscale; backgrounds are then kept muted.
        public var isColorful: Bool
    }

    // MARK: Palette extraction

    public static func palette(of image: CGImage) -> Palette {
        let maxSide = 96
        let scale = min(1, Double(maxSide) / Double(max(image.width, image.height)))
        let w = max(Int(Double(image.width) * scale), 1)
        let h = max(Int(Double(image.height) * scale), 1)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        let fallback = Palette(primaryHue: 0.64, secondaryHue: 0.75, isColorful: false)
        guard drawn else { return fallback }

        // Weight hues by how colourful each pixel is. Greys, near-whites and near-blacks
        // (most of any UI) carry almost no weight, so accent colours win.
        let bins = 36
        var weights = [Double](repeating: 0, count: bins)
        var colorfulPixels = 0
        var counted = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let a = Double(bytes[i + 3]) / 255
            guard a > 0.8 else { continue }
            counted += 1
            let (hue, sat, bri) = hsb(r: Double(bytes[i]) / 255 / a, g: Double(bytes[i + 1]) / 255 / a, b: Double(bytes[i + 2]) / 255 / a)
            guard sat > 0.25, bri > 0.25 else { continue }
            colorfulPixels += 1
            let bin = min(Int(hue * Double(bins)), bins - 1)
            weights[bin] += sat * sat * bri
        }
        guard counted > 0, colorfulPixels > max(counted / 400, 2),
              let top = weights.indices.max(by: { weights[$0] < weights[$1] }) else { return fallback }

        // Smooth with neighbours so a hue split across two bins is found as one.
        func smoothed(_ i: Int) -> Double {
            weights[(i - 1 + bins) % bins] * 0.5 + weights[i] + weights[(i + 1) % bins] * 0.5
        }
        let primaryBin = (0..<bins).max(by: { smoothed($0) < smoothed($1) }) ?? top
        let primary = (Double(primaryBin) + 0.5) / Double(bins)

        // Second hue: the strongest one at least 40 degrees away, if it is meaningful.
        let distant = (0..<bins).filter { hueDistance((Double($0) + 0.5) / Double(bins), primary) >= 40.0 / 360 }
        var secondary = wrap(primary + 35.0 / 360)
        if let best = distant.max(by: { smoothed($0) < smoothed($1) }), smoothed(best) >= smoothed(primaryBin) * 0.2 {
            secondary = (Double(best) + 0.5) / Double(bins)
        }
        // Gradients between far-apart hues (e.g. orange and indigo) turn muddy in the middle.
        // Keep the pair within 60 degrees, leaning towards the screenshot's second accent.
        let maxSpread = 60.0 / 360
        if hueDistance(primary, secondary) > maxSpread {
            let forward = wrap(secondary - primary) < 0.5
            secondary = wrap(primary + (forward ? maxSpread : -maxSpread))
        }
        return Palette(primaryHue: primary, secondaryHue: secondary, isColorful: true)
    }

    // MARK: Styles

    public static func style(for image: CGImage, variant: Variant) -> BackgroundStyle {
        style(for: palette(of: image), variant: variant)
    }

    public static func style(for palette: Palette, variant: Variant) -> BackgroundStyle {
        let h1 = palette.primaryHue
        let h2 = palette.secondaryHue
        // Muted versions for greyscale screenshots.
        let s: Double = palette.isColorful ? 1 : 0.35
        func c(_ hue: Double, _ sat: Double, _ bri: Double) -> RGBAColor {
            color(hue: wrap(hue), saturation: min(sat * s, 1), brightness: bri)
        }

        switch variant {
        case .vibrant:
            return .linearGradient(LinearGradientSpec(stops: [
                GradientStop(c(h1, 0.60, 0.97), 0),
                GradientStop(c(h2, 0.72, 0.82), 1),
            ], angle: 135))
        case .mesh:
            return .mesh(MeshSpec(base: c(h1, 0.55, 0.88), blobs: [
                MeshBlob(x: 0.12, y: 0.10, radius: 0.70, color: c(h1 + 0.05, 0.55, 1.0)),
                MeshBlob(x: 0.92, y: 0.18, radius: 0.60, color: c(h2, 0.60, 0.97)),
                MeshBlob(x: 0.28, y: 0.95, radius: 0.70, color: c(h1 - 0.07, 0.70, 0.78)),
                MeshBlob(x: 0.90, y: 0.90, radius: 0.60, color: c(h2 + 0.08, 0.55, 0.90)),
            ]))
        case .pastel:
            return .linearGradient(LinearGradientSpec(stops: [
                GradientStop(c(h1, 0.16, 1.0), 0),
                GradientStop(c(h2, 0.26, 0.97), 1),
            ], angle: 160))
        case .dark:
            return .mesh(MeshSpec(base: c(h1, 0.55, 0.12), blobs: [
                MeshBlob(x: 0.15, y: 0.10, radius: 0.65, color: c(h1, 0.75, 0.55)),
                MeshBlob(x: 0.90, y: 0.95, radius: 0.70, color: c(h2, 0.75, 0.42)),
                MeshBlob(x: 0.85, y: 0.15, radius: 0.40, color: c(h2 + 0.05, 0.6, 0.25)),
            ]))
        }
    }

    // MARK: Colour maths

    static func hsb(r: Double, g: Double, b: Double) -> (Double, Double, Double) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC
        var hue = 0.0
        if delta > 0 {
            if maxC == r { hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxC == g { hue = (b - r) / delta + 2 }
            else { hue = (r - g) / delta + 4 }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, maxC == 0 ? 0 : delta / maxC, maxC)
    }

    public static func color(hue: Double, saturation: Double, brightness: Double) -> RGBAColor {
        let h = wrap(hue) * 6
        let c = brightness * saturation
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        let (r, g, b): (Double, Double, Double)
        switch Int(h) {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return RGBAColor(red: r + m, green: g + m, blue: b + m)
    }

    static func wrap(_ hue: Double) -> Double {
        let v = hue.truncatingRemainder(dividingBy: 1)
        return v < 0 ? v + 1 : v
    }

    static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b)
        return min(d, 1 - d)
    }
}
