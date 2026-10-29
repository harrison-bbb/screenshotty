import ScreenshottyCore
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @ObservedObject var model: EditorModel
    let actions: EditorActions

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                CanvasView(model: model)
                Divider()
                ActionBar(model: model, actions: actions)
            }
            .frame(minWidth: 520)
            Divider()
            InspectorView(model: model)
                .frame(width: 310)
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}

private struct CanvasView: View {
    @ObservedObject var model: EditorModel
    @State private var isDropTarget = false

    /// Space around the preview inside the canvas area (top leaves room for the toolbar).
    private let insets = EdgeInsets(top: 92, leading: 36, bottom: 28, trailing: 36)

    var body: some View {
        GeometryReader { geo in
            let canvas = model.outputSize
            let available = CGSize(width: max(geo.size.width - insets.leading - insets.trailing, 1),
                                   height: max(geo.size.height - insets.top - insets.bottom, 1))
            let scale = min(available.width / canvas.width, available.height / canvas.height)
            let size = CGSize(width: canvas.width * scale, height: canvas.height * scale)
            let origin = CGPoint(x: insets.leading + (available.width - size.width) / 2,
                                 y: insets.top + (available.height - size.height) / 2)

            ZStack(alignment: .topLeading) {
                Color(nsColor: .underPageBackgroundColor)

                if let preview = model.preview {
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .background {
                            if model.settings.background == .transparent { Checkerboard() }
                        }
                        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
                        .frame(width: size.width, height: size.height)
                        .offset(x: origin.x, y: origin.y)

                    AnnotationOverlay(model: model, scale: scale)
                        .frame(width: size.width, height: size.height)
                        .offset(x: origin.x, y: origin.y)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                AnnotationToolbar(model: model)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)

                if isDropTarget {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                        .padding(16)
                }
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTarget) { providers in
            loadDroppedImage(providers) { model.replaceImage($0) }
        }
    }
}

/// Loads the first image from dropped item providers.
@MainActor
func loadDroppedImage(_ providers: [NSItemProvider], completion: @escaping @MainActor (CGImage) -> Void) -> Bool {
    guard let provider = providers.first else { return false }
    if provider.canLoadObject(ofClass: URL.self) {
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, let image = ImageLoader.load(url) else { return }
            Task { @MainActor in completion(image) }
        }
        return true
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data, let image = ImageLoader.load(data) else { return }
            Task { @MainActor in completion(image) }
        }
        return true
    }
    return false
}

private struct ActionBar: View {
    @ObservedObject var model: EditorModel
    let actions: EditorActions

    var body: some View {
        HStack(spacing: 10) {
            let size = model.outputSize
            Label("\(Int(size.width)) × \(Int(size.height)) px", systemImage: "aspectratio")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            if model.trimmedSomething {
                Text(model.hasPlainBackground ? "Margins balanced" : "Margins trimmed")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            DragOutHandle(model: model)
            Button("Save As…", action: actions.saveAs)
            Button(action: actions.save) {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            Button(action: actions.copy) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 10
            for row in 0..<Int(ceil(size.height / tile)) {
                for col in 0..<Int(ceil(size.width / tile)) where (row + col) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(col) * tile, y: CGFloat(row) * tile, width: tile, height: tile)),
                                 with: .color(.gray.opacity(0.25)))
                }
            }
        }
        .background(Color.white)
    }
}

/// Drag this into Slack, X, Figma or Finder to drop the finished PNG there.
private struct DragOutHandle: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        Label("Drag", systemImage: "hand.draw")
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
            .onDrag {
                guard let image = try? model.renderFull(), let url = Exporter.temporaryFile(image),
                      let provider = NSItemProvider(contentsOf: url) else { return NSItemProvider() }
                provider.suggestedName = url.deletingPathExtension().lastPathComponent
                return provider
            }
            .help("Drag the finished image into any app")
    }
}
