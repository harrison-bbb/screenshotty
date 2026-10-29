import AppKit
import Combine
import ScreenshottyCore

enum AnnotationTool: String, CaseIterable, Identifiable {
    case select, arrow, box, blur, redact
    var id: String { rawValue }

    var kind: Annotation.Kind? {
        switch self {
        case .select: nil
        case .arrow: .arrow
        case .box: .box
        case .blur: .blur
        case .redact: .redact
        }
    }

    var title: String {
        switch self {
        case .select: "Select"
        case .arrow: "Arrow"
        case .box: "Highlight box"
        case .blur: "Blur"
        case .redact: "Redact"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .box: "rectangle"
        case .blur: "circle.grid.3x3.fill"
        case .redact: "rectangle.fill"
        }
    }

    /// Single-key shortcut, like Preview and Figma.
    var key: Character {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .box: "b"
        case .blur: "u"
        case .redact: "r"
        }
    }
}

/// State for one editor window: the captured image, the style, annotations, and a live preview.
@MainActor
final class EditorModel: ObservableObject {
    @Published private(set) var source: CGImage
    @Published var settings: CompositionSettings {
        didSet {
            guard settings != oldValue else { return }
            // Picking any non-matched background turns smart mode off.
            if let variant = settings.smartBackground,
               settings.background != smartSuggestions.first(where: { $0.variant == variant })?.style {
                settings.smartBackground = nil // no re-entry: Swift doesn't re-run didSet from inside it
            }
            Preferences.shared.lastSettings = settings
            if settings.autoTrim != oldValue.autoTrim || settings.innerPadding != oldValue.innerPadding
                || settings.effectiveCornerRadius != oldValue.effectiveCornerRadius {
                updateShot()
            } else {
                scheduleRender()
            }
        }
    }
    @Published private(set) var preview: CGImage?

    // MARK: Annotations

    @Published private(set) var annotations: [Annotation] = [] {
        didSet { scheduleRender() }
    }
    @Published var selectedID: UUID?
    @Published var tool: AnnotationTool = .arrow
    @Published var annotationColor: RGBAColor = Annotation.defaultColor {
        didSet {
            // Recolour the selected arrow or box too.
            guard let id = selectedID, let index = annotations.firstIndex(where: { $0.id == id }),
                  annotations[index].kind.usesColor, annotations[index].color != annotationColor else { return }
            recordUndo()
            annotations[index].color = annotationColor
        }
    }
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    /// Backgrounds generated from this screenshot's colours.
    @Published private(set) var smartSuggestions: [SmartSuggestion] = []

    /// True when the screenshot sits on a plain background, so the inner margin applies.
    @Published private(set) var hasPlainBackground = false

    /// The screenshot after optional trimming and inner margin (without annotations).
    private(set) var prepared: PreparedShot
    private var analysis: ShotAnalysis?
    private var renderTask: Task<Void, Never>?

    /// Longest side of the preview render, in pixels. Keeps sliders smooth on huge captures.
    private let previewMaxDimension: CGFloat = 2000

    init(image: CGImage, settings: CompositionSettings) {
        source = image
        prepared = PreparedShot(image: image, offset: .zero)
        smartSuggestions = Self.suggestions(for: image)
        // A smart look from last time is re-matched to this screenshot.
        self.settings = settings.resolved(for: image)
        updateShot()
    }

    private static func suggestions(for image: CGImage) -> [SmartSuggestion] {
        let palette = SmartBackground.palette(of: image)
        return SmartBackground.Variant.allCases.map {
            SmartSuggestion(variant: $0, style: SmartBackground.style(for: palette, variant: $0))
        }
    }

    var layout: CompositionLayout {
        CompositionLayout(imageSize: CGSize(width: prepared.image.width, height: prepared.image.height), settings: settings)
    }

    var outputSize: CGSize { layout.canvasSize }

    var trimmedSomething: Bool {
        prepared.image.width != source.width || prepared.image.height != source.height
    }

    func replaceImage(_ image: CGImage) {
        source = image
        analysis = nil
        smartSuggestions = Self.suggestions(for: image)
        if settings.smartBackground != nil { settings = settings.resolved(for: image) }
        recordUndo()
        annotations = []
        selectedID = nil
        updateShot()
    }

    func resetStyle() {
        settings = .default
    }

    /// Full-resolution output for export.
    func renderFull() throws -> CGImage {
        let shot = AnnotationRenderer.apply(annotations, to: prepared.image, offset: prepared.offset)
        return try Compositor.render(shot, settings: settings)
    }

    // MARK: Coordinate mapping (canvas pixels <-> original capture pixels)

    func sourcePoint(fromCanvas point: CGPoint) -> CGPoint {
        let image = layout.imageRect
        return CGPoint(x: point.x - image.minX - prepared.offset.x, y: point.y - image.minY - prepared.offset.y)
    }

    func canvasPoint(fromSource point: CGPoint) -> CGPoint {
        let image = layout.imageRect
        return CGPoint(x: point.x + image.minX + prepared.offset.x, y: point.y + image.minY + prepared.offset.y)
    }

    /// Stroke width of arrows and boxes, in canvas pixels.
    var annotationStrokeWidth: CGFloat {
        AnnotationRenderer.strokeWidth(unit: CGFloat(max(prepared.image.width, prepared.image.height)) / 1000)
    }

    // MARK: Editing annotations

    func annotation(at point: CGPoint, tolerance: CGFloat) -> Annotation? {
        annotations.last { $0.hitTest(point, tolerance: tolerance) }
    }

    func add(_ annotation: Annotation) {
        recordUndo()
        annotations.append(annotation)
        selectedID = annotation.id
    }

    /// Call once before a series of `move` calls (one drag = one undo step).
    func beginMove() { recordUndo() }

    func move(_ id: UUID, by delta: CGVector) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index] = annotations[index].translated(by: delta)
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        recordUndo()
        annotations.removeAll { $0.id == id }
        selectedID = nil
    }

    func clearAnnotations() {
        guard !annotations.isEmpty else { return }
        recordUndo()
        annotations = []
        selectedID = nil
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        if let id = selectedID, !annotations.contains(where: { $0.id == id }) { selectedID = nil }
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
    }

    private func recordUndo() {
        undoStack.append(annotations)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
        objectWillChange.send()
    }

    // MARK: Rendering

    private func updateShot() {
        let analysis = self.analysis ?? ImageTrimmer.analyze(source)
        self.analysis = analysis
        hasPlainBackground = analysis.backgroundColor != nil
        prepared = ShotPreparer.prepareShot(source, analysis: analysis, settings: settings)
        scheduleRender(debounce: false)
    }

    private func scheduleRender(debounce: Bool = true) {
        renderTask?.cancel()
        let prepared = self.prepared
        let annotations = self.annotations
        let settings = self.settings
        let canvas = layout.canvasSize
        let scale = min(1, previewMaxDimension / max(canvas.width, canvas.height))

        renderTask = Task { [weak self] in
            if debounce {
                try? await Task.sleep(nanoseconds: 12_000_000)
            }
            guard !Task.isCancelled else { return }
            let image = await Task.detached(priority: .userInitiated) {
                let shot = AnnotationRenderer.apply(annotations, to: prepared.image, offset: prepared.offset)
                return try? Compositor.render(shot, settings: settings, scale: scale)
            }.value
            guard !Task.isCancelled, let image else { return }
            self?.preview = image
        }
    }
}
