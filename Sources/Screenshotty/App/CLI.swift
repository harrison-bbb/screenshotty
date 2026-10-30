import Foundation
import ScreenshottyCore

/// Minimal command line interface, handy for scripting and for testing the renderer.
///
///     Screenshotty render input.png [-o output.png] [--preset ocean] [--aspect 16:9]
///                         [--padding 90] [--radius 12] [--shadow medium] [--chrome dark]
///                         [--frame glass] [--no-trim] [--settings settings.json]
enum CLI {
    static func run(_ args: [String]) -> Int32 {
        var input: String?
        var output: String?
        var settings = CompositionSettings.default
        var upscale = true
        // A project brings its own look, crop and annotations; options below still override the look.
        var project: ProjectDocument?
        if let path = args.first(where: { $0.hasSuffix("." + ProjectDocument.fileExtension) }) {
            guard let data = FileManager.default.contents(atPath: path), let document = try? ProjectDocument.decode(data) else {
                return fail("Could not read the project \(path)")
            }
            project = document
            settings = document.settings(unpackingInto: FileManager.default.temporaryDirectory.appendingPathComponent("screenshotty-assets"))
        }
        var redact = false
        var i = 0

        func value() -> String? {
            i += 1
            return i < args.count ? args[i] : nil
        }

        /// The next argument as a finite number inside `range` ("nan" and "inf" parse as Doubles).
        func number(in range: ClosedRange<Double>) -> Double? {
            guard let v = value().flatMap(Double.init), v.isFinite, range.contains(v) else { return nil }
            return v
        }

        while i < args.count {
            let arg = args[i]
            switch arg {
            case "-o", "--output": output = value()
            case "--settings":
                guard let path = value(), let data = FileManager.default.contents(atPath: path),
                      let decoded = try? JSONDecoder().decode(CompositionSettings.self, from: data)
                else { return fail("Could not read settings file") }
                settings = decoded
            case "--preset":
                guard let id = value(), let preset = Presets.preset(id: id) else {
                    return fail("Unknown preset. Available: \(Presets.all.map(\.id).joined(separator: ", "))")
                }
                settings.background = preset.style
                settings.smartBackground = nil
            case "--color":
                guard let hex = value(), let color = RGBAColor(hex: hex) else { return fail("Invalid colour") }
                settings.background = .solid(color)
                settings.smartBackground = nil
            case "--transparent":
                settings.background = .transparent
                settings.smartBackground = nil
            case "--smart":
                guard let v = value().flatMap(SmartBackground.Variant.init(rawValue:)) else {
                    return fail("Unknown smart style. Available: \(SmartBackground.Variant.allCases.map(\.rawValue).joined(separator: ", "))")
                }
                settings.smartBackground = v
            case "--aspect":
                guard let v = value(), let aspect = AspectRatio(rawValue: v) else {
                    return fail("Unknown aspect. Available: \(AspectRatio.allCases.map(\.rawValue).joined(separator: ", "))")
                }
                settings.aspectRatio = aspect
            case "--padding":
                guard let v = number(in: CompositionSettings.paddingRange) else { return fail("Padding must be 0 to 300") }
                settings.padding = v
            case "--radius":
                guard let v = number(in: CompositionSettings.cornerRadiusRange) else { return fail("Radius must be 0 to 60") }
                settings.cornerRadius = v
            case "--shadow":
                guard let v = value().flatMap(ShadowStyle.init(rawValue:)) else { return fail("Invalid shadow") }
                settings.shadow = v
            case "--chrome":
                guard let v = value().flatMap(WindowChromeStyle.init(rawValue:)) else { return fail("Invalid chrome") }
                settings.windowChrome = v
            case "--url":
                guard let v = value() else { return fail("Missing URL") }
                settings.browserURL = v
            case "--device":
                guard let v = value().flatMap(DeviceStyle.init(rawValue:)) else {
                    return fail("Unknown device. Available: \(DeviceStyle.allCases.map(\.rawValue).joined(separator: ", "))")
                }
                settings.device = v
            case "--width":
                guard let v = value().flatMap(Int.init), v >= 100, v <= 8000 else { return fail("Width must be 100 to 8000 pixels") }
                settings.exportWidth = v
            case "--style":
                guard let id = value(), let style = Style.builtIn.first(where: { $0.id == "builtin." + id || $0.id == id }) else {
                    return fail("Unknown style. Available: \(Style.builtIn.map { String($0.id.dropFirst(8)) }.joined(separator: ", "))")
                }
                settings = style.settings
            case "--watermark":
                guard let v = value() else { return fail("Missing watermark text") }
                var mark = settings.watermark ?? Watermark()
                mark.text = v
                settings.watermark = mark
            case "--logo":
                guard let v = value(), FileManager.default.fileExists(atPath: v) else { return fail("Logo file not found") }
                var mark = settings.watermark ?? Watermark()
                mark.logoPath = (v as NSString).expandingTildeInPath
                settings.watermark = mark
            case "--watermark-position":
                guard let v = value().flatMap(Watermark.Position.init(rawValue:)) else {
                    return fail("Watermark position: \(Watermark.Position.allCases.map(\.rawValue).joined(separator: ", "))")
                }
                var mark = settings.watermark ?? Watermark()
                mark.position = v
                settings.watermark = mark
            case "--style-file":
                guard let path = value(), let data = FileManager.default.contents(atPath: path),
                      let document = try? StyleDocument.decode(data) else { return fail("Could not read the style file") }
                settings = document.style(unpackingInto: FileManager.default.temporaryDirectory.appendingPathComponent("screenshotty-assets")).settings
            case "--redact":
                redact = true
            case "--frame":
                guard let v = value().flatMap(FrameStyle.init(rawValue:)) else { return fail("Invalid frame") }
                settings.frame = v
            case "--no-trim": settings.autoTrim = false
            case "--no-upscale": upscale = false
            case "--inner":
                guard let v = number(in: CompositionSettings.innerPaddingRange) else { return fail("Inner margin must be 0 to 150") }
                settings.innerPadding = v
            case "-h", "--help":
                print(usage)
                return 0
            default:
                if arg.hasPrefix("-") { return fail("Unknown option \(arg)\n\n\(usage)") }
                input = arg
            }
            i += 1
        }

        guard let input else { return fail(usage) }
        guard let image = project?.capture ?? ImageLoader.load(URL(fileURLWithPath: input)) else { return fail("Could not read \(input)") }
        let outPath = output ?? (input as NSString).deletingPathExtension + "-screenshotty.png"
        do {
            var annotations = project?.annotations ?? []
            if redact {
                let findings = SensitiveScanner.scan(image)
                annotations += findings.map(\.redaction)
                for finding in findings { print("Redacted \(finding.kind.singularTitle): \(finding.masked)") }
            }
            let result = try Compositor.compose(image, settings: settings, annotations: annotations, crop: project?.crop,
                                               minimumLongSide: upscale ? ExportScale.defaultMinimumLongSide : nil)
            try PNGEncoder.write(result, to: URL(fileURLWithPath: outPath))
            print("\(outPath) (\(result.width)×\(result.height))")
            return 0
        } catch {
            return fail("Render failed: \(error)")
        }
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return 1
    }

    static let usage = """
    Usage: Screenshotty render <image or .screenshotty project> [-o output.png] [options]

    Options:
      --preset <id>        Background preset (\(Presets.all.map(\.id).joined(separator: ", ")))
      --color <hex>        Solid background colour, e.g. #FFFFFF
      --smart <style>      Background matched to the screenshot's colours: vibrant (default), mesh, pastel, dark
      --transparent        No background
      --aspect <ratio>     \(AspectRatio.allCases.map(\.rawValue).joined(separator: ", "))
      --padding <units>    Padding, in 1/1000ths of the screenshot's longest side (default 90)
      --radius <units>     Corner radius (default 12)
      --shadow <style>     none, soft, medium, strong
      --chrome <style>     none, light, dark, browser-light, browser-dark
      --url <text>         Address shown in the browser window chrome
      --device <name>      none, macbook, iphone
      --width <pixels>     Exact export width (height follows the canvas shape)
      --style-file <file>  A shared .screenshotty-style file
      --style <id>         A built-in style: \(Style.builtIn.map { String($0.id.dropFirst(8)) }.joined(separator: ", "))
      --watermark <text>   Text in a corner of the canvas, e.g. @yourhandle or yourapp.com
      --logo <file>        Logo image in a corner of the canvas (with --watermark, the text follows it)
      --watermark-position \(Watermark.Position.allCases.map(\.rawValue).joined(separator: ", ")) (default bottomRight)
      --redact             Find emails, API keys, card numbers and similar, and cover them before export
      --frame <style>      none, hairline, glass
      --inner <units>      Even inner margin for screenshots on a plain background (default 40)
      --no-trim            Keep the screenshot exactly as captured (also keeps sloppy edges)
      --no-upscale         Don't enlarge small results (by default they are doubled pixel-for-pixel up to 1600 px)
      --settings <file>    Load settings from a JSON file (see docs/composition-format.md)
    """
}
