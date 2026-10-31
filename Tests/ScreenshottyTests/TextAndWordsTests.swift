import CoreGraphics
import Testing
@testable import ScreenshottyCore

/// Copying text out of screenshots, and the user's own words to hide.
@Suite(.timeLimit(.minutes(1))) struct TextAndWordsTests {
    @Test func linesComeOutInReadingOrder() {
        // Vision boxes: bottom-left origin, in no particular order.
        let lines = [
            TextRecognizer.Line(text: "world", box: CGRect(x: 0.5, y: 0.80, width: 0.2, height: 0.05)),
            TextRecognizer.Line(text: "Second line", box: CGRect(x: 0.1, y: 0.72, width: 0.4, height: 0.05)),
            TextRecognizer.Line(text: "Hello", box: CGRect(x: 0.1, y: 0.81, width: 0.2, height: 0.05)),
            TextRecognizer.Line(text: "New paragraph", box: CGRect(x: 0.1, y: 0.50, width: 0.4, height: 0.05)),
        ]
        #expect(TextRecognizer.arrange(lines) == "Hello  world\nSecond line\n\nNew paragraph")
    }

    @Test func readsTextFromAnImage() async {
        let image = TestImages.text(["Quarterly revenue grew", "Ship the update on Friday"])
        let text = await TextRecognizer.textInBackground(in: image)
        #expect(text.contains("Quarterly revenue grew"))
        #expect(text.contains("Ship the update on Friday"))
        #expect(text.firstRange(of: "Quarterly")!.lowerBound < text.firstRange(of: "Ship")!.lowerBound)
    }

    @Test func hiddenWordsMatchIgnoringCaseAndAccents() {
        let matches = SensitiveScanner.matches(in: "Invoice for ACME Corp and Café Rouge, acme corp again",
                                               customWords: ["acme corp", "cafe rouge"])
        #expect(matches.map(\.kind) == [.customWord, .customWord, .customWord])
    }

    @Test func aHiddenWordInsideAnEmailStillHidesTheWholeEmail() {
        let text = "Contact jane@acme.com today"
        let matches = SensitiveScanner.matches(in: text, customWords: ["acme"])
        #expect(matches.count == 1)
        #expect(matches.first.map { String(text[$0.range]) } == "jane@acme.com")
        #expect(matches.first?.kind == .email)
    }

    @Test func hiddenWordsAreFoundInScreenshots() async {
        let image = TestImages.text(["Meeting notes for Northwind", "Nothing secret here"])
        let findings = await SensitiveScanner.scanInBackground(image, customWords: ["northwind"])
        #expect(findings.map(\.kind) == [.customWord])
        #expect(SensitiveFinding.summary(findings) == "1 word from your list")
    }
}

extension TextAndWordsTests {
    @Test func readsInTheMacsLanguagesWithEnglishAsFallback() {
        let supported = ["en-US", "fr-FR", "de-DE", "zh-Hans"]
        #expect(TextRecognizer.preferredLanguages(supported: supported, preferred: ["fr-CA", "en-GB"]) == ["fr-FR", "en-US"])
        #expect(TextRecognizer.preferredLanguages(supported: supported, preferred: ["ja-JP"]) == ["en-US"])
    }
}
