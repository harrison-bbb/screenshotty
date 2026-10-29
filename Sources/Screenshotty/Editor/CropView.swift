import ScreenshottyCore
import SwiftUI

/// The crop tool: the whole capture with a box you can resize from any edge or corner, or drag to move.
/// Done applies it; the finished image then updates from the cropped area.
struct CropView: View {
    @ObservedObject var model: EditorModel
    /// Where the capture is shown, in the canvas' coordinates.
    let frame: CGRect

    @State private var draft: CGRect = .zero
    @State private var dragStart: CGRect?
    @State private var dragMode: DragMode?

    private enum DragMode { case move, new(CGPoint), edges(left: Bool, right: Bool, top: Bool, bottom: Bool) }

    private var imageSize: CGSize { CGSize(width: model.source.width, height: model.source.height) }
    private var scale: CGFloat { frame.width / imageSize.width }
    private var full: CGRect { CGRect(origin: .zero, size: imageSize) }

    private func toView(_ r: CGRect) -> CGRect {
        CGRect(x: frame.minX + r.minX * scale, y: frame.minY + r.minY * scale, width: r.width * scale, height: r.height * scale)
    }

    private func toImage(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - frame.minX) / scale, y: (p.y - frame.minY) / scale)
    }

    var body: some View {
        let box = toView(draft)
        ZStack(alignment: .topLeading) {
            Image(decorative: model.source, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)

            // Dim everything outside the box.
            Path { path in
                path.addRect(frame)
                path.addRect(box)
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))

            // What auto-trim kept, for reference.
            if let auto = model.autoContentRect, model.crop == nil {
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(width: toView(auto).width, height: toView(auto).height)
                    .offset(x: toView(auto).minX, y: toView(auto).minY)
                    .allowsHitTesting(false)
            }

            // Box, thirds and handles.
            Path { path in
                for i in 1...2 {
                    let x = box.minX + box.width * CGFloat(i) / 3
                    let y = box.minY + box.height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: box.minY)); path.addLine(to: CGPoint(x: x, y: box.maxY))
                    path.move(to: CGPoint(x: box.minX, y: y)); path.addLine(to: CGPoint(x: box.maxX, y: y))
                }
            }
            .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
            Rectangle()
                .strokeBorder(Color.white, lineWidth: 1.5)
                .frame(width: box.width, height: box.height)
                .offset(x: box.minX, y: box.minY)
            ForEach(Array(handlePoints(box).enumerated()), id: \.offset) { _, point in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: 9, height: 9)
                    .shadow(color: .black.opacity(0.4), radius: 1.5)
                    .offset(x: point.x - 4.5, y: point.y - 4.5)
            }

            controls
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 10)
        }
        .contentShape(Rectangle())
        .gesture(dragGesture(box: box))
        .onAppear { draft = model.crop ?? full }
        .onHover { inside in if inside { NSCursor.crosshair.set() } else { NSCursor.arrow.set() } }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Label("\(Int(draft.width)) × \(Int(draft.height))", systemImage: "crop")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Divider().frame(height: 16)
            Button("Reset") { draft = full }
                .disabled(draft == full)
            Button("Cancel", role: .cancel) { model.tool = .select }
                .keyboardShortcut(.cancelAction)
            Button("Done") {
                model.setCrop(draft)
                model.tool = .select
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }

    private func handlePoints(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
         CGPoint(x: r.minX, y: r.midY), CGPoint(x: r.maxX, y: r.midY),
         CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
    }

    private func dragGesture(box: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = draft
                    dragMode = mode(at: value.startLocation, box: box)
                }
                guard let start = dragStart, let mode = dragMode else { return }
                let dx = value.translation.width / scale
                let dy = value.translation.height / scale
                draft = adjusted(start, mode: mode, dx: dx, dy: dy, location: toImage(value.location))
            }
            .onEnded { _ in
                dragStart = nil
                dragMode = nil
            }
    }

    /// Which part of the box a drag starting at `point` grabs (12 points of slack around edges).
    private func mode(at point: CGPoint, box: CGRect) -> DragMode {
        let slack: CGFloat = 12
        let nearLeft = abs(point.x - box.minX) < slack
        let nearRight = abs(point.x - box.maxX) < slack
        let nearTop = abs(point.y - box.minY) < slack
        let nearBottom = abs(point.y - box.maxY) < slack
        let withinX = point.x > box.minX - slack && point.x < box.maxX + slack
        let withinY = point.y > box.minY - slack && point.y < box.maxY + slack
        if withinX, withinY, nearLeft || nearRight || nearTop || nearBottom {
            return .edges(left: nearLeft, right: nearRight && !nearLeft, top: nearTop, bottom: nearBottom && !nearTop)
        }
        if box.contains(point) { return .move }
        return .new(toImage(point))
    }

    private func adjusted(_ start: CGRect, mode: DragMode, dx: CGFloat, dy: CGFloat, location: CGPoint) -> CGRect {
        let minSize: CGFloat = 16
        var r = start
        switch mode {
        case .move:
            r.origin.x = min(max(start.minX + dx, 0), full.width - start.width)
            r.origin.y = min(max(start.minY + dy, 0), full.height - start.height)
        case .new(let anchor):
            let p = CGPoint(x: min(max(location.x, 0), full.width), y: min(max(location.y, 0), full.height))
            r = CGRect(x: min(anchor.x, p.x), y: min(anchor.y, p.y), width: abs(p.x - anchor.x), height: abs(p.y - anchor.y))
        case .edges(let left, let right, let top, let bottom):
            var minX = start.minX, maxX = start.maxX, minY = start.minY, maxY = start.maxY
            if left { minX = min(max(start.minX + dx, 0), maxX - minSize) }
            if right { maxX = max(min(start.maxX + dx, full.width), minX + minSize) }
            if top { minY = min(max(start.minY + dy, 0), maxY - minSize) }
            if bottom { maxY = max(min(start.maxY + dy, full.height), minY + minSize) }
            r = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        return r.integral.intersection(full)
    }
}
