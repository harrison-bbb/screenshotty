import CoreGraphics

/// Draws a macOS-style window title bar with traffic lights.
enum WindowChrome {
    static let lightRadius: CGFloat = 6
    static let lightSpacing: CGFloat = 20
    static let firstLightX: CGFloat = 20

    /// Centres of the three traffic lights. They sit where macOS puts them, but move right when needed
    /// so the first light always fits inside the rounded top-left corner.
    static func trafficLightCenters(in rect: CGRect, unit: CGFloat, cornerRadius: CGFloat) -> [CGPoint] {
        let lightRadius = Self.lightRadius * unit
        let gap = 2 * unit
        let y = rect.midY
        var firstX = rect.minX + firstLightX * unit
        let cornerCentre = CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius)
        if y < cornerCentre.y {
            // The light must lie within (cornerRadius - lightRadius - gap) of the corner arc's centre.
            let reach = cornerRadius - lightRadius - gap
            let dy = cornerCentre.y - y
            if reach > dy {
                let dx = (reach * reach - dy * dy).squareRoot()
                firstX = max(firstX, cornerCentre.x - dx)
            } else {
                // Title bar too short for this radius: move clear of the curve entirely.
                firstX = max(firstX, cornerCentre.x + lightRadius)
            }
        }
        return (0..<3).map { CGPoint(x: firstX + CGFloat($0) * lightSpacing * unit, y: y) }
    }

    static func draw(_ style: WindowChromeStyle, in ctx: CGContext, rect: CGRect, unit: CGFloat, cornerRadius: CGFloat) {
        guard style != .none, rect.height > 0 else { return }
        let fill = style == .light ? RGBAColor(hex: "#EDECEC")! : RGBAColor(hex: "#2C2C2E")!
        let separator = style == .light ? RGBAColor(hex: "#D4D3D3")! : RGBAColor(hex: "#1A1A1C")!

        ctx.saveGState()
        ctx.setFillColor(fill.cgColor)
        ctx.fill(rect)
        let lineHeight = max(unit, 1)
        ctx.setFillColor(separator.cgColor)
        ctx.fill(CGRect(x: rect.minX, y: rect.maxY - lineHeight, width: rect.width, height: lineHeight))

        let radius = lightRadius * unit
        let centers = trafficLightCenters(in: rect, unit: unit, cornerRadius: cornerRadius)
        let colors = ["#FF5F57", "#FEBC2E", "#28C840"].compactMap { RGBAColor(hex: $0) }
        for (center, color) in zip(centers, colors) {
            let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: circle)
            ctx.setStrokeColor(RGBAColor.black.withAlpha(0.12).cgColor)
            ctx.setLineWidth(max(unit * 0.5, 0.5))
            ctx.strokeEllipse(in: circle.insetBy(dx: unit * 0.25, dy: unit * 0.25))
        }
        ctx.restoreGState()
    }
}
