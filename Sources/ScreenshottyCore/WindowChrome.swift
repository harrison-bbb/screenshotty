import CoreGraphics
import CoreText
import Foundation

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

    static func draw(_ style: WindowChromeStyle, in ctx: CGContext, rect: CGRect, unit: CGFloat, cornerRadius: CGFloat,
                     url: String = "") {
        guard style != .none, rect.height > 0 else { return }
        let dark = style.isDark
        let fill: RGBAColor
        let separator: RGBAColor
        switch style.kind {
        case .browser:
            fill = dark ? RGBAColor(hex: "#2B2B2E")! : RGBAColor(hex: "#F2F2F3")!
            separator = dark ? RGBAColor(hex: "#151517")! : RGBAColor(hex: "#D9D9DB")!
        default:
            fill = dark ? RGBAColor(hex: "#2C2C2E")! : RGBAColor(hex: "#EDECEC")!
            separator = dark ? RGBAColor(hex: "#1A1A1C")! : RGBAColor(hex: "#D4D3D3")!
        }

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
        if style.kind == .browser, let last = centers.last {
            drawBrowserControls(in: ctx, rect: rect, unit: unit, afterX: last.x + radius, dark: dark, url: url)
        }
        ctx.restoreGState()
    }

    /// Address bar geometry, exposed for tests: centred, and never overlapping the buttons on the left.
    static func addressBarRect(in rect: CGRect, unit: CGFloat, controlsEndX: CGFloat) -> CGRect {
        let height = 26 * unit
        let margin = 24 * unit
        let preferred = min(rect.width * 0.56, 640 * unit)
        let minX = controlsEndX + margin
        var width = preferred
        var x = rect.midX - width / 2
        if x < minX {
            x = minX
            width = max(rect.maxX - margin - minX, 0)
            width = min(width, preferred)
        }
        return CGRect(x: x, y: rect.midY - height / 2, width: width, height: height)
    }

    private static func drawBrowserControls(in ctx: CGContext, rect: CGRect, unit: CGFloat, afterX: CGFloat,
                                            dark: Bool, url: String) {
        let ink = dark ? RGBAColor.white.withAlpha(0.55) : RGBAColor.black.withAlpha(0.45)
        let faint = dark ? RGBAColor.white.withAlpha(0.25) : RGBAColor.black.withAlpha(0.2)

        // Back and forward chevrons.
        let size = 5 * unit
        let backX = afterX + 26 * unit
        let forwardX = backX + 22 * unit
        ctx.setLineWidth(max(1.6 * unit, 1))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for (x, color, pointsLeft) in [(backX, ink, true), (forwardX, faint, false)] {
            ctx.setStrokeColor(color.cgColor)
            let tip = pointsLeft ? x - size / 2 : x + size / 2
            let tail = pointsLeft ? x + size / 2 : x - size / 2
            ctx.move(to: CGPoint(x: tail, y: rect.midY - size))
            ctx.addLine(to: CGPoint(x: tip, y: rect.midY))
            ctx.addLine(to: CGPoint(x: tail, y: rect.midY + size))
            ctx.strokePath()
        }

        let field = addressBarRect(in: rect, unit: unit, controlsEndX: forwardX + size)
        guard field.width > 40 * unit else { return }
        let fieldColor = dark ? RGBAColor(hex: "#3A3A3E")! : RGBAColor(hex: "#E3E3E6")!
        ctx.addPath(CGPath(roundedRect: field, cornerWidth: 8 * unit, cornerHeight: 8 * unit, transform: nil))
        ctx.setFillColor(fieldColor.cgColor)
        ctx.fillPath()

        let text = url.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let fontSize = 12.5 * unit
        let textColor = dark ? RGBAColor.white.withAlpha(0.85) : RGBAColor.black.withAlpha(0.75)
        let lockWidth = 8 * unit
        let gap = 6 * unit
        let line = TextLine(text, size: fontSize, color: textColor)
        let maxTextWidth = field.width - lockWidth - gap - 24 * unit
        let textWidth = min(line.width, maxTextWidth)
        let totalWidth = lockWidth + gap + textWidth
        let startX = field.midX - totalWidth / 2

        // Padlock.
        let lockBody = CGRect(x: startX, y: field.midY - 1 * unit, width: lockWidth, height: 6.5 * unit)
        ctx.setFillColor(ink.cgColor)
        ctx.addPath(CGPath(roundedRect: lockBody, cornerWidth: 1.5 * unit, cornerHeight: 1.5 * unit, transform: nil))
        ctx.fillPath()
        ctx.setStrokeColor(ink.cgColor)
        ctx.setLineWidth(max(1.4 * unit, 0.8))
        ctx.addArc(center: CGPoint(x: lockBody.midX, y: lockBody.minY), radius: 2.6 * unit,
                   startAngle: .pi, endAngle: 0, clockwise: false)
        ctx.strokePath()

        line.draw(in: ctx, x: startX + lockWidth + gap, centerY: field.midY, maxWidth: maxTextWidth)
    }
}
