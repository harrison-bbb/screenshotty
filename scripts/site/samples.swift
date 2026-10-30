// Draws the made-up app screens used for the website pictures (no real data).
// Usage: swift scripts/site/samples.swift dashboard|phone out.png
import AppKit

let args = CommandLine.arguments
let kind = args[1]
let out = URL(fileURLWithPath: args[2])
let scale: CGFloat = 2
let size = kind == "phone" ? CGSize(width: 393, height: 852) : CGSize(width: 1280, height: 800)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = context
// Top-left origin; text is drawn through a flipped helper.
let ctx = context.cgContext
ctx.translateBy(x: 0, y: size.height)
ctx.scaleBy(x: 1, y: -1)

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}
func rect(_ r: CGRect, _ c: NSColor, radius: CGFloat = 0, stroke: NSColor? = nil) {
    let p = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
    c.setFill(); p.fill()
    if let stroke { stroke.setStroke(); p.lineWidth = 1; p.stroke() }
}
func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = hex(0x111827),
          mono: Bool = false, align: NSTextAlignment = .left, width: CGFloat = 600) {
    let style = NSMutableParagraphStyle(); style.alignment = align
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    let h = ceil(a.size().height)
    NSGraphicsContext.saveGraphicsState()
    ctx.translateBy(x: 0, y: y * 2 + h)
    ctx.scaleBy(x: 1, y: -1)
    a.draw(in: CGRect(x: x, y: y, width: width, height: h))
    NSGraphicsContext.restoreGraphicsState()
}
func line(_ points: [CGPoint], _ c: NSColor, width: CGFloat) {
    let p = NSBezierPath(); p.move(to: points[0]); points.dropFirst().forEach { p.line(to: $0) }
    p.lineWidth = width; p.lineJoinStyle = .round; p.lineCapStyle = .round; c.setStroke(); p.stroke()
}

let ink = hex(0x111827), muted = hex(0x6B7280), border = hex(0xE5E7EB), indigo = hex(0x4F46E5)

if kind == "dashboard" {
    rect(CGRect(origin: .zero, size: size), hex(0xF9FAFB))
    // Sidebar
    rect(CGRect(x: 0, y: 0, width: 232, height: size.height), .white)
    rect(CGRect(x: 231, y: 0, width: 1, height: size.height), border)
    rect(CGRect(x: 24, y: 26, width: 30, height: 30), indigo, radius: 8)
    text("N", 24, 31, size: 16, weight: .bold, color: .white, align: .center, width: 30)
    text("Northwind", 64, 30, size: 16, weight: .semibold)
    let nav = ["Overview", "Customers", "Subscriptions", "Invoices", "Reports", "Integrations", "Settings"]
    for (i, item) in nav.enumerated() {
        let y = 92 + CGFloat(i) * 40
        if i == 0 { rect(CGRect(x: 14, y: y - 8, width: 204, height: 34), hex(0xEEF2FF), radius: 8) }
        rect(CGRect(x: 28, y: y + 1, width: 16, height: 16), i == 0 ? indigo : hex(0xD1D5DB), radius: 4)
        text(item, 56, y, size: 14, weight: i == 0 ? .semibold : .regular, color: i == 0 ? indigo : hex(0x374151))
    }
    rect(CGRect(x: 14, y: size.height - 74, width: 204, height: 56), hex(0xF3F4F6), radius: 10)
    rect(CGRect(x: 26, y: size.height - 62, width: 32, height: 32), hex(0xFDBA74), radius: 16)
    text("Maya Chen", 68, size.height - 64, size: 13, weight: .semibold)
    text("maya.chen@northwind.io", 68, size.height - 46, size: 11.5, color: muted)

    // Header
    text("Overview", 264, 28, size: 24, weight: .bold)
    text("Last 30 days · Updated 2 minutes ago", 264, 62, size: 13, color: muted)
    rect(CGRect(x: 1032, y: 28, width: 104, height: 36), .white, radius: 8, stroke: border)
    text("Export", 1032, 37, size: 13.5, weight: .medium, color: hex(0x374151), align: .center, width: 104)
    rect(CGRect(x: 1148, y: 28, width: 104, height: 36), indigo, radius: 8)
    text("New invoice", 1148, 37, size: 13.5, weight: .semibold, color: .white, align: .center, width: 104)

    // KPI cards
    let kpis = [("Revenue", "$48,210", "+12.4%"), ("Active customers", "1,284", "+3.1%"), ("Churn", "1.8%", "−0.4%"), ("Avg. order", "$37.55", "+5.2%")]
    for (i, k) in kpis.enumerated() {
        let x = 264 + CGFloat(i) * 252
        rect(CGRect(x: x, y: 96, width: 236, height: 112), .white, radius: 12, stroke: border)
        text(k.0, x + 20, 114, size: 13, color: muted)
        text(k.1, x + 20, 138, size: 28, weight: .bold)
        rect(CGRect(x: x + 20, y: 178, width: 62, height: 20), hex(0xDCFCE7), radius: 10)
        text(k.2, x + 20, 180.5, size: 11.5, weight: .semibold, color: hex(0x15803D), align: .center, width: 62)
    }

    // Chart card
    rect(CGRect(x: 264, y: 224, width: 640, height: 300), .white, radius: 12, stroke: border)
    text("Monthly recurring revenue", 284, 242, size: 15, weight: .semibold)
    text("$412,880", 284, 266, size: 13, color: muted)
    for g in 0..<4 { rect(CGRect(x: 284, y: 330 + CGFloat(g) * 44, width: 600, height: 1), hex(0xF3F4F6)) }
    let values: [CGFloat] = [0.30, 0.36, 0.33, 0.45, 0.42, 0.55, 0.52, 0.63, 0.60, 0.72, 0.70, 0.84]
    let pts = values.enumerated().map { CGPoint(x: 296 + CGFloat($0.offset) * 52.5, y: 500 - $0.element * 170) }
    let area = NSBezierPath(); area.move(to: CGPoint(x: pts[0].x, y: 500)); pts.forEach { area.line(to: $0) }
    area.line(to: CGPoint(x: pts.last!.x, y: 500)); area.close()
    NSGradient(colors: [hex(0x6366F1, 0.22), hex(0x6366F1, 0)])!.draw(in: area, angle: -90)
    line(pts, hex(0x6366F1), width: 3)
    for (i, m) in ["Jan", "Mar", "May", "Jul", "Sep", "Nov"].enumerated() {
        text(m, 290 + CGFloat(i) * 105, 504, size: 11, color: hex(0x9CA3AF))
    }

    // API key card
    rect(CGRect(x: 920, y: 224, width: 332, height: 300), .white, radius: 12, stroke: border)
    text("API access", 940, 242, size: 15, weight: .semibold)
    text("Use this key to connect your billing system.", 940, 266, size: 12.5, color: muted, width: 300)
    text("Secret key", 940, 302, size: 12, weight: .medium, color: hex(0x374151))
    rect(CGRect(x: 940, y: 322, width: 292, height: 38), hex(0xF9FAFB), radius: 8, stroke: border)
    text("sk_live_51Hx9QeL2mT8vK4pZr7Wn", 952, 333, size: 12, color: ink, mono: true, width: 280)
    text("Webhook", 940, 378, size: 12, weight: .medium, color: hex(0x374151))
    rect(CGRect(x: 940, y: 398, width: 292, height: 38), hex(0xF9FAFB), radius: 8, stroke: border)
    text("https://api.northwind.io/hooks/billing", 952, 409, size: 12, color: ink, mono: true, width: 280)
    rect(CGRect(x: 940, y: 456, width: 292, height: 48), hex(0xEEF2FF), radius: 8)
    text("Server 10.24.188.42 · Healthy", 956, 471, size: 12.5, weight: .medium, color: indigo, width: 270)

    // Customers table
    rect(CGRect(x: 264, y: 540, width: 988, height: 236), .white, radius: 12, stroke: border)
    text("Recent customers", 284, 558, size: 15, weight: .semibold)
    let cols: [CGFloat] = [284, 520, 820, 980, 1120]
    for (i, h) in ["Customer", "Email", "Plan", "Status", "Amount"].enumerated() { text(h, cols[i], 592, size: 12, weight: .medium, color: muted) }
    rect(CGRect(x: 264, y: 614, width: 988, height: 1), border)
    let rows = [("Ava Thompson", "ava.thompson@brightlabs.co", "Business", "Paid", "$249.00", 0xA5B4FC as UInt32),
                ("Leo Martins", "leo@martins.studio", "Starter", "Paid", "$29.00", 0xFCA5A5),
                ("Priya Raman", "priya.raman@fieldnote.app", "Business", "Due", "$249.00", 0x86EFAC),
                ("Jonas Weber", "jonas.weber@kleinhaus.de", "Pro", "Paid", "$79.00", 0xFDE68A)]
    for (i, r) in rows.enumerated() {
        let y = 628 + CGFloat(i) * 37
        rect(CGRect(x: 284, y: y, width: 24, height: 24), hex(r.5), radius: 12)
        text(r.0, 318, y + 4, size: 13.5, weight: .medium)
        text(r.1, cols[1], y + 4, size: 13.5, color: hex(0x374151))
        text(r.2, cols[2], y + 4, size: 13.5, color: hex(0x374151))
        let paid = r.3 == "Paid"
        rect(CGRect(x: cols[3], y: y + 2, width: 48, height: 20), paid ? hex(0xDCFCE7) : hex(0xFEF3C7), radius: 10)
        text(r.3, cols[3], y + 4.5, size: 11.5, weight: .semibold, color: paid ? hex(0x15803D) : hex(0xB45309), align: .center, width: 48)
        text(r.4, cols[4], y + 4, size: 13.5, weight: .medium)
    }
} else {
    // A habit-tracker style phone app.
    rect(CGRect(origin: .zero, size: size), hex(0xF5F3FF))
    text("Good morning, Sam", 24, 70, size: 15, color: muted)
    text("Today", 24, 92, size: 34, weight: .bold)
    // Progress ring card
    rect(CGRect(x: 20, y: 150, width: 353, height: 170), .white, radius: 22)
    let ring = NSBezierPath(); ring.appendArc(withCenter: CGPoint(x: 100, y: 235), radius: 52, startAngle: 0, endAngle: 360)
    ring.lineWidth = 14; hex(0xEDE9FE).setStroke(); ring.stroke()
    let prog = NSBezierPath(); prog.appendArc(withCenter: CGPoint(x: 100, y: 235), radius: 52, startAngle: -90, endAngle: 162)
    prog.lineWidth = 14; prog.lineCapStyle = .round; hex(0x7C3AED).setStroke(); prog.stroke()
    text("70%", 48, 222, size: 22, weight: .bold, align: .center, width: 104)
    text("5 of 7 habits", 180, 196, size: 19, weight: .semibold)
    text("You're on a 12-day streak.\nKeep it going!", 180, 226, size: 14, color: muted, width: 180)
    let habits = [("Morning run", "3.2 km", true, 0xFDBA74 as UInt32), ("Read 20 pages", "Done at 8:10", true, 0x93C5FD),
                  ("Drink water", "6 of 8 glasses", false, 0x67E8F9), ("Meditate", "10 minutes", true, 0xC4B5FD),
                  ("No phone after 10", "Tonight", false, 0xF9A8D4)]
    text("Habits", 24, 344, size: 20, weight: .bold)
    for (i, h) in habits.enumerated() {
        let y = 382 + CGFloat(i) * 70
        rect(CGRect(x: 20, y: y, width: 353, height: 60), .white, radius: 16)
        rect(CGRect(x: 34, y: y + 12, width: 36, height: 36), hex(h.3), radius: 10)
        text(h.0, 82, y + 11, size: 15.5, weight: .semibold)
        text(h.1, 82, y + 32, size: 13, color: muted)
        if h.2 {
            rect(CGRect(x: 327, y: y + 17, width: 26, height: 26), hex(0x7C3AED), radius: 13)
            line([CGPoint(x: 334, y: y + 30), CGPoint(x: 338.5, y: y + 34.5), CGPoint(x: 346, y: y + 25)], .white, width: 2.5)
        } else {
            rect(CGRect(x: 327, y: y + 17, width: 26, height: 26), .white, radius: 13, stroke: hex(0xD1D5DB))
        }
    }
    // Tab bar
    rect(CGRect(x: 0, y: size.height - 84, width: size.width, height: 84), hex(0xFFFFFF, 0.95))
    rect(CGRect(x: 0, y: size.height - 84, width: size.width, height: 1), border)
    for (i, t) in ["Today", "Stats", "Friends", "Profile"].enumerated() {
        let x = 20 + CGFloat(i) * 88
        rect(CGRect(x: x + 33, y: size.height - 72, width: 22, height: 22), i == 0 ? hex(0x7C3AED) : hex(0xD1D5DB), radius: 6)
        text(t, x, size.height - 46, size: 11, weight: .medium, color: i == 0 ? hex(0x7C3AED) : muted, align: .center, width: 88)
    }
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
