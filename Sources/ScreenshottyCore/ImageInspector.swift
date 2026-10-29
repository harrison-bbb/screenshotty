import CoreGraphics

public enum ImageInspector {
    /// True when every sampled pixel is fully transparent.
    ///
    /// macOS returns a transparent image (instead of an error) when screen capture is blocked,
    /// for example when the Screen Recording permission belongs to an older build of the app.
    public static func isFullyTransparent(_ image: CGImage, samplesPerSide: Int = 64) -> Bool {
        guard let pixels = RGBABuffer(image: image) else { return false }
        let stepX = max(pixels.width / samplesPerSide, 1)
        let stepY = max(pixels.height / samplesPerSide, 1)
        var y = 0
        while y < pixels.height {
            var x = 0
            while x < pixels.width {
                if pixels[x, y].a > 0 { return false }
                x += stepX
            }
            y += stepY
        }
        // Also check the exact centre, in case content is narrower than the sampling grid.
        return pixels[pixels.width / 2, pixels.height / 2].a == 0
    }
}
