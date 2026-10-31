import CoreGraphics
import Foundation
import Vision

/// Something in a screenshot that probably shouldn't be posted: an email, an API key, a card number…
public struct SensitiveFinding: Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case email, apiKey, token, cardNumber, phoneNumber, ipAddress, customWord

        public var title: String {
            switch self {
            case .email: "Email"
            case .apiKey: "API key"
            case .token: "Token"
            case .cardNumber: "Card number"
            case .phoneNumber: "Phone number"
            case .ipAddress: "IP address"
            case .customWord: "Word from your list"
            }
        }

        /// Lower case for use inside a sentence, keeping acronyms.
        public var singularTitle: String {
            switch self {
            case .apiKey: "API key"
            case .ipAddress: "IP address"
            case .customWord: "word from your list"
            default: title.lowercased()
            }
        }

        public var pluralTitle: String {
            switch self {
            case .email: "emails"
            case .apiKey: "API keys"
            case .token: "tokens"
            case .cardNumber: "card numbers"
            case .phoneNumber: "phone numbers"
            case .ipAddress: "IP addresses"
            case .customWord: "words from your list"
            }
        }
    }

    public var kind: Kind
    public var text: String
    /// Where it is, in the capture's pixels (top-left origin), with a little padding.
    public var rect: CGRect

    public init(kind: Kind, text: String, rect: CGRect) {
        self.kind = kind
        self.text = text
        self.rect = rect
    }

    /// The text with most characters hidden, safe to show or log.
    public var masked: String {
        guard text.count > 6 else { return String(repeating: "•", count: text.count) }
        return String(text.prefix(3)) + String(repeating: "•", count: min(text.count - 5, 12)) + String(text.suffix(2))
    }

    /// An annotation that hides this finding.
    public func annotation(_ kind: Annotation.Kind = .redact) -> Annotation {
        Annotation(kind: kind, start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.maxY),
                   color: RGBAColor(hex: "#111111")!)
    }

    public var redaction: Annotation { annotation(.redact) }

    /// "2 emails and 1 API key"
    public static func summary(_ findings: [SensitiveFinding]) -> String {
        let counts = Kind.allCases.compactMap { kind -> String? in
            let n = findings.filter { $0.kind == kind }.count
            guard n > 0 else { return nil }
            return "\(n) \(n == 1 ? kind.singularTitle : kind.pluralTitle)"
        }
        switch counts.count {
        case 0: return ""
        case 1: return counts[0]
        default: return counts.dropLast().joined(separator: ", ") + " and " + counts.last!
        }
    }
}

/// Finds sensitive text in screenshots, entirely on this Mac (Apple's Vision text recognition).
public enum SensitiveScanner {
    // MARK: Scanning images

    /// `customWords` are extra words or phrases to hide (client names, internal domains…), matched
    /// anywhere in the text, ignoring case and accents.
    public static func scan(_ image: CGImage, customWords: [String] = []) -> [SensitiveFinding] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Language correction "fixes" keys and addresses into words, so it stays off.
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return [] }

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        var findings: [SensitiveFinding] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            for match in matches(in: text, customWords: customWords) {
                let box = (try? candidate.boundingBox(for: match.range))?.boundingBox ?? observation.boundingBox
                // Vision boxes are normalised with a bottom-left origin.
                var rect = CGRect(x: box.minX * width, y: (1 - box.maxY) * height,
                                  width: box.width * width, height: box.height * height)
                let pad = max(rect.height * 0.25, 2)
                rect = rect.insetBy(dx: -pad, dy: -pad).intersection(CGRect(x: 0, y: 0, width: width, height: height))
                findings.append(SensitiveFinding(kind: match.kind, text: String(text[match.range]), rect: rect.integral))
            }
        }
        return findings
    }

    /// Loads the text recognition model ahead of time. The first scan in a process otherwise takes
    /// many seconds; call this once at launch, off the main thread.
    public static func warmUp() {
        guard let ctx = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 8, y: 12, width: 48, height: 8))
        if let image = ctx.makeImage() { _ = scan(image) }
    }

    // MARK: Matching text

    public struct Match {
        public var range: Range<String.Index>
        public var kind: SensitiveFinding.Kind
    }

    private static let patterns: [(SensitiveFinding.Kind, NSRegularExpression)] = {
        let list: [(SensitiveFinding.Kind, String)] = [
            (.email, #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#),
            (.token, #"eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{6,}"#),
            (.apiKey, #"\b(?:sk|pk|rk)[-_](?:live|test|proj|ant)?[-_]?[A-Za-z0-9_\-]{16,}"#),
            (.apiKey, #"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}|\bgithub_pat_[A-Za-z0-9_]{20,}"#),
            (.apiKey, #"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#),
            (.apiKey, #"\bxox[abprs]-[A-Za-z0-9\-]{10,}"#),
            (.apiKey, #"\bAIza[0-9A-Za-z_\-]{30,}"#),
            (.apiKey, #"\b(?:glpat|npm|pypi|shpat|shpss|whsec|SG)[-_.][A-Za-z0-9_\-.]{16,}"#),
            (.apiKey, #"\b[A-Za-z0-9_\-]{32,}\b"#),   // long high-entropy strings, checked below
            (.cardNumber, #"\b\d(?:[ \-]?\d){12,18}\b"#),
            (.phoneNumber, #"(?:\+\d{1,3}[\s.\-]?)?\(?\d{3}\)?[\s.\-]\d{3}[\s.\-]\d{3,4}\b|\+\d{1,3}(?:[\s.\-]?\d{2,4}){3,5}"#),
            (.ipAddress, #"\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b"#),
        ]
        return list.map { ($0.0, try! NSRegularExpression(pattern: $0.1)) }
    }()

    /// Sensitive matches in one line of text, without overlaps (the first, most specific pattern wins).
    /// Words from the user's list are added on top, unless a built-in match already covers them.
    public static func matches(in text: String, customWords: [String] = []) -> [Match] {
        var found: [Match] = []
        let ns = NSRange(text.startIndex..., in: text)
        for (kind, regex) in patterns {
            for result in regex.matches(in: text, range: ns) {
                guard let range = Range(result.range, in: text) else { continue }
                if found.contains(where: { $0.range.overlaps(range) }) { continue }
                let value = String(text[range])
                switch kind {
                case .cardNumber:
                    guard passesLuhn(value) else { continue }
                case .apiKey where value.count >= 32 && !looksLikeKnownKey(value):
                    guard looksRandom(value) else { continue }
                default:
                    break
                }
                found.append(Match(range: range, kind: kind))
            }
        }
        for word in customWords.map({ $0.trimmingCharacters(in: .whitespaces) }) where !word.isEmpty {
            var searchStart = text.startIndex
            while let range = text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive],
                                         range: searchStart ..< text.endIndex) {
                if !found.contains(where: { $0.range.clamped(to: range) == range }) {
                    found.append(Match(range: range, kind: .customWord))
                }
                searchStart = range.upperBound
            }
        }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    private static func looksLikeKnownKey(_ value: String) -> Bool {
        ["sk-", "sk_", "pk_", "rk_", "ghp_", "gho_", "github_pat_", "AKIA", "ASIA", "xox", "AIza", "glpat-", "whsec_", "shpat_"]
            .contains { value.hasPrefix($0) }
    }

    /// Random secrets mix upper case, lower case and digits. Words, file paths and hashes in
    /// one case (like git commit hashes) mostly don't qualify.
    static func looksRandom(_ value: String) -> Bool {
        let upper = value.contains { $0.isUppercase }
        let lower = value.contains { $0.isLowercase }
        let digits = value.filter(\.isNumber).count
        return upper && lower && digits >= 3
    }

    static func passesLuhn(_ value: String) -> Bool {
        let digits = value.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count), Set(digits).count > 1 else { return false }
        var sum = 0
        for (i, d) in digits.reversed().enumerated() {
            if i % 2 == 1 {
                let doubled = d * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += d
            }
        }
        return sum % 10 == 0
    }
}
