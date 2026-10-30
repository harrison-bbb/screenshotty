// Renders the DMG window background (drag-to-Applications arrow plus the first-open steps).
// Usage: swift scripts/make-dmg-background.swift out.png scale   (the window is 660x420 points)
import AppKit

let args = CommandLine.arguments
let out = URL(fileURLWithPath: args[1])
let scale = CGFloat(Double(args.count > 2 ? args[2] : "1") ?? 1)
let size = CGSize(width: 660, height: 420)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let flipped = NSAffineTransform()
flipped.translateX(by: 0, yBy: size.height)
flipped.scaleX(by: 1, yBy: -1)
flipped.concat()   // top-left origin, like the Finder icon positions in make-dmg.sh

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Soft, light background so Finder's black icon labels stay readable.
NSGradient(colors: [color(0xF7F5FF), color(0xFFF4F1)])!.draw(in: CGRect(origin: .zero, size: size), angle: 90)
for (x, y, r, hex) in [(120.0, 60.0, 260.0, 0xC9C2FF as UInt32), (560.0, 330.0, 280.0, 0xFFD3C2 as UInt32)] {
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [color(hex, 0.55).cgColor, color(hex, 0).cgColor] as CFArray, locations: [0, 1])!
    NSGraphicsContext.current!.cgContext.drawRadialGradient(glow, startCenter: CGPoint(x: x, y: y), startRadius: 0,
                                                            endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
}

func text(_ string: String, at point: CGPoint, width: CGFloat, size: CGFloat, weight: NSFont.Weight,
          color textColor: NSColor, align: NSTextAlignment = .center) {
    let style = NSMutableParagraphStyle()
    style.alignment = align
    style.lineSpacing = 2
    let attributed = NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: textColor, .paragraphStyle: style,
    ])
    let height = attributed.boundingRect(with: CGSize(width: width, height: 400), options: [.usesLineFragmentOrigin]).height
    NSGraphicsContext.saveGraphicsState()
    // Undo the flip for text so glyphs aren't upside down.
    let t = NSAffineTransform()
    t.translateX(by: 0, yBy: point.y * 2 + height)
    t.scaleX(by: 1, yBy: -1)
    t.concat()
    attributed.draw(with: CGRect(x: point.x, y: point.y, width: width, height: height), options: [.usesLineFragmentOrigin])
    NSGraphicsContext.restoreGraphicsState()
}

text("Drag Screenshotty into Applications", at: CGPoint(x: 0, y: 34), width: size.width, size: 19, weight: .semibold,
     color: color(0x1D1B2E))

// Arrow between the two icons (icons sit at x 170 and 490, y 160).
let arrow = NSBezierPath()
arrow.move(to: CGPoint(x: 262, y: 160))
arrow.curve(to: CGPoint(x: 392, y: 160), controlPoint1: CGPoint(x: 300, y: 138), controlPoint2: CGPoint(x: 354, y: 138))
arrow.lineWidth = 3.5
arrow.lineCapStyle = .round
color(0x6B5BEF).setStroke()
arrow.stroke()
let head = NSBezierPath()
head.move(to: CGPoint(x: 378, y: 144))
head.line(to: CGPoint(x: 394, y: 161))
head.line(to: CGPoint(x: 372, y: 166))
head.lineWidth = 3.5
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.stroke()

// First-open card.
let card = CGRect(x: 40, y: 268, width: 580, height: 118)
color(0xFFFFFF, 0.78).setFill()
NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14).fill()
color(0x1D1B2E, 0.08).setStroke()
NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14).stroke()
text("Opening it the first time", at: CGPoint(x: 62, y: 284), width: 536, size: 13, weight: .semibold,
     color: color(0x1D1B2E), align: .left)
text("""
Screenshotty is free, so it isn't signed through Apple's paid program and macOS warns you once. \
Click Done, open System Settings → Privacy & Security, scroll down and click Open Anyway. \
After that it opens normally, and updates install themselves.
""", at: CGPoint(x: 62, y: 306), width: 536, size: 11.5, weight: .regular, color: color(0x4A4760), align: .left)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
