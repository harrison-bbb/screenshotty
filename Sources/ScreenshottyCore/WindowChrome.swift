import CoreGraphics

/// Draws a macOS-style window title bar with traffic lights.
enum WindowChrome {
    static func draw(_ style: WindowChromeStyle, in ctx: CGContext, rect: CGRect, unit: CGFloat) {
        guard style != .none, rect.height > 0 else { return }
        let fill = style == .light ? RGBAColor(hex: "#EDECEC")! : RGBAColor(hex: "#2C2C2E")!
        let separator = style == .light ? RGBAColor(hex: "#D4D3D3")! : RGBAColor(hex: "#1A1A1C")!

        ctx.saveGState()
        ctx.setFillColor(fill.cgColor)
        ctx.fill(rect)
        let lineHeight = max(unit, 1)
        ctx.setFillColor(separator.cgColor)
        ctx.fill(CGRect(x: rect.minX, y: rect.maxY - lineHeight, width: rect.width, height: lineHeight))

        let radius = 6 * unit
        let spacing = 20 * unit
        let firstX = rect.minX + 20 * unit
        let y = rect.midY
        let colors = ["#FF5F57", "#FEBC2E", "#28C840"].compactMap { RGBAColor(hex: $0) }
        for (i, color) in colors.enumerated() {
            let center = CGPoint(x: firstX + CGFloat(i) * spacing, y: y)
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
