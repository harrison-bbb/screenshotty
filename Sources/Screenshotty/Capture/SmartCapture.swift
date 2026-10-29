import AppKit
import SwiftUI

/// Screenshotty's own area picker. The screens freeze; moving the pointer locks onto interface elements,
/// text blocks and windows; dragging draws a custom area that snaps to nearby edges.
///
/// Click: capture what's highlighted · Drag: custom area · Scroll or ↑/↓: bigger or smaller element ·
/// Space: whole windows · Return: capture · Esc: cancel.
@MainActor
final class SmartCapture {
    private var overlays: [OverlayWindow] = []
    private var continuation: CheckedContinuation<CaptureResult, Never>?
    let detector: RegionDetector
    private let detectQueue = DispatchQueue(label: "screenshotty.detect", qos: .userInteractive)
    private var detecting = false
    private var pendingPoint: CGPoint?
    var windowsOnly = false

    private init(screens: [FrozenScreen], detector: RegionDetector) {
        self.detector = detector
        overlays = screens.map { OverlayWindow(frozen: $0) }
        overlays.forEach { $0.overlayView.controller = self }
    }

    /// Runs the picker. Returns nil if it couldn't start (e.g. ScreenCaptureKit unavailable), so the caller
    /// can fall back to the system picker.
    static func run() async -> CaptureResult? {
        let windows = ScreenFreezer.windows()
        guard let screens = try? await ScreenFreezer.freeze(), !screens.isEmpty else { return nil }
        let detector = RegionDetector(windows: windows)
        let capture = SmartCapture(screens: screens, detector: detector)
        active = capture
        for screen in screens {
            DispatchQueue.global(qos: .userInitiated).async {
                detector.findTextBlocks(in: screen)
                // Text blocks arrive a moment after the picker opens: re-check what's under the pointer.
                DispatchQueue.main.async { MainActor.assumeIsolated { capture.refreshHover() } }
            }
        }
        return await withCheckedContinuation { continuation in
            capture.continuation = continuation
            capture.show()
        }
    }

    private func show() {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = NSWorkspace.shared.frontmostApplication
        }
        NSApp.activate(ignoringOtherApps: true)
        for overlay in overlays {
            overlay.orderFrontRegardless()
        }
        let mouse = NSEvent.mouseLocation
        let active = overlays.first { $0.frame.contains(mouse) } ?? overlays.first
        active?.makeKey()
        active?.makeFirstResponder(active?.overlayView)
        overlays.forEach { $0.overlayView.pointerMoved(to: $0.mouseLocationOutsideOfEventStream) }
    }

    // MARK: Detection (latest request wins, off the main thread)

    func detect(at point: CGPoint, for view: OverlayView) {
        pendingPoint = point
        guard !detecting else { return }
        runDetection(for: view)
    }

    private func runDetection(for view: OverlayView) {
        guard let point = pendingPoint else { return }
        pendingPoint = nil
        detecting = true
        let windowsOnly = windowsOnly
        let detector = detector
        detectQueue.async {
            let regions = detector.regions(at: point, windowsOnly: windowsOnly)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.detecting = false
                    view.show(regions)
                    if self.pendingPoint != nil { self.runDetection(for: view) }
                }
            }
        }
    }

    // MARK: Finishing

    func finish(rect: CGRect, windowID: CGWindowID?, on frozen: FrozenScreen) {
        // Hide the overlay but keep its windows until the editor is up. If Screenshotty had no windows for
        // a moment, macOS would hand focus to another app (often on another desktop) and pull you away.
        overlays.forEach {
            $0.alphaValue = 0
            $0.ignoresMouseEvents = true
        }
        Task { @MainActor in
            var image: CGImage?
            if let windowID {
                image = await ScreenFreezer.capture(window: windowID, scale: frozen.scale)
            }
            if image == nil { image = frozen.crop(rect) }
            if let image {
                Log.write("smart capture: \(image.width)x\(image.height) window=\(windowID != nil)")
                continuation?.resume(returning: .image(image))
            } else {
                continuation?.resume(returning: .cancelled)
                dismiss(returnFocus: true)
            }
            continuation = nil
            // Safety net: if nobody dismisses the hidden overlay (it should be within a moment), do it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                MainActor.assumeIsolated { self?.dismiss(returnFocus: false) }
            }
        }
    }

    /// The picker whose hidden overlay is waiting for the capture to be handled.
    private static var active: SmartCapture?

    /// Called once the capture has been handled (editor open, or image copied or saved). Removes the
    /// hidden overlay; `returnFocus` gives focus back to the app the user was in when no editor opened.
    static func captureHandled(openedWindow: Bool) {
        active?.dismiss(returnFocus: !openedWindow)
    }

    private func dismiss(returnFocus: Bool) {
        guard !overlays.isEmpty else { return }
        close()
        if returnFocus { returnFocusIfIdle() }
        if Self.active === self { Self.active = nil }
    }

    /// The app that was in front before the picker opened.
    private var previousApp: NSRunningApplication?

    private func returnFocusIfIdle() {
        let showing = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
        if !showing { previousApp?.activate() }
    }

    func cancel() {
        continuation?.resume(returning: .cancelled)
        continuation = nil
        dismiss(returnFocus: true)
    }

    private func close() {
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
    }

    func toggleWindowsOnly() {
        windowsOnly.toggle()
        refreshHover()
    }

    func refreshHover() {
        overlays.forEach { $0.overlayView.pointerMoved(to: $0.mouseLocationOutsideOfEventStream) }
    }
}

// MARK: - Window

final class OverlayWindow: NSWindow {
    let overlayView: OverlayView

    init(frozen: FrozenScreen) {
        overlayView = OverlayView(frozen: frozen)
        super.init(contentRect: frozen.screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        contentView = overlayView
        setFrame(frozen.screen.frame, display: false)

        let hint = NSHostingView(rootView: CaptureHint())
        hint.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: overlayView.bottomAnchor, constant: -28),
        ])
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - View

final class OverlayView: NSView {
    let frozen: FrozenScreen
    weak var controller: SmartCapture?

    /// What can be locked onto under the pointer (smallest first) and which one is chosen.
    private var regions: [DetectedRegion] = []
    private var index = 0
    /// The outline as drawn (it glides towards the target).
    private var shown: CGRect?
    private var target: CGRect?
    private var animation: Timer?
    private var dragStart: CGPoint?
    private var dragRect: CGRect?
    private var scrollAccumulator: CGFloat = 0

    init(frozen: FrozenScreen) {
        self.frozen = frozen
        super.init(frame: CGRect(origin: .zero, size: frozen.screen.frame.size))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
                                       owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    // Coordinates: the view is the screen, flipped, so local = global - screen origin.
    private func global(_ local: CGPoint) -> CGPoint {
        CGPoint(x: local.x + frozen.globalFrame.minX, y: local.y + frozen.globalFrame.minY)
    }

    private func local(_ global: CGRect) -> CGRect {
        global.offsetBy(dx: -frozen.globalFrame.minX, dy: -frozen.globalFrame.minY)
    }

    // MARK: Hover

    func pointerMoved(to windowPoint: CGPoint) {
        let point = convert(windowPoint, from: nil)
        guard bounds.contains(point), dragRect == nil else { return }
        controller?.detect(at: global(point), for: self)
    }

    override func mouseMoved(with event: NSEvent) {
        pointerMoved(to: event.locationInWindow)
    }

    func show(_ regions: [DetectedRegion]) {
        let previous = self.regions.indices.contains(index) ? self.regions[index].rect : nil
        self.regions = regions
        // Keep the same element when it's still under the pointer; otherwise lock onto a sensible block.
        if let previous, let same = regions.firstIndex(where: { RegionDetector.nearlyEqual($0.rect, previous) }) {
            index = same
        } else {
            index = RegionDetector.preferredIndex(in: regions)
        }
        setTarget(regions.indices.contains(index) ? local(regions[index].rect) : nil)
    }

    private func setTarget(_ rect: CGRect?) {
        target = rect
        guard let rect else {
            shown = nil
            needsDisplay = true
            return
        }
        if shown == nil {
            shown = rect
            needsDisplay = true
            return
        }
        guard animation == nil else { return }
        animation = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, let target = self.target, let current = self.shown else { timer.invalidate(); return }
                func ease(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * 0.32 }
                let next = CGRect(x: ease(current.minX, target.minX), y: ease(current.minY, target.minY),
                                  width: ease(current.width, target.width), height: ease(current.height, target.height))
                let done = RegionDetector.nearlyEqual(next, target, tolerance: 0.5)
                self.shown = done ? target : next
                self.needsDisplay = true
                if done {
                    timer.invalidate()
                    self.animation = nil
                }
            }
        }
    }

    /// Bigger (+1) or smaller (−1) element around the pointer.
    private func step(_ direction: Int) {
        let next = index + direction
        guard regions.indices.contains(next) else { NSSound.beep(); return }
        index = next
        setTarget(local(regions[index].rect))
    }

    override func scrollWheel(with event: NSEvent) {
        scrollAccumulator += event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 10)
        if abs(scrollAccumulator) > 24 {
            step(scrollAccumulator > 0 ? 1 : -1)
            scrollAccumulator = 0
        }
    }

    // MARK: Click and drag

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard dragRect != nil || hypot(point.x - start.x, point.y - start.y) > 3 else { return }
        dragRect = snapped(CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                                  width: abs(point.x - start.x), height: abs(point.y - start.y)), moving: point)
        animation?.invalidate()
        animation = nil
        shown = dragRect
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        if let drag = dragRect {
            dragRect = nil
            guard drag.width >= 4, drag.height >= 4 else { return }
            finish(globalRect: drag.offsetBy(dx: frozen.globalFrame.minX, dy: frozen.globalFrame.minY), windowID: nil)
        } else {
            captureHighlighted()
        }
    }

    private func captureHighlighted() {
        if regions.indices.contains(index) {
            let region = regions[index]
            finish(globalRect: region.rect, windowID: region.windowID)
        } else {
            finish(globalRect: frozen.globalFrame, windowID: nil)   // nothing under the pointer: the whole screen
        }
    }

    private func finish(globalRect: CGRect, windowID: CGWindowID?) {
        controller?.finish(rect: globalRect, windowID: windowID, on: frozen)
    }

    /// Pulls the dragged corner onto window and text edges within 6 points.
    private func snapped(_ rect: CGRect, moving point: CGPoint) -> CGRect {
        guard let edges = controller?.detector.snapEdges() else { return rect }
        let origin = frozen.globalFrame.origin
        func snap(_ value: CGFloat, _ candidates: [CGFloat], _ offset: CGFloat) -> CGFloat {
            let global = value + offset
            guard let best = candidates.min(by: { abs($0 - global) < abs($1 - global) }), abs(best - global) <= 6 else { return value }
            return best - offset
        }
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        if abs(point.x - rect.minX) < abs(point.x - rect.maxX) { minX = snap(minX, edges.x, origin.x) } else { maxX = snap(maxX, edges.x, origin.x) }
        if abs(point.y - rect.minY) < abs(point.y - rect.maxY) { minY = snap(minY, edges.y, origin.y) } else { maxY = snap(maxY, edges.y, origin.y) }
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 0), height: max(maxY - minY, 0))
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: controller?.cancel()                 // Esc
        case 36, 76: captureHighlighted()             // Return, Enter
        case 49: controller?.toggleWindowsOnly()      // Space
        case 126: step(1)                             // ↑ bigger
        case 125: step(-1)                            // ↓ smaller
        default: super.keyDown(with: event)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(frozen.image, in: bounds)
        ctx.restoreGState()

        let selection = shown.map { $0.integral.intersection(bounds) }
        // A soft spotlight: the rest of the screen dims gently, the selection stays untouched.
        let radius = selection.map { min(10, min($0.width, $0.height) / 4) } ?? 0
        let selectionPath = selection.map { CGPath(roundedRect: $0, cornerWidth: radius, cornerHeight: radius, transform: nil) }
        ctx.saveGState()
        ctx.addRect(bounds)
        if let selectionPath { ctx.addPath(selectionPath) }
        ctx.setFillColor(NSColor.black.withAlphaComponent(selection == nil ? 0.12 : 0.34).cgColor)
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()

        guard let selection, let selectionPath, !selection.isEmpty else { return }
        // Thin white edge, lifted by a soft shadow, with a faint inner line for definition on light content.
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 14, color: NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.addPath(selectionPath)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokePath()
        ctx.restoreGState()
        let inner = selection.insetBy(dx: 1.5, dy: 1.5)
        ctx.addPath(CGPath(roundedRect: inner, cornerWidth: max(radius - 1.5, 0), cornerHeight: max(radius - 1.5, 0), transform: nil))
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.18).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()

        drawLabel(for: selection)
    }

    /// A small dark pill under the selection: what it is and its size in pixels.
    private func drawLabel(for selection: CGRect) {
        let pixels = "\(Int((selection.width * frozen.scale).rounded())) × \(Int((selection.height * frozen.scale).rounded()))"
        let name = dragRect != nil ? nil : (regions.indices.contains(index) ? regions[index].label : nil)
        let text = NSMutableAttributedString()
        if let name {
            text.append(NSAttributedString(string: name + "   ", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.7)]))
        }
        text.append(NSAttributedString(string: pixels, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.white]))
        let size = text.size()
        let pillSize = CGSize(width: size.width + 18, height: size.height + 8)
        // Below the selection; above it if there's no room; inside the bottom edge as a last resort.
        var origin = CGPoint(x: selection.minX, y: selection.maxY + 8)
        if origin.y + pillSize.height > bounds.height - 70 {
            origin.y = selection.minY - pillSize.height - 8
            if origin.y < 6 { origin.y = selection.maxY - pillSize.height - 8 }
        }
        origin.x = min(max(origin.x, 6), bounds.width - pillSize.width - 6)
        let pill = CGRect(origin: origin, size: pillSize)
        let path = NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2)
        NSColor.black.withAlphaComponent(0.62).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        path.lineWidth = 1
        path.stroke()
        text.draw(at: CGPoint(x: pill.minX + 9, y: pill.minY + 4))
    }
}

// MARK: - Hint bar

private struct CaptureHint: View {
    @State private var smart = AXIsProcessTrusted()

    var body: some View {
        HStack(spacing: 14) {
            hint("Click", "capture")
            hint("Drag", "select area")
            hint("Scroll", "bigger · smaller")
            hint("Space", "windows")
            hint("Esc", "cancel")
            if !smart {
                Divider().frame(height: 14)
                Button("Turn on smart selection") {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    smart = AXIsProcessTrustedWithOptions(options)
                }
                .buttonStyle(.link)
                .help("Lets Screenshotty find buttons, panels and paragraphs in apps (Accessibility permission). Without it, text blocks and windows still work.")
            }
        }
        .font(.system(size: 12))
        .fixedSize()
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.72), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
    }

    private func hint(_ key: String, _ action: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
            Text(action)
        }
    }
}
