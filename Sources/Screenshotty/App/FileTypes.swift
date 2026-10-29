import ScreenshottyCore
import UniformTypeIdentifiers

extension UTType {
    /// A re-editable Screenshotty project (`.screenshotty`). Declared in Info.plist.
    static let screenshottyProject = UTType(exportedAs: "com.screenshotty.project", conformingTo: .json)
    /// A shareable style (`.screenshotty-style`). Declared in Info.plist.
    static let screenshottyStyle = UTType(exportedAs: "com.screenshotty.style", conformingTo: .json)
}
