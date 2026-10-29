import AppKit
import ScreenshottyCore
import SwiftUI

/// The floating card that appears in the corner after a capture: the finished image with Copy, Save
/// and Edit, which can also be dragged straight into another app. It slides away on its own.
@MainActor
final class QuickPreviewManager {
    static let shared = QuickPreviewManager()

    private var items: [QuickPreviewItem] = []
    private let margin: CGFloat = 20
    private let spacing: CGFloat = 12
    private let maxVisible = 4

    func show(_ image: CGImage) {
        let item = QuickPreviewItem(source: image, settings: Preferences.shared.lastSettings)
        item.onDismiss = { [weak self, weak item] in
            guard let self, let item else { return }
            self.items.removeAll { $0 === item }
            self.layout(animated: true)
        }
        items.insert(item, at: 0)
        while items.count > maxVisible { items.removeLast().dismiss(animated: false) }
        layout(animated: true, appearing: item)
    }

    /// Newest card sits in the bottom-left corner, older ones stack above it.
    private func layout(animated: Bool, appearing: QuickPreviewItem? = nil) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        var y = frame.minY + margin
        for item in items {
            let size = item.panel.frame.size
            let target = NSPoint(x: frame.minX + margin, y: y)
            if item === appearing {
                item.panel.setFrameOrigin(NSPoint(x: target.x - 60, y: target.y))
                item.panel.alphaValue = 0
                item.panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.28
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    item.panel.animator().setFrameOrigin(target)
                    item.panel.animator().alphaValue = 1
                }
            } else if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    item.panel.animator().setFrameOrigin(target)
                }
            } else {
                item.panel.setFrameOrigin(target)
            }
            y += size.height + spacing
        }
    }
}

@MainActor
final class QuickPreviewItem: ObservableObject {
    let source: CGImage
    let settings: CompositionSettings
    @Published var thumbnail: CGImage?
    @Published var copied = false
    var onDismiss: (() -> Void)?

    private(set) var panel: NSPanel!
    private var hideWork: DispatchWorkItem?
    private var finished: CGImage?
    private var isHovering = false
    private var dismissed = false

    /// How long the card stays when left alone.
    private let lifetime: TimeInterval = 10

    init(source: CGImage, settings: CompositionSettings) {
        self.source = source
        self.settings = settings.resolved(for: source)
        let width: CGFloat = 280
        let layout = CompositionLayout(imageSize: CGSize(width: source.width, height: source.height), settings: self.settings)
        let aspect = layout.canvasSize.height / max(layout.canvasSize.width, 1)
        let thumbHeight = min(max((width - 20) * aspect, 90), 260)

        let host = FirstClickHostingView(rootView: QuickPreviewView(item: self, thumbHeight: thumbHeight))
        let size = NSSize(width: width, height: thumbHeight + 66)
        host.frame = NSRect(origin: .zero, size: size)
        let panel = QuickPreviewPanel(contentRect: NSRect(origin: .zero, size: size),
                                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = host
        self.panel = panel

        renderThumbnail(maxSide: (width - 20) * 2)
        scheduleHide()
    }

    private func renderThumbnail(maxSide: CGFloat) {
        let source = source
        let settings = settings
        Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                let prepared = ShotPreparer.prepareShot(source, settings: settings)
                let layout = CompositionLayout(imageSize: CGSize(width: prepared.image.width, height: prepared.image.height),
                                               settings: settings)
                let scale = min(1, maxSide / max(layout.canvasSize.width, layout.canvasSize.height))
                return try? Compositor.render(prepared.image, settings: settings, scale: scale)
            }.value
            self?.thumbnail = image
        }
    }

    /// The full-resolution result, made once and reused.
    func finishedImage() -> CGImage? {
        if let finished { return finished }
        finished = try? Compositor.compose(source, settings: settings,
                                           minimumLongSide: Preferences.shared.exportMinimumLongSide)
        return finished
    }

    // MARK: Actions

    func copy() {
        guard let image = finishedImage() else { return }
        Exporter.copyToPasteboard(image)
        copied = true
        hideWork?.cancel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.dismiss() }
    }

    func save() {
        guard let image = finishedImage() else { return }
        do {
            let url = try Exporter.save(image, in: Preferences.shared.saveFolder)
            Toast.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)")
            dismiss()
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }

    func edit() {
        WindowManager.shared.openEditor(with: source)
        dismiss()
    }

    func dragProvider() -> NSItemProvider {
        guard let image = finishedImage(), let url = Exporter.temporaryFile(image),
              let provider = NSItemProvider(contentsOf: url) else { return NSItemProvider() }
        provider.suggestedName = url.deletingPathExtension().lastPathComponent
        return provider
    }

    func hover(_ inside: Bool) {
        isHovering = inside
        if inside { hideWork?.cancel() } else if !copied { scheduleHide() }
    }

    private func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isHovering else { return }
            self.dismiss()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime, execute: work)
    }

    func dismiss(animated: Bool = true) {
        guard !dismissed else { return }
        dismissed = true
        hideWork?.cancel()
        let panel = panel!
        onDismiss?()
        guard animated else { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(NSPoint(x: panel.frame.minX - 60, y: panel.frame.minY))
        }, completionHandler: { panel.orderOut(nil) })
    }
}

/// Borderless panels can't become key by default, which would swallow the first click on a button.
private final class QuickPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct QuickPreviewView: View {
    @ObservedObject var item: QuickPreviewItem
    let thumbHeight: CGFloat
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let thumbnail = item.thumbnail {
                        Image(decorative: thumbnail, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .onTapGesture { item.edit() }
                .onDrag { item.dragProvider() }
                .help("Click to edit, or drag into any app")

                if item.copied {
                    Label("Copied", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.scale.combined(with: .opacity))
                }

                Button { item.dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(.regularMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.2)))
                }
                .buttonStyle(.plain)
                .padding(6)
                .opacity(hovering ? 1 : 0)
                .help("Dismiss")
            }
            .frame(height: thumbHeight)

            HStack(spacing: 6) {
                Button { item.copy() } label: {
                    Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button { item.save() } label: {
                    Label("Save", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
                }
                Button { item.edit() } label: {
                    Label("Edit", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
                }
            }
            .controlSize(.regular)
            .labelStyle(.titleAndIcon)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12)))
        .animation(.spring(duration: 0.25), value: item.copied)
        .onHover { inside in
            hovering = inside
            item.hover(inside)
        }
    }
}
