import AppKit
import ApplicationServices
import ScreenshottyCore
import Vision

/// Something the selection can lock onto. Rects are global top-left points.
struct DetectedRegion: Equatable {
    var rect: CGRect
    var label: String
    /// Set for whole windows, which are captured on their own (clean corners, nothing covering them).
    var windowID: CGWindowID?
}

/// Finds what's under the pointer: interface elements (through Accessibility), text blocks (found in the
/// frozen image) and windows. Thread-safe: `regions(at:)` runs off the main thread.
final class RegionDetector: @unchecked Sendable {
    let windows: [PickableWindow]
    let canReadElements: Bool
    private let lock = NSLock()
    private var textBlocks: [CGRect] = []
    /// The frozen displays, for finding visual sections.
    var screens: [FrozenScreen] = []
    /// Visual sections per window (global points), found the first time the window is hovered.
    private var sectionsByWindow: [CGWindowID: [CGRect]] = [:]

    init(windows: [PickableWindow]) {
        self.windows = windows
        canReadElements = AXIsProcessTrusted()
    }

    /// Regions containing `point`, smallest first, ending with the window. `windowsOnly` skips the rest.
    func regions(at point: CGPoint, windowsOnly: Bool) -> [DetectedRegion] {
        guard let window = windows.first(where: { $0.frame.contains(point) }) else { return [] }
        var windowRegion = DetectedRegion(rect: window.frame, label: window.appName.isEmpty ? "Window" : window.appName,
                                          windowID: window.id)

        var found: [DetectedRegion] = []
        if canReadElements {
            let (elements, axWindow) = elements(at: point, in: window)
            found += elements
            // The app knows its real window. If that differs from the window list's guess, trust the app,
            // and capture by cropping since no listed window matches it exactly.
            if let axWindow, !Self.nearlyEqual(axWindow, window.frame) {
                let match = windows.first { $0.pid == window.pid && Self.nearlyEqual($0.frame, axWindow) }
                windowRegion = DetectedRegion(rect: axWindow, label: windowRegion.label, windowID: match?.id)
            }
        }
        if windowsOnly { return [windowRegion] }
        lock.lock()
        let blocks = textBlocks
        lock.unlock()
        found += blocks.filter { $0.contains(point) && window.frame.contains($0) }.map { DetectedRegion(rect: $0, label: "Text") }
        // Visual sections: blocks separated by gutters, which pages often don't describe to Accessibility.
        found += sections(of: window).filter { $0.contains(point) }.map { DetectedRegion(rect: $0, label: "Section") }

        // Smallest first; drop near-duplicates (the first, usually the named element, wins).
        found.sort { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }
        var unique: [DetectedRegion] = []
        for region in found where region.rect.width < window.frame.width - 2 || region.rect.height < window.frame.height - 2 {
            if !unique.contains(where: { Self.nearlyEqual($0.rect, region.rect) }) { unique.append(region) }
        }
        return unique + [windowRegion]
    }

    /// The region a hover should lock onto first: big enough to be a real block, not a single word or icon.
    static func preferredIndex(in regions: [DetectedRegion]) -> Int {
        guard let window = regions.last else { return 0 }
        let threshold = max(5000, window.rect.width * window.rect.height * 0.008)
        return regions.firstIndex { $0.rect.width >= 60 && $0.rect.height >= 24 && $0.rect.width * $0.rect.height >= threshold }
            ?? regions.count - 1
    }

    static func nearlyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 4) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance &&
            abs(a.maxX - b.maxX) <= tolerance && abs(a.maxY - b.maxY) <= tolerance
    }

    // MARK: Web pages in Chromium browsers and Electron apps

    private static let webLock = NSLock()
    nonisolated(unsafe) private static var webEnabled = Set<pid_t>()

    /// Chrome, Arc, Brave, Edge and other Chromium browsers, and Electron apps (Slack, Notion, VS Code…),
    /// only build the accessibility tree of their web content when an assistive app asks for it. Without
    /// it a page is one big block. This asks each visible app once, as the picker opens.
    func enableWebStructure() {
        guard canReadElements else { return }
        for pid in Set(windows.map(\.pid)) {
            Self.webLock.lock()
            let done = !Self.webEnabled.insert(pid).inserted
            Self.webLock.unlock()
            if done { continue }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.2)
            // The flag Chromium and Electron provide for this.
            let manual = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            // Older Chromium builds only listen to the general flag VoiceOver sets; only used as a fallback,
            // and only for browsers, because some apps animate windows differently while it's on.
            if manual != .success, Self.isChromiumBrowser(pid) {
                AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            }
        }
    }

    private static func isChromiumBrowser(_ pid: pid_t) -> Bool {
        guard let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return false }
        return ["com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac",
                "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "org.chromium.Chromium", "com.google.Chrome.canary"]
            .contains { id.hasPrefix($0) }
    }

    // MARK: Accessibility

    /// The elements under `point`, smallest first, and the frame of the window they're in.
    private func elements(at point: CGPoint, in window: PickableWindow) -> ([DetectedRegion], CGRect?) {
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(app, 0.12)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success else { return ([], nil) }
        var result: [DetectedRegion] = []
        var current = hit
        var depth = 0
        while let element = current, depth < 40 {
            let role = Self.string(element, kAXRoleAttribute) ?? ""
            if role == kAXWindowRole {
                return (result, Self.frame(element))
            }
            if role == kAXApplicationRole { break }
            if let frame = Self.frame(element)?.intersection(window.frame), frame.width >= 12, frame.height >= 12,
               frame.insetBy(dx: -3, dy: -3).contains(point) {
                result.append(DetectedRegion(rect: frame, label: Self.label(role: role, element: element)))
            }
            current = Self.parent(element)
            depth += 1
        }
        return (result, nil)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func parent(_ element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef,
              CFGetTypeID(positionRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        let rect = CGRect(origin: position, size: size)
        return rect.isEmpty || rect.isInfinite ? nil : rect
    }

    private static func label(role: String, element: AXUIElement) -> String {
        switch role {
        case "AXButton", "AXPopUpButton", "AXMenuButton", "AXCheckBox", "AXRadioButton": return "Button"
        case "AXStaticText", "AXTextArea": return "Text"
        case "AXTextField", "AXSearchField", "AXComboBox": return "Field"
        case "AXImage": return "Image"
        case "AXLink": return "Link"
        case "AXHeading": return "Heading"
        case "AXWebArea": return "Page"
        case "AXScrollArea": return "Scroll area"
        case "AXTable", "AXOutline", "AXList", "AXBrowser", "AXGrid": return "List"
        case "AXRow", "AXCell": return "Row"
        case "AXToolbar": return "Toolbar"
        case "AXTabGroup": return "Tabs"
        case "AXSplitGroup": return "Panels"
        case "AXGroup", "AXLayoutArea", "AXLayoutItem": return "Section"
        default:
            return string(element, kAXRoleDescriptionAttribute)?.capitalized ?? "Element"
        }
    }

    // MARK: Text blocks

    /// Finds paragraphs and other blocks of text in a frozen screen, in the background.
    func findTextBlocks(in screen: FrozenScreen) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        guard (try? VNImageRequestHandler(cgImage: screen.image).perform([request])) != nil else { return }
        let frame = screen.globalFrame
        let lines = (request.results ?? []).map { observation -> CGRect in
            let box = observation.boundingBox
            return CGRect(x: frame.minX + box.minX * frame.width, y: frame.minY + (1 - box.maxY) * frame.height,
                          width: box.width * frame.width, height: box.height * frame.height)
        }
        let blocks = TextBlocks.group(lines)
        lock.lock()
        textBlocks += blocks
        lock.unlock()
    }

    /// Loads the fast text model ahead of time, so text blocks are ready the moment the picker opens.
    static func warmUp() {
        guard let ctx = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let image = ctx.makeImage() else { return }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        try? VNImageRequestHandler(cgImage: image).perform([request])
    }

    // MARK: Visual sections

    /// The window's visual sections, worked out once from the frozen screen.
    func sections(of window: PickableWindow) -> [CGRect] {
        lock.lock()
        if let cached = sectionsByWindow[window.id] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let found = Self.findSections(of: window, screens: screens)
        lock.lock()
        sectionsByWindow[window.id] = found
        lock.unlock()
        return found
    }

    private static func findSections(of window: PickableWindow, screens: [FrozenScreen]) -> [CGRect] {
        let centre = CGPoint(x: window.frame.midX, y: window.frame.midY)
        guard let screen = screens.first(where: { $0.globalFrame.contains(centre) }) ?? screens.first else { return [] }
        let visible = window.frame.intersection(screen.globalFrame)
        guard !visible.isEmpty, let crop = screen.crop(visible) else { return [] }
        // Work on a copy about 1000 px wide: fast, and still sharp enough to see gutters.
        let shrink = min(1, 1000 / CGFloat(crop.width))
        let width = max(Int(CGFloat(crop.width) * shrink), 1)
        let height = max(Int(CGFloat(crop.height) * shrink), 1)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.interpolationQuality = .medium
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let small = ctx.makeImage() else { return [] }
        let pixelsPerPoint = CGFloat(width) / visible.width
        let blocks = LayoutSegmenter.sections(in: small, minGap: Int((10 * pixelsPerPoint).rounded()),
                                              minSize: Int((24 * pixelsPerPoint).rounded()))
        return blocks.map {
            CGRect(x: visible.minX + $0.minX / pixelsPerPoint, y: visible.minY + $0.minY / pixelsPerPoint,
                   width: $0.width / pixelsPerPoint, height: $0.height / pixelsPerPoint)
        }
    }

    /// Edges the drag can snap to: windows, text blocks and the sections found so far.
    func snapEdges() -> (x: [CGFloat], y: [CGFloat]) {
        lock.lock()
        let rects = textBlocks + windows.map(\.frame) + sectionsByWindow.values.flatMap { $0 }
        lock.unlock()
        return (rects.flatMap { [$0.minX, $0.maxX] }, rects.flatMap { [$0.minY, $0.maxY] })
    }
}
