import AppKit
import Combine
import ScreenshottyCore

/// State for one editor window: the captured image, the style, and a live preview.
@MainActor
final class EditorModel: ObservableObject {
    @Published private(set) var source: CGImage
    @Published var settings: CompositionSettings {
        didSet {
            guard settings != oldValue else { return }
            Preferences.shared.lastSettings = settings
            if settings.autoTrim != oldValue.autoTrim { updateShot() } else { scheduleRender() }
        }
    }
    @Published private(set) var preview: CGImage?

    /// The screenshot after optional auto-trim.
    private(set) var shot: CGImage
    private var renderTask: Task<Void, Never>?

    /// Longest side of the preview render, in pixels. Keeps sliders smooth on huge captures.
    private let previewMaxDimension: CGFloat = 2000

    init(image: CGImage, settings: CompositionSettings) {
        source = image
        shot = image
        self.settings = settings
        updateShot()
    }

    var outputSize: CGSize {
        CompositionLayout(imageSize: CGSize(width: shot.width, height: shot.height), settings: settings).canvasSize
    }

    var trimmedSomething: Bool {
        shot.width != source.width || shot.height != source.height
    }

    func replaceImage(_ image: CGImage) {
        source = image
        updateShot()
    }

    func resetStyle() {
        settings = .default
    }

    /// Full-resolution output for export.
    func renderFull() throws -> CGImage {
        try Compositor.render(shot, settings: settings)
    }

    private func updateShot() {
        shot = settings.autoTrim ? ImageTrimmer.trim(source) : source
        scheduleRender(debounce: false)
    }

    private func scheduleRender(debounce: Bool = true) {
        renderTask?.cancel()
        let shot = self.shot
        let settings = self.settings
        let canvas = CompositionLayout(imageSize: CGSize(width: shot.width, height: shot.height), settings: settings).canvasSize
        let scale = min(1, previewMaxDimension / max(canvas.width, canvas.height))

        renderTask = Task { [weak self] in
            if debounce {
                try? await Task.sleep(nanoseconds: 12_000_000)
            }
            guard !Task.isCancelled else { return }
            let image = await Task.detached(priority: .userInitiated) {
                try? Compositor.render(shot, settings: settings, scale: scale)
            }.value
            guard !Task.isCancelled, let image else { return }
            self?.preview = image
        }
    }
}
