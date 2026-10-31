import CoreGraphics
import Dispatch

/// Vision blocks its thread while it reads text and can wait on Swift's shared task threads, so a few
/// reads started from tasks at once can stall every task on a Mac with few cores. These run it on its
/// own queue and let the caller wait without holding a task thread.
enum VisionWork {
    private static let queue = DispatchQueue(label: "Screenshotty.vision", qos: .userInitiated, attributes: .concurrent)

    static func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }
}

extension SensitiveScanner {
    /// `scan(_:customWords:)` for async code, run away from Swift's shared task threads.
    public static func scanInBackground(_ image: CGImage, customWords: [String] = []) async -> [SensitiveFinding] {
        await VisionWork.run { scan(image, customWords: customWords) }
    }
}

extension TextRecognizer {
    /// `text(in:)` for async code, run away from Swift's shared task threads.
    public static func textInBackground(in image: CGImage) async -> String {
        await VisionWork.run { text(in: image) }
    }
}
