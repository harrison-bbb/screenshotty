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

                if model.showOriginal {
                    let source = CGSize(width: model.source.width, height: model.source.height)
                    // Same zoom as the finished preview, so the two compare like for like.
                    let fit = min(scale, available.width / source.width, available.height / source.height)
                    let shown = CGSize(width: source.width * fit, height: source.height * fit)
                    Image(decorative: model.source, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: shown.width, height: shown.height)
                        .overlay(Rectangle().strokeBorder(Color.primary.opacity(0.15)))
                        .offset(x: insets.leading + (available.width - shown.width) / 2,
                                y: insets.top + (available.height - shown.height) / 2)
                    Text("Original capture")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 8)
                } else if let preview = model.preview {
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

                if !model.showOriginal {
                    SensitiveBanner(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 10)
                }

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
            let fixes = model.fixes
            if !fixes.isEmpty {
                Label(fixes.joined(separator: " · "), systemImage: "wand.and.stars")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
                    .help("Improved automatically: " + fixes.joined(separator: ", "))
            }
            Spacer(minLength: 8)
            CompareButton(model: model)
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

/// Warns about emails, keys and similar in the capture, and hides them in one click.
/// "Auto-hide" is remembered, so every later capture is covered automatically.
private struct SensitiveBanner: View {
    @ObservedObject var model: EditorModel
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        let visible = model.visibleFindings
        if model.scanState == .done, !model.findings.isEmpty {
            HStack(spacing: 10) {
                if visible.isEmpty {
                    Label("Hidden: \(SensitiveFinding.summary(model.findings))", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Found \(SensitiveFinding.summary(visible))", systemImage: "exclamationmark.shield.fill")
                        .foregroundStyle(.orange)
                    Picker("", selection: $prefs.sensitiveHideKind) {
                        Text("Bar").tag(Annotation.Kind.redact)
                        Text("Blur").tag(Annotation.Kind.blur)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 96)
                    .help("Cover with a solid bar (safest) or pixelate")
                    Button("Hide") { model.hideSensitive() }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }
                Divider().frame(height: 16)
                Toggle("Auto-hide", isOn: $prefs.autoHideSensitive)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help("Hide sensitive info automatically on every capture")
            }
            .font(.callout.weight(.medium))
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .onChange(of: prefs.autoHideSensitive) { _, on in if on { model.hideSensitive() } }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Hold to see the capture exactly as it was taken.
private struct CompareButton: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        Label("Compare", systemImage: "rectangle.split.2x1")
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(model.showOriginal ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.08)))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !model.showOriginal { model.showOriginal = true } }
                .onEnded { _ in model.showOriginal = false })
            .help("Hold to see the original capture")
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
