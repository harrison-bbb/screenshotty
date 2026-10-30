import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageLoader {
    /// Loads the first frame of an image file and decodes it right away.
    ///
    /// ImageIO normally decodes lazily, reading the file again when the image is first drawn. Captures
    /// are written to a temporary file that is deleted straight after loading, so a lazy image would
    /// later draw as nothing (only the background showed). Reading the bytes into memory and decoding
    /// immediately makes the image independent of the file.
    public static func load(_ url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return load(data)
    }

    public static func load(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        // Photos (phone JPEGs and HEICs) are often stored sideways with an EXIF orientation; turn them upright.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        if let orientation = properties?[kCGImagePropertyOrientation] as? UInt32, orientation != 1,
           let width = properties?[kCGImagePropertyPixelWidth] as? Int, let height = properties?[kCGImagePropertyPixelHeight] as? Int,
           let upright = CGImageSourceCreateThumbnailAtIndex(source, 0, [
               kCGImageSourceCreateThumbnailFromImageAlways: true,
               kCGImageSourceCreateThumbnailWithTransform: true,
               kCGImageSourceThumbnailMaxPixelSize: max(width, height),
               kCGImageSourceShouldCacheImmediately: true,
           ] as CFDictionary) {
            return decoded(upright) ?? upright
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        return decoded(image) ?? image
    }

    /// Redraws the image into an in-memory sRGB bitmap, so nothing about it is deferred any more.
    static func decoded(_ image: CGImage) -> CGImage? {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }
}

public enum PNGEncoder {
    public static func data(for image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    public static func write(_ image: CGImage, to url: URL) throws {
        guard let data = data(for: image) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
    }
}

extension CGColorSpace {
    /// The colour space to draw output in: the image's own RGB space (Mac captures are usually Display P3,
    /// and converting to sRGB would dull vivid colours), or sRGB for anything else.
    public static func working(for image: CGImage) -> CGColorSpace {
        if let space = image.colorSpace, space.model == .rgb, space.supportsOutput { return space }
        return CGColorSpace(name: CGColorSpace.sRGB)!
    }
}
