import CoreGraphics

/// Draws MacBook and iPhone mockups around the screenshot, entirely in code (no image assets),
/// so they scale to any resolution and port easily to other platforms.
enum DeviceFrame {
    typealias Geometry = CompositionLayout.DeviceGeometry

    /// The colours the screen is filled with around the screenshot.
    struct ScreenColors {
        /// The most common colour along each edge of the screenshot. Gaps beside the screenshot are
        /// filled with the colour of the edge they touch, so the content seems to carry on.
        var top: RGBAColor
        var bottom: RGBAColor
        var left: RGBAColor
        var right: RGBAColor
        var fill: RGBAColor { bottom }

        static func sample(_ image: CGImage) -> ScreenColors {
            func dominant(_ rect: CGRect) -> RGBAColor? {
                guard let strip = image.cropping(to: rect), let pixels = RGBABuffer(image: strip) else { return nil }
                var list: [RGBAPixel] = []
                for y in 0..<pixels.height { for x in stride(from: 0, to: pixels.width, by: max(1, pixels.width / 400)) { list.append(pixels[x, y]) } }
                return ImageTrimmer.dominantColor(list).map {
                    RGBAColor(red: Double($0.r) / 255, green: Double($0.g) / 255, blue: Double($0.b) / 255)
                }
            }
            let w = CGFloat(image.width), h = CGFloat(image.height)
            let top = dominant(CGRect(x: 0, y: 0, width: w, height: 1)) ?? .white
            let bottom = dominant(CGRect(x: 0, y: h - 1, width: w, height: 1)) ?? top
            let left = dominant(CGRect(x: 0, y: 0, width: 1, height: h)) ?? bottom
            let right = dominant(CGRect(x: w - 1, y: 0, width: 1, height: h)) ?? bottom
            return ScreenColors(top: top, bottom: bottom, left: left, right: right)
        }
    }

    // MARK: Body

    /// Draws the device (and laptop base) with its shadow. The screen is left black for the content.
    static func drawBody(_ style: DeviceStyle, geometry g: Geometry, shadow: ShadowStyle, unit: CGFloat, in ctx: CGContext) {
        ctx.saveGState()
        if let s = shadow.parameters {
            let scale = ctx.ctm.a
            ctx.setShadow(offset: CGSize(width: 0, height: -s.offsetY * unit * scale), blur: s.blur * unit * scale,
                          color: RGBAColor.black.withAlpha(s.opacity).cgColor)
        }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        switch style {
        case .none: break
        case .macbook: drawMacBook(g, in: ctx)
        case .iphone: drawIPhone(g, in: ctx)
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    private static func roundedRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
        let radius = min(radius, min(r.width, r.height) / 2)
        return CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private static func gradient(_ colors: [String], _ locations: [CGFloat]) -> CGGradient? {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                   colors: colors.compactMap { RGBAColor(hex: $0)?.cgColor } as CFArray, locations: locations)
    }

    private static func drawMacBook(_ g: Geometry, in ctx: CGContext) {
        let lid = g.bodyRect
        if let base = g.baseRect {
            // Keyboard base: a thin aluminium slab, rounded at the front, with a thumb scoop in the middle.
            let r = base.height * 0.85
            let path = CGMutablePath()
            path.move(to: CGPoint(x: base.minX, y: base.minY))
            path.addLine(to: CGPoint(x: base.maxX, y: base.minY))
            path.addArc(tangent1End: CGPoint(x: base.maxX, y: base.maxY), tangent2End: CGPoint(x: base.midX, y: base.maxY), radius: r)
            path.addArc(tangent1End: CGPoint(x: base.minX, y: base.maxY), tangent2End: CGPoint(x: base.minX, y: base.minY), radius: r)
            path.closeSubpath()
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            if let gr = gradient(["#EDEEF0", "#CDCFD3", "#8F9197"], [0, 0.4, 1]) {
                ctx.drawLinearGradient(gr, start: CGPoint(x: 0, y: base.minY), end: CGPoint(x: 0, y: base.maxY), options: [])
            }
            let scoopW = lid.width * 0.14
            let scoopH = base.height * 0.42
            let scoop = CGRect(x: base.midX - scoopW / 2, y: base.minY - scoopH, width: scoopW, height: scoopH * 2)
            ctx.addPath(roundedRect(scoop, scoopH))
            if let gr = gradient(["#B3B5BA", "#C9CBCF"], [0, 1]) {
                ctx.saveGState()
                ctx.clip()
                ctx.drawLinearGradient(gr, start: CGPoint(x: 0, y: base.minY), end: CGPoint(x: 0, y: base.minY + scoopH), options: [])
                ctx.restoreGState()
            }
            ctx.setFillColor(RGBAColor.white.withAlpha(0.8).cgColor)
            ctx.fill(CGRect(x: base.minX, y: base.minY, width: base.width, height: max(base.height * 0.06, 1)))
            ctx.restoreGState()
        }

        // Lid: a thin silver rim, then black glass to the edge of the display.
        ctx.addPath(roundedRect(lid, g.bodyCornerRadius))
        ctx.setFillColor(RGBAColor(hex: "#A7A9AE")!.cgColor)
        ctx.fillPath()
        let rim = max(lid.width * 0.0025, 1)
        ctx.addPath(roundedRect(lid.insetBy(dx: rim, dy: rim), g.bodyCornerRadius - rim))
        ctx.setFillColor(RGBAColor(hex: "#050506")!.cgColor)
        ctx.fillPath()
        // Subtle reflection on the glass bezel.
        ctx.saveGState()
        ctx.addPath(roundedRect(lid.insetBy(dx: rim, dy: rim), g.bodyCornerRadius - rim))
        ctx.clip()
        if let gr = gradient(["#FFFFFF14", "#FFFFFF00"], [0, 1]) {
            ctx.drawLinearGradient(gr, start: CGPoint(x: lid.minX, y: lid.minY), end: CGPoint(x: lid.midX, y: lid.midY), options: [])
        }
        ctx.restoreGState()
        ctx.addPath(roundedRect(g.screenRect, g.screenCornerRadius))
        ctx.setFillColor(RGBAColor(hex: "#000000")!.cgColor)
        ctx.fillPath()
    }

    private static func drawIPhone(_ g: Geometry, in ctx: CGContext) {
        let body = g.bodyRect
        let short = min(body.width, body.height)
        let buttonDepth = max(short * 0.008, 1.5)
        // Side buttons, positioned along the phone's long side from its top (left when landscape).
        func button(onLeftSide: Bool, from: CGFloat, length: CGFloat) {
            let rect: CGRect
            if g.landscape {
                // Turned so the top is on the left: the phone's left side faces down.
                let x = body.minX + body.width * from
                rect = CGRect(x: x, y: onLeftSide ? body.maxY - buttonDepth : body.minY - buttonDepth,
                              width: body.width * length, height: buttonDepth * 2)
            } else {
                let y = body.minY + body.height * from
                rect = CGRect(x: onLeftSide ? body.minX - buttonDepth : body.maxX - buttonDepth, y: y,
                              width: buttonDepth * 2, height: body.height * length)
            }
            ctx.addPath(roundedRect(rect, buttonDepth))
            ctx.setFillColor(RGBAColor(hex: "#7C7C82")!.cgColor)
            ctx.fillPath()
        }
        button(onLeftSide: true, from: 0.155, length: 0.04)   // action button
        button(onLeftSide: true, from: 0.225, length: 0.07)   // volume up
        button(onLeftSide: true, from: 0.31, length: 0.07)    // volume down
        button(onLeftSide: false, from: 0.25, length: 0.11)   // side button

        // Titanium frame with a soft sheen, then the black border around the display.
        ctx.saveGState()
        ctx.addPath(roundedRect(body, g.bodyCornerRadius))
        ctx.clip()
        if let gr = gradient(["#C7C7CC", "#8E8E93", "#B5B5BA", "#7A7A80"], [0, 0.35, 0.65, 1]) {
            ctx.drawLinearGradient(gr, start: CGPoint(x: body.minX, y: body.minY), end: CGPoint(x: body.maxX, y: body.maxY), options: [])
        }
        ctx.restoreGState()
        let frame = max(short * 0.011, 1)
        ctx.addPath(roundedRect(body.insetBy(dx: frame, dy: frame), g.bodyCornerRadius - frame))
        ctx.setFillColor(RGBAColor(hex: "#0A0A0B")!.cgColor)
        ctx.fillPath()
        ctx.addPath(roundedRect(g.screenRect, g.screenCornerRadius))
        ctx.setFillColor(RGBAColor(hex: "#000000")!.cgColor)
        ctx.fillPath()
    }

    // MARK: On top of the screen

    /// The MacBook notch, the iPhone's Dynamic Island, status bar and home indicator.
    static func drawOverlay(_ style: DeviceStyle, geometry g: Geometry, colors: ScreenColors, in ctx: CGContext) {
        let screen = g.screenRect
        switch style {
        case .none:
            break
        case .macbook:
            // The notch only shows on a desktop, where it can't cover the screenshot itself.
            guard g.mode == .desktop else { return }
            let w = screen.width * 0.105
            let h = screen.width * 0.021
            let r = h * 0.45
            let notch = CGMutablePath()
            notch.move(to: CGPoint(x: screen.midX - w / 2, y: screen.minY - 1))
            notch.addLine(to: CGPoint(x: screen.midX + w / 2, y: screen.minY - 1))
            notch.addArc(tangent1End: CGPoint(x: screen.midX + w / 2, y: screen.minY + h),
                         tangent2End: CGPoint(x: screen.midX, y: screen.minY + h), radius: r)
            notch.addArc(tangent1End: CGPoint(x: screen.midX - w / 2, y: screen.minY + h),
                         tangent2End: CGPoint(x: screen.midX - w / 2, y: screen.minY), radius: r)
            notch.closeSubpath()
            ctx.addPath(notch)
            ctx.setFillColor(RGBAColor(hex: "#000000")!.cgColor)
            ctx.fillPath()
        case .iphone:
            let short = min(screen.width, screen.height)
            let islandLong = short * 0.318
            let islandShort = short * 0.094
            let inset = short * 0.028
            let island = g.landscape
                ? CGRect(x: screen.minX + inset, y: screen.midY - islandLong / 2, width: islandShort, height: islandLong)
                : CGRect(x: screen.midX - islandLong / 2, y: screen.minY + inset, width: islandLong, height: islandShort)
            ctx.addPath(roundedRect(island, islandShort / 2))
            ctx.setFillColor(RGBAColor(hex: "#000000")!.cgColor)
            ctx.fillPath()
            if g.mode == .phoneApp {
                drawStatusBar(in: ctx, screen: screen, islandCenterY: island.midY, background: colors.top)
                let indicatorW = screen.width * 0.35
                let indicatorH = max(screen.width * 0.013, 2)
                let indicator = CGRect(x: screen.midX - indicatorW / 2, y: screen.maxY - screen.width * 0.022 - indicatorH,
                                       width: indicatorW, height: indicatorH)
                ctx.addPath(roundedRect(indicator, indicatorH / 2))
                ctx.setFillColor((colors.fill.isLight ? RGBAColor.black : .white).withAlpha(0.85).cgColor)
                ctx.fillPath()
            }
        }
    }

    /// "9:41", signal, Wi-Fi and battery, in black or white to suit the background.
    private static func drawStatusBar(in ctx: CGContext, screen: CGRect, islandCenterY: CGFloat, background: RGBAColor) {
        let w = screen.width
        let ink = background.isLight ? RGBAColor.black : RGBAColor.white
        let time = TextLine("9:41", size: w * 0.043, color: ink, weight: 0.4)
        time.draw(in: ctx, x: screen.minX + w * 0.165 - time.width / 2, centerY: islandCenterY, maxWidth: w * 0.3)

        ctx.saveGState()
        ctx.setFillColor(ink.cgColor)
        ctx.setStrokeColor(ink.cgColor)
        let unit = w / 393   // one iOS point on a 393 pt wide screen
        // Battery, from the right edge inwards.
        let battery = CGRect(x: screen.maxX - 33 * unit - 27 * unit, y: islandCenterY - 6.5 * unit, width: 25 * unit, height: 13 * unit)
        ctx.setLineWidth(1 * unit)
        ctx.setAlpha(0.4)
        ctx.addPath(roundedRect(battery, 4 * unit))
        ctx.strokePath()
        ctx.fill(CGRect(x: battery.maxX + 1.2 * unit, y: battery.midY - 2.2 * unit, width: 1.6 * unit, height: 4.4 * unit))
        ctx.setAlpha(1)
        ctx.addPath(roundedRect(battery.insetBy(dx: 2 * unit, dy: 2 * unit), 2.5 * unit))
        ctx.fillPath()
        // Wi-Fi: three arcs and a dot.
        let wifiCenter = CGPoint(x: battery.minX - 14 * unit, y: islandCenterY + 5 * unit)
        ctx.setLineWidth(2.1 * unit)
        ctx.setLineCap(.round)
        for (i, radius) in [3.5, 7.5, 11.5].enumerated() where i > 0 {
            ctx.addArc(center: wifiCenter, radius: radius * unit, startAngle: -.pi * 0.75, endAngle: -.pi * 0.25, clockwise: false)
            ctx.strokePath()
        }
        ctx.move(to: wifiCenter)
        ctx.addArc(center: wifiCenter, radius: 3.6 * unit, startAngle: -.pi * 0.75, endAngle: -.pi * 0.25, clockwise: false)
        ctx.closePath()
        ctx.fillPath()
        // Signal: four bars.
        let signalRight = wifiCenter.x - 14 * unit
        for i in 0..<4 {
            let h = (4 + CGFloat(i) * 2.6) * unit
            let x = signalRight - CGFloat(4 - i) * 4.8 * unit
            ctx.addPath(roundedRect(CGRect(x: x, y: islandCenterY + 5.5 * unit - h, width: 3.2 * unit, height: h), 1 * unit))
            ctx.fillPath()
        }
        ctx.restoreGState()
    }
}

extension RGBAColor {
    /// True for colours where black text reads better than white.
    var isLight: Bool { 0.2126 * red + 0.7152 * green + 0.0722 * blue > 0.6 }
}
