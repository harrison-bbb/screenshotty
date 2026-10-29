import ScreenshottyCore

/// The editor's tools: selecting, the annotation kinds, and crop.
enum AnnotationTool: String, CaseIterable, Identifiable {
    case select, arrow, box, blur, redact, crop
    var id: String { rawValue }

    var kind: Annotation.Kind? {
        switch self {
        case .select: nil
        case .arrow: .arrow
        case .box: .box
        case .blur: .blur
        case .redact: .redact
        case .crop: nil
        }
    }

    var title: String {
        switch self {
        case .select: "Select"
        case .arrow: "Arrow"
        case .box: "Highlight box"
        case .blur: "Blur"
        case .redact: "Redact"
        case .crop: "Crop"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .box: "rectangle"
        case .blur: "circle.grid.3x3.fill"
        case .redact: "rectangle.fill"
        case .crop: "crop"
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
        case .crop: "c"
        }
    }
}
