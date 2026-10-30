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
            // View points per layout-canvas pixel. The output can be larger than the layout (sharpened small
            // shots, fixed export widths), so this differs from `scale`; annotations live in layout space.
            let canvasScale = size.width / max(model.layout.canvasSize.width, 1)

            ZStack(alignment: .topLeading) {
                Color(nsColor: .underPageBackgroundColor)

                if model.tool == .crop {
                    let source = CGSize(width: model.source.width, height: model.source.height)
                    let fit = min(available.width / source.width, available.height / source.height)
                    let shown = CGSize(width: source.width * fit, height: source.height * fit)
                    CropView(model: model, frame: CGRect(x: insets.leading + (available.width - shown.width) / 2,
                                                         y: insets.top + (available.height - shown.height) / 2,
                                                         width: shown.width, height: shown.height))
                } else if model.showOriginal {
                    let source = CGSize(width: model.source.width, height: model.source.height)
                    // Same zoom as the finished preview, so the two compare like for like.
                    let fit = min(canvasScale, available.width / source.width, available.height / source.height)
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

                    AnnotationOverlay(model: model, scale: canvasScale)
                        .frame(width: size.width, height: size.height)
                        .offset(x: origin.x, y: origin.y)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                AnnotationToolbar(model: model)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)

                if !model.showOriginal, model.tool != .crop {
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
            Text("\(Int(size.width)) × \(Int(size.height)) px")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            FixesChip(fixes: model.fixes)
            Spacer(minLength: 8)
            Menu {
                Button("Save As…", action: actions.saveAs)
                Divider()
                Button("Save Project…", action: actions.saveProject)
                    .help("A .screenshotty file that reopens with the crop, annotations and style still editable")
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            } primaryAction: {
                actions.save()
            }
            .menuStyle(.button)
            .fixedSize()
            .help("Save to your save folder (⌘S). Use the arrow for Save As.")
            Button(action: actions.copy) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .help("Copy the finished image (⌘C). ⌘↩ copies and closes, Esc closes.")
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
        .background { EditorShortcuts(model: model, actions: actions) }
    }
}

/// The editor's main shortcuts, attached to the window itself. Over full-screen apps Screenshotty runs as a
/// menu bar app with no visible menu bar, so these must not depend on the menus. Off while typing.
private struct EditorShortcuts: View {
    @ObservedObject var model: EditorModel
    let actions: EditorActions

    var body: some View {
        let on = !model.isTyping
        ZStack {
            Button("Copy", action: actions.copy).keyboardShortcut(on ? KeyboardShortcut("c") : nil)
            Button("Save", action: actions.save).keyboardShortcut(on ? KeyboardShortcut("s") : nil)
            Button("Save As", action: actions.saveAs).keyboardShortcut(on ? KeyboardShortcut("s", modifiers: [.command, .shift]) : nil)
            Button("Save Project", action: actions.saveProject).keyboardShortcut(on ? KeyboardShortcut("s", modifiers: [.command, .option]) : nil)
            Button("Copy and Close", action: actions.copyAndClose).keyboardShortcut(on ? KeyboardShortcut(.return) : nil)
            Button("Undo") { model.undo() }.keyboardShortcut(on ? KeyboardShortcut("z") : nil)
            Button("Redo") { model.redo() }.keyboardShortcut(on ? KeyboardShortcut("z", modifiers: [.command, .shift]) : nil)
            Button("Paste Image") {
                if let image = AppDelegate.clipboardImage() { model.replaceImage(image) }
            }
            .keyboardShortcut(on ? KeyboardShortcut("v") : nil)
            Button("Delete Annotation") { model.deleteSelected() }
                .keyboardShortcut(on && model.selectedID != nil ? KeyboardShortcut(.delete, modifiers: []) : nil)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

/// "3 fixes": what Screenshotty improved automatically. Click for the list.
private struct FixesChip: View {
    let fixes: [String]
    @State private var showing = false

    var body: some View {
        if !fixes.isEmpty {
            Button { showing.toggle() } label: {
                Label(fixes.count == 1 ? fixes[0] : "\(fixes.count) fixes", systemImage: "wand.and.stars")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help(fixes.joined(separator: "\n"))
            .popover(isPresented: $showing, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Improved automatically").font(.headline)
                    ForEach(fixes, id: \.self) { fix in
                        Label(fix, systemImage: "checkmark.circle.fill")
                            .symbolRenderingMode(.multicolor)
                    }
                    Text("Hold the eye button in the toolbar to compare with the original.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(width: 260)
            }
        }
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
                    Button("Show") { model.showSensitive() }
                        .help("Remove the covers from this screenshot")
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
            // The switch acts on this screenshot too: on covers everything, off uncovers it again.
            .onChange(of: prefs.autoHideSensitive) { _, on in on ? model.hideSensitive() : model.showSensitive() }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}


