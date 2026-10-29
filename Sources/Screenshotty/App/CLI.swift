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
        var i = 0

        func value() -> String? {
            i += 1
            return i < args.count ? args[i] : nil
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
                guard let v = value().flatMap(Double.init) else { return fail("Invalid padding") }
                settings.padding = v
            case "--radius":
                guard let v = value().flatMap(Double.init) else { return fail("Invalid radius") }
                settings.cornerRadius = v
            case "--shadow":
                guard let v = value().flatMap(ShadowStyle.init(rawValue:)) else { return fail("Invalid shadow") }
                settings.shadow = v
            case "--chrome":
                guard let v = value().flatMap(WindowChromeStyle.init(rawValue:)) else { return fail("Invalid chrome") }
                settings.windowChrome = v
            case "--frame":
                guard let v = value().flatMap(FrameStyle.init(rawValue:)) else { return fail("Invalid frame") }
                settings.frame = v
            case "--no-trim": settings.autoTrim = false
            case "--no-upscale": upscale = false
            case "--inner":
                guard let v = value().flatMap(Double.init) else { return fail("Invalid inner margin") }
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
        guard let image = ImageLoader.load(URL(fileURLWithPath: input)) else { return fail("Could not read \(input)") }
        let outPath = output ?? (input as NSString).deletingPathExtension + "-screenshotty.png"
        do {
            let result = try Compositor.compose(image, settings: settings,
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
    Usage: Screenshotty render <input> [-o output.png] [options]

    Options:
      --preset <id>        Background preset (\(Presets.all.map(\.id).joined(separator: ", ")))
      --color <hex>        Solid background colour, e.g. #FFFFFF
      --smart <style>      Background matched to the screenshot's colours: vibrant (default), mesh, pastel, dark
      --transparent        No background
      --aspect <ratio>     \(AspectRatio.allCases.map(\.rawValue).joined(separator: ", "))
      --padding <units>    Padding, in 1/1000ths of the screenshot's longest side (default 90)
      --radius <units>     Corner radius (default 12)
      --shadow <style>     none, soft, medium, strong
      --chrome <style>     none, light, dark
      --frame <style>      none, hairline, glass
      --inner <units>      Even inner margin for screenshots on a plain background (default 40)
      --no-trim            Keep the screenshot exactly as captured (also keeps sloppy edges)
      --no-upscale         Don't enlarge small results (by default they are doubled pixel-for-pixel up to 1600 px)
      --settings <file>    Load settings from a JSON file (see docs/composition-format.md)
    """
}
