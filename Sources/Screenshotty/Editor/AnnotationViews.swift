import AppKit
import ScreenshottyCore
import SwiftUI

/// Transparent layer over the preview that turns drags into annotations.
/// Works in view points; converts to original-capture pixels through the model.
struct AnnotationOverlay: View {
    @ObservedObject var model: EditorModel
    /// View points per canvas pixel.
    let scale: CGFloat

    @State private var draft: Annotation?
    @State private var dragging: DragState?

    private enum DragState {
        case drawing(start: CGPoint)
        case moving(id: UUID, last: CGPoint)
        /// Select tool on empty canvas: becomes a drag of the finished image once the pointer moves.
        case idle
    }

    /// Where the gesture that started a drag-out began, so its later events are ignored.
    @State private var dragOutStart: CGPoint?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())

            if let draft {
                DraftShape(annotation: draft, model: model, scale: scale)
            }
            if let id = model.selectedID, let selected = model.annotations.first(where: { $0.id == id }) {
                SelectionOutline(annotation: selected, model: model, scale: scale)
            }
        }
        .gesture(dragGesture)
        .onHover { inside in
            if inside, model.tool != .select { NSCursor.crosshair.set() } else { NSCursor.arrow.set() }
        }
        .help(model.tool == .select ? "Drag the image into any app, or click an annotation to edit it" : "")
        .onChange(of: model.tool) { _, tool in
            if tool != .select { model.selectedID = nil }
        }
    }

    private func source(_ viewPoint: CGPoint) -> CGPoint {
        model.sourcePoint(fromCanvas: CGPoint(x: viewPoint.x / scale, y: viewPoint.y / scale))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if let start = dragOutStart {
                    if start == value.startLocation { return }   // still the same drag-out gesture
                    dragOutStart = nil
                    dragging = nil
                }
                if case .idle = dragging, hypot(value.translation.width, value.translation.height) > 4 {
                    dragOutStart = value.startLocation
                    dragging = nil
                    DragOut.begin(model)
                    return
                }
                let point = source(value.location)
                switch dragging {
                case nil:
                    begin(at: source(value.startLocation))
                    update(to: point)
                default:
                    update(to: point)
                }
            }
            .onEnded { value in
                if dragOutStart != nil {
                    dragOutStart = nil
                    dragging = nil
                    return
                }
                finish(viewDistance: hypot(value.translation.width, value.translation.height))
            }
    }

    private func begin(at point: CGPoint) {
        if let kind = model.tool.kind {
            dragging = .drawing(start: point)
            draft = Annotation(kind: kind, start: point, end: point, color: model.annotationColor)
            return
        }
        // Select tool: grab whatever is under the pointer (10 view points of slack).
        if let hit = model.annotation(at: point, tolerance: 10 / scale) {
            model.selectedID = hit.id
            model.beginMove()
            dragging = .moving(id: hit.id, last: point)
        } else {
            model.selectedID = nil
            dragging = .idle
        }
    }

    private func update(to point: CGPoint) {
        switch dragging {
        case .drawing:
            draft?.end = point
        case .moving(let id, let last):
            model.move(id, by: CGVector(dx: point.x - last.x, dy: point.y - last.y))
            dragging = .moving(id: id, last: point)
        default:
            break
        }
    }

    private func finish(viewDistance: CGFloat) {
        if case .drawing = dragging, let draft {
            // Ignore clicks and tiny accidental drags.
            let big = draft.kind == .arrow ? viewDistance > 8 : (draft.rect.width * scale > 6 && draft.rect.height * scale > 6)
            if big { model.add(draft) }
        }
        draft = nil
        dragging = nil
    }
}

/// Live preview of the annotation being drawn, before it is rendered into the image.
private struct DraftShape: View {
    let annotation: Annotation
    let model: EditorModel
    let scale: CGFloat

    var body: some View {
        let start = view(annotation.start)
        let end = view(annotation.end)
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        let lineWidth = max(model.annotationStrokeWidth * scale, 2)
        let color = annotation.color.swiftUIColor

        switch annotation.kind {
        case .arrow:
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth * 1.15, lineCap: .round))
        case .box:
            RoundedRectangle(cornerRadius: 4)
                .stroke(color, lineWidth: lineWidth)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
        case .blur:
            RoundedRectangle(cornerRadius: 3)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4])))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
        case .redact:
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(white: 0.07))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
        }
    }

    private func view(_ source: CGPoint) -> CGPoint {
        let canvas = model.canvasPoint(fromSource: source)
        return CGPoint(x: canvas.x * scale, y: canvas.y * scale)
    }
}

/// Dashed outline around the selected annotation.
private struct SelectionOutline: View {
    let annotation: Annotation
    let model: EditorModel
    let scale: CGFloat

    var body: some View {
        let a = view(annotation.start)
        let b = view(annotation.end)
        let pad: CGFloat = 6
        let rect = CGRect(x: min(a.x, b.x) - pad, y: min(a.y, b.y) - pad,
                          width: abs(b.x - a.x) + pad * 2, height: abs(b.y - a.y) + pad * 2)
        RoundedRectangle(cornerRadius: 5)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .allowsHitTesting(false)
    }

    private func view(_ source: CGPoint) -> CGPoint {
        let canvas = model.canvasPoint(fromSource: source)
        return CGPoint(x: canvas.x * scale, y: canvas.y * scale)
    }
}

/// Floating toolbar above the canvas: tools, colours, undo and delete.
struct AnnotationToolbar: View {
    @ObservedObject var model: EditorModel

    /// Colours only matter for arrows and boxes.
    private var showsColors: Bool {
        if model.tool == .arrow || model.tool == .box { return true }
        guard let id = model.selectedID, let selected = model.annotations.first(where: { $0.id == id }) else { return false }
        return selected.kind.usesColor
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationTool.allCases) { tool in
                Button {
                    model.tool = tool
                } label: {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 30, height: 26)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(model.tool == tool ? Color.accentColor.opacity(0.9) : .clear))
                        .foregroundStyle(model.tool == tool ? Color.white : Color.primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(tool.key), modifiers: [])
                .help("\(tool.title) (\(String(tool.key).uppercased()))")
                .accessibilityLabel(tool.title)
            }

            if showsColors {
            Divider().frame(height: 18).padding(.horizontal, 4)

            ForEach(Annotation.palette, id: \.self) { color in
                Button {
                    model.annotationColor = color
                } label: {
                    Circle()
                        .fill(color.swiftUIColor)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                        .padding(3)
                        .overlay(Circle().strokeBorder(model.annotationColor == color ? Color.accentColor : .clear, lineWidth: 2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Arrow and box colour")
            }
            }

            Divider().frame(height: 18).padding(.horizontal, 4)

            Button { model.undo() } label: {
                Image(systemName: "arrow.uturn.backward").frame(width: 26, height: 26).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canUndo)
            .help("Undo (⌘Z)")

            Button { model.deleteSelected() } label: {
                Image(systemName: "trash").frame(width: 26, height: 26).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.selectedID == nil)
            .help("Delete selected (⌫)")

            Divider().frame(height: 18).padding(.horizontal, 4)

            CompareButton(model: model)
        }
        .animation(.easeOut(duration: 0.15), value: showsColors)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }
}

/// Hold to see the capture exactly as it was taken.
struct CompareButton: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        Image(systemName: model.showOriginal ? "eye.fill" : "eye")
            .font(.system(size: 13, weight: .medium))
            .frame(width: 30, height: 26)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(model.showOriginal ? Color.accentColor.opacity(0.9) : .clear))
            .foregroundStyle(model.showOriginal ? Color.white : Color.primary)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !model.showOriginal { model.showOriginal = true } }
                .onEnded { _ in model.showOriginal = false })
            .help("Hold to compare with the original capture")
            .accessibilityLabel("Compare with original")
    }
}

/// Starts a standard macOS drag of the finished PNG from wherever the pointer is.
@MainActor
enum DragOut {
    private static let source = Source()

    final class Source: NSObject, NSDraggingSource {
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .copy
        }
    }

    static func begin(_ model: EditorModel) {
        guard let event = NSApp.currentEvent, let window = event.window ?? NSApp.keyWindow, let view = window.contentView,
              let image = try? model.renderFull(), let url = Exporter.temporaryFile(image) else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let width: CGFloat = 180
        let size = NSSize(width: width, height: width * CGFloat(image.height) / CGFloat(max(image.width, 1)))
        let point = view.convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                     width: size.width, height: size.height),
                              contents: NSImage(cgImage: image, size: size))
        view.beginDraggingSession(with: [item], event: event, source: source)
    }
}
