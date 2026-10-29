import CoreGraphics

/// Draws MacBook and iPhone mockups around the screenshot, entirely in code (no image assets),
/// so they scale to any resolution and port easily to other platforms.
enum DeviceFrame {
    /// Draws the device body (and laptop base) with its shadow. The screen content is drawn afterwards.
    static func drawBody(_ style: DeviceStyle, geometry g: CompositionLayout.DeviceGeometry, shadow: ShadowStyle,
                         unit: CGFloat, in ctx: CGContext) {
        ctx.saveGState()
        if let s = shadow.parameters {
            let scale = ctx.ctm.a
            ctx.setShadow(offset: CGSize(width: 0, height: -s.offsetY * unit * scale), blur: s.blur * unit * scale,
                          color: RGBAColor.black.withAlpha(s.opacity).cgColor)
        }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        switch style {
        case .none: break
        case .macbook: drawMacBook(g, unit: unit, in: ctx)
        case .iphone: drawIPhone(g, unit: unit, in: ctx)
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// Details that sit on top of the screen, such as the iPhone's Dynamic Island.
    static func drawOverlay(_ style: DeviceStyle, geometry g: CompositionLayout.DeviceGeometry, screen: CGRect,
                            in ctx: CGContext) {
        guard style == .iphone else { return }
        let width = screen.width * 0.30
        let height = min(screen.width * 0.088, screen.height * 0.06)
        let island = CGRect(x: screen.midX - width / 2, y: screen.minY + g.bezel * 0.55, width: width, height: height)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: island, cornerWidth: height / 2, cornerHeight: height / 2, transform: nil))
        ctx.setFillColor(RGBAColor(hex: "#000000")!.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }

    private static func drawMacBook(_ g: CompositionLayout.DeviceGeometry, unit: CGFloat, in ctx: CGContext) {
        let lid = g.bodyRect
        let rim = max(g.bezel * 0.12, 1)

        // Base first, so the lid's bottom edge sits on top of it.
        if let base = g.baseRect {
            let r = base.height * 0.9
            let path = CGMutablePath()
            path.move(to: CGPoint(x: base.minX, y: base.minY))
            path.addLine(to: CGPoint(x: base.maxX, y: base.minY))
            path.addArc(tangent1End: CGPoint(x: base.maxX, y: base.maxY), tangent2End: CGPoint(x: base.midX, y: base.maxY), radius: r)
            path.addArc(tangent1End: CGPoint(x: base.minX, y: base.maxY), tangent2End: CGPoint(x: base.minX, y: base.minY), radius: r)
            path.closeSubpath()
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            let colors = [RGBAColor(hex: "#E6E7EA")!, RGBAColor(hex: "#C3C5CA")!, RGBAColor(hex: "#8E9097")!]
            if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                         colors: colors.map(\.cgColor) as CFArray, locations: [0, 0.45, 1]) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: base.minY), end: CGPoint(x: 0, y: base.maxY), options: [])
            }
            // Thumb notch for opening the lid.
            let notchW = lid.width * 0.13
            let notchH = base.height * 0.38
            let notch = CGRect(x: base.midX - notchW / 2, y: base.minY - notchH, width: notchW, height: notchH * 2)
            ctx.addPath(CGPath(roundedRect: notch, cornerWidth: notchH, cornerHeight: notchH, transform: nil))
            ctx.setFillColor(RGBAColor(hex: "#A8AAB0")!.cgColor)
            ctx.fillPath()
            // Highlight along the top edge.
            ctx.setFillColor(RGBAColor.white.withAlpha(0.7).cgColor)
            ctx.fill(CGRect(x: base.minX, y: base.minY, width: base.width, height: max(unit * 0.8, 1)))
            ctx.restoreGState()
        }

        // Lid: thin aluminium rim around a black bezel.
        let outer = CGPath(roundedRect: lid, cornerWidth: g.bodyCornerRadius, cornerHeight: g.bodyCornerRadius, transform: nil)
        ctx.addPath(outer)
        ctx.setFillColor(RGBAColor(hex: "#B9BBC1")!.cgColor)
        ctx.fillPath()
        let inner = lid.insetBy(dx: rim, dy: rim)
        let innerRadius = max(g.bodyCornerRadius - rim, 0)
        ctx.addPath(CGPath(roundedRect: inner, cornerWidth: innerRadius, cornerHeight: innerRadius, transform: nil))
        ctx.setFillColor(RGBAColor(hex: "#0B0B0D")!.cgColor)
        ctx.fillPath()

        // Camera.
        let cameraR = max(g.bezel * 0.13, 1)
        let camera = CGRect(x: lid.midX - cameraR, y: lid.minY + g.bezel / 2 - cameraR, width: cameraR * 2, height: cameraR * 2)
        ctx.setFillColor(RGBAColor(hex: "#24242A")!.cgColor)
        ctx.fillEllipse(in: camera)
    }

    private static func drawIPhone(_ g: CompositionLayout.DeviceGeometry, unit: CGFloat, in ctx: CGContext) {
        let body = g.bodyRect
        let buttonW = max(g.bezel * 0.16, 1.5)
        let buttonColor = RGBAColor(hex: "#5E5E63")!

        // Side buttons, drawn first so the body overlaps their inner edge.
        func button(_ x: CGFloat, _ y: CGFloat, _ length: CGFloat) {
            let rect = CGRect(x: x, y: body.minY + body.height * y, width: buttonW * 2, height: body.height * length)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: buttonW, cornerHeight: buttonW, transform: nil))
            ctx.setFillColor(buttonColor.cgColor)
            ctx.fillPath()
        }
        button(body.minX - buttonW, 0.16, 0.035)   // action button
        button(body.minX - buttonW, 0.23, 0.065)   // volume up
        button(body.minX - buttonW, 0.31, 0.065)   // volume down
        button(body.maxX - buttonW, 0.25, 0.10)    // side button

        let radius = g.bodyCornerRadius
        ctx.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(RGBAColor(hex: "#8A8A8F")!.cgColor)   // titanium edge
        ctx.fillPath()
        let edge = max(g.bezel * 0.14, 1)
        let inner = body.insetBy(dx: edge, dy: edge)
        ctx.addPath(CGPath(roundedRect: inner, cornerWidth: max(radius - edge, 0), cornerHeight: max(radius - edge, 0), transform: nil))
        ctx.setFillColor(RGBAColor(hex: "#0A0A0B")!.cgColor)
        ctx.fillPath()
    }
}
