import CoreGraphics

/// Makes small captures export at a useful size. A 700 px capture from a non-Retina screen looks tiny
/// and soft once a social network scales it; doubling it pixel-for-pixel keeps it sharp.
public enum ExportScale {
    /// Results whose longest side is under this get enlarged.
    public static let defaultMinimumLongSide: CGFloat = 1600
    public static let maxFactor = 4

    /// The smallest whole factor (1...4) that brings the longest side up to `minimumLongSide`.
    public static func factor(for canvas: CGSize, minimumLongSide: CGFloat) -> Int {
        let longSide = max(canvas.width, canvas.height)
        guard longSide > 0, longSide < minimumLongSide else { return 1 }
        return min(maxFactor, Int((minimumLongSide / longSide).rounded(.up)))
    }

    /// Enlarges by a whole factor with nearest-neighbour sampling: every pixel becomes a crisp block.
    public static func enlarge(_ image: CGImage, by factor: Int) -> CGImage? {
        guard factor > 1 else { return image }
        let width = image.width * factor
        let height = image.height * factor
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}
