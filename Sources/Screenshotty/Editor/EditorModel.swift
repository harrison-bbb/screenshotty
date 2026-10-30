import AppKit
import Combine
import ScreenshottyCore

/// State for one editor window: the captured image, the style, annotations, and a live preview.
@MainActor
final class EditorModel: ObservableObject {
    @Published private(set) var source: CGImage
    @Published var settings: CompositionSettings {
        didSet {
            guard settings != oldValue else { return }
            recordSettingsUndo(previous: oldValue)
            // Picking any non-matched background turns smart mode off.
            if let variant = settings.smartBackground,
               settings.background != smartSuggestions.first(where: { $0.variant == variant })?.style {
                settings.smartBackground = nil // no re-entry: Swift doesn't re-run didSet from inside it
            }
            Preferences.shared.lastSettings = settings
            if case .image(let spec) = settings.background { Preferences.shared.rememberBackgroundImage(spec.path) }
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
        didSet {
            scheduleRender()
            refreshStyleThumbnails()
        }
    }
    @Published var selectedID: UUID?
    @Published var tool: AnnotationTool = .select
    @Published var annotationColor: RGBAColor = Annotation.defaultColor {
        didSet {
            // Recolour the selected arrow or box too.
            guard let id = selectedID, let index = annotations.firstIndex(where: { $0.id == id }),
                  annotations[index].kind.usesColor, annotations[index].color != annotationColor else { return }
            recordUndo()
            annotations[index].color = annotationColor
        }
    }
    /// Everything ⌘Z can take back: annotations, the look and the crop.
    private struct EditState {
        var annotations: [Annotation]
        var settings: CompositionSettings
        var crop: CGRect?
    }
    private var undoStack: [EditState] = []
    private var redoStack: [EditState] = []
    private var isRestoring = false
    /// A burst of settings changes (a slider drag, typing a URL) counts as one undo step.
    private var settingsEditOpen = false
    private var settingsEditEnd: DispatchWorkItem?

    /// Backgrounds generated from this screenshot's colours.
    @Published private(set) var smartSuggestions: [SmartSuggestion] = []

    /// True when the screenshot sits on a plain background, so the inner margin applies.
    @Published private(set) var hasPlainBackground = false

    /// True when slivers of desktop or another window were cut off the capture's edges.
    @Published private(set) var cleanedEdges = false
    /// True when content cut through by the capture edge (half labels, clipped icons) was removed.
    @Published private(set) var removedClippedContent = false

    /// The part of the capture the user kept with the crop tool, in capture pixels. Nil = all of it.
    @Published private(set) var crop: CGRect?

    func setCrop(_ rect: CGRect?) {
        let full = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        var cleaned = rect.map { $0.integral.intersection(full) }
        if let c = cleaned, c.width < 8 || c.height < 8 || c == full { cleaned = nil }
        guard cleaned != crop else { return }
        if !isRestoring { recordUndo() }
        crop = cleaned
        analysis = nil
        updateShot()
        refreshStyleThumbnails()
    }

    /// What auto-trim kept, in capture pixels (for showing it in the crop tool).
    var autoContentRect: CGRect? {
        guard settings.autoTrim, let analysis else { return nil }
        return analysis.contentRect.offsetBy(dx: crop?.minX ?? 0, dy: crop?.minY ?? 0)
    }

    /// While true the canvas shows the capture exactly as taken, for comparison.
    @Published var showOriginal = false

    // MARK: Sensitive info

    enum ScanState { case scanning, done }
    @Published private(set) var scanState: ScanState = .scanning
    @Published private(set) var findings: [SensitiveFinding] = []
    private var scanTask: Task<Void, Never>?

    /// Findings not yet covered by a blur or redact annotation.
    var visibleFindings: [SensitiveFinding] {
        findings.filter { finding in !annotations.contains { Self.covers($0, finding) } }
    }

    private static func covers(_ mark: Annotation, _ finding: SensitiveFinding) -> Bool {
        (mark.kind == .redact || mark.kind == .blur) && mark.rect.insetBy(dx: -2, dy: -2).contains(finding.rect)
    }

    /// Removes the blurs and bars covering sensitive findings, in one undoable step.
    func showSensitive() {
        let covering = annotations.filter { mark in findings.contains { Self.covers(mark, $0) } }
        guard !covering.isEmpty else { return }
        recordUndo()
        let ids = Set(covering.map(\.id))
        annotations.removeAll { ids.contains($0.id) }
        if let selectedID, ids.contains(selectedID) { select(nil) }
    }

    /// Covers every visible finding in one undoable step, with the user's preferred blur or bar.
    func hideSensitive() {
        let pending = visibleFindings
        guard !pending.isEmpty else { return }
        recordUndo()
        annotations.append(contentsOf: pending.map { $0.annotation(Preferences.shared.sensitiveHideKind) })
    }

    private func scanForSensitiveInfo() {
        scanTask?.cancel()
        scanState = .scanning
        findings = []
        let image = source
        scanTask = Task { [weak self] in
            let found = await Task.detached(priority: .utility) { SensitiveScanner.scan(image) }.value
            guard let self, !Task.isCancelled, image === self.source else { return }
            self.findings = found
            self.scanState = .done
            if Preferences.shared.autoHideSensitive { self.hideSensitive() }
        }
    }

    // MARK: Styles

    /// This screenshot rendered in each style, keyed by style id, for the style cards.
    @Published private(set) var styleThumbnails: [String: CGImage] = [:]
    private var thumbnailTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private func refreshStyleThumbnails() {
        thumbnailTask?.cancel()
        let styles = Preferences.shared.allStyles
        let source = source
        let crop = crop
        let annotations = annotations
        let analysis = analysis
        thumbnailTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let rendered = await Task.detached(priority: .utility) { () -> [String: CGImage] in
                var result: [String: CGImage] = [:]
                for style in styles {
                    let settings = style.settings.resolved(for: source)
                    let prepared = ShotPreparer.prepareShot(source, crop: crop, analysis: analysis, settings: settings)
                    let shot = AnnotationRenderer.apply(annotations, to: prepared.image, offset: prepared.offset)
                    let canvas = CompositionLayout(imageSize: CGSize(width: shot.width, height: shot.height), settings: settings).canvasSize
                    let scale = min(1, 360 / max(canvas.width, canvas.height))
                    result[style.id] = try? Compositor.render(shot, settings: settings, scale: scale)
                }
                return result
            }.value
            guard !Task.isCancelled else { return }
            self?.styleThumbnails = rendered
        }
    }

    func apply(_ style: Style) {
        settings = style.settings.resolved(for: source)
    }

    /// The saved or built-in style the current look matches, if any.
    var activeStyle: Style? {
        Preferences.shared.allStyles.first { settings.looksLike($0.settings) }
    }

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
        scanForSensitiveInfo()
        refreshStyleThumbnails()
        Preferences.shared.$savedStyles
            .dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refreshStyleThumbnails() } }
            .store(in: &cancellables)
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

    /// Whole-number enlargement applied on export so small captures stay sharp.
    var exportFactor: Int {
        guard settings.exportWidth == nil, let minimum = Preferences.shared.exportMinimumLongSide else { return 1 }
        return ExportScale.factor(for: layout.canvasSize, minimumLongSide: minimum)
    }

    var outputSize: CGSize {
        let canvas = layout.canvasSize
        if let width = settings.exportWidth {
            return ExportScale.size(forWidth: width, canvas: canvas, aspect: settings.aspectRatio)
        }
        let factor = CGFloat(exportFactor)
        return CGSize(width: canvas.width * factor, height: canvas.height * factor)
    }

    /// Short descriptions of what was improved automatically, shown under the canvas.
    var fixes: [String] {
        var list: [String] = []
        if crop != nil { list.append("Cropped") }
        if cleanedEdges { list.append("Edges cleaned") }
        if removedClippedContent { list.append("Cut-off content removed") }
        if trimmedSomething { list.append(hasPlainBackground ? "Margins balanced" : "Margins trimmed") }
        if settings.smartBackground != nil { list.append("Colours matched") }
        if scanState == .done, !findings.isEmpty, visibleFindings.isEmpty { list.append("Sensitive info hidden") }
        if exportFactor > 1 { list.append("Sharpened \(exportFactor)×") }
        return list
    }

    var trimmedSomething: Bool {
        prepared.image.width != source.width || prepared.image.height != source.height
    }

    func replaceImage(_ image: CGImage) {
        source = image
        analysis = nil
        crop = nil
        smartSuggestions = Self.suggestions(for: image)
        isRestoring = true
        if settings.smartBackground != nil { settings = settings.resolved(for: image) }
        isRestoring = false
        // A new picture starts a new history.
        undoStack.removeAll()
        redoStack.removeAll()
        annotations = []
        selectedID = nil
        updateShot()
        scanForSensitiveInfo()
        refreshStyleThumbnails()
    }

    func resetStyle() {
        settings = .default
    }

    /// Full-resolution output for export.
    func renderFull() throws -> CGImage {
        try Compositor.renderExport(prepared, annotations: annotations, settings: settings,
                                    minimumLongSide: Preferences.shared.exportMinimumLongSide)
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

    /// Layout unit of the prepared shot (annotations are drawn on it), in capture pixels.
    var annotationUnit: CGFloat { CGFloat(max(prepared.image.width, prepared.image.height)) / 1000 }

    /// Stroke width of arrows and boxes, in canvas pixels.
    var annotationStrokeWidth: CGFloat { AnnotationRenderer.strokeWidth(unit: annotationUnit) }

    // MARK: Editing annotations

    func annotation(at point: CGPoint, tolerance: CGFloat) -> Annotation? {
        annotations.last { $0.hitTest(point, tolerance: tolerance, unit: annotationUnit) }
    }

    /// Selects an annotation and shows its colour and size in the toolbar.
    func select(_ id: UUID?) {
        selectedID = id
        guard let id, let annotation = annotations.first(where: { $0.id == id }) else { return }
        if annotation.kind.usesColor { annotationColor = annotation.color }
        if annotation.kind.isPlaced { textSize = annotation.size }
    }

    // MARK: Text and steps

    /// Size used for new text labels and steps; changing it resizes the selected one.
    @Published var textSize: Double = Annotation.defaultTextSize {
        didSet {
            guard let id = selectedID, let index = annotations.firstIndex(where: { $0.id == id }),
                  annotations[index].kind.isPlaced, annotations[index].size != textSize else { return }
            recordUndo()
            annotations[index].size = textSize
        }
    }

    /// A text label being typed: a new one at `point`, or an existing one (`id`).
    struct TextEditing: Equatable {
        var id: UUID?
        var point: CGPoint
        var text: String
    }
    @Published var textEditing: TextEditing?

    /// True while a text field in the editor has focus: single-key tool shortcuts step aside.
    @Published var isTyping = false

    func placeStep(at point: CGPoint) {
        add(Annotation(kind: .step, start: point, end: point, color: annotationColor, size: textSize))
    }

    func beginText(at point: CGPoint) {
        // Deselect, or colour and size changes made while typing would also restyle the last label.
        selectedID = nil
        textEditing = TextEditing(id: nil, point: point, text: "")
    }

    func editText(_ id: UUID) {
        guard let annotation = annotations.first(where: { $0.id == id }), annotation.kind == .text else { return }
        select(id)
        textEditing = TextEditing(id: id, point: annotation.start, text: annotation.text)
    }

    func commitText() {
        guard let editing = textEditing else { return }
        textEditing = nil
        let text = editing.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = editing.id, let index = annotations.firstIndex(where: { $0.id == id }) {
            guard annotations[index].text != text else { return }
            recordUndo()
            if text.isEmpty { annotations.remove(at: index); selectedID = nil } else { annotations[index].text = text }
        } else if editing.id == nil, !text.isEmpty {
            // (A label deleted or undone while being edited stays gone.)
            add(Annotation(kind: .text, start: editing.point, end: editing.point, color: annotationColor,
                           text: text, size: textSize))
        }
    }

    func cancelText() { textEditing = nil }

    /// The `.screenshotty` file this editor was opened from or last saved to.
    var projectURL: URL?

    /// Restores a project's annotations and crop as the starting point (not an undoable change).
    func loadProject(annotations marks: [Annotation], crop: CGRect?) {
        isRestoring = true
        annotations = marks
        setCrop(crop)
        isRestoring = false
        undoStack.removeAll()
        redoStack.removeAll()
    }

    /// Annotations carried over from the quick preview (e.g. sensitive info it already hid).
    func preload(_ marks: [Annotation]) {
        guard !marks.isEmpty else { return }
        annotations = marks
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

    private var currentState: EditState { EditState(annotations: annotations, settings: settings, crop: crop) }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(currentState)
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(currentState)
        restore(next)
    }

    private func restore(_ state: EditState) {
        closeSettingsEdit()
        isRestoring = true
        annotations = state.annotations
        settings = state.settings
        setCrop(state.crop)
        isRestoring = false
        if let id = selectedID, !annotations.contains(where: { $0.id == id }) { selectedID = nil }
        objectWillChange.send()
    }

    private func recordUndo() {
        closeSettingsEdit()
        push(currentState)
    }

    private func push(_ state: EditState) {
        undoStack.append(state)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
        objectWillChange.send()
    }

    /// Records the look before a change, once per burst of changes.
    private func recordSettingsUndo(previous: CompositionSettings) {
        guard !isRestoring else { return }
        if !settingsEditOpen {
            push(EditState(annotations: annotations, settings: previous, crop: crop))
            settingsEditOpen = true
        }
        settingsEditEnd?.cancel()
        let end = DispatchWorkItem { [weak self] in self?.settingsEditOpen = false }
        settingsEditEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: end)
    }

    private func closeSettingsEdit() {
        settingsEditEnd?.cancel()
        settingsEditOpen = false
    }

    // MARK: Rendering

    private func updateShot() {
        let working = crop.flatMap { source.cropping(to: $0) } ?? source
        // A hand-made crop is the user's call, so slivers and clipped content are left alone.
        let analysis = self.analysis ?? ImageTrimmer.analyze(working, repairEdges: crop == nil)
        self.analysis = analysis
        hasPlainBackground = analysis.backgroundColor != nil
        cleanedEdges = settings.autoTrim && analysis.cleanedEdges
        removedClippedContent = settings.autoTrim && analysis.removedClippedContent
        prepared = ShotPreparer.prepareShot(source, crop: crop, analysis: analysis, settings: settings)
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
