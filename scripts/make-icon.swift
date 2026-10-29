// Renders the Screenshotty app icon (1024x1024 PNG). Usage: swift scripts/make-icon.swift out.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Top-left origin.
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// macOS icon grid: 824pt body with ~185pt corner radius, centred.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Drop shadow under the body.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.3))
ctx.addPath(bodyPath)
ctx.setFillColor(color(0x5B4BDB))
ctx.fillPath()
ctx.restoreGState()

// Background: indigo to pink gradient plus soft blobs.
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let base = CGGradient(colorsSpace: nil, colors: [color(0x5B5BF0), color(0x9B4DDB), color(0xF2709C)] as CFArray,
                      locations: [0, 0.55, 1])!
ctx.drawLinearGradient(base, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 924, y: 924), options: [])
for (x, y, r, hex) in [(220.0, 200.0, 420.0, 0x7FD1FF as UInt32), (880.0, 860.0, 460.0, 0xFFB86B as UInt32)] {
    let g = CGGradient(colorsSpace: nil, colors: [color(hex, 0.55), color(hex, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0,
                           endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
}
ctx.restoreGState()

// The "screenshot" card.
let card = CGRect(x: 262, y: 322, width: 500, height: 380)
let cardPath = CGPath(roundedRect: card, cornerWidth: 34, cornerHeight: 34, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 60, color: color(0x1A0B40, 0.45))
ctx.addPath(cardPath)
ctx.setFillColor(color(0xFFFFFF))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(cardPath)
ctx.clip()
ctx.setFillColor(color(0xEFEFF4))
ctx.fill(CGRect(x: card.minX, y: card.minY, width: card.width, height: 64))
for (i, hex) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
    ctx.setFillColor(color(UInt32(hex)))
    ctx.fillEllipse(in: CGRect(x: card.minX + 30 + CGFloat(i) * 40, y: card.minY + 20, width: 24, height: 24))
}
// Content lines.
ctx.setFillColor(color(0x5B5BF0, 0.9))
ctx.addPath(CGPath(roundedRect: CGRect(x: card.minX + 40, y: card.minY + 110, width: 250, height: 30), cornerWidth: 15, cornerHeight: 15, transform: nil))
ctx.fillPath()
ctx.setFillColor(color(0xC9C9D6))
for (i, w) in [400.0, 340.0, 380.0].enumerated() {
    ctx.addPath(CGPath(roundedRect: CGRect(x: card.minX + 40, y: card.minY + 170 + CGFloat(i) * 46, width: w, height: 22),
                       cornerWidth: 11, cornerHeight: 11, transform: nil))
    ctx.fillPath()
}
ctx.restoreGState()

// Viewfinder corners.
ctx.setStrokeColor(color(0xFFFFFF, 0.95))
ctx.setLineWidth(30)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
let outer = card.insetBy(dx: -78, dy: -78)
let arm: CGFloat = 92
for (corner, dx, dy) in [(CGPoint(x: outer.minX, y: outer.minY), 1.0, 1.0),
                         (CGPoint(x: outer.maxX, y: outer.minY), -1.0, 1.0),
                         (CGPoint(x: outer.minX, y: outer.maxY), 1.0, -1.0),
                         (CGPoint(x: outer.maxX, y: outer.maxY), -1.0, -1.0)] {
    ctx.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
    ctx.addLine(to: corner)
    ctx.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
    ctx.strokePath()
}

let image = ctx.makeImage()!
let url = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png")
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
