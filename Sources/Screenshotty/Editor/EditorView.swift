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

    var body: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            if let preview = model.preview {
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .background {
                        if model.settings.background == .transparent { Checkerboard() }
                    }
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
                    .padding(.horizontal, 36)
                    .padding(.top, 52)
                    .padding(.bottom, 28)
                    .onDrag {
                        guard let image = try? model.renderFull(), let url = Exporter.temporaryFile(image),
                              let provider = NSItemProvider(contentsOf: url) else { return NSItemProvider() }
                        provider.suggestedName = url.deletingPathExtension().lastPathComponent
                        return provider
                    }
                    .help("Drag the image into any app, or press ⌘C to copy it")
            } else {
                ProgressView()
            }
            if isDropTarget {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(16)
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
                Text("Margins trimmed")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }
            Spacer()
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
