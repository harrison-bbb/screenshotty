import CoreGraphics
import Foundation
import Vision

/// Reads the text in an image, on this Mac (Apple's Vision text recognition), for copying it out.
public enum TextRecognizer {
    /// A recognised line: its text and box (normalised, bottom-left origin, as Vision gives it).
    public struct Line: Equatable, Sendable {
        public var text: String
        public var box: CGRect

        public init(text: String, box: CGRect) {
            self.text = text
            self.box = box
        }
    }

    /// The image's text in reading order, or an empty string if there is none.
    public static func text(in image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // The Mac's own languages. Automatic detection is far slower (many seconds instead of a fraction of one).
        let languages = preferredLanguages(supported: (try? request.supportedRecognitionLanguages()) ?? [])
        if !languages.isEmpty { request.recognitionLanguages = languages }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            // Some language combinations aren't allowed together; fall back to the default.
            request.recognitionLanguages = ["en-US"]
            do { try handler.perform([request]) } catch { return "" }
        }
        let lines = (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { Line(text: $0.string, box: observation.boundingBox) }
        }
        return arrange(lines)
    }

    /// Loads the model ahead of time, so the first copy is quick. Call once at launch, off the main thread.
    public static func warmUp() {
        guard let ctx = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        if let image = ctx.makeImage() { _ = text(in: image) }
    }

    /// The user's languages that Vision can read, in their order, with English last as a fallback.
    static func preferredLanguages(supported: [String], preferred: [String] = Locale.preferredLanguages) -> [String] {
        var result: [String] = []
        for language in preferred + ["en-US"] {
            let code = language.prefix(2)
            guard let match = supported.first(where: { $0 == language }) ?? supported.first(where: { $0.prefix(2) == code }),
                  !result.contains(match) else { continue }
            result.append(match)
        }
        return result
    }

    /// Puts lines in reading order: top to bottom, pieces on the same line left to right. A gap bigger
    /// than a line's height starts a new paragraph.
    public static func arrange(_ lines: [Line]) -> String {
        let sorted = lines.filter { !$0.text.isEmpty }.sorted { $0.box.midY > $1.box.midY }
        var rows: [[Line]] = []
        for line in sorted {
            // Same row when it overlaps the row's first piece by more than half its height.
            if let first = rows.last?.first {
                let overlap = min(first.box.maxY, line.box.maxY) - max(first.box.minY, line.box.minY)
                if overlap > min(first.box.height, line.box.height) * 0.5 {
                    rows[rows.count - 1].append(line)
                    continue
                }
            }
            rows.append([line])
        }
        var output = ""
        var previous: CGRect?
        for row in rows {
            let pieces = row.sorted { $0.box.minX < $1.box.minX }
            let box = pieces.map(\.box).reduce(pieces[0].box) { $0.union($1) }
            if let previous {
                let gap = previous.minY - box.maxY
                output += gap > min(previous.height, box.height) * 1.0 ? "\n\n" : "\n"
            }
            output += pieces.map(\.text).joined(separator: "  ")
            previous = box
        }
        return output
    }
}
