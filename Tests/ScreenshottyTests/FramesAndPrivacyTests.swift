import CoreGraphics
import Testing
@testable import ScreenshottyCore

/// Fake secrets, assembled at runtime so secret scanners don't mistake the source for a leak.
enum Fake {
    static let stripeKey = ["sk", "live", "51Hx9QaB7kP2mTz4R8vYcLdE3nWq0"].joined(separator: "_")
}

@Suite struct SensitivePatternTests {
    @Test func findsEmails() {
        #expect(Text.kinds("Contact jamie.rivera@acme-corp.com today") == [.email])
    }

    @Test func findsWellKnownKeys() {
        #expect(Text.kinds(Fake.stripeKey) == [.apiKey])
        #expect(Text.kinds("token ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8") == [.apiKey])
        #expect(Text.kinds("AKIAIOSFODNN7EXAMPLE") == [.apiKey])
        #expect(Text.kinds("xoxb-1234567890-abcdefghij") == [.apiKey])
    }

    @Test func findsJWTs() {
        #expect(Text.kinds("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N") == [.token])
    }

    @Test func cardNumbersMustPassLuhn() {
        #expect(Text.kinds("Card 4242 4242 4242 4242") == [.cardNumber])
        #expect(Text.kinds("Order 4242 4242 4242 4241").isEmpty)
    }

    @Test func findsPhoneNumbersAndIPs() {
        #expect(Text.kinds("Call (415) 555-0132") == [.phoneNumber])
        #expect(Text.kinds("Server 192.168.1.20 is up") == [.ipAddress])
    }

    @Test func ignoresOrdinaryText() {
        #expect(Text.kinds("Revenue grew 12.5% to $1,234,567 in Q3 2025").isEmpty)
        #expect(Text.kinds("Version 2.3.1 released on 2025-10-01").isEmpty)
        #expect(Text.kinds("commit 3f9a2b1c4d5e6f708192a3b4c5d6e7f8091a2b3c").isEmpty) // one-case hash
        #expect(Text.kinds("https://acme-corp.com/settings/billing").isEmpty)
    }

    @Test func summaryReadsNaturally() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        let findings = [SensitiveFinding(kind: .email, text: "a@b.co", rect: rect),
                        SensitiveFinding(kind: .email, text: "c@d.co", rect: rect),
                        SensitiveFinding(kind: .apiKey, text: "sk_live_x", rect: rect)]
        #expect(SensitiveFinding.summary(findings) == "2 emails and 1 API key")
    }

    @Test func maskingHidesTheMiddle() {
        let finding = SensitiveFinding(kind: .apiKey, text: String(Fake.stripeKey.prefix(20)), rect: .zero)
        #expect(finding.masked.hasPrefix("sk_"))
        #expect(!finding.masked.contains("51Hx9"))
    }
}

@Suite struct SensitiveScanTests {
    @Test func locatesSecretsInAnImage() {
        let image = TestImages.text(["Owner: jamie.rivera@acme-corp.com", "Plan: Pro (monthly)",
                                     "Key: " + Fake.stripeKey])
        let findings = SensitiveScanner.scan(image)
        #expect(Set(findings.map(\.kind)) == [.email, .apiKey])
        // The email is on the first line, the key on the third.
        if let email = findings.first(where: { $0.kind == .email }), let key = findings.first(where: { $0.kind == .apiKey }) {
            #expect(email.rect.midY < key.rect.midY)
            #expect(email.rect.minX > 150) // starts after "Owner: "
        }
    }

    @Test func hidingCoversTheText() {
        let image = TestImages.text(["Key: " + Fake.stripeKey])
        let marks = SensitiveScanner.scan(image).map(\.redaction)
        #expect(!marks.isEmpty)
        #expect(SensitiveScanner.scan(AnnotationRenderer.apply(marks, to: image, offset: .zero)).isEmpty)
    }
}

@Suite struct DeviceLayoutTests {
    @Test(arguments: DeviceStyle.allCases.filter { $0 != .none })
    func deviceIsCentredAndHoldsTheCard(device: DeviceStyle) throws {
        var settings = CompositionSettings.default
        settings.device = device
        let layout = CompositionLayout(imageSize: CGSize(width: 1600, height: 1000), settings: settings)
        let geometry = try #require(layout.device)
        #expect(geometry.bodyRect.contains(layout.cardRect))
        #expect(abs(layout.objectRect.midX - layout.canvasSize.width / 2) < 0.01)
        #expect(abs(layout.objectRect.midY - layout.canvasSize.height / 2) < 0.01)
        #expect(layout.cardRect.minX == layout.cardRect.minX.rounded())
        #expect(layout.cardRect.minY == layout.cardRect.minY.rounded())
    }

    @Test func laptopBaseIsWiderThanLid() throws {
        var settings = CompositionSettings.default
        settings.device = .macbook
        let geometry = CompositionLayout(imageSize: CGSize(width: 1600, height: 1000), settings: settings).device!
        let base = try #require(geometry.baseRect)
        #expect(base.width > geometry.bodyRect.width)
        #expect(base.minY == geometry.bodyRect.maxY)
        #expect(abs(base.midX - geometry.bodyRect.midX) < 0.01)
    }

    @Test func browserBarIsTallerThanMacOSBar() {
        var settings = CompositionSettings.default
        settings.windowChrome = .light
        let mac = CompositionLayout(imageSize: CGSize(width: 1000, height: 600), settings: settings).titleBarHeight
        settings.windowChrome = .browserDark
        let browser = CompositionLayout(imageSize: CGSize(width: 1000, height: 600), settings: settings).titleBarHeight
        #expect(browser > mac)
    }

    @Test func addressBarClearsTheButtons() {
        let bar = CGRect(x: 0, y: 0, width: 400, height: 46)
        let field = WindowChrome.addressBarRect(in: bar, unit: 1, controlsEndX: 150)
        #expect(field.minX >= 150)
        #expect(field.maxX <= bar.maxX)
    }

    @Test func browserAndDeviceRender() throws {
        let image = TestImages.make(width: 600, height: 400, background: RGBAColor(hex: "#3366FF")!)
        var settings = CompositionSettings.default
        settings.smartBackground = nil
        settings.windowChrome = .browserLight
        settings.browserURL = "screenshotty.app"
        settings.device = .macbook
        let output = try Compositor.compose(image, settings: settings)
        let layout = CompositionLayout(imageSize: CGSize(width: 600, height: 400), settings: settings)
        #expect(output.width == Int(layout.canvasSize.width))
    }
}

@Suite struct ExportWidthTests {
    @Test(arguments: [(AspectRatio.widescreen, 1920, 1080), (.social, 1200, 628), (.portrait, 1080, 1350), (.square, 1600, 1600)])
    func fixedAspectGivesExactSize(aspect: AspectRatio, width: Int, height: Int) throws {
        let image = TestImages.make(width: 1234, height: 777, background: RGBAColor(hex: "#222222")!)
        var settings = CompositionSettings.default
        settings.aspectRatio = aspect
        settings.exportWidth = width
        let output = try Compositor.compose(image, settings: settings)
        #expect(output.width == width)
        #expect(output.height == height)
    }

    @Test func autoAspectKeepsShape() throws {
        let image = TestImages.make(width: 800, height: 500, background: RGBAColor(hex: "#222222")!)
        var settings = CompositionSettings.default
        settings.exportWidth = 2400
        let output = try Compositor.compose(image, settings: settings)
        let natural = try Compositor.compose(image, settings: { var s = settings; s.exportWidth = nil; return s }(),
                                             minimumLongSide: nil)
        #expect(output.width == 2400)
        #expect(abs(Double(output.height) / Double(output.width) - Double(natural.height) / Double(natural.width)) < 0.002)
    }
}

@Suite struct StyleTests {
    @Test func builtInStylesHaveUniqueIDs() {
        #expect(Set(Style.builtIn.map(\.id)).count == Style.builtIn.count)
        #expect(Style.builtIn.allSatisfy { $0.isBuiltIn })
    }

    @Test func smartStyleMatchesWhateverColoursItResolvedTo() {
        let style = Style.builtIn[0]
        var applied = style.settings
        applied.background = .solid(RGBAColor(hex: "#123456")!)
        #expect(applied.looksLike(style.settings))
        applied.padding += 1
        #expect(!applied.looksLike(style.settings))
    }

    @Test func newFieldsRoundTripAndOldSettingsStillDecode() throws {
        var settings = CompositionSettings.default
        settings.device = .iphone
        settings.windowChrome = .browserDark
        settings.browserURL = "acme.com"
        settings.exportWidth = 1080
        #expect(try JSON.roundTrip(settings) == settings)
        let old = try JSON.decode(#"{"padding": 50, "windowChrome": "dark"}"#)
        #expect(old.device == .none)
        #expect(old.exportWidth == nil)
        #expect(old.windowChrome == .dark)
    }
}

@Suite struct DeviceModeTests {
    func geometry(_ device: DeviceStyle, _ w: CGFloat, _ h: CGFloat) -> CompositionLayout.DeviceGeometry {
        var settings = CompositionSettings.default
        settings.device = device
        return CompositionLayout(imageSize: CGSize(width: w, height: h), settings: settings).device!
    }

    @Test func iPhoneKeepsARealScreenShape() {
        for (w, h) in [(1600.0, 1000.0), (800.0, 1400.0), (1179.0, 2556.0), (1000.0, 1000.0)] {
            let g = geometry(.iphone, w, h)
            let aspect = g.screenRect.width / g.screenRect.height
            let expected = g.landscape ? 1 / CompositionLayout.iPhoneScreenAspect : CompositionLayout.iPhoneScreenAspect
            #expect(abs(aspect / expected - 1) < 0.06, "screen \(g.screenRect.size) for a \(w)×\(h) shot")
        }
    }

    @Test func wideShotsTurnThePhoneLandscape() {
        #expect(geometry(.iphone, 1600, 1000).landscape)
        #expect(!geometry(.iphone, 800, 1400).landscape)
    }

    @Test func phoneScreenshotsFillTheScreenAndOthersGetAStatusBar() {
        let native = geometry(.iphone, 1179, 2556)
        #expect(native.mode == .fullBleed)
        #expect(native.statusBarHeight == 0)
        let app = geometry(.iphone, 800, 1400)
        #expect(app.mode == .phoneApp)
        #expect(app.statusBarHeight > 0)
    }

    @Test func macBookFillsWithScreenShapedShotsAndShowsADesktopOtherwise() {
        #expect(geometry(.macbook, 3024, 1964).mode == .fullBleed)
        #expect(geometry(.macbook, 1600, 1040).mode == .fullBleed)
        let tall = geometry(.macbook, 800, 1200)
        #expect(tall.mode == .desktop)
        #expect(abs(tall.screenRect.width / tall.screenRect.height / CompositionLayout.macBookScreenAspect - 1) < 0.01)
    }

    @Test func windowInsideMacBookStaysWhole() {
        var settings = CompositionSettings.default
        settings.device = .macbook
        settings.windowChrome = .browserLight
        let layout = CompositionLayout(imageSize: CGSize(width: 900, height: 900), settings: settings)
        let g = layout.device!
        #expect(g.screenRect.contains(layout.cardRect))
        #expect(layout.cornerRadius > 0)   // a window on a desktop keeps its rounded corners
    }
}
