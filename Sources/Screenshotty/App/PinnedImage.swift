import AppKit
import ScreenshottyCore

/// Screenshots pinned above every window, to keep as a reference while you work.
///
/// Drag to move · scroll or pinch to resize · double-click or Esc to close · right-click for more.
@MainActor
enum PinnedImages {
    private static var windows: [PinnedWindow] = []

    static func pin(_ image: CGImage) {
        let window = PinnedWindow(image: image)
        window.onClose = { [weak window] in windows.removeAll { $0 === window } }
        windows.append(window)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

final class PinnedWindow: NSPanel {
    var onClose: (() -> Void)?
    let image: CGImage
    let aspect: CGFloat

    init(image: CGImage) {
        self.image = image
        aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        // Shown at its real size, unless that's more than half the screen.
        let scale = screen?.backingScaleFactor ?? 2
        var size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let fit = min(1, visible.width * 0.5 / size.width, visible.height * 0.6 / size.height)
        size = CGSize(width: max(size.width * fit, 40), height: max(size.height * fit, 40))
        // Near the top right, cascading so several pins don't stack exactly.
        let offset = CGFloat(NSApp.windows.filter { $0 is PinnedWindow && $0.isVisible }.count % 6) * 24
        let origin = CGPoint(x: visible.maxX - size.width - 40 - offset, y: visible.maxY - size.height - 40 - offset)
        super.init(contentRect: CGRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = PinnedView(window: self)
    }

    override var canBecomeKey: Bool { true }

    override func close() {
        super.close()
        onClose?()
        onClose = nil
    }

    /// Grows or shrinks around the centre, keeping the shape.
    func resize(by factor: CGFloat) {
        let current = frame
        let width = min(max(current.width * factor, 40), 4000)
        let height = width / aspect
        guard height >= 40 else { return }
        setFrame(CGRect(x: current.midX - width / 2, y: current.midY - height / 2, width: width, height: height), display: true)
        contentView.map { invalidateCursorRects(for: $0) }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close() } else { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
            copyImage()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc func copyImage() {
        Exporter.copyToPasteboard(image)
        Toast.show("Copied to clipboard")
    }

    @objc func copyText() { TextCopier.copyText(from: image) }

    @objc func edit() {
        WindowManager.shared.openEditor(with: image)
        close()
    }

    @objc func save() {
        do {
            let url = try Exporter.save(image, in: Preferences.shared.saveFolder)
            Toast.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)")
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc func setOpacity(_ sender: NSMenuItem) {
        alphaValue = CGFloat(sender.tag) / 100
    }

    @objc func actualSize() {
        let scale = screen?.backingScaleFactor ?? 2
        let width = CGFloat(image.width) / scale
        resize(by: width / frame.width)
    }
}

private final class PinnedView: NSView {
    private unowned let pinned: PinnedWindow
    private let closeButton: NSButton

    init(window: PinnedWindow) {
        pinned = window
        closeButton = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")!,
                               target: window, action: #selector(NSWindow.close))
        super.init(frame: CGRect(origin: .zero, size: window.frame.size))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.black.withAlphaComponent(0.15).cgColor
        layer?.contents = window.image
        layer?.contentsGravity = .resize
        layer?.magnificationFilter = .linear

        closeButton.isBordered = false
        closeButton.symbolConfiguration = .init(pointSize: 16, weight: .semibold)
        closeButton.contentTintColor = .white
        closeButton.shadow = { let s = NSShadow(); s.shadowBlurRadius = 3; s.shadowColor = .black.withAlphaComponent(0.6); return s }()
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isHidden = true
        closeButton.toolTip = "Close (Esc)"
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 6),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate,
                                                                    .activeAlways, .inVisibleRect], owner: self))
        toolTip = "Drag to move, drag an edge or scroll to resize, double-click to close"
    }

    // MARK: Resizing from the edges

    /// Which edges a point is near (within the grab margin), in this view's bottom-left coordinates.
    private struct Grip: Equatable {
        var left = false, right = false, top = false, bottom = false
        var isEmpty: Bool { !(left || right || top || bottom) }
    }

    private static let margin: CGFloat = 7

    private func grip(at point: CGPoint) -> Grip {
        let m = min(Self.margin, bounds.width / 4, bounds.height / 4)
        return Grip(left: point.x < m, right: point.x > bounds.width - m, top: point.y > bounds.height - m, bottom: point.y < m)
    }

    private func cursor(for grip: Grip) -> NSCursor {
        if #available(macOS 15, *) {
            let position: NSCursor.FrameResizePosition = switch (grip.left, grip.right, grip.top, grip.bottom) {
            case (true, _, true, _): .topLeft
            case (_, true, true, _): .topRight
            case (true, _, _, true): .bottomLeft
            case (_, true, _, true): .bottomRight
            case (true, _, _, _): .left
            case (_, true, _, _): .right
            case (_, _, true, _): .top
            default: .bottom
            }
            return NSCursor.frameResize(position: position, directions: .all)
        }
        return grip.left || grip.right ? .resizeLeftRight : .resizeUpDown
    }

    override func resetCursorRects() {
        let m = min(Self.margin, bounds.width / 4, bounds.height / 4)
        let w = bounds.width, h = bounds.height
        let zones: [(CGRect, Grip)] = [
            (CGRect(x: m, y: 0, width: w - 2 * m, height: m), Grip(bottom: true)),
            (CGRect(x: m, y: h - m, width: w - 2 * m, height: m), Grip(top: true)),
            (CGRect(x: 0, y: m, width: m, height: h - 2 * m), Grip(left: true)),
            (CGRect(x: w - m, y: m, width: m, height: h - 2 * m), Grip(right: true)),
            (CGRect(x: 0, y: 0, width: m, height: m), Grip(left: true, bottom: true)),
            (CGRect(x: w - m, y: 0, width: m, height: m), Grip(right: true, bottom: true)),
            (CGRect(x: 0, y: h - m, width: m, height: m), Grip(left: true, top: true)),
            (CGRect(x: w - m, y: h - m, width: m, height: m), Grip(right: true, top: true)),
        ]
        for (rect, grip) in zones { addCursorRect(rect, cursor: cursor(for: grip)) }
    }

    /// Follows the pointer until the button is released, resizing from the grabbed edges and keeping the
    /// picture's shape. The opposite edge or corner stays where it is.
    private func resize(from event: NSEvent, grip: Grip) {
        guard let window = self.window else { return }
        let start = window.frame
        let startPoint = NSEvent.mouseLocation
        let aspect = pinned.aspect
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), next.type == .leftMouseDragged {
            let point = NSEvent.mouseLocation
            let dx = point.x - startPoint.x, dy = point.y - startPoint.y
            // Sideways edges and corners follow the pointer's horizontal movement; top and bottom its vertical.
            var width = start.width
            if grip.left { width = start.width - dx } else if grip.right { width = start.width + dx }
            else if grip.top { width = (start.height + dy) * aspect } else if grip.bottom { width = (start.height - dy) * aspect }
            width = min(max(width, 60), 4000)
            let height = width / aspect
            var frame = CGRect(x: start.minX, y: start.minY, width: width, height: height)
            if grip.left { frame.origin.x = start.maxX - width } else if !grip.right { frame.origin.x = start.midX - width / 2 }
            if grip.bottom { frame.origin.y = start.maxY - height } else if !grip.top { frame.origin.y = start.midY - height / 2 }
            window.setFrame(frame, display: true)
        }
        window.invalidateCursorRects(for: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { closeButton.isHidden = false }
    override func mouseExited(with event: NSEvent) { closeButton.isHidden = true }
    // Cursor rects only work in the key window; these keep the resize pointers right while another app is in front.
    override func mouseMoved(with event: NSEvent) { updateCursor(event) }
    override func cursorUpdate(with event: NSEvent) { updateCursor(event) }

    private func updateCursor(_ event: NSEvent) {
        let edges = grip(at: convert(event.locationInWindow, from: nil))
        (edges.isEmpty ? NSCursor.arrow : cursor(for: edges)).set()
    }

    override func mouseDown(with event: NSEvent) {
        let edges = grip(at: convert(event.locationInWindow, from: nil))
        if event.clickCount == 2 {
            pinned.close()
        } else if !edges.isEmpty {
            resize(from: event, grip: edges)
        } else {
            pinned.makeKey()
            pinned.performDrag(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.004 : 0.04)
        guard delta != 0 else { return }
        pinned.resize(by: 1 + max(min(delta, 0.3), -0.3))
    }

    override func magnify(with event: NSEvent) {
        pinned.resize(by: 1 + event.magnification)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, tag: Int = 0) -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = pinned
            item.tag = tag
            return item
        }
        _ = add("Copy", #selector(PinnedWindow.copyImage))
        _ = add("Copy Text", #selector(PinnedWindow.copyText))
        _ = add("Save", #selector(PinnedWindow.save))
        _ = add("Edit…", #selector(PinnedWindow.edit))
        menu.addItem(.separator())
        _ = add("Actual Size", #selector(PinnedWindow.actualSize))
        let opacity = NSMenu()
        for percent in [100, 80, 60, 40] {
            let item = opacity.addItem(withTitle: "\(percent)%", action: #selector(PinnedWindow.setOpacity(_:)), keyEquivalent: "")
            item.target = pinned
            item.tag = percent
            item.state = Int((pinned.alphaValue * 100).rounded()) == percent ? .on : .off
        }
        menu.addItem(withTitle: "Opacity", action: nil, keyEquivalent: "").submenu = opacity
        menu.addItem(.separator())
        _ = add("Close", #selector(NSWindow.close))
        return menu
    }
}

/// Copies the text in an image to the clipboard.
@MainActor
enum TextCopier {
    static func copyText(from image: CGImage) {
        Toast.show("Reading text…", systemImage: "text.viewfinder")
        Task {
            let text = await Task.detached(priority: .userInitiated) { TextRecognizer.text(in: image) }.value
            guard !text.isEmpty else {
                Toast.show("No text found", systemImage: "exclamationmark.triangle.fill")
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            // Show what was copied, so you know it's right without pasting.
            let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let preview = flat.count > 48 ? flat.prefix(46) + "…" : Substring(flat)
            Toast.show("Copied “\(preview)”", systemImage: "text.viewfinder")
        }
    }
}
