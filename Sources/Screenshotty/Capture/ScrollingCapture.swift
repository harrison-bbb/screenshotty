import AppKit
import ScreenCaptureKit
import ScreenshottyCore
import SwiftUI

/// Captures a page taller than the screen. You choose the area, then scroll (or let Screenshotty scroll);
/// frames are taken as the content moves and joined into one tall image.
@MainActor
final class ScrollingCapture {
    /// The tallest result, in pixels. Very wide areas get less, to keep memory reasonable.
    private static let maxHeight = 30_000
    private static let maxBytes = 400_000_000

    private let area: SmartCapture.PickedArea
    private let status = ScrollingStatus()
    private var outline: NSWindow?
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var continuation: CheckedContinuation<CaptureResult, Never>?
    private var stitcher: StitchSession?
    private var loop: Task<Void, Never>?
    private var counts: [String: Int] = [:]
    private var stream: FrameStream?
    private var onlyApp: String?
    private var autoScroll: Task<Void, Never>?
    /// When the image last grew.
    private var lastProgress = ContinuousClock.now
    /// Frames in a row that couldn't be matched.
    private var misses = 0

    private init(area: SmartCapture.PickedArea) {
        self.area = area
    }

    static func run() async -> CaptureResult {
        guard let area = await SmartCapture.pickArea() else { return .cancelled }
        guard area.rect.width >= 20, area.rect.height >= 40 else {
            Toast.show("Choose a bigger area to scroll", systemImage: "exclamationmark.triangle.fill")
            return .cancelled
        }
        return await run(area: area)
    }

    /// `onlyApp`: capture just that app's front window (for tests), never anything else on screen.
    static func run(area: SmartCapture.PickedArea, stopAfter seconds: Double? = nil, onlyApp: String? = nil) async -> CaptureResult {
        let capture = ScrollingCapture(area: area)
        capture.onlyApp = onlyApp
        if let seconds {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { capture.finish() }
        }
        return await withCheckedContinuation { continuation in
            capture.continuation = continuation
            capture.start()
        }
    }

    // MARK: Running

    private func start() {
        showOutline()
        showPanel()
        // Return finishes and Esc cancels, even while the app being scrolled is in front. This needs the
        // Accessibility permission; without it the panel's buttons still work.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                switch event.keyCode {
                case 53: self?.cancel()
                case 36, 76: self?.finish()
                default: break
                }
            }
        }
        loop = Task { [weak self] in await self?.run() }
    }

    private func run() async {
        // Started after our windows are up, so the outline and panel are left out of every frame.
        guard let stream = await FrameStream(area: area, ownWindows: [outline, panel].compactMap { $0 }.count, onlyApp: onlyApp) else {
            fail("Couldn't start the scrolling capture")
            return
        }
        self.stream = stream
        do {
            try await stream.start()
        } catch {
            Log.write("scrolling capture: stream failed: \(error.localizedDescription)")
            fail("Couldn't start the scrolling capture")
            return
        }
        defer { Log.write("scrolling capture frames: \(counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))") }
        // Frames arrive whenever the area changes; while one is being joined, only the newest waits.
        let debugFolder = ProcessInfo.processInfo.environment["SCREENSHOTTY_SCROLL_FRAMES"]
        var frameNumber = 0
        for await frame in stream.frames {
            guard continuation != nil else { return }
            if let debugFolder, frameNumber < 400 {
                // Development: keep every frame, to replay through the stitcher.
                try? PNGEncoder.write(frame, to: URL(fileURLWithPath: debugFolder).appendingPathComponent(String(format: "%04d.png", frameNumber)))
            }
            frameNumber += 1
            guard let stitcher else {
                let maxHeight = min(Self.maxHeight, Self.maxBytes / max(frame.width * 4, 1))
                stitcher = StitchSession(first: frame, ignoredRightColumns: Int(16 * area.screen.scale), maxHeight: maxHeight)
                if stitcher == nil { fail("Couldn't start the scrolling capture"); return }
                status.height = frame.height
                continue
            }
            let outcome = await stitcher.add(frame)
            counts[String(describing: outcome).components(separatedBy: "(")[0], default: 0] += 1
            switch outcome {
            case .added:
                status.height = await stitcher.height
                status.lost = false
                misses = 0
                lastProgress = .now
            case .noMatch:
                misses += 1
                if misses <= 3 || misses % 20 == 0 { Log.write("scrolling capture: no match (\(await stitcher.diagnosis))") }
                // Browsers show half-drawn frames while you flick (blank patches not painted yet); those don't
                // match, and the next proper frame does. Only warn when nothing has joined for a while.
                if misses >= 6, ContinuousClock.now - lastProgress > .milliseconds(1200) { status.lost = true }
            case .unchanged:
                // The view is back on content already joined: not lost.
                misses = 0
                status.lost = false
            case .full:
                status.full = true
                finish()
                return
            }
        }
    }

    func toggleAutoScroll() {
        if status.autoScrolling {
            status.autoScrolling = false
            return
        }
        guard AutoScroller.isAllowed else {
            AutoScroller.askForPermission()
            status.needsPermission = true
            return
        }
        status.needsPermission = false
        // The pointer has to be over the area for the app under it to scroll; it's left alone if it already is.
        if !AutoScroller.pointerIsInside(area.rect) { AutoScroller.movePointer(into: area.rect) }
        status.autoScrolling = true
        lastProgress = .now
        autoScroll = Task { [weak self] in
            var recoveries = 0
            while let self, self.status.autoScrolling, !Task.isCancelled {
                // Scroll events go to whatever is under the pointer. When it's moved off the area (to press
                // Done, say), pause instead of scrolling something else or pulling the pointer back.
                guard AutoScroller.pointerIsInside(self.area.rect) else {
                    self.status.autoPaused = true
                    self.lastProgress = .now
                    try? await Task.sleep(for: .milliseconds(150))
                    continue
                }
                self.status.autoPaused = false
                if self.status.lost, recoveries < 5 {
                    // Jumped too far (the page scrolled further than asked): go back up a little to find the place.
                    recoveries += 1
                    self.status.lost = false
                    self.misses = 0
                    await AutoScroller.scroll(by: -self.area.rect.height * 0.25, at: self.area.rect)
                    self.lastProgress = .now
                } else {
                    // A third of the area per step, so every step overlaps the last frame comfortably.
                    await AutoScroller.scroll(by: self.area.rect.height * 0.33, at: self.area.rect)
                }
                try? await Task.sleep(for: .milliseconds(180))
                // Nothing new for a while: the page reached its end.
                if ContinuousClock.now - self.lastProgress > .milliseconds(1800) {
                    self.finish()
                    return
                }
            }
        }
    }

    func finish() {
        guard continuation != nil else { return }
        loop?.cancel()
        stream?.stop()
        Task {
            let image = await stitcher?.image()
            close()
            if let image {
                Log.write("scrolling capture: \(image.width)x\(image.height)")
                resume(.image(image))
            } else {
                resume(.cancelled)
            }
        }
    }

    func cancel() {
        guard continuation != nil else { return }
        loop?.cancel()
        close()
        resume(.cancelled)
    }

    private func fail(_ message: String) {
        close()
        Toast.show(message, systemImage: "exclamationmark.triangle.fill")
        resume(.cancelled)
    }

    private func resume(_ result: CaptureResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }

    private func close() {
        status.autoScrolling = false
        autoScroll?.cancel()
        stream?.stop()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        outline?.orderOut(nil)
        panel?.orderOut(nil)
        outline = nil
        panel = nil
    }

    // MARK: Windows

    /// AppKit's bottom-left frame for a global top-left rect.
    private func appKitFrame(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: ScreenFreezer.mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// A dashed outline just outside the area; clicks and scrolling pass through it.
    private func showOutline() {
        let frame = appKitFrame(area.rect).insetBy(dx: -4, dy: -4)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ScrollingOutline(status: status))
        window.orderFrontRegardless()
        outline = window
    }

    private func showPanel() {
        let view = NSHostingView(rootView: ScrollingPanel(status: status, capture: self))
        let size = view.fittingSize
        let frame = appKitFrame(area.rect)
        let screen = area.screen.screen.visibleFrame
        // Under the area, or above it, or inside its bottom edge when it fills the screen.
        var origin = CGPoint(x: frame.midX - size.width / 2, y: frame.minY - size.height - 14)
        if origin.y < screen.minY + 8 {
            origin.y = frame.maxY + 14
            if origin.y + size.height > screen.maxY - 8 { origin.y = frame.minY + 24 }
        }
        origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
        let panel = NSPanel(contentRect: CGRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        panel.orderFrontRegardless()
        self.panel = panel
    }
}

// MARK: - Testing

/// Captures a fixed area for a few seconds while something else scrolls it, writes the result and quits.
/// For checking stitching against real apps without touching the pointer:
///
///     open -n build/Screenshotty.app --env SCREENSHOTTY_SCROLL_TEST=100,100,800,700 \
///         --env SCREENSHOTTY_SCROLL_TEST_OUT=/tmp/out.png [--env SCREENSHOTTY_SCROLL_TEST_SECONDS=12] \
///         [--env SCREENSHOTTY_SCROLL_TEST_APP=name]    (capture only that app's window, nothing else on screen)
///         [--env SCREENSHOTTY_SCROLL_FRAMES=folder]    (also keep every frame as a PNG, to replay through the stitcher)
@MainActor
enum ScrollTest {
    private static let env = ProcessInfo.processInfo.environment
    static var isRequested: Bool { env["SCREENSHOTTY_SCROLL_TEST"] != nil }

    static func run() {
        let numbers = (env["SCREENSHOTTY_SCROLL_TEST"] ?? "").split(separator: ",").compactMap { Double($0) }
        guard numbers.count == 4, let out = env["SCREENSHOTTY_SCROLL_TEST_OUT"],
              let screen = NSScreen.screens.first,
              let blank = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage() else { exit(1) }
        let rect = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        let area = SmartCapture.PickedArea(rect: rect, screen: FrozenScreen(screen: screen, image: blank,
                                                                            globalFrame: ScreenFreezer.globalFrame(of: screen)))
        Task { @MainActor in
            let result = await ScrollingCapture.run(area: area, stopAfter: Double(env["SCREENSHOTTY_SCROLL_TEST_SECONDS"] ?? "") ?? 12,
                                                    onlyApp: env["SCREENSHOTTY_SCROLL_TEST_APP"])
            guard case .image(let image) = result else { Log.write("scroll test: no image"); exit(1) }
            try? PNGEncoder.write(image, to: URL(fileURLWithPath: out))
            Log.write("scroll test: wrote \(image.width)x\(image.height)")
            exit(0)
        }
    }
}

// MARK: - Frames

/// A live stream of the area, leaving Screenshotty's own windows out. Frames come only when something in
/// the area changes, up to 60 a second, so fast scrolling still overlaps from one frame to the next.
private final class FrameStream: NSObject, SCStreamOutput, @unchecked Sendable {
    let frames: AsyncStream<CGImage>
    private let continuation: AsyncStream<CGImage>.Continuation
    private let stream: SCStream
    private let queue = DispatchQueue(label: "screenshotty.scrolling-frames", qos: .userInteractive)

    /// `ownWindows`: how many windows Screenshotty is showing (outline and panel), to leave out of every frame.
    init?(area: SmartCapture.PickedArea, ownWindows: Int, onlyApp: String? = nil) async {
        let pid = ProcessInfo.processInfo.processIdentifier
        // Windows that were only just ordered in can take a moment to be listed; wait for them, briefly.
        var content: SCShareableContent?
        var own: [SCWindow] = []
        for _ in 0 ..< 20 {
            content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            own = content?.windows.filter { $0.owningApplication?.processID == pid } ?? []
            if own.count >= ownWindows { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        let number = area.screen.screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        guard let content, let display = content.displays.first(where: { $0.displayID == number?.uint32Value }) else { return nil }
        if own.count < ownWindows { Log.write("scrolling capture: only \(own.count) of our windows listed") }

        let scale = area.screen.scale
        let local = area.rect.offsetBy(dx: -area.screen.globalFrame.minX, dy: -area.screen.globalFrame.minY)
            .intersection(CGRect(origin: .zero, size: area.screen.globalFrame.size))
        var filter = SCContentFilter(display: display, excludingWindows: own)
        var source = local
        if let onlyApp {
            guard let window = content.windows.first(where: { $0.owningApplication?.applicationName == onlyApp && $0.windowLayer >= 0 && $0.frame.width > 100 })
            else { return nil }
            filter = SCContentFilter(desktopIndependentWindow: window)
            source = area.rect.offsetBy(dx: -window.frame.minX, dy: -window.frame.minY)
        }
        let config = SCStreamConfiguration()
        config.sourceRect = source
        config.width = Int((local.width * scale).rounded())
        config.height = Int((local.height * scale).rounded())
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.queueDepth = 4
        if let name = area.screen.screen.colorSpace?.cgColorSpace?.name { config.colorSpaceName = name }

        (frames, continuation) = AsyncStream.makeStream(of: CGImage.self, bufferingPolicy: .bufferingNewest(1))
        stream = SCStream(filter: filter, configuration: config, delegate: nil)
        super.init()
        do { try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue) } catch { return nil }
    }

    func start() async throws { try await stream.startCapture() }

    func stop() {
        continuation.finish()
        let stream = stream
        Task { try? await stream.stopCapture() }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid,
              let info = (CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              let rawStatus = info[.status] as? Int, SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixels = buffer.imageBuffer, let image = Self.image(from: pixels) else { return }
        continuation.yield(image)
    }

    /// Copies a BGRA frame into an image of its own. The stream reuses its buffers, so an image that only
    /// pointed at one could change later. The alpha byte is ignored: the stream doesn't always fill it in,
    /// and a frame read as see-through comes out dark and never matches the others.
    private static func image(from pixels: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels) else { return nil }
        let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels)
        let sourceRow = CVPixelBufferGetBytesPerRow(pixels), row = width * 4
        var bytes = Data(count: row * height)
        bytes.withUnsafeMutableBytes { target in
            for y in 0 ..< height {
                (target.baseAddress! + y * row).copyMemory(from: base + y * sourceRow, byteCount: row)
            }
        }
        let space = CVImageBufferGetColorSpace(pixels)?.takeUnretainedValue() ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: row, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// Does the joining away from the main thread.
private actor StitchSession {
    private let stitcher: ScrollStitcher

    init?(first: CGImage, ignoredRightColumns: Int, maxHeight: Int) {
        guard let stitcher = ScrollStitcher(first: first, ignoredRightColumns: ignoredRightColumns, maxHeight: maxHeight) else { return nil }
        self.stitcher = stitcher
    }

    func add(_ frame: CGImage) -> ScrollStitcher.Outcome { stitcher.add(frame) }
    var diagnosis: String { stitcher.diagnosis }
    var height: Int { stitcher.height }
    func image() -> CGImage? { stitcher.image() }
}

// MARK: - Auto-scroll

/// Scrolls the app under the area by sending scroll-wheel events (needs the Accessibility permission).
private enum AutoScroller {
    static var isAllowed: Bool { AXIsProcessTrusted() }

    static func askForPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Scroll events go to whatever is under the pointer, so it has to be inside the area.
    static func movePointer(into rect: CGRect) {
        let point = CGPoint(x: rect.midX, y: rect.midY)
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    /// Whether the pointer is over `rect` (global top-left points).
    static func pointerIsInside(_ rect: CGRect) -> Bool {
        let location = NSEvent.mouseLocation
        return rect.contains(CGPoint(x: location.x, y: ScreenFreezer.mainHeight - location.y))
    }

    /// Scrolls whatever is under the pointer down by about `points` (up when negative), in small steps like
    /// a trackpad: some apps ignore or cap one big jump. The events don't move the pointer.
    static func scroll(by points: CGFloat, at rect: CGRect) async {
        let steps = max(Int((abs(points) / 40).rounded(.up)), 1)
        let step = Int32((points / CGFloat(steps)).rounded())
        for _ in 0 ..< steps {
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                      wheel1: -step, wheel2: 0, wheel3: 0) else { return }
            event.post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(8))
        }
    }
}

// MARK: - Views

@MainActor
final class ScrollingStatus: ObservableObject {
    @Published var height = 0
    @Published var lost = false
    @Published var full = false
    @Published var autoScrolling = false
    /// Auto-scroll is waiting for the pointer to come back over the area.
    @Published var autoPaused = false
    @Published var needsPermission = false
}

private struct ScrollingOutline: View {
    @ObservedObject var status: ScrollingStatus

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            .foregroundStyle(status.lost ? Color.orange : Color.accentColor)
            .shadow(color: .black.opacity(0.35), radius: 3)
            .padding(1)
    }
}

private struct ScrollingPanel: View {
    @ObservedObject var status: ScrollingStatus
    let capture: ScrollingCapture

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(status.lost ? Color.orange : .secondary)
            }
            .frame(width: 230, alignment: .leading)
            Button(status.autoScrolling ? "Stop" : "Auto-scroll") { capture.toggleAutoScroll() }
                .help("Screenshotty scrolls for you and stops at the bottom (needs the Accessibility permission)")
            Button("Cancel") { capture.cancel() }
            Button("Done") { capture.finish() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.regular)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.1)))
        .padding(10)
    }

    private var title: String {
        if status.autoScrolling { return status.autoPaused ? "Auto-scroll paused" : "Scrolling…" }
        return status.height == 0 ? "Getting ready…" : "Scroll down slowly"
    }

    private var detail: String {
        if status.needsPermission { return "Allow Screenshotty in Accessibility, then try again" }
        if status.autoScrolling, status.autoPaused { return "Move the pointer back over the area to carry on" }
        if status.lost { return "Lost my place. Scroll back up a little." }
        if status.full { return "That's as tall as it goes" }
        return status.height == 0 ? "Press Done when you reach the end" : "\(status.height.formatted()) px so far · Done when finished"
    }
}
