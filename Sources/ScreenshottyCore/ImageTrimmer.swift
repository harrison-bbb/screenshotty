import CoreGraphics

/// Finds and removes uniform margins (solid colour or transparent) around a screenshot,
/// so the content itself can be centred on the canvas.
public enum ImageTrimmer {
    /// Returns the crop rect (in pixels, origin top-left) of the content inside uniform margins.
    ///
    /// Trimming only happens when all four corners share a colour (or are all transparent).
    /// This avoids eating into solid-colour UI such as a coloured nav bar at the top of a page.
    /// - Parameter tolerance: Max per-channel difference (0...255) still treated as "the same colour".
    ///   Kept tight because screenshots are lossless and light UI greys (e.g. #F7F7FA) sit very close to white.
    public static func contentRect(of image: CGImage, tolerance: Int = 2) -> CGRect {
        let width = image.width
        let height = image.height
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        guard width > 2, height > 2, let pixels = RGBABuffer(image: image) else { return full }

        let corners = [pixels[0, 0], pixels[width - 1, 0], pixels[0, height - 1], pixels[width - 1, height - 1]]
        let reference = corners[0]
        let transparent = corners.allSatisfy { $0.a < 8 }
        guard transparent || corners.allSatisfy({ $0.isClose(to: reference, tolerance: tolerance) }) else {
            return full
        }

        func matches(_ x: Int, _ y: Int) -> Bool {
            let p = pixels[x, y]
            return transparent ? p.a < 8 : p.isClose(to: reference, tolerance: tolerance)
        }
        func rowIsMargin(_ y: Int) -> Bool { (0..<width).allSatisfy { matches($0, y) } }
        func columnIsMargin(_ x: Int, _ yRange: Range<Int>) -> Bool { yRange.allSatisfy { matches(x, $0) } }

        var top = 0
        while top < height, rowIsMargin(top) { top += 1 }
        guard top < height else { return full } // the whole image is one colour
        var bottom = height - 1
        while bottom > top, rowIsMargin(bottom) { bottom -= 1 }

        let rows = top..<(bottom + 1)
        var left = 0
        while left < width, columnIsMargin(left, rows) { left += 1 }
        var right = width - 1
        while right > left, columnIsMargin(right, rows) { right -= 1 }

        return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
    }

    /// Returns the image with uniform margins removed (or the original if there are none).
    public static func trim(_ image: CGImage, tolerance: Int = 2) -> CGImage {
        let rect = contentRect(of: image, tolerance: tolerance)
        if rect.width == CGFloat(image.width), rect.height == CGFloat(image.height) { return image }
        return image.cropping(to: rect) ?? image
    }
}

struct RGBAPixel {
    var r: UInt8, g: UInt8, b: UInt8, a: UInt8

    func isClose(to other: RGBAPixel, tolerance: Int) -> Bool {
        abs(Int(r) - Int(other.r)) <= tolerance &&
            abs(Int(g) - Int(other.g)) <= tolerance &&
            abs(Int(b) - Int(other.b)) <= tolerance &&
            abs(Int(a) - Int(other.a)) <= tolerance
    }
}

/// The image redrawn into a known 8-bit RGBA layout with a top-left origin.
struct RGBABuffer {
    let width: Int
    let height: Int
    private let data: [UInt8]

    init?(image: CGImage) {
        let width = image.width
        let height = image.height
        self.width = width
        self.height = height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        data = bytes
    }

    /// (x, y) with y measured from the top.
    subscript(x: Int, y: Int) -> RGBAPixel {
        // Bitmap memory starts at the top row, so no flip is needed.
        let i = (y * width + x) * 4
        return RGBAPixel(r: data[i], g: data[i + 1], b: data[i + 2], a: data[i + 3])
    }
}
